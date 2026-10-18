"""PDF Extractor — cloud VLM (Bifrost) + local OCR fallback + web UI."""

import os, io, base64, tempfile, asyncio, subprocess, json, logging, uuid, time
from datetime import datetime, timezone
import fitz, httpx
from fastapi import FastAPI, Request, HTTPException, UploadFile, File, Form
from fastapi.responses import JSONResponse, HTMLResponse, RedirectResponse

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(title="PDF Extractor")

# Config
ENGINE = os.environ.get("PDF_ENGINE", "cloud")
BIFROST_URL = os.environ.get("BIFROST_URL", "http://bifrost:8080")
# Comma-separated fallback chain: primary first, fallbacks after
VISION_MODELS = [m.strip() for m in os.environ.get(
    "VISION_MODELS",
    "cohere/command-a-vision-07-2025,opencode-go/mimo-v2.5",
).split(",") if m.strip()]
VISION_MODEL = VISION_MODELS[0]  # primary, for display/compat
MAX_CONCURRENT = int(os.environ.get("MAX_CONCURRENT", "3"))
MAX_TOKENS = int(os.environ.get("MAX_TOKENS", "4096"))
JOBS_DIR = os.environ.get("JOBS_DIR", "/data/jobs")
os.makedirs(JOBS_DIR, exist_ok=True)

# Shared per-job model state: circuit breaker for dead primary models.
# After FAIL_THRESHOLD consecutive failures we stay on the next model
# so remaining pages skip the doomed primary call entirely.
FAIL_THRESHOLD = int(os.environ.get("FAIL_THRESHOLD", "2"))

SYSTEM_PROMPT = """You are a precise document text extractor. Convert this page to clean markdown.

Rules:
- Extract ALL visible text — every word
- Preserve headers as ## or ### headings
- Bullet points as - items
- Checkboxes as [x] (checked) or [ ] (unchecked)
- Tables as markdown tables with | separators
- Keep paragraph spacing
- If the page contains images, diagrams, or charts that convey information, describe them briefly in [brackets]
- Do NOT add extra commentary or notes
- If the page is blank or only has page numbers, return [Page N is blank]"""


# ── Job tracking ──
def save_job(job: dict, pdf_bytes: bytes | None = None):
    job_dir = os.path.join(JOBS_DIR, job["id"])
    os.makedirs(job_dir, exist_ok=True)
    serializable = {k: v for k, v in job.items() if k != "pdf_bytes"}
    with open(os.path.join(job_dir, "job.json"), "w") as f:
        json.dump(serializable, f)
    if job.get("content"):
        with open(os.path.join(job_dir, "output.md"), "w") as f:
            f.write(job["content"])
    if pdf_bytes:
        with open(os.path.join(job_dir, "input.pdf"), "wb") as f:
            f.write(pdf_bytes)


def list_jobs() -> list[dict]:
    jobs = []
    if not os.path.exists(JOBS_DIR):
        return jobs
    for d in sorted(os.listdir(JOBS_DIR), reverse=True):
        jp = os.path.join(JOBS_DIR, d, "job.json")
        if os.path.exists(jp):
            with open(jp) as f:
                job = json.load(f)
            jobs.append(job)
    # Sort by created_at descending
    jobs.sort(key=lambda j: j.get("created_at", ""), reverse=True)
    return jobs


def get_job(job_id: str) -> dict | None:
    jp = os.path.join(JOBS_DIR, job_id, "job.json")
    if os.path.exists(jp):
        with open(jp) as f:
            return json.load(f)
    return None


# ── PDF processing ──
def pdf_to_images(pdf_bytes: bytes, dpi: int = 150) -> list[bytes]:
    doc = fitz.open(stream=pdf_bytes, filetype="pdf")
    images = []
    for page in doc:
        mat = fitz.Matrix(dpi / 72, dpi / 72)
        pix = page.get_pixmap(matrix=mat)
        images.append(pix.tobytes("jpeg"))
    doc.close()
    return images


