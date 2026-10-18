"""pdf-parse — Cohere Parse API extraction with full web UI + job dashboard.

Architecture:
  - Parse v5.0 for ALL documents (purpose-built, HTML tables, LaTeX math)
  - Per-page: Parse → on failure → PyMuPDF fallback → only then "failed"
  - Oversize guard (>200 pages → 413)
  - Semaphore caps concurrent Parse calls (500 req/min API limit)
  - Retry with backoff (3 attempts for transient DNS/network/5xx)
  - Web UI: upload, job history, rendered markdown, auto-refresh
  - Per-page extraction status in API response metadata
"""

import os
import time
import json
import base64
import uuid
import asyncio
import logging

import fitz
import re
import html

import httpx
from fastapi import FastAPI, Request, HTTPException, UploadFile, File
from fastapi.responses import HTMLResponse, JSONResponse, Response

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("pdf-parse")

DATA_DIR = os.environ.get("DATA_DIR", "/data")
JOBS_DIR = os.path.join(DATA_DIR, "jobs")
os.makedirs(JOBS_DIR, exist_ok=True)

COHERE_API_KEY = os.environ.get("COHERE_API_KEY", "")
PARSE_MODEL = os.environ.get("PARSE_MODEL", "parse-v5.0")
MAX_PAGES = int(os.environ.get("MAX_PAGES", "200"))
PARSE_CONCURRENCY = int(os.environ.get("PARSE_CONCURRENCY", "20"))
PER_DOC_PARALLELISM = int(os.environ.get("PER_DOC_PARALLELISM", "8"))
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


def save_job(job: dict, markdown: str = None, error: str = None, elapsed: float = None,
             pages: int = None, page_results: list = None):
    if elapsed is not None:
        job["elapsed_seconds"] = elapsed
    if pages is not None:
        job["pages_total"] = pages
    if page_results is not None:
        job["page_results"] = page_results
        job["pages_extracted"] = sum(1 for p in page_results if p.get("engine") != "failed")
        job["pages_parse"] = sum(1 for p in page_results if p.get("engine") == "parse")
        job["pages_pymupdf"] = sum(1 for p in page_results if p.get("engine") == "pymupdf")
        job["all_pages_extracted"] = all(p.get("engine") != "failed" for p in page_results)
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
            if 400 <= status < 500 and status != 429:
                raise
            last_err = e
            if attempt < PARSE_RETRIES:
                wait = float(e.response.headers.get("retry-after", RETRY_BACKOFF * (attempt + 1)))
                logger.warning("Parse HTTP %d (attempt %d/%d), retrying in %.1fs",
                               status, attempt + 1, PARSE_RETRIES + 1, wait)
                await asyncio.sleep(wait)
        except (httpx.ConnectError, httpx.ConnectTimeout, httpx.ReadTimeout, OSError) as e:
            last_err = e
            if attempt < PARSE_RETRIES:
                wait = RETRY_BACKOFF * (attempt + 1)
                logger.warning("Parse network error (attempt %d/%d): %s — retrying in %.1fs",
                               attempt + 1, PARSE_RETRIES + 1, type(e).__name__, wait)
                await asyncio.sleep(wait)
    raise last_err


def pymupdf_page(doc, idx: int) -> str:
    """Extract text from a single page via PyMuPDF (fast, reliable, flat text)."""
    if idx < len(doc):
        text = doc[idx].get_text().strip()
        if text:
            return text
    return ""


