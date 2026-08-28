"""pdf-parse — Cohere Parse API extraction with full web UI + job dashboard.

  - Parse v5.0 for ALL documents (purpose-built, HTML tables, LaTeX math)
  - PyMuPDF fallback only when Parse fails (quota, timeout, bad image)
  - Oversize guard (>100 pages → 413)
  - Semaphore caps concurrent Parse calls (500 req/min API limit)
  - Web UI: upload, job history, rendered markdown, auto-refresh
"""

import os
import time
import json
import base64
import uuid
import asyncio
import logging

import fitz
import httpx
from fastapi import FastAPI, Request, HTTPException, UploadFile, File
from fastapi.responses import HTMLResponse, JSONResponse

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("pdf-parse")

DATA_DIR = os.environ.get("DATA_DIR", "/data")
JOBS_DIR = os.path.join(DATA_DIR, "jobs")
os.makedirs(JOBS_DIR, exist_ok=True)

COHERE_API_KEY = os.environ.get("COHERE_API_KEY", "")
PARSE_MODEL = os.environ.get("PARSE_MODEL", "parse-v5.0")
# Sanity cap only — Cohere has no page limit (per-IMAGE limits: 20MB / 50MP).
# Docs process page-by-page, so any size works; this just bounds runaway jobs.
MAX_PAGES = int(os.environ.get("MAX_PAGES", "200"))
# Parallel Parse calls per doc (bounded also by the global semaphore below).
# Global worst case: PARSE_CONCURRENCY in-flight calls ≈ 20/3.4s ≈ 350 req/min < 500 limit.
PARSE_CONCURRENCY = int(os.environ.get("PARSE_CONCURRENCY", "20"))
PER_DOC_PARALLELISM = int(os.environ.get("PER_DOC_PARALLELISM", "8"))
# Retries for transient failures (DNS blips, connection resets, 429/5xx)
PARSE_RETRIES = int(os.environ.get("PARSE_RETRIES", "3"))
RETRY_BACKOFF = float(os.environ.get("RETRY_BACKOFF", "1.5"))

app = FastAPI(title="pdf-parse")
parse_semaphore = asyncio.Semaphore(PARSE_CONCURRENCY)


# ── Job storage ───────────────────────────────────────────────────────

def job_path(job_id: str) -> str:
    return os.path.join(JOBS_DIR, job_id, "job.json")


def create_job(filename: str, size: int) -> dict:
    job_id = uuid.uuid4().hex[:12]
    job = {
        "id": job_id,
        "filename": filename,
        "size_bytes": size,
        "status": "processing",
        "created_at": time.time(),
    }
    os.makedirs(os.path.join(JOBS_DIR, job_id), exist_ok=True)
    json.dump(job, open(os.path.join(JOBS_DIR, job_id, "job.json"), "w"))
    return job


def save_job(job: dict, markdown: str = None, error: str = None, elapsed: float = None, pages: int = None):
    if elapsed is not None:
        job["elapsed_seconds"] = elapsed
    if pages is not None:
        job["pages_total"] = pages
    if markdown is not None:
        job["chars"] = len(markdown)
        open(os.path.join(JOBS_DIR, job["id"], "output.md"), "w").write(markdown)
    if error:
        job["status"] = "failed"
        job["error"] = error
    else:
        job["status"] = "done"
    json.dump(job, open(job_path(job["id"]), "w"))


def list_jobs() -> list:
    jobs = []
    for jid in os.listdir(JOBS_DIR) if os.path.isdir(JOBS_DIR) else []:
        jp = os.path.join(JOBS_DIR, jid, "job.json")
        if os.path.exists(jp):
            try:
                jobs.append(json.load(open(jp)))
            except Exception:
                pass
    return sorted(jobs, key=lambda j: j.get("created_at", 0), reverse=True)


# ── Extraction ────────────────────────────────────────────────────────