async def extract_page(client: httpx.AsyncClient, img_bytes: bytes, page_num: int, total: int, state: dict) -> str:
    img_b64 = base64.b64encode(img_bytes).decode()
    last_err = ""
    # Start from the model the circuit breaker is currently on
    for idx in range(state["model_idx"], len(VISION_MODELS)):
        model = VISION_MODELS[idx]
        # Some models (e.g. cohere/c4ai-aya-vision-32b) reject OpenAI-style
        # image_url and need the raw "image" field instead.
        image_formats = [
            {"type": "image_url", "image_url": {"url": f"data:image/jpeg;base64,{img_b64}"}},
            {"type": "image", "image": f"data:image/jpeg;base64,{img_b64}"},
        ]
        for img_content in image_formats:
            try:
                response = await client.post(
                    f"{BIFROST_URL}/v1/chat/completions",
                    json={
                        "model": model,
                        "messages": [
                            {"role": "system", "content": SYSTEM_PROMPT},
                            {"role": "user", "content": [
                                {"type": "text", "text": f"Page {page_num} of {total}:"},
                                img_content,
                            ]}
                        ],
                        "max_tokens": MAX_TOKENS, "temperature": 0.0,
                    },
                )
                if response.status_code == 200:
                    text = response.json()["choices"][0]["message"]["content"].strip()
                    if text:
                        # Success — reset breaker if we were mid-fallback
                        state["failures"] = 0
                        if idx != state["model_idx"]:
                            state["model_idx"] = idx
                        logger.info("Page %d/%d via %s: %d chars", page_num, total, model, len(text))
                        return f"<!-- page {page_num} -->\n{text}"
                    last_err = f"empty response from {model}"
                elif response.status_code == 422:
                    # Invalid payload — try alternate image format next
                    last_err = f"HTTP 422 from {model} (retrying alternate image format)"
                    continue
                else:
                    last_err = f"HTTP {response.status_code} from {model}"
            except Exception as e:
                last_err = f"{type(e).__name__} from {model}: {e}"
            # Only break out of the format loop on non-422 failures
            if "retrying alternate" not in last_err:
                break

        # This model failed — count it, advance circuit breaker if threshold hit
        state["failures"] += 1
        logger.warning("Page %d/%d: %s — failures=%d", page_num, total, last_err, state["failures"])
        if state["failures"] >= FAIL_THRESHOLD and idx + 1 < len(VISION_MODELS):
            state["model_idx"] = idx + 1
            state["failures"] = 0
            logger.warning("Circuit breaker: switching to fallback model %s", VISION_MODELS[idx + 1])

    return f"<!-- page {page_num} -->\n[Error: all models failed: {last_err}]"


async def extract_with_cloud(pdf_bytes: bytes, filename: str) -> str:
    images = pdf_to_images(pdf_bytes, dpi=150)
    total = len(images)
    logger.info("Extracting %d pages via %s (fallbacks: %s, concurrency=%d)",
                total, VISION_MODEL, ",".join(VISION_MODELS[1:]) or "none", MAX_CONCURRENT)
    sem = asyncio.Semaphore(MAX_CONCURRENT)
    state = {"model_idx": 0, "failures": 0}

    async def limited(client, img, page):
        async with sem:
            return await extract_page(client, img, page, total, state)

    async with httpx.AsyncClient(timeout=120.0) as client:
        tasks = [limited(client, img, i + 1) for i, img in enumerate(images)]
        results = await asyncio.gather(*tasks)

    return "\n\n".join(results)


def extract_with_local(pdf_bytes: bytes, filename: str) -> str:
    """Local OCR via pdf-ocr service. Chain: PP-OCRv6 → RapidOCR → OCRmyPDF."""
    import urllib.request
    LOCAL_OCR_URL = os.environ.get("LOCAL_OCR_URL", "http://pdf-ocr:8000/process")

    def _call(engine: str | None) -> tuple[str | None, str]:
        req = urllib.request.Request(LOCAL_OCR_URL, data=pdf_bytes, method="PUT")
        req.add_header("X-Filename", filename)
        if engine:
            req.add_header("X-Ocr-Engine", engine)
        try:
            with urllib.request.urlopen(req, timeout=1800) as resp:
                data = json.loads(resp.read())
                return data.get("page_content", ""), data.get("metadata", {}).get("ocr_engine", engine or "ppocrv6")
        except Exception as e:
            return None, f"{type(e).__name__}: {e}"

    # 1. PP-OCRv6 (best quality)
    content, used = _call(None)
    if content and content.strip():
        logger.info("local: PP-OCRv6 OK (%s, %d chars)", filename, len(content))
        return content

    # 2. Retry with RapidOCR (same docling pipeline → markdown preserved)
    logger.warning("local: PP-OCRv6 failed/empty for %s (%s) — retrying with RapidOCR", filename, used)
    content, used2 = _call("rapid")
    if content and content.strip():
        logger.info("local: RapidOCR OK (%s, %d chars)", filename, len(content))
        return content

    # 3. Last resort: OCRmyPDF flat text
    logger.error("local: RapidOCR also failed (%s) for %s — falling back to OCRmyPDF", used2, filename)
    return _extract_ocrmypdf(pdf_bytes, filename)


