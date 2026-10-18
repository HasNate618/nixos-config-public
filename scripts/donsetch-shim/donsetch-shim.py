#!/usr/bin/env python3
"""HTTP shim for donsetch (CLI -> HTTP for Trawl).

donsetch cannot run inside the Trawl container (NixOS glibc/linker mismatch),
so it runs on the host and is exposed here. Trawl's `local` backend calls
GET http://donsetch-shim:8899/search?q=... and gets trawl-normalized JSON.

Concurrency: donsetch fans out to 10+ keyless engines per query. Running many
queries at once overloads the resolver and the engines, which shows up as
DNS timeouts and SILENTLY EMPTY result sets. A bounded semaphore keeps the
in-flight query count at MAX_CONCURRENCY so overnight agent runs degrade
gracefully instead of returning blanks.

Observability: every response carries ok / weak / error / engines / elapsed_ms,
and GET /health reports semaphore state. Callers must NOT treat an empty
results list as "the web has nothing" without checking these signals.
"""
import json
import os
import re
import subprocess
import threading
import time
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

DONSEK = "/opt/donsetch/donsetch"
LINKER = "/nix/store/qqiqd3ah10x8hzsif4j1y4xc1miw23nx-glibc-2.42-67/lib/ld-linux-x86-64.so.2"
LIB = "/nix/store/qqiqd3ah10x8hzsif4j1y4xc1miw23nx-glibc-2.42-67/lib"
PORT = int(os.environ.get("DONSHIM_PORT", "8899"))

# Bounded concurrency: caps simultaneous donsetch processes (and therefore
# simultaneous engine fan-out + DNS load).
MAX_CONCURRENCY = int(os.environ.get("DONSHIM_MAX_CONCURRENCY", "2"))
# How long a request waits for a slot before returning an overloaded error.
SEM_WAIT_SECS = float(os.environ.get("DONSHIM_SEM_WAIT", "120"))
# Hard wall-clock budget handed to donsetch itself (bounds the latency tail).
DEADLINE_MS = int(os.environ.get("DONSHIM_DEADLINE_MS", "20000"))
# Subprocess timeout: deadline + slack for startup/teardown.
PROC_TIMEOUT = DEADLINE_MS / 1000.0 + 20
MAX_ATTEMPTS = int(os.environ.get("DONSHIM_MAX_ATTEMPTS", "2"))

# donsetch exit codes: 0 ok, 1 permanent, 2 transient (retry), 3 walled.
TRANSIENT_EXIT = 2

_SEM = threading.BoundedSemaphore(MAX_CONCURRENCY)
_INFLIGHT = 0
_INFLIGHT_LOCK = threading.Lock()


def _domain(url: str) -> str:
    from urllib.parse import urlparse
    try:
        h = urlparse(url).hostname or ""
        return h[4:] if h.startswith("www.") else h
    except Exception:
        return ""


def _run_once(query: str, max_results: int) -> dict:
    """One donsetch invocation. Returns parsed envelope or an error dict."""
    try:
        proc = subprocess.run(
            [LINKER, DONSEK, "search", query, "--max-results", str(max_results),
             "--deadline-ms", str(DEADLINE_MS), "--json"],
            capture_output=True, text=True,
            env={"LD_LIBRARY_PATH": LIB, "PATH": "/usr/bin:/bin"},
            timeout=PROC_TIMEOUT,
        )
    except subprocess.TimeoutExpired:
        return {"_err": "timeout", "_transient": True}

    out = proc.stdout or ""
    rc = proc.returncode

    m = re.search(r'\{"content".*\}\s*$', out, re.DOTALL)
    if not m:
        # No envelope: only worth retrying if donsetch called itself transient.
        return {"_err": "no_envelope_rc%d" % rc, "_transient": rc == TRANSIENT_EXIT}
    try:
        env = json.loads(m.group(0))
    except json.JSONDecodeError:
        return {"_err": "json_decode", "_transient": rc == TRANSIENT_EXIT}

    meta = env.get("meta", {})
    results = []
    for r in meta.get("results", []):
        results.append({
            "title": r.get("title", ""),
            "url": r.get("url", ""),
            "snippet": r.get("snippet", ""),
            "source": ",".join(r.get("engines", [])) or "donsetch",
            "score": r.get("score", 0),
            "domain": _domain(r.get("url", "")),
        })
    return {
        "ok": env.get("ok", False),
        "weak": meta.get("weak", False),
        "engines": [
            {"engine": e.get("engine"), "egress": e.get("egress"),
             "status": e.get("status")}
            for e in meta.get("engines", [])
        ],
        "results": results,
        "_err": None if results else "empty",
        "_transient": False,
    }


def _run_search(query: str, max_results: int = 8) -> dict:
    """Bounded-concurrency donsetch search with transient-only retry."""
    global _INFLIGHT
    t0 = time.time()

    if not _SEM.acquire(timeout=SEM_WAIT_SECS):
        return {"ok": False, "weak": True, "error": "overloaded",
                "engines": [], "results": [],
                "elapsed_ms": int((time.time() - t0) * 1000)}
    try:
        with _INFLIGHT_LOCK:
            _INFLIGHT += 1
        for attempt in range(1, MAX_ATTEMPTS + 1):
            res = _run_once(query, max_results)
            if res.get("_err") is None:
                break
            if not res.get("_transient") or attempt == MAX_ATTEMPTS:
                break
            time.sleep(0.5)
    finally:
        with _INFLIGHT_LOCK:
            _INFLIGHT -= 1
        _SEM.release()

    err = res.get("_err")
    return {
        "ok": res.get("ok", False),
        "weak": res.get("weak", True),
        "error": err,
        # An empty list with error set means the shim FAILED; callers must
        # escalate to another backend rather than report "no results".
        "engines": res.get("engines", []),
        "results": res.get("results", []),
        "elapsed_ms": int((time.time() - t0) * 1000),
    }


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)

        if parsed.path == "/health":
            with _INFLIGHT_LOCK:
                inflight = _INFLIGHT
            self._json(200, {
                "status": "ok",
                "inflight": inflight,
                "max_concurrency": MAX_CONCURRENCY,
                "deadline_ms": DEADLINE_MS,
            })
            return

        if parsed.path != "/search":
            self._json(404, {"error": "not found"})
            return

        qs = urllib.parse.parse_qs(parsed.query)
        q = (qs.get("q") or qs.get("query") or [""])[0]
        try:
            mr = int((qs.get("max_results") or ["8"])[0])
        except ValueError:
            mr = 8
        if not q:
            self._json(400, {"error": "missing q"})
            return

        data = _run_search(q, mr)
        self._json(200, data)

    def _json(self, code, obj):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    print("donsetch-shim listening on 0.0.0.0:%d (max_concurrency=%d, deadline=%dms)"
          % (PORT, MAX_CONCURRENCY, DEADLINE_MS), flush=True)
    srv = ThreadingHTTPServer(("0.0.0.0", PORT), Handler)
    srv.daemon_threads = True
    srv.serve_forever()