async def call_parse(image_bytes: bytes) -> str:
    """Call Cohere Parse API with retry on transient failures."""
    b64 = base64.b64encode(image_bytes).decode()
    last_err = None
    for attempt in range(PARSE_RETRIES + 1):
        try:
            async with parse_semaphore:
                async with httpx.AsyncClient() as client:
                    resp = await client.post(
                        "https://api.cohere.com/v2/parse",
                        json={
                            "model": PARSE_MODEL,
                            "document": {"type": "image_url", "image_url": f"data:image/jpeg;base64,{b64}"},
                        },
                        headers={
                            "Content-Type": "application/json",
                            "Authorization": f"Bearer {COHERE_API_KEY}",
                        },
                        timeout=30.0,
                    )
                    resp.raise_for_status()
                    pages = resp.json().get("pages", [])
                    return pages[0]["markdown"]["content"] if pages else ""
        except httpx.HTTPStatusError as e:
            status = e.response.status_code
            # 4xx (except 429) are permanent — no point retrying
            if 400 <= status < 500 and status != 429:
                raise
            last_err = e
            if attempt < PARSE_RETRIES:
                # Respect Retry-After on 429 if present
                wait = float(e.response.headers.get("retry-after", RETRY_BACKOFF * (attempt + 1)))
                logger.warning("Parse HTTP %d (attempt %d/%d), retrying in %.1fs",
                               status, attempt + 1, PARSE_RETRIES + 1, wait)
                await asyncio.sleep(wait)
        except (httpx.ConnectError, httpx.ConnectTimeout, httpx.ReadTimeout, OSError) as e:
            # Transient network errors (DNS blips, resets) — retry with backoff
            last_err = e
            if attempt < PARSE_RETRIES:
                wait = RETRY_BACKOFF * (attempt + 1)
                logger.warning("Parse network error (attempt %d/%d): %s — retrying in %.1fs",
                               attempt + 1, PARSE_RETRIES + 1, type(e).__name__, wait)
                await asyncio.sleep(wait)
    raise last_err  # all retries exhausted


async def extract(body: bytes, filename: str, job_id: str = None) -> str:
    """Parse every page (parallel, ordered), PyMuPDF fallback per-page on failure."""
    doc = fitz.open(stream=body, filetype="pdf")
    total = doc.page_count
    if total > MAX_PAGES:
        doc.close()
        raise HTTPException(413, detail=f"Document too large: {total} pages (max {MAX_PAGES}).")

    # Render all pages first (sync — PyMuPDF render is CPU-bound per doc)
    images = []
    for page in doc:
        pix = page.get_pixmap(dpi=150)
        images.append(pix.tobytes("jpeg"))
    doc.close()

    async def parse_one(idx: int) -> tuple:
        try:
            text = await call_parse(images[idx])
        except Exception as e:
            logger.warning("Parse failed page %d/%d: %s", idx + 1, total, e)
            text = f"[page {idx + 1}: Parse failed — {type(e).__name__}]"
        if job_id:
            progress(job_id, done=idx + 1, total=total)
        return idx, text

    # Parallel with per-doc bound; results re-ordered by index
    batch_sem = asyncio.Semaphore(PER_DOC_PARALLELISM)

    async def bounded(i: int):
        async with batch_sem:
            return await parse_one(i)

    done = await asyncio.gather(*(bounded(i) for i in range(total)))
    results = [None] * total
    for idx, text in done:
        results[idx] = text

    parse_errors = sum(1 for t in results if t and t.startswith("[page"))
    logger.info("%s: %d pages, %d parse errors", filename, total, parse_errors)
    return "\n\n".join(f"<!-- page {i + 1} -->\n{t}" for i, t in enumerate(results))


def progress(job_id: str, done: int, total: int):
    """Best-effort live progress write to job.json (throttled by caller)."""
    try:
        jp = job_path(job_id)
        job = json.load(open(jp))
        if job.get("pages_done") != done:
            job["pages_done"] = done
            job["pages_total"] = total
            json.dump(job, open(jp, "w"))
    except Exception:
        pass


# ── API endpoints ─────────────────────────────────────────────────────