def _extract_ocrmypdf(pdf_bytes: bytes, filename: str) -> str:
    """Fallback: OCRmyPDF + PyMuPDF text extraction (same as before)."""
    with tempfile.NamedTemporaryFile(suffix=".pdf", delete=False) as f:
        f.write(pdf_bytes)
        input_path = f.name
    ocr_path = input_path + ".ocr.pdf"
    try:
        result = subprocess.run(
            ["ocrmypdf", "--force-ocr", "--jobs", "2", input_path, ocr_path],
            capture_output=True, text=True, timeout=300,
        )
        if result.returncode not in (0, 5):
            raise Exception(f"OCR failed: {result.stderr[-200:]}")
        doc = fitz.open(ocr_path)
        pages = []
        for pn, page in enumerate(doc):
            text = page.get_text()
            if text.strip():
                pages.append(f"<!-- page {pn + 1} -->\n{text.strip()}")
        doc.close()
        return "\n\n".join(pages)
    finally:
        os.unlink(input_path)
        if os.path.exists(ocr_path):
            os.unlink(ocr_path)


def create_job(filename: str, pdf_bytes: bytes) -> dict:
    job_id = uuid.uuid4().hex[:12]
    now = datetime.now(timezone.utc).isoformat()
    return {
        "id": job_id,
        "filename": filename,
        "status": "processing",
        "pages_total": 0,
        "pages_done": 0,
        "error": None,
        "created_at": now,
        "finished_at": None,
        "processing_time_seconds": None,
    }


def process_job(job: dict, pdf_bytes: bytes, engine: str = "auto"):
    start = time.time()
    try:
        doc = fitz.open(stream=pdf_bytes, filetype="pdf")
        job["pages_total"] = doc.page_count
        doc.close()
        job_dir = os.path.join(JOBS_DIR, job["id"])
        os.makedirs(job_dir, exist_ok=True)
        with open(os.path.join(job_dir, "input.pdf"), "wb") as f:
            f.write(pdf_bytes)
        with open(os.path.join(job_dir, "job.json"), "w") as f:
            json.dump(job, f)

        content = asyncio.run(run_extraction(pdf_bytes, job["filename"], engine))

        job["content"] = content
        job["status"] = "done"
        job["pages_done"] = job["pages_total"]
    except Exception as e:
        logger.error("Job %s failed: %s", job["id"], e)
        job["status"] = "failed"
        job["error"] = str(e)
    finally:
        job["finished_at"] = datetime.now(timezone.utc).isoformat()
        job["processing_time_seconds"] = round(time.time() - start, 1)
        save_job(job)


# ── API endpoints ──
@app.put("/process")
async def process_pdf(request: Request):
    """Open WebUI-compatible endpoint: PUT raw PDF bytes, get markdown.
    Engine selection: ?engine=auto|local|cloud query param, else global ENGINE.
    Also records a job entry so /process calls show up in the dashboard."""
    filename = request.headers.get("X-Filename", "document.pdf")
    engine = request.query_params.get("engine", ENGINE)
    body = await request.body()
    if not body:
        raise HTTPException(400, detail="Empty request body")
    start = time.time()
    try:
        markdown = await run_extraction(body, filename, engine)
        elapsed = round(time.time() - start, 1)
        record_process_job(filename, engine, body, markdown, elapsed, error=None)
        return JSONResponse({"page_content": markdown, "metadata": {"source": filename, "engine": engine, "elapsed_seconds": elapsed}})
    except HTTPException as e:
        # Preserve intentional status codes (e.g. 413 oversize refusal)
        elapsed = round(time.time() - start, 1)
        record_process_job(filename, engine, body, None, elapsed, error=str(e.detail))
        raise
    except Exception as e:
        elapsed = round(time.time() - start, 1)
        record_process_job(filename, engine, body, None, elapsed, error=str(e))
        raise HTTPException(500, detail=str(e))