async def extract(body: bytes, filename: str, job_id: str = None) -> tuple:
    """
    Extract every page: Parse → on failure → PyMuPDF fallback.
    Returns (markdown, page_results_list).
    page_results = [{page: 1, engine: "parse|pymupdf|failed", chars: N, error: "..."}]
    """
    doc = fitz.open(stream=body, filetype="pdf")
    total = doc.page_count
    if total > MAX_PAGES:
        doc.close()
        raise HTTPException(413, detail=f"Document too large: {total} pages (max {MAX_PAGES}).")

    # Render all pages to JPEG for Parse (sync — CPU-bound per doc)
    images = []
    for page in doc:
        pix = page.get_pixmap(dpi=150)
        images.append(pix.tobytes("jpeg"))

    # Parse every page (parallel)
    async def parse_one(idx: int) -> tuple:
        try:
            text = await call_parse(images[idx])
            if job_id:
                progress(job_id, done=idx + 1, total=total)
            return idx, "parse", text, None
        except Exception as e:
            logger.warning("Parse failed page %d/%d: %s — falling back to PyMuPDF", idx + 1, total, e)
            fallback = pymupdf_page(doc, idx)
            if job_id:
                progress(job_id, done=idx + 1, total=total)
            if fallback:
                return idx, "pymupdf", fallback, None  # fallback succeeded — no error
            return idx, "failed", f"[page {idx + 1}: Parse failed — {type(e).__name__}]", str(e)[:80]

    batch_sem = asyncio.Semaphore(PER_DOC_PARALLELISM)

    async def bounded(i):
        async with batch_sem:
            return await parse_one(i)

    done = await asyncio.gather(*(bounded(i) for i in range(total)))
    doc.close()

    # Re-order by index, collect page results
    results = [None] * total
    page_results = []
    for idx, engine, text, error in done:
        results[idx] = (engine, text)
        page_results.append({
            "page": idx + 1,
            "engine": engine,
            "chars": len(text) if text else 0,
            "error": error,
        })

    # Build clean markdown — status only in metadata, not in page content
    markdown = "\n\n".join(f"<!-- page {i + 1} -->\n{t}" for i, (_, t) in enumerate(results))
    # Cohere Parse emits tables as HTML; normalise to GFM pipe tables
    markdown = html_tables_to_markdown(markdown)

    # Summary
    n_parse = sum(1 for p in page_results if p["engine"] == "parse")
    n_fallback = sum(1 for p in page_results if p["engine"] == "pymupdf")
    n_failed = sum(1 for p in page_results if p["engine"] == "failed")
    logger.info("%s: %d pages — parse=%d fallback=%d failed=%d",
                filename, total, n_parse, n_fallback, n_failed)

    return markdown, page_results


def progress(job_id: str, done: int, total: int):
    try:
        jp = job_path(job_id)
        job = json.load(open(jp))
        if job.get("pages_done") != done:
            job["pages_done"] = done
            job["pages_total"] = total
            json.dump(job, open(jp, "w"))
    except Exception:
        pass


# ── Markdown cleanup ──────────────────────────────────────────────────

_INLINE_MD = [
    (re.compile(r'</?(?:b|strong)[^>]*>', re.I), '**'),
    (re.compile(r'</?(?:i|em)[^>]*>', re.I), '*'),
    (re.compile(r'</?code[^>]*>', re.I), '`'),
]
_BR_RE = re.compile(r'<br\s*/?>', re.I)
_TAG_RE = re.compile(r'<[^>]+>')


def _cell_text(raw: str) -> str:
    """HTML cell fragment -> single-line markdown text."""
    t = raw
    for pat, rep in _INLINE_MD:
        t = pat.sub(rep, t)
    t = _BR_RE.sub(' ', t)
    t = _TAG_RE.sub('', t)
    t = html.unescape(t)
    t = re.sub(r'\s+', ' ', t).strip()
    return t.replace('|', r'\|')


def html_tables_to_markdown(text: str) -> str:
    """Convert Cohere Parse's HTML tables to GFM pipe tables so output.md is
    genuine markdown. Idempotent — returns text unchanged when no tables."""
    if '<table' not in text.lower():
        return text

    def conv(m):
        rows = []
        for tr in re.findall(r'<tr[^>]*>(.*?)</tr>', m.group(0), re.S | re.I):
            cells = []
            for c in re.finditer(r'<t[hd]([^>]*)>(.*?)</t[hd]>', tr, re.S | re.I):
                span_m = re.search(r'colspan\s*=\s*"?([0-9]+)', c.group(1), re.I)
                cells.append(_cell_text(c.group(2)))
                if span_m:
                    cells.extend([''] * (int(span_m.group(1)) - 1))
            if cells:
                rows.append(cells)
        if not rows:
            return ''
        width = max(len(r) for r in rows)
        rows = [r + [''] * (width - len(r)) for r in rows]
        out = ['| ' + ' | '.join(rows[0]) + ' |',
               '| ' + ' | '.join(['---'] * width) + ' |']
        out += ['| ' + ' | '.join(r) + ' |' for r in rows[1:]]
        return '\n'.join(out)

    return re.sub(r'<table[^>]*>.*?</table>', conv, text, flags=re.S | re.I)


# ── API endpoints ─────────────────────────────────────────────────────