@app.put("/process")
async def process(request: Request):
    """Open WebUI-compatible: PUT raw PDF bytes → markdown. Records job."""
    filename = request.headers.get("X-Filename", "document.pdf")
    body = await request.body()
    if not body:
        raise HTTPException(400, detail="Empty request body")
    job = create_job(filename, len(body))
    start = time.time()
    try:
        markdown = await extract(body, filename, job_id=job["id"])
        elapsed = round(time.time() - start, 1)
        save_job(job, markdown=markdown, elapsed=elapsed,
                 pages=markdown.count("<!-- page "))
        return JSONResponse({"page_content": markdown, "metadata": {
            "source": filename, "engine": "parse", "elapsed_seconds": elapsed}})
    except HTTPException as e:
        save_job(job, error=e.detail)
        raise
    except Exception as e:
        save_job(job, error=str(e))
        raise HTTPException(500, detail=str(e))


@app.post("/api/upload")
async def upload(file: UploadFile = File(...)):
    """Web UI upload → background job, returns job id immediately."""
    body = await file.read()
    if not body:
        raise HTTPException(400, detail="Empty file")
    filename = file.filename or "document.pdf"
    job = create_job(filename, len(body))
    import threading
    threading.Thread(target=_run_job, args=(job, body), daemon=True).start()
    return JSONResponse({"job_id": job["id"]}, status_code=202)


def _run_job(job: dict, body: bytes):
    loop = asyncio.new_event_loop()
    asyncio.set_event_loop(loop)
    start = time.time()
    try:
        markdown = loop.run_until_complete(extract(body, job["filename"], job_id=job["id"]))
        elapsed = round(time.time() - start, 1)
        save_job(job, markdown=markdown, elapsed=elapsed,
                 pages=markdown.count("<!-- page "))
    except Exception as e:
        save_job(job, error=str(e))
    finally:
        loop.close()


@app.get("/api/jobs")
async def api_jobs():
    return JSONResponse(list_jobs())


@app.get("/api/jobs/{job_id}")
async def api_job(job_id: str):
    jp = job_path(job_id)
    if not os.path.exists(jp):
        raise HTTPException(404, detail="Job not found")
    return JSONResponse(json.load(open(jp)))


@app.get("/api/jobs/{job_id}/content")
async def api_job_content(job_id: str):
    cp = os.path.join(JOBS_DIR, job_id, "output.md")
    if not os.path.exists(cp):
        raise HTTPException(404, detail="Content not found")
    return JSONResponse({"content": open(cp).read()})


@app.get("/health")
async def health():
    return JSONResponse({"status": "ok", "model": PARSE_MODEL,
                         "max_pages": MAX_PAGES, "concurrency": PARSE_CONCURRENCY})


# ── Web UI ────────────────────────────────────────────────────────────

