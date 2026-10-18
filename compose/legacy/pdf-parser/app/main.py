import os
import json
import uuid
import asyncio
import logging
from pathlib import Path
from datetime import datetime

from fastapi import FastAPI, UploadFile, File, HTTPException, Request
from fastapi.responses import HTMLResponse, FileResponse, JSONResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
import urllib.parse

from parser import PDFParser, VLM_PROVIDERS
from jobqueue import JobQueue

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

DATA_DIR = Path("/data")
JOBS_DIR = DATA_DIR / "jobs"
CACHE_DIR = DATA_DIR / "cache"
CONFIG_PATH = DATA_DIR / "config.json"
JOBS_DIR.mkdir(parents=True, exist_ok=True)
CACHE_DIR.mkdir(parents=True, exist_ok=True)

device = os.environ.get("DOCLING_DEVICE", "cuda")

app = FastAPI(title="Docling")
templates = Jinja2Templates(directory="templates")
app.mount("/static", StaticFiles(directory="static"), name="static")

def _load_config() -> dict:
    if CONFIG_PATH.exists():
        try:
            return json.loads(CONFIG_PATH.read_text())
        except Exception:
            pass
    return {}

def _load_vlm_provider() -> str:
    if CONFIG_PATH.exists():
        try:
            cfg = json.loads(CONFIG_PATH.read_text())
            return cfg.get("vlm_provider", "local")
        except Exception:
            pass
    return "local"

cfg = _load_config()
parser = PDFParser(CACHE_DIR, device=device, provider=cfg.get("vlm_provider", "local"), ocr_engine=cfg.get("ocr_engine", "rapid"))
queue = JobQueue(JOBS_DIR)


def short_id() -> str:
    return uuid.uuid4().hex[:12]


async def worker_loop():
    await asyncio.sleep(3)
    try:
        await parser.warmup()
        logger.info("Parser initialized on device=%s", parser.device)
    except Exception as e:
        logger.warning("Warmup failed, will init on first job: %s", e)

    while True:
        try:
            job = queue.dequeue()
            if job:
                logger.info("Processing job %s: %s", job.id, job.filename)
                job.status = "processing"
                queue.save(job)
                try:
                    page_count = await parser.parse(job.input_path, job.output_path)
                    job.status = "done"
                    job.pages_total = page_count
                    job.pages_done = page_count
                    job.finished_at = datetime.utcnow().isoformat()
                    logger.info("Job %s done: %d pages", job.id, page_count)
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


@app.put("/process")
async def openwebui_process(request: Request):
    filename = urllib.parse.unquote(request.headers.get("X-Filename", "document.pdf"))
    body = await request.body()

    job_id = short_id()
    job = queue.create(job_id, filename, body)
    job.status = "processing"
    queue.save(job)

    try:
        page_count = await parser.parse(job.input_path, job.output_path)
        markdown = job.output_path.read_text(encoding="utf-8")
        job.status = "done"
        job.pages_total = page_count
        job.pages_done = page_count
        job.finished_at = datetime.utcnow().isoformat()
        queue.save(job)
        return {"page_content": markdown, "metadata": {"source": filename}}
    except Exception as e:
        job.status = "failed"
        job.error = str(e)
        job.finished_at = datetime.utcnow().isoformat()
        queue.save(job)
        raise HTTPException(500, detail=str(e))


@app.post("/v1/convert/file")
async def docling_convert(files: list[UploadFile] = File(...)):
    """Docling-compatible API endpoint for Open WebUI integration."""
    if not files:
        raise HTTPException(400, detail="No files provided")

    f = files[0]
    content = await f.read()
    filename = f.filename or "document.pdf"

    job_id = short_id()
    job = queue.create(job_id, filename, content)
    job.status = "processing"
    queue.save(job)

    try:
        page_count = await parser.parse(job.input_path, job.output_path)
        markdown = job.output_path.read_text(encoding="utf-8")
        job.status = "done"
        job.pages_total = page_count
        job.pages_done = page_count
        job.finished_at = datetime.utcnow().isoformat()
        queue.save(job)
        return {"document": {"md_content": markdown}}
    except Exception as e:
        job.status = "failed"
        job.error = str(e)
        job.finished_at = datetime.utcnow().isoformat()
        queue.save(job)
        raise HTTPException(500, detail=str(e))


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
        queue.create(job_id, f.filename or "unnamed.pdf", content)
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
    output = job_dir / "output.md"
    if not output.exists():
        raise HTTPException(404, "Output not found")
    return FileResponse(
        str(output),
        media_type="text/markdown",
        filename=f"{job_id}.md",
    )


@app.get("/api/jobs/{job_id}/content")
async def job_content(job_id: str):
    job_dir = JOBS_DIR / job_id
    output = job_dir / "output.md"
    if not output.exists():
        raise HTTPException(404, "Output not found")
    return JSONResponse({"content": output.read_text(encoding="utf-8")})


@app.delete("/api/jobs/{job_id}")
async def delete_job(job_id: str):
    queue.remove(job_id)
    return JSONResponse({"ok": True})


@app.get("/api/vlm/config")
async def vlm_config():
    return JSONResponse({**parser.vlm_config, "providers": list(VLM_PROVIDERS.keys())})


@app.post("/api/vlm/config")
async def vlm_set_config(request: Request):
    body = await request.json()
    provider = body.get("provider", "local")
    parser.vlm_provider = provider
    CONFIG_PATH.write_text(json.dumps({"vlm_provider": provider}))
    logger.info("VLM provider switched to %s", provider)
    return JSONResponse({**parser.vlm_config, "providers": list(VLM_PROVIDERS.keys())})


@app.get("/api/ocr/config")
async def ocr_config():
    return JSONResponse({"engine": parser.ocr_engine, "engines": ["rapid", "ppocrv6"]})


@app.post("/api/ocr/config")
async def ocr_set_config(request: Request):
    body = await request.json()
    engine = body.get("engine", "rapid")
    parser.ocr_engine = engine
    cfg = _load_config()
    cfg["ocr_engine"] = engine
    CONFIG_PATH.write_text(json.dumps(cfg))
    logger.info("OCR engine switched to %s", engine)
    return JSONResponse({"engine": parser.ocr_engine, "engines": ["rapid", "ppocrv6"]})