@app.put("/process")
async def process(request: Request):
    """Open WebUI-compatible: PUT raw PDF bytes → markdown + per-page status."""
    filename = request.headers.get("X-Filename", "document.pdf")
    body = await request.body()
    if not body:
        raise HTTPException(400, detail="Empty request body")
    job = create_job(filename, len(body))
    start = time.time()
    try:
        markdown, page_results = await extract(body, filename, job_id=job["id"])
        elapsed = round(time.time() - start, 1)
        save_job(job, markdown=markdown, elapsed=elapsed,
                 pages=len(page_results), page_results=page_results)
        return JSONResponse({
            "page_content": markdown,
            "metadata": {
                "source": filename,
                "engine": "parse",
                "elapsed_seconds": elapsed,
                "pages_total": len(page_results),
                "pages_parse": job.get("pages_parse", 0),
                "pages_pymupdf": job.get("pages_pymupdf", 0),
                "all_pages_extracted": job.get("all_pages_extracted", True),
                "page_results": page_results,
            },
        })
    except HTTPException as e:
        save_job(job, error=e.detail)
        raise
    except Exception as e:
        save_job(job, error=str(e))
        raise HTTPException(500, detail=str(e))


@app.post("/api/upload")
async def upload(file: UploadFile = File(...)):
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
        markdown, page_results = loop.run_until_complete(
            extract(body, job["filename"], job_id=job["id"]))
        elapsed = round(time.time() - start, 1)
        save_job(job, markdown=markdown, elapsed=elapsed,
                 pages=len(page_results), page_results=page_results)
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
    return JSONResponse({"content": html_tables_to_markdown(open(cp).read())})