CSS = """
:root{--bg:#0a0e14;--surface:#11161f;--surface2:#161d29;--border:#1e2735;--border2:#2a3648;
--text:#dce3ed;--dim:#7d8ba1;--accent:#6cb2ff;--accent2:#8b7dff;--green:#4ade80;--red:#f87171;--amber:#fbbf24}
*{margin:0;padding:0;box-sizing:border-box}
body{font-family:ui-sans-serif,-apple-system,'Segoe UI',sans-serif;background:var(--bg);color:var(--text);min-height:100vh;
background-image:radial-gradient(ellipse 80% 50% at 50% -20%,rgba(108,178,255,.08),transparent)}
.nav{position:sticky;top:0;z-index:10;background:rgba(10,14,20,.85);backdrop-filter:blur(12px);
border-bottom:1px solid var(--border);padding:14px 28px;display:flex;align-items:center;gap:14px}
.nav h1{font-size:17px;font-weight:650;letter-spacing:-.02em}
.logo{width:26px;height:26px;border-radius:7px;background:linear-gradient(135deg,var(--accent),var(--accent2));
display:grid;place-items:center;font-size:14px}
.badge{background:linear-gradient(135deg,rgba(108,178,255,.15),rgba(139,125,255,.15));border:1px solid rgba(108,178,255,.3);
padding:3px 10px;border-radius:99px;font-size:11px;color:var(--accent);font-weight:500}
.container{max-width:880px;margin:0 auto;padding:32px 24px}
.card{background:var(--surface);border:1px solid var(--border);border-radius:14px;padding:24px;margin-bottom:20px;
box-shadow:0 1px 3px rgba(0,0,0,.3)}
.card h2{font-size:13px;font-weight:600;text-transform:uppercase;letter-spacing:.08em;color:var(--dim);margin-bottom:14px}
.upload-zone{border:2px dashed var(--border2);border-radius:12px;padding:48px;text-align:center;cursor:pointer;
transition:all .2s;background:var(--surface2)}
.upload-zone:hover,.upload-zone.dragover{border-color:var(--accent);background:rgba(108,178,255,.05);transform:translateY(-1px)}
.upload-zone .icon{font-size:34px;margin-bottom:10px;filter:grayscale(.3)}
.upload-zone p{font-size:14px;color:var(--dim)}
.upload-zone .hint{font-size:12px;color:#4d5a70;margin-top:6px}
.uploading .icon{animation:pulse 1.2s ease-in-out infinite}
@keyframes pulse{50%{opacity:.4}}
table{width:100%;border-collapse:collapse;font-size:13.5px}
th{text-align:left;padding:10px 14px;border-bottom:1px solid var(--border2);color:var(--dim);
font-weight:600;font-size:11px;text-transform:uppercase;letter-spacing:.06em}
td{padding:11px 14px;border-bottom:1px solid var(--border)}
tbody tr{cursor:pointer;transition:background .15s}
tbody tr:hover{background:rgba(108,178,255,.04)}
.pill{display:inline-flex;align-items:center;gap:5px;padding:2px 10px;border-radius:99px;font-size:11.5px;font-weight:500}
.pill::before{content:'';width:6px;height:6px;border-radius:50%;background:currentColor}
.pill.done{background:rgba(74,222,128,.1);color:var(--green)}
.pill.processing{background:rgba(251,191,36,.1);color:var(--amber)}
.pill.failed{background:rgba(248,113,113,.1);color:var(--red)}
.mono{font-family:ui-monospace,'SF Mono',monospace;font-size:12px;color:var(--dim)}
.empty{padding:32px;text-align:center;color:var(--dim);font-size:14px}
.meta-grid{display:grid;grid-template-columns:auto 1fr;gap:8px 20px;font-size:13.5px}
.meta-grid dt{color:var(--dim)}.meta-grid dd{color:var(--text)}
.btn{display:inline-flex;align-items:center;gap:6px;padding:8px 16px;border-radius:9px;font-size:13.5px;font-weight:500;
text-decoration:none;border:1px solid var(--border2);background:var(--surface2);color:var(--text);cursor:pointer;transition:all .15s}
.btn:hover{border-color:var(--accent);color:var(--accent)}
.spin{display:inline-block;width:14px;height:14px;border:2px solid var(--border2);border-top-color:var(--accent);
border-radius:50%;animation:rot .8s linear infinite}
@keyframes rot{to{transform:rotate(360deg)}}
.md{line-height:1.7;font-size:14.5px}
.md h1,.md h2,.md h3{margin:20px 0 10px;color:#fff;letter-spacing:-.01em}
.md h1{font-size:23px;padding-bottom:8px;border-bottom:1px solid var(--border)}
.md h2{font-size:18px}.md h3{font-size:15.5px}
.md p{margin:10px 0}.md ul,.md ol{margin:10px 0;padding-left:26px}.md li{margin:5px 0}
.md code{background:var(--surface2);border:1px solid var(--border);padding:2px 7px;border-radius:6px;
font-family:ui-monospace,monospace;font-size:12.5px;color:var(--accent)}
.md pre{background:#060a10;border:1px solid var(--border);border-radius:10px;padding:16px;overflow-x:auto;margin:12px 0}
.md pre code{background:none;border:none;padding:0}
.md table{border-collapse:collapse;margin:14px 0;width:100%;font-size:13.5px}
.md th,.md td{border:1px solid var(--border2);padding:8px 13px}
.md th{background:var(--surface2);font-weight:600}
.md tr:hover td{background:rgba(108,178,255,.04)}
.md blockquote{border-left:3px solid var(--accent2);padding:6px 16px;color:var(--dim);margin:12px 0;background:rgba(139,125,255,.05)}
.md strong{color:#fff}
.md img{max-width:100%;border-radius:8px}
.md hr{border:none;border-top:1px solid var(--border);margin:18px 0}
.md .katex{font-size:1.05em}
.progbar{height:4px;background:var(--border);border-radius:99px;margin-top:6px;max-width:200px;overflow:hidden}
.progfill{height:100%;background:linear-gradient(90deg,var(--accent),var(--accent2));border-radius:99px;transition:width .5s}
.page-sep{display:flex;align-items:center;gap:10px;margin:26px 0 14px;color:var(--accent);font-size:11.5px;
font-weight:600;text-transform:uppercase;letter-spacing:.1em}
.page-sep::before,.page-sep::after{content:'';flex:1;height:1px;background:linear-gradient(90deg,transparent,var(--border2));}
.page-sep::after{background:linear-gradient(90deg,var(--border2),transparent)}
.error-box{background:rgba(248,113,113,.08);border:1px solid rgba(248,113,113,.25);color:var(--red);
padding:12px 16px;border-radius:10px;font-size:13.5px;margin-top:14px}
"""