def record_process_job(filename: str, engine: str, pdf_bytes: bytes, markdown: str | None, elapsed: float, error: str | None):
    """Record a /process call in the job store so it appears in the dashboard.
    Best-effort: failures here must never break the extraction response."""
    try:
        job_id = uuid.uuid4().hex[:12]
        now = datetime.now(timezone.utc).isoformat()
        # Count pages from page markers in the markdown output
        import re
        pages = len(re.findall(r"<!-- page (\d+) -->", markdown or "")) or 0
        job = {
            "id": job_id,
            "filename": filename,
            "status": "failed" if error else "done",
            "engine": engine,
            "pages_total": pages,
            "pages_done": pages,
            "error": error,
            "created_at": now,
            "finished_at": now,
            "processing_time_seconds": elapsed,
        }
        job_dir = os.path.join(JOBS_DIR, job_id)
        os.makedirs(job_dir, exist_ok=True)
        with open(os.path.join(job_dir, "job.json"), "w") as f:
            json.dump(job, f)
        if markdown:
            with open(os.path.join(job_dir, "output.md"), "w") as f:
                f.write(markdown)
        # Save original PDF (same layout as web uploads)
        with open(os.path.join(job_dir, "input.pdf"), "wb") as f:
            f.write(pdf_bytes)
        logger.info("Recorded /process job %s (%s, %s, %.1fs)", job_id, filename, engine, elapsed)
    except Exception as e:
        logger.warning("Failed to record /process job: %s", e)


AUTO_VLM_MAX_PAGES = int(os.environ.get("AUTO_VLM_MAX_PAGES", "6"))
# Docs over this size: use embedded text if available, otherwise refuse to parse
AUTO_MAX_PAGES = int(os.environ.get("AUTO_MAX_PAGES", "100"))


def _embedded_text(pages_text):
    parts = []
    for i, t in enumerate(pages_text):
        parts.append(f"<!-- page {i + 1} -->\n{t}" if t.strip() else f"<!-- page {i + 1} -->\n[Page {i + 1} is blank]")
    return "\n\n".join(parts)


def _has_table_drawings(doc, threshold: int = 5) -> bool:
    """Cheap heuristic: pages with many vector drawings are likely table-heavy."""
    try:
        for page in doc:
            if len(page.get_drawings()) > threshold:
                return True
    except Exception:
        pass
    return False


async def run_extraction(pdf_bytes: bytes, filename: str, engine: str) -> str:
    """Dispatch to cloud VLM, local PP-OCRv6, or auto (smart routing)."""
    if engine == "auto":
        # 1. Inspect: page count + text layer
        doc = fitz.open(stream=pdf_bytes, filetype="pdf")
        pages_text = [p.get_text().strip() for p in doc]
        total = doc.page_count
        has_text = sum(1 for t in pages_text if len(t) > 20)
        is_digital = total > 0 and has_text / total >= 0.8

        # 2. Oversize guard: >AUTO_MAX_PAGES → embedded text or refuse
        if total > AUTO_MAX_PAGES:
            doc.close()
            if is_digital:
                logger.info("auto: %d pages (oversize), text layer present — using embedded text", total)
                return _embedded_text(pages_text)
            raise HTTPException(
                413,
                detail=f"Document too large for OCR: {total} pages, no text layer. "
                       f"Auto refuses to parse docs over {AUTO_MAX_PAGES} pages without embedded text "
                       f"(would take hours). Split it or use a smaller file.",
            )

        # 3. Digital docs (≤100 pages): tables → local (markdown), pure text → embedded
        if is_digital:
            doc.close()
            table_heavy = _has_table_drawings(fitz.open(stream=pdf_bytes, filetype="pdf"))
            if table_heavy:
                logger.info("auto: %d/%d pages text + table drawings — using local PP-OCRv6", has_text, total)
                return await asyncio.to_thread(extract_with_local, pdf_bytes, filename)
            logger.info("auto: %d/%d pages text, no tables — using embedded text", has_text, total)
            return _embedded_text(pages_text)

        # 4. Scanned docs: short → VLM (quality), long → local (quota)
        if total <= AUTO_VLM_MAX_PAGES:
            logger.info("auto: %d pages scanned, ≤%d — using VLM %s", total, AUTO_VLM_MAX_PAGES, VISION_MODEL)
            return await extract_with_cloud(pdf_bytes, filename)
        logger.info("auto: %d pages scanned, >%d — using local PP-OCRv6", total, AUTO_VLM_MAX_PAGES)
        return await asyncio.to_thread(extract_with_local, pdf_bytes, filename)
    elif engine == "cloud":
        return await extract_with_cloud(pdf_bytes, filename)
    elif engine == "local":
        # Run blocking OCR (urllib proxy to pdf-ocr, up to minutes) in a thread —
        # never block the event loop or the whole web UI / health endpoint freezes.
        return await asyncio.to_thread(extract_with_local, pdf_bytes, filename)
    else:
        raise HTTPException(400, detail=f"Unknown engine '{engine}' (use auto, local, or cloud)")


