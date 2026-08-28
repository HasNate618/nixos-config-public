import os
import uuid
import asyncio
import logging
from pathlib import Path
from datetime import datetime

from fastapi import FastAPI, UploadFile, File, HTTPException, Request
from fastapi.responses import HTMLResponse, FileResponse, JSONResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates

from jobqueue import JobQueue
from transcriber import Transcriber, MODELS

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

DATA_DIR = Path("/data")
JOBS_DIR = DATA_DIR / "jobs"
CACHE_DIR = DATA_DIR / "cache"
CONFIG_PATH = DATA_DIR / "config.json"
JOBS_DIR.mkdir(parents=True, exist_ok=True)
CACHE_DIR.mkdir(parents=True, exist_ok=True)

device = os.environ.get("WHISPER_DEVICE", "cuda")
model_name = os.environ.get("WHISPER_MODEL", "cohere-transcribe-03-2026")

app = FastAPI(title="Whisper Transcriber")
templates = Jinja2Templates(directory="templates")
app.mount("/static", StaticFiles(directory="static"), name="static")


def _load_config() -> dict:
    if CONFIG_PATH.exists():
        try:
            return json.loads(CONFIG_PATH.read_text())
        except Exception:
            pass
    return {}


import json

cfg = _load_config()
transcriber = Transcriber(device=device, model_name=cfg.get("model", model_name))
queue = JobQueue(JOBS_DIR)


def short_id() -> str:
    return uuid.uuid4().hex[:12]


async def worker_loop():
    await asyncio.sleep(3)
    try:
        await transcriber.warmup()
        logger.info("Transcriber initialized: model=%s device=%s", transcriber.model_name, transcriber.device)
    except Exception as e:
        logger.warning("Warmup failed, will init on first job: %s", e)

    while True:
        try:
            job = queue.dequeue()
            if job:
                logger.info("Processing job %s: %s", job.id, job.filename)
                job.status = "processing"
                job.model = transcriber.model_name
                queue.save(job)
                try:
                    def on_progress(segments_done):
                        job.segments_done = segments_done
                        queue.save(job)
                    text, language, duration = await transcriber.transcribe(
                        job.input_path, job.output_path, on_progress=on_progress
                    )
                    job.status = "done"
                    job.language = language
                    job.duration_seconds = round(duration, 1)
                    job.finished_at = datetime.utcnow().isoformat()
                    logger.info("Job %s done: %s %.1fs", job.id, language, duration)
                except Exception as e:
                    logger.error("Job %s failed: %s", job.id, e)
                    job.status = "failed"
                    job.error = str(e)
                    job.finished_at = datetime.utcnow().isoformat()
                queue.save(job)
        except Exception as e:
            logger.error("Worker error: %s", e)
        await asyncio.sleep(2)


@app.on_event("startup")
async def startup():
    queue.reset_stuck()
    asyncio.create_task(worker_loop())


@app.get("/", response_class=HTMLResponse)
async def index(request: Request):
    return templates.TemplateResponse(request, "index.html")


@app.get("/api/jobs")
async def list_jobs():
    jobs = queue.all()
    return JSONResponse([j.to_dict() for j in jobs])


@app.post("/api/upload")
async def upload(files: list[UploadFile] = File(...)):
    ids = []
    for f in files:
        content = await f.read()
        job_id = short_id()
        queue.create(job_id, f.filename or "unnamed.mp3", content)
        ids.append(job_id)
    return JSONResponse({"job_ids": ids})


@app.get("/api/jobs/{job_id}")
async def get_job(job_id: str):
    for job in queue.all():
        if job.id == job_id:
            return JSONResponse(job.to_dict())
    raise HTTPException(404, "Job not found")


@app.get("/api/jobs/{job_id}/download")
async def download(job_id: str):
    job_dir = JOBS_DIR / job_id
    output = job_dir / "output.txt"
    if not output.exists():
        raise HTTPException(404, "Output not found")
    return FileResponse(
        str(output),
        media_type="text/plain",
        filename=f"{job_id}.txt",
    )


@app.get("/api/jobs/{job_id}/content")
async def job_content(job_id: str):
    job_dir = JOBS_DIR / job_id
    output = job_dir / "output.txt"
    if not output.exists():
        raise HTTPException(404, "Output not found")
    return JSONResponse({"content": output.read_text(encoding="utf-8")})


@app.delete("/api/jobs/{job_id}")
async def delete_job(job_id: str):
    queue.remove(job_id)
    return JSONResponse({"ok": True})


@app.get("/api/config")
async def get_config():
    return JSONResponse(transcriber.info)


@app.post("/api/config/model")
async def set_model(request: Request):
    body = await request.json()
    model = body.get("model", "cohere-transcribe-03-2026")
    if model not in MODELS:
        raise HTTPException(400, f"Unknown model: {model}")
    transcriber._load_model(model)
    cfg = _load_config()
    cfg["model"] = model
    CONFIG_PATH.write_text(json.dumps(cfg))
    logger.info("Model switched to %s", model)
    return JSONResponse(transcriber.info)