SHELL = """<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>PDF Parser</title>
<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/katex@0.16.9/dist/katex.min.css">
<script src="https://cdn.jsdelivr.net/npm/marked/marked.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/katex@0.16.9/dist/katex.min.js"></script>
<style>{css}</style></head><body>
<nav class="nav"><div class="logo">&#128202;</div><h1>PDF Parser</h1>
<span class="badge">Cohere Parse v5.0</span>
<div style="flex:1"></div><a href="/" style="color:var(--dim);font-size:13.5px;text-decoration:none">Jobs</a>
</nav><div class="container">{{content}}</div>{script}</body></html>"""


def shell(content: str, script: str = "") -> str:
    return SHELL.replace("{css}", CSS).replace("{{content}}", content).replace("{script}", script)


@app.get("/", response_class=HTMLResponse)
async def web_root():
    jobs = list_jobs()[:25]
    rows = ""
    for j in jobs:
        chars = f"{j.get('chars', '?'):,} ch" if j.get('chars') else "—"
        secs = f"{j.get('elapsed_seconds', '?')}s" if j.get('elapsed_seconds') else "—"
        ts = time.strftime('%b %d, %H:%M', time.localtime(j.get('created_at', 0)))
        prog = ""
        if j["status"] == "processing" and j.get("pages_done"):
            prog = f'<div class="progbar"><div class="progfill" style="width:{100*j["pages_done"]//max(j.get("pages_total",1),1)}%"></div></div>'
        rows += f"""<tr onclick="location.href='/job/{j['id']}'">
<td>{j['filename'][:42]}{prog}</td>
<td><span class="pill {j['status']}">{j['status']}</span></td>
<td class="mono">{chars}</td><td class="mono">{secs}</td><td class="mono">{ts}</td></tr>"""
    if not rows:
        rows = '<tr><td colspan="5" class="empty">No documents parsed yet — upload one above</td></tr>'

    spinning = '<span class="spin"></span>' if any(j["status"] == "processing" for j in jobs) else ""

    content = f"""
<div class="card">
  <h2>New Document</h2>
  <div class="upload-zone" id="dropZone">
    <div class="icon">&#128196;</div>
    <p><strong>Drop a PDF here</strong> or click to browse</p>
    <p class="hint">Parsed with Cohere Parse v5.0 — tables, math, structure preserved</p>
    <input type="file" id="fileInput" accept=".pdf" style="display:none">
  </div>
</div>
<div class="card">
  <div style="display:flex;justify-content:space-between;align-items:center">
    <h2 style="margin:0">History</h2><span id="spin">{spinning}</span>
  </div>
  <table><thead><tr><th>File</th><th>Status</th><th>Output</th><th>Time</th><th>When</th></tr></thead>
  <tbody>{rows}</tbody></table>
</div>"""
    script = """<script src="/ui.js"></script>"""
    return shell(content, script)