@app.post("/api/upload")
async def upload_pdf(file: UploadFile = File(...), engine: str = Form("auto")):
    """Web UI upload endpoint — processes PDF and stores result.
    Accepts ?engine=auto|local|cloud or form field engine."""
    pdf_bytes = await file.read()
    if not pdf_bytes:
        raise HTTPException(400, detail="Empty file")
    job = create_job(file.filename or "document.pdf", pdf_bytes)
    job["engine"] = engine
    import threading
    t = threading.Thread(target=process_job, args=(job, pdf_bytes, engine), daemon=True)
    t.start()
    return RedirectResponse(url=f"/job/{job['id']}", status_code=302)


@app.get("/api/jobs")
async def api_jobs():
    return JSONResponse(list_jobs())


@app.get("/api/jobs/{job_id}")
async def api_job(job_id: str):
    job = get_job(job_id)
    if not job:
        raise HTTPException(404, detail="Job not found")
    return JSONResponse(job)


@app.get("/api/jobs/{job_id}/content")
async def api_job_content(job_id: str):
    cp = os.path.join(JOBS_DIR, job_id, "output.md")
    if os.path.exists(cp):
        with open(cp) as f:
            return JSONResponse({"content": f.read()})
    raise HTTPException(404, detail="Content not found")


@app.get("/api/config")
async def get_config():
    return {"engine": ENGINE, "bifrost_url": BIFROST_URL, "vision_model": VISION_MODEL,
            "max_concurrent": MAX_CONCURRENT, "max_tokens": MAX_TOKENS}


@app.post("/api/config")
async def set_config(request: Request):
    global ENGINE
    data = await request.json()
    if "engine" in data:
        ENGINE = data["engine"]
    return {"engine": ENGINE}