@app.get("/api/jobs/{job_id}/download")
async def api_job_download(job_id: str):
    """Serve the extracted markdown as a file download."""
    jp = job_path(job_id)
    if not os.path.exists(jp):
        raise HTTPException(404, detail="Job not found")
    cp = os.path.join(JOBS_DIR, job_id, "output.md")
    if not os.path.exists(cp):
        raise HTTPException(404, detail="Content not found")
    job = json.load(open(jp))
    # Derive <name>.md from the original PDF filename, sanitized for the header
    base = os.path.splitext(os.path.basename(job.get("filename") or "document.pdf"))[0]
    safe = re.sub(r'[^A-Za-z0-9._-]', "_", base)[:100] or "document"
    md = html_tables_to_markdown(open(cp, encoding="utf-8").read())
    return Response(
        content=md.encode("utf-8"),
        media_type="text/markdown; charset=utf-8",
        headers={"Content-Disposition": f'attachment; filename="{safe}.md"'},
    )


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
.container{max-width:1000px;margin:0 auto;padding:36px 24px 64px}
.card{background:var(--surface);border:1px solid var(--border);border-radius:16px;padding:26px;margin-bottom:18px;
box-shadow:0 1px 2px rgba(0,0,0,.25),0 8px 24px -12px rgba(0,0,0,.4)}
.card h2{font-size:14px;font-weight:600;letter-spacing:-.01em;color:var(--text);margin-bottom:16px}
.upload-zone{border:1.5px dashed var(--border2);border-radius:12px;padding:40px 32px;text-align:center;cursor:pointer;
transition:border-color .15s,background .15s;background:transparent}
.upload-zone:hover,.upload-zone.dragover{border-color:var(--accent);background:rgba(108,178,255,.04)}
.upload-zone .icon{width:44px;height:44px;margin:0 auto 14px;border-radius:11px;display:grid;place-items:center;
background:var(--surface2);border:1px solid var(--border);font-size:19px;filter:none}
.upload-zone p{font-size:14.5px;color:var(--text)}
.upload-zone p strong{font-weight:600}
.upload-zone .hint{font-size:12.5px;color:var(--dim);margin-top:7px}
.upload-zone .cta{color:var(--accent);font-weight:500}
.uploading .icon{animation:pulse 1.2s ease-in-out infinite}
.uploading .hint{color:var(--accent)}
@keyframes pulse{50%{opacity:.4}}
table{width:100%;border-collapse:collapse;font-size:13.5px}
th{text-align:left;padding:0 12px 10px;border-bottom:1px solid var(--border);color:var(--dim);
font-weight:500;font-size:12px}
th:first-child,td:first-child{padding-left:2px}
td{padding:12px;border-bottom:1px solid var(--border);color:var(--text)}
tbody tr:last-child td{border-bottom:none}
tbody tr{cursor:pointer;transition:background .12s}
tbody tr:hover{background:rgba(108,178,255,.045)}
.pill{display:inline-flex;align-items:center;gap:5px;padding:2px 10px;border-radius:99px;font-size:11.5px;font-weight:500}
.pill::before{content:'';width:6px;height:6px;border-radius:50%;background:currentColor}
.pill.done{background:rgba(74,222,128,.1);color:var(--green)}
.pill.processing{background:rgba(251,191,36,.1);color:var(--amber)}
.pill.failed{background:rgba(248,113,113,.1);color:var(--red)}
.mono{font-family:ui-monospace,'SF Mono',monospace;font-size:12px;color:var(--dim)}
.empty{padding:32px;text-align:center;color:var(--dim);font-size:14px}
.meta-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));gap:18px 24px;font-size:14px}
.meta-grid dt{color:var(--dim);font-size:12px;margin-bottom:3px}
.meta-grid dd{color:var(--text);font-variant-numeric:tabular-nums;word-break:break-word}
.btn{display:inline-flex;align-items:center;gap:6px;padding:8px 16px;border-radius:9px;font-size:13.5px;font-weight:500;
text-decoration:none;border:1px solid var(--border2);background:var(--surface2);color:var(--text);cursor:pointer;transition:all .15s}
.btn:hover{border-color:var(--accent);color:var(--accent)}
.btn-sm{padding:4px 9px;font-size:12px;gap:0}
.btn-primary{background:var(--accent);border-color:var(--accent);color:#07101c;font-weight:600}
.btn-primary:hover{background:#8cc0ff;border-color:#8cc0ff;color:#07101c}
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
.progbar{height:3px;background:var(--border2);border-radius:99px;margin-top:7px;max-width:170px;overflow:hidden}
.progfill{height:100%;background:linear-gradient(90deg,var(--accent),var(--accent2));border-radius:99px;transition:width .5s}
.page-sep{display:flex;align-items:center;gap:10px;margin:26px 0 14px;color:var(--accent);font-size:11.5px;
font-weight:600;text-transform:uppercase;letter-spacing:.1em}
.page-sep::before,.page-sep::after{content:'';flex:1;height:1px;background:linear-gradient(90deg,transparent,var(--border2));}
.page-sep::after{background:linear-gradient(90deg,var(--border2),transparent)}
.error-box{background:rgba(248,113,113,.08);border:1px solid rgba(248,113,113,.25);color:var(--red);
padding:12px 16px;border-radius:10px;font-size:13.5px;margin-top:14px}
.warn-box{background:rgba(251,191,36,.08);border:1px solid rgba(251,191,36,.25);color:var(--amber);
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
        dl = (f'<a class="btn btn-sm" href="/api/jobs/{j["id"]}/download" download '
              f'title="Download markdown">&#8595;</a>') if j["status"] == "done" else '<span class="mono">—</span>'
        rows += f"""<tr onclick="location.href='/job/{j['id']}'">
<td>{j['filename'][:42]}{prog}</td>
<td><span class="pill {j['status']}">{j['status']}</span></td>
<td class="mono">{chars}</td><td class="mono">{secs}</td><td class="mono">{ts}</td>
<td class="mono" onclick="event.stopPropagation()">{dl}</td></tr>"""
    if not rows:
        rows = '<tr><td colspan="6" class="empty">No documents parsed yet — upload one above</td></tr>'
    spinning = '<span class="spin"></span>' if any(j["status"] == "processing" for j in jobs) else ""
    content = f"""
<div class="card">
  <h2>Upload a document</h2>
  <div class="upload-zone" id="dropZone">
    <div class="icon">&#128196;</div>
    <p>Drop a PDF here, or <span class="cta">browse</span></p>
    <p class="hint">Cohere Parse v5.0 &middot; tables, math, and structure preserved &middot; up to 200 pages</p>
    <input type="file" id="fileInput" accept=".pdf" style="display:none">
  </div>
</div>
<div class="card">
  <div style="display:flex;justify-content:space-between;align-items:center">
    <h2 style="margin:0">History</h2><span id="spin">{spinning}</span>
  </div>
  <table><thead><tr><th>File</th><th>Status</th><th>Output</th><th>Time</th><th>When</th><th></th></tr></thead>
  <tbody>{rows}</tbody></table>
</div>"""
    script = '<script src="/ui.js"></script>'
    return shell(content, script)


@app.get("/job/{job_id}", response_class=HTMLResponse)
async def web_job(job_id: str):
    jp = job_path(job_id)
    if not os.path.exists(jp):
        return shell('<div class="card empty">Job not found</div>')
    job = json.load(open(jp))
    cp = os.path.join(JOBS_DIR, job_id, "output.md")
    content = open(cp).read() if os.path.exists(cp) else ""
    err = ""
    if job.get("error"):
        err = f'<div class="error-box">Error: {job["error"]}</div>'
    prs = job.get("page_results", [])
    if prs:
        n_fb = sum(1 for p in prs if p["engine"] == "pymupdf")
        n_fail = sum(1 for p in prs if p["engine"] == "failed")
        if n_fb or n_fail:
            note = f"PyMuPDF fallback: {n_fb} pages" if n_fb else ""
            if n_fail:
                note = (note + " — " if note else "") + f"{n_fail} pages failed"
            err += f'<div class="warn-box">Extraction: {note}</div>'
    parse_ct = job.get("pages_parse", "")
    fallback_ct = job.get("pages_pymupdf", "")
    pages_dd = job.get('pages_total', '—')
    if fallback_ct:
        pages_dd += f'<span class="mono"> (parse: {parse_ct}, fallback: {fallback_ct})</span>'
    download_btn = ""
    if content:
        download_btn = (f'<a class="btn btn-primary" href="/api/jobs/{job_id}/download" download>\n'
                        f'    &#8595; Download markdown</a>')
    meta = f"""
<dl class="meta-grid">
  <dt>Status</dt><dd><span class="pill {job['status']}">{job['status']}</span></dd>
  <dt>Pages</dt><dd>{pages_dd}</dd>
  <dt>Elapsed</dt><dd>{job.get('elapsed_seconds', '—')}s</dd>
  <dt>Output</dt><dd>{job.get('chars', len(content)):,} chars</dd>
  <dt>File</dt><dd>{job['filename']}</dd>
</dl>{err}
<div style="margin-top:20px;display:flex;gap:10px">
  {download_btn}
  <a class="btn" href="/">&larr; All jobs</a>
</div>"""
    body_card = f"""
<div class="card"><h2>Document</h2>{meta}</div>
<div class="card"><h2>Extracted markdown</h2>
<div class="md" id="rendered"></div></div>"""
    script = '<script src="/ui.js"></script>'
    return shell(body_card, script)


@app.get("/ui.js", response_class=HTMLResponse)
async def ui_js():
    return HTMLResponse("""
// Upload
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
  var hint = dz.querySelector('.hint');
  if (hint) hint.textContent = 'Uploading ' + file.name + '\u2026';
  var fd = new FormData(); fd.append('file', file);
  try {
    var r = await fetch('/api/upload', { method: 'POST', body: fd });
    var d = await r.json();
    if (r.ok && d.job_id) { if (hint) hint.textContent = 'Uploaded \u2014 parsing\u2026'; return; }
    else { dz.classList.remove('uploading'); hint.textContent = 'Upload failed: ' + (d.detail || r.statusText); }
  } catch (e) { dz.classList.remove('uploading'); hint.textContent = 'Upload failed: ' + e.message; }
}

// Job page
var el = document.getElementById('rendered');
if (el) {
  var m = location.pathname.match(/job\\/([a-f0-9]+)/);
  if (m) loadJob(m[1]);
}
async function loadJob(id) {
  var r = await fetch('/api/jobs/' + id);
  var job = await r.json();
  if (job.status === 'processing') {
    var pg = job.pages_done ? ' \\u2014 page ' + job.pages_done + ' of ' + job.pages_total : '';
    el.innerHTML = '<div class="empty"><span class="spin"></span> Parsing' + pg + '\\u2026</div>';
    setTimeout(function(){ loadJob(id); }, 2000);
    return;
  }
  if (job.status === 'failed') { el.innerHTML = '<div class="error-box">' + (job.error || 'failed') + '</div>'; return; }
  var c = await (await fetch('/api/jobs/' + id + '/content')).json();
  var html = marked.parse(c.content || '');
  html = html.replace(/<!-- page (\\d+) -->/g, '<div class="page-sep">Page $1</div>');
  el.innerHTML = html;
  if (window.renderMathInElement) {
    renderMathInElement(el, { delimiters: [
      {left:'$$',right:'$$',display:true},{left:'\\\\(',right:'\\\\)',display:false},
      {left:'\\\\[',right:'\\\\]',display:true} ], throwOnError:false });
  }
}

// Auto-refresh while processing
var spin = document.getElementById('spin');
if (spin && spin.querySelector('.spin')) setTimeout(function(){ location.reload(); }, 3000);
""", media_type="application/javascript")