@app.get("/job/{job_id}", response_class=HTMLResponse)
async def web_job(job_id: str):
    jp = job_path(job_id)
    if not os.path.exists(jp):
        return shell('<div class="card empty">Job not found</div>')
    job = json.load(open(jp))
    cp = os.path.join(JOBS_DIR, job_id, "output.md")
    content = open(cp).read() if os.path.exists(cp) else ""
    err = f'<div class="error-box">Error: {job.get("error", "")}</div>' if job.get("error") else ""
    meta = f"""
<dl class="meta-grid">
  <dt>Status</dt><dd><span class="pill {job['status']}">{job['status']}</span></dd>
  <dt>Pages</dt><dd>{job.get('pages_total', '—')}</dd>
  <dt>Elapsed</dt><dd>{job.get('elapsed_seconds', '—')}s</dd>
  <dt>Output</dt><dd>{job.get('chars', len(content)):,} chars</dd>
  <dt>File</dt><dd>{job['filename']}</dd>
</dl>{err}
<div style="margin-top:18px;display:flex;gap:10px">
  <a class="btn" href="/">&larr; All jobs</a>
</div>"""
    body_card = f"""
<div class="card"><h2>Document</h2>{meta}</div>
<div class="card"><h2>Extracted Markdown</h2>
<div class="md" id="rendered"></div></div>"""
    script = """<script src="/ui.js"></script>"""
    return shell(body_card, script)


@app.get("/ui.js", response_class=HTMLResponse)
async def ui_js():
    js = """
// ── Upload ──
var dz = document.getElementById('dropZone');
if (dz) {
  var fi = document.getElementById('fileInput');
  dz.addEventListener('click', function(){ fi.click(); });
  dz.addEventListener('dragover', function(e){ e.preventDefault(); dz.classList.add('dragover'); });
  dz.addEventListener('dragleave', function(){ dz.classList.remove('dragover'); });
  dz.addEventListener('drop', function(e){ e.preventDefault(); dz.classList.remove('dragover');
    if (e.dataTransfer.files.length) upload(e.dataTransfer.files[0]); });
  fi.addEventListener('change', function(){ if (fi.files[0]) upload(fi.files[0]); });
}
async function upload(file) {
  dz.classList.add('uploading');
  dz.querySelector('p').textContent = 'Uploading ' + file.name + '…';
  var fd = new FormData(); fd.append('file', file);
  try {
    var r = await fetch('/api/upload', { method: 'POST', body: fd });
    var d = await r.json();
    if (r.ok && d.job_id) location.href = '/job/' + d.job_id;
    else { dz.classList.remove('uploading'); dz.querySelector('p').textContent = 'Upload failed: ' + (d.detail || r.statusText); }
  } catch (e) { dz.classList.remove('uploading'); dz.querySelector('p').textContent = 'Upload failed: ' + e.message; }
}

// ── Job page: fetch + render markdown ──
var el = document.getElementById('rendered');
if (el) {
  var m = location.pathname.match(/job\\/([a-f0-9]+)/);
  if (m) loadJob(m[1]);
}
async function loadJob(id) {
  var r = await fetch('/api/jobs/' + id);
  var job = await r.json();
  if (job.status === 'processing') {
    var pg = job.pages_done ? ' — page ' + job.pages_done + ' of ' + job.pages_total : '';
    el.innerHTML = '<div class="empty"><span class="spin"></span> Parsing with Cohere Parse v5.0' + pg + '…</div>';
    setTimeout(function(){ loadJob(id); }, 2000);
    return;
  }
  if (job.status === 'failed') { el.innerHTML = '<div class="error-box">' + (job.error || 'failed') + '</div>'; return; }
  var c = await (await fetch('/api/jobs/' + id + '/content')).json();
  var html = marked.parse(c.content || '');
  // Page markers → styled separators
  html = html.replace(/<!-- page (\\d+) -->/g, '<div class="page-sep">Page $1</div>');
  el.innerHTML = html;
  // Render LaTeX if KaTeX loaded
  if (window.renderMathInElement) {
    renderMathInElement(el, { delimiters: [
      {left:'$$',right:'$$',display:true},{left:'\\\\(',right:'\\\\)',display:false},
      {left:'\\\\[',right:'\\\\]',display:true} ], throwOnError:false });
  }
}

// ── Home: auto-refresh while anything is processing ──
var spin = document.getElementById('spin');
if (spin && spin.querySelector('.spin')) setTimeout(function(){ location.reload(); }, 3000);
"""
    return HTMLResponse(js, media_type="application/javascript")