# ── Web UI ──
HEAD = """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>PDF Extractor</title>
<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/katex@0.16.9/dist/katex.min.css">
<script src="https://cdn.jsdelivr.net/npm/marked/marked.min.js"></script>
<style>
*{margin:0;padding:0;box-sizing:border-box}
body{font-family:-apple-system,system-ui,sans-serif;background:#0d1117;color:#c9d1d9;min-height:100vh}
.nav{background:#161b22;border-bottom:1px solid #30363d;padding:12px 24px;display:flex;align-items:center;gap:16px}
.nav h1{font-size:18px;color:#f0f6fc}
.nav a{color:#58a6ff;text-decoration:none;font-size:14px}
.nav .badge{background:#1f6feb;padding:2px 8px;border-radius:12px;font-size:11px;color:#fff}
.container{max-width:960px;margin:0 auto;padding:24px}
.card{background:#161b22;border:1px solid #30363d;border-radius:8px;padding:20px;margin-bottom:16px}
.card h2{font-size:16px;margin-bottom:12px;color:#f0f6fc}
.upload-zone{border:2px dashed #30363d;border-radius:8px;padding:40px;text-align:center;cursor:pointer;transition:.2s}
.upload-zone:hover{border-color:#58a6ff;background:#1c2128}
.upload-zone.dragover{border-color:#58a6ff;background:#1c2128}
.upload-zone input{display:none}
.upload-zone p{font-size:14px;color:#8b949e}
.upload-zone .icon{font-size:32px;margin-bottom:8px}
table{width:100%;border-collapse:collapse;font-size:13px}
th{text-align:left;padding:8px 12px;border-bottom:2px solid #30363d;color:#8b949e;font-weight:600}
td{padding:8px 12px;border-bottom:1px solid #21262d}
tr:hover td{background:#1c2128}
.status-done{color:#3fb950}.status-processing{color:#d29922}.status-failed{color:#f85149}
.mono{font-family:'SFMono-Regular',monospace;font-size:12px;color:#8b949e}
.meta-grid{display:grid;grid-template-columns:auto 1fr;gap:4px 16px;font-size:13px}
.meta-grid dt{color:#8b949e}.meta-grid dd{color:#c9d1d9}
/* Markdown rendered content */
.md-content{line-height:1.6;font-size:14px}
.md-content h1,.md-content h2,.md-content h3{margin:16px 0 8px;color:#f0f6fc}
.md-content h1{font-size:24px;border-bottom:1px solid #30363d;padding-bottom:8px}
.md-content h2{font-size:18px;border-bottom:1px solid #21262d;padding-bottom:6px}
.md-content h3{font-size:15px}
.md-content p{margin:8px 0}
.md-content ul,.md-content ol{margin:8px 0;padding-left:24px}
.md-content li{margin:4px 0}
.md-content code{background:#1c2128;padding:2px 6px;border-radius:4px;font-size:13px}
.md-content pre{background:#0d1117;border:1px solid #30363d;border-radius:6px;padding:16px;overflow-x:auto}
.md-content pre code{background:transparent;padding:0}
.md-content table{border-collapse:collapse;margin:12px 0;width:100%}
.md-content th,.md-content td{border:1px solid #30363d;padding:6px 12px}
.md-content th{background:#161b22}
.md-content blockquote{border-left:4px solid #30363d;padding:8px 16px;color:#8b949e;margin:8px 0}
.md-content strong{color:#f0f6fc}
.md-content img{max-width:100%}
.md-content hr{border:none;border-top:1px solid #30363d;margin:16px 0}
.page-sep{border-left:3px solid #1f6feb;padding:4px 12px;margin:16px 0 8px;color:#58a6ff;font-size:12px}
.btn{display:inline-block;padding:6px 14px;border-radius:6px;font-size:13px;text-decoration:none;border:none;cursor:pointer}
.btn-primary{background:#238636;color:#fff}.btn-primary:hover{background:#2ea043}
.spinner{display:inline-block;width:16px;height:16px;border:2px solid #30363d;border-top-color:#58a6ff;border-radius:50%;animation:spin 1s linear infinite;margin-right:8px}
@keyframes spin{to{transform:rotate(360deg)}}
</style>
</head>
<body>"""

FOOT = """<script>
var dz=document.getElementById('dropZone');
if(dz){dz.addEventListener('dragover',function(e){e.preventDefault();dz.classList.add('dragover')});
dz.addEventListener('dragleave',function(){dz.classList.remove('dragover')});
dz.addEventListener('drop',function(e){e.preventDefault();dz.classList.remove('dragover');
var files=e.dataTransfer.files;if(files.length>0){document.getElementById('fileInput').files=files;document.getElementById('uploadForm').submit();}});}
function renderMarkdown(){
document.querySelectorAll('.md-render').forEach(function(el){
var raw=el.getAttribute('data-md');
var html=marked.parse(raw);
el.innerHTML=html;});}
renderMarkdown();
</script>
</body></html>"""


@app.get("/health")
async def health():
    """Health check endpoint for monitoring."""
    return JSONResponse({"status": "ok", "engine": ENGINE})


@app.get("/", response_class=HTMLResponse)
async def web_root():
    jobs = list_jobs()
    engine_label = "VLM (Bifrost)" if ENGINE == "cloud" else "Local (OCRmyPDF)"

    rows = ""
    for j in jobs[:20]:
        sc = f"status-{j['status']}"
        pages = f"{j.get('pages_done', '?')}/{j.get('pages_total', '?')}"
        ts = f"{j.get('processing_time_seconds', '')}s" if j.get('processing_time_seconds') else ""
        rows += f"""<tr>
<td><a href="/job/{j['id']}" style="color:#58a6ff;">{j['filename'][:50]}</a></td>
<td><span class="{sc}">{j['status']}</span></td>
<td><span class="engine-badge">{j.get('engine', ENGINE)}</span></td>
<td>{pages}</td><td>{ts}</td>
<td class="mono">{j.get('created_at','')[:19]}</td></tr>"""

    return HTMLResponse(f"""{HEAD}
<div class="nav"><h1>PDF Extractor</h1>
<a href="/">Documents</a>
<span class="badge">{engine_label}</span></div>
<div class="container">
<div class="card"><h2>Upload Document</h2>
<form action="/api/upload" method="post" enctype="multipart/form-data" id="uploadForm">
<div style="display:flex;gap:12px;margin-bottom:12px;align-items:center;">
<div>
<label for="engine" style="font-size:13px;color:#8b949e;display:block;margin-bottom:4px;">Engine</label>
<select name="engine" id="engine" style="background:#0d1117;color:#c9d1d9;border:1px solid #30363d;border-radius:6px;padding:6px 10px;font-size:13px;">
<option value="auto" selected>Auto — text layer, else VLM</option>
<option value="cloud">Cloud — Cohere VLM (Bifrost)</option>
<option value="local">Local — PP-OCRv6 (CPU, overnight)</option>
</select>
</div>
<div style="font-size:12px;color:#8b949e;padding-top:18px;">
<span class="engine-badge">auto</span> instant for digital PDFs &nbsp;·&nbsp; <span class="engine-badge">local</span> ~27s/page, no API &nbsp;·&nbsp; <span class="engine-badge">cloud</span> ~3s/page best quality
</div>
</div>
<div class="upload-zone" id="dropZone" onclick="document.getElementById('fileInput').click()">
<div class="icon">&#128196;</div><p>Drop a PDF here or click to upload</p>
<input type="file" name="file" id="fileInput" accept=".pdf" required onchange="document.getElementById('uploadForm').submit();">
</div></form></div>
<div class="card"><h2>Recent Documents</h2>
<table><thead><tr><th>Name</th><th>Status</th><th>Engine</th><th>Pages</th><th>Time</th><th>Uploaded</th></tr></thead>
<tbody>{rows if rows else '<tr><td colspan="6" style="text-align:center;color:#8b949e;padding:24px;">No documents yet</td></tr>'}</tbody></table></div></div>{FOOT}""")


@app.get("/job/{job_id}", response_class=HTMLResponse)
async def web_job(job_id: str):
    job = get_job(job_id)
    if not job:
        return HTMLResponse(f"{HEAD}<div class='container'><h2>Job not found</h2><a href='/'>Back</a></div>{FOOT}", status_code=404)

    is_done = job["status"] == "done"
    is_proc = job["status"] == "processing"
    content = ""
    if is_done:
        cp = os.path.join(JOBS_DIR, job_id, "output.md")
        if os.path.exists(cp):
            with open(cp) as f:
                content = f.read()

    sc = f"status-{job['status']}"
    pages = f"{job.get('pages_done', '?')}/{job.get('pages_total', '?')}"
    ts = f"{job.get('processing_time_seconds', '')}s" if job.get('processing_time_seconds') else ""
    err = job.get("error", "")
    err_html = f'<div class="card" style="border-color:#f85149;"><pre style="color:#f85149;background:transparent;border:none;">{err}</pre></div>' if err else ""

    # Process pages into rendered sections
    rendered = ""
    if is_done and content:
        import re
        pages_raw = content.split("<!-- page ")
        for section in pages_raw:
            m = re.match(r'(\d+)\s*-->\s*\n(.*)', section, re.DOTALL)
            if m:
                page_num = m.group(1)
                page_text = m.group(2).strip()
                rendered += f'<div class="page-sep">Page {page_num}</div>\n<div class="md-render" data-md="{page_text.replace(chr(34), "&#34;")[:50000]}"></div>\n'
            elif section.strip():
                rendered += f'<div class="md-render" data-md="{section.strip().replace(chr(34), "&#34;")[:50000]}"></div>\n'

    proc_html = ""
    if is_proc:
        proc_html = f"<p style=\"color:#d29922;\"><span class=\"spinner\"></span>Processing... <strong>{pages}</strong> pages</p>\n<script>setTimeout(function(){{window.location.reload()}},3000);</script>"

    return HTMLResponse(f"""{HEAD}
<div class="nav"><h1>{job['filename'][:60]}</h1><a href="/">← Documents</a></div>
<div class="container">
<div class="card"><dl class="meta-grid">
<dt>Status</dt><dd><span class="{sc}">{job['status']}</span></dd>
<dt>Engine</dt><dd><span class="engine-badge">{job.get('engine', ENGINE)}</span></dd>
<dt>Pages</dt><dd>{pages}</dd><dt>Time</dt><dd>{ts}</dd>
<dt>Uploaded</dt><dd>{job.get('created_at','')[:19]}</dd>
</dl>{proc_html}</div>
{err_html}
<div class="card"><h2>Extracted Text</h2>
<div class="md-content">{rendered if rendered else '<p style="color:#8b949e;">No content</p>'}</div></div></div>{FOOT}""")
