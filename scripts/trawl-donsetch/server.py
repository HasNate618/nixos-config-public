"""
trawl — MCP server that bundles web search + content extraction.

Tools:
  search            — Search the web (SearXNG or DeGoog)
  read              — Extract clean markdown from a URL via crawl4ai
  search_and_read   — Search + auto-crawl top results
  screenshot        — Full-page screenshot of a URL
  query_screenshot  — Screenshot + vision LLM answer a question about the page
  map               — Discover all links on a page
"""

import os
import time
import base64
import asyncio
from typing import Optional
from urllib.parse import urlparse

import httpx
from mcp import types
from mcp.server.fastmcp import FastMCP

# ---------------------------------------------------------------------------
# Config from env
# ---------------------------------------------------------------------------
SEARCH_BACKEND = os.environ.get("SEARCH_BACKEND", "exa")  # "exa" | "donsetch" | "searxng" | "degoog"
DEGOOG_URL = os.environ.get("DEGOOG_URL", "http://degoog:4444/degoog/api")
SEARXNG_URL = os.environ.get("SEARXNG_URL", "http://searxng:8080")
CRAWL4AI_URL = os.environ.get("CRAWL4AI_URL", "http://crawl4ai:11235")
CRAWL4AI_API_TOKEN = os.environ.get("CRAWL4AI_API_TOKEN", "")
FLARESOLVERR_URL = os.environ.get("FLARESOLVERR_URL", "http://byparr:8191")
GLUETUN_PROXY = os.environ.get("GLUETUN_PROXY", "http://gluetun:8888")
BIFROST_URL = os.environ.get("BIFROST_URL", "http://bifrost:8080/v1")
VISION_MODEL = os.environ.get("VISION_MODEL", "cohere/command-a-vision-07-2025")
DONSEETCH_URL = os.environ.get("DONSEETCH_URL", "http://donsetch-shim:8899")
EXA_API_KEY = os.environ.get("EXA_API_KEY", "")

# Multi-key failover for Exa. EXA_API_KEYS is a comma-separated pool; keys are
# tried in order and a key that reports 402 / NO_MORE_CREDITS is put in cooldown
# so it stops costing a round trip. Each Exa free-tier account gets $10/month
# (resets on the 1st), so a pool of keys roughly multiplies the monthly budget.
# Cooldown is a probe interval, not a hard ban: a 402 is not billed, so
# re-testing a cooled key later is free and picks up a monthly top-up.
EXA_API_KEYS = os.environ.get("EXA_API_KEYS", "")
EXA_KEY_COOLDOWN = float(os.environ.get("EXA_KEY_COOLDOWN", "1800"))
_exa_cooldown_until: dict = {}


def _exa_keys() -> list:
    """Ordered pool of Exa keys. EXA_API_KEYS wins; EXA_API_KEY is the fallback."""
    raw = EXA_API_KEYS or EXA_API_KEY
    return [k.strip() for k in raw.split(",") if k.strip()]


def _exa_available_keys() -> list:
    """Keys not currently in cooldown, in preference order."""
    now = time.time()
    return [k for k in _exa_keys() if _exa_cooldown_until.get(k, 0) <= now]


def _exa_mark_exhausted(key: str) -> None:
    _exa_cooldown_until[key] = time.time() + EXA_KEY_COOLDOWN


def _exa_clear(key: str) -> None:
    _exa_cooldown_until.pop(key, None)
EXA_SEARCH_TYPE = os.environ.get("EXA_SEARCH_TYPE", "auto")  # keyword | neural | auto
EXA_NUM_RESULTS = int(os.environ.get("EXA_NUM_RESULTS", "5"))
REQUEST_TIMEOUT = float(os.environ.get("REQUEST_TIMEOUT", "30"))
# When the keyless local (donsetch) backend returns nothing, escalate to Exa so
# an unattended run never silently proceeds on "no results". Exa credits are
# spent only on that failure path. Set LOCAL_FALLBACK_EXA=0 to disable.
LOCAL_FALLBACK_EXA = os.environ.get("LOCAL_FALLBACK_EXA", "1").lower() not in ("0", "false", "no")

# ---------------------------------------------------------------------------
# MCP server
# ---------------------------------------------------------------------------
mcp = FastMCP(
    "trawl", host="0.0.0.0",
    instructions=(
        "Web search and content extraction tools. "
        "Use 'search' to find pages, 'read' to extract markdown from a URL, "
        "'search_and_read' to do both in one call, 'screenshot' for visual "
        "capture, 'query_screenshot' to ask a question about a page's "
        "visual content, and 'map' to discover all links on a page."
    ),
)

# Shared async HTTP client (connection pooling)
_client: Optional[httpx.AsyncClient] = None


async def get_client() -> httpx.AsyncClient:
    global _client
    if _client is None or _client.is_closed:
        _c4a_headers = {"Authorization": f"Bearer {CRAWL4AI_API_TOKEN}"} if CRAWL4AI_API_TOKEN else {}
        _client = httpx.AsyncClient(timeout=REQUEST_TIMEOUT, headers=_c4a_headers)
    return _client


def _extract_domain(url: str) -> str:
    """Extract domain from URL, stripping www. prefix."""
    try:
        host = urlparse(url).hostname or ""
        return host[4:] if host.startswith("www.") else host
    except Exception:
        return ""


def _dedup_results(results: list[dict]) -> list[dict]:
    """Remove duplicate URLs from results, keeping the first occurrence."""
    seen = set()
    deduped = []
    for r in results:
        url = r.get("url", "")
        # Normalize: strip trailing slash, fragment
        normalized = url.rstrip("/").split("#")[0]
        if normalized not in seen:
            seen.add(normalized)
            deduped.append(r)
    return deduped


def _filter_by_domains(
    results: list[dict],
    include: Optional[list[str]] = None,
    exclude: Optional[list[str]] = None,
) -> list[dict]:
    """Filter results by domain inclusion/exclusion lists."""
    if not include and not exclude:
        return results

    filtered = []
    for r in results:
        domain = _extract_domain(r.get("url", ""))

        if include:
            # Include only if domain matches any in the list
            if not any(d in domain or domain.endswith("." + d) for d in include):
                continue

        if exclude:
            # Exclude if domain matches any in the list
            if any(d in domain or domain.endswith("." + d) for d in exclude):
                continue

        filtered.append(r)

    return filtered


def _is_cloudflare_error(error: Exception) -> bool:
    """Check if an error is a Cloudflare challenge."""
    msg = str(error).lower()
    return any(s in msg for s in [
        "403", "503", "cloudflare", "challenge", "blocked",
        "anti-bot", "forbidden", "bad gateway",
    ])


async def _solve_cloudflare(url: str) -> Optional[dict]:
    """Use FlareSolverr to solve a Cloudflare challenge and return cookies + UA."""
    try:
        async with httpx.AsyncClient(timeout=90) as fs:
            resp = await fs.post(
                f"{FLARESOLVERR_URL}/v1",
                json={"cmd": "request.get", "url": url, "maxTimeout": 60000},
            )
            data = resp.json()
            if data.get("status") == "ok" and data.get("solution"):
                return {
                    "cookies": data["solution"].get("cookies", []),
                    "userAgent": data["solution"].get("userAgent", ""),
                }
    except Exception:
        pass
    return None


async def _crawl_with_retry(
    client: httpx.AsyncClient,
    url: str,
    mode: str = "fit",
    query: Optional[str] = None,
    max_retries: int = 1,
    cf_cookies: Optional[list] = None,
    cf_ua: Optional[str] = None,
) -> dict:
    """Crawl with retry and Cloudflare bypass via FlareSolverr."""
    payload = {"url": url, "f": mode}
    if query:
        payload["q"] = query
    if cf_cookies:
        payload["cookies"] = cf_cookies
    # Route crawls through gluetun (NordVPN) so sites see VPN IP, not homelab IP
    payload["crawler_config"] = {
        "proxy": {"server": GLUETUN_PROXY}
    }
    headers = {}
    if cf_ua:
        headers["User-Agent"] = cf_ua
    last_error = None
    for attempt in range(max_retries + 1):
        try:
            resp = await client.post(f"{CRAWL4AI_URL}/md", json=payload, headers=headers)
            resp.raise_for_status()
            data = resp.json()
            return {
                "markdown": data.get("markdown", data.get("result", "")),
                "success": True,
                "metadata": {
                    "title": data.get("title", ""),
                    "filter": data.get("filter", mode),
                    "cached": data.get("cache", "0") != "0",
                },
            }
        except Exception as e:
            last_error = e
            if attempt < max_retries:
                await asyncio.sleep(1 * (attempt + 1))  # backoff: 1s, 2s
    # If Cloudflare error and no CF cookies yet, try FlareSolverr
    if not cf_cookies and last_error and _is_cloudflare_error(last_error):
        cf = await _solve_cloudflare(url)
        if cf and cf["cookies"]:
            return await _crawl_with_retry(
                client, url, mode, query, max_retries=0,
                cf_cookies=cf["cookies"], cf_ua=cf["userAgent"],
            )

    return {
        "markdown": f"[crawl failed after {max_retries + 1} attempts: {last_error}]",
        "success": False,
        "metadata": {"error": str(last_error)},
    }


# ---------------------------------------------------------------------------
# Tool: search
# ---------------------------------------------------------------------------
async def _search_exa(query: str, max_results: int,
                      allow_donsetch_fallback: bool = True) -> list[dict]:
    """Search via Exa with multi-key failover.

    Tries each key in the pool until one answers. A key that returns 402 /
    NO_MORE_CREDITS is cooled down and the next key is tried, so a drained key
    never blocks a search and the spare is consumed only when needed.
    Falls back to donsetch if every key fails or the query returns nothing.
    """
    keys = _exa_available_keys()
    raw = []
    used_key = None
    for key in keys:
        try:
            async with httpx.AsyncClient(timeout=REQUEST_TIMEOUT) as c:
                resp = await c.post(
                    "https://api.exa.ai/search",
                    headers={"Authorization": f"Bearer {key}"},
                    json={
                        "query": query,
                        "type": EXA_SEARCH_TYPE,
                        "numResults": max_results,
                        "contents": {"text": False, "highlights": True, "maxAgeHours": -1},
                    },
                )
                if resp.status_code == 402 or "NO_MORE_CREDITS" in resp.text:
                    _exa_mark_exhausted(key)
                    continue
                resp.raise_for_status()
                raw = resp.json().get("results", [])
                used_key = key
                _exa_clear(key)
                break
        except Exception:
            continue
    results = []
    for r in raw:
        hl = r.get("highlights") or []
        results.append({
            "title": r.get("title", ""),
            "url": r.get("url", ""),
            "snippet": hl[0] if hl else r.get("text", "")[:200],
            "source": "exa",
            "score": r.get("score", 0),
            "domain": _extract_domain(r.get("url", "")),
            "key": f"exa-{_exa_keys().index(used_key) + 1}" if used_key else "exa",
        })
    if not results and allow_donsetch_fallback:
        results, _diag = await _search_donsetch(query, max_results)
    return results


async def _search_donsetch(query: str, max_results: int) -> tuple[list[dict], dict]:
    """Search via donsetch shim (keyless multi-engine fusion).

    Returns (results, diagnostics). An EMPTY results list means the local
    backend failed or found nothing — the shim never reports blank as success,
    so callers must inspect diagnostics before treating emptiness as an answer.
    """
    diag = {"ok": False, "weak": True, "error": "unreachable", "engines": []}
    try:
        async with httpx.AsyncClient(timeout=REQUEST_TIMEOUT) as c:
            resp = await c.get(
                f"{DONSEETCH_URL}/search",
                params={"q": query, "max_results": max_results},
            )
            resp.raise_for_status()
            data = resp.json()
    except Exception as exc:
        diag["error"] = "shim_call_failed: %s" % type(exc).__name__
        return [], diag

    for key in ("ok", "weak", "error", "engines", "elapsed_ms"):
        if key in data:
            diag[key] = data[key]
    results = []
    for r in data.get("results", []):
        results.append({
            "title": r.get("title", ""),
            "url": r.get("url", ""),
            "snippet": r.get("snippet", ""),
            "source": r.get("source", "donsetch"),
            "score": r.get("score", 0),
            "domain": r.get("domain", _extract_domain(r.get("url", ""))),
        })
    return results, diag


@mcp.tool()
async def search(
    query: str,
    max_results: int = 8,
    include_domains: Optional[list[str]] = None,
    exclude_domains: Optional[list[str]] = None,
    backend: str = "auto",
) -> list[dict]:
    """Search the web.

    Args:
        query: Search query string
        max_results: Maximum number of results to return (default 8)
        include_domains: Only return results from these domains
                         (e.g. ["linkedin.com", "indeed.com"])
        exclude_domains: Exclude results from these domains
                         (e.g. ["reddit.com", "pinterest.com"])
        backend: "auto" (use server default, exa), "local" (private: donsetch,
                 keyless, no third-party API), or "exa" (general web via Exa API).
                 Use "local" for personal/private queries you don't want sent to
                 any external API. "local" automatically escalates to Exa when
                 donsetch returns nothing, so an empty list is a real absence of
                 results, not a silent backend failure.

    Returns:
        List of results with title, url, snippet, source, score, and domain.
    """
    client = await get_client()

    # Resolve effective backend: explicit param overrides env default
    eff = backend if backend in ("local", "exa", "searxng", "degoog") else SEARCH_BACKEND
    if eff == "local":
        results, local_diag = await _search_donsetch(query, max_results)
        # Local returned nothing: escalate to Exa instead of handing the agent a
        # silent blank. See LOCAL_FALLBACK_EXA.
        if not results and LOCAL_FALLBACK_EXA and _exa_keys():
            results = await _search_exa(query, max_results, allow_donsetch_fallback=False)
            for r in results:
                r["fallback"] = "exa_after_local_empty"
    elif eff == "exa":
        results = await _search_exa(query, max_results)
    elif eff == "searxng":
        resp = await client.get(
            f"{SEARXNG_URL}/search",
            params={"q": query, "format": "json"},
        )
        resp.raise_for_status()
        data = resp.json()
        raw_results = data.get("results", [])

        # Normalize SearXNG results to trawl format
        results = []
        for r in raw_results:
            results.append({
                "title": r.get("title", ""),
                "url": r.get("url", ""),
                "snippet": r.get("content", ""),
                "source": ", ".join(r.get("engines", [])),
                "score": r.get("score", 0),
                "domain": _extract_domain(r.get("url", "")),
            })
    else:
        # DeGoog backend
        resp = await client.get(
            f"{DEGOOG_URL}/search",
            params={"q": query},
        )
        resp.raise_for_status()
        data = resp.json()
        results = data.get("results", [])

        # Enrich with domain
        for r in results:
            r["domain"] = _extract_domain(r.get("url", ""))

    # Deduplicate
    results = _dedup_results(results)

    # Filter by domains
    results = _filter_by_domains(results, include_domains, exclude_domains)

    # Limit
    results = results[:max_results]

    return [
        {
            "title": r.get("title", ""),
            "url": r.get("url", ""),
            "snippet": r.get("snippet", ""),
            "source": r.get("source", ""),
            "score": r.get("score", 0),
            "domain": r.get("domain", ""),
            **({"fallback": r["fallback"]} if r.get("fallback") else {}),
        }
        for r in results
    ]


# ---------------------------------------------------------------------------
# Tool: read
# ---------------------------------------------------------------------------
@mcp.tool()
async def read(
    url: str,
    mode: str = "fit",
    query: Optional[str] = None,
) -> dict:
    """Extract clean markdown content from a URL via crawl4ai.

    Args:
        url: The URL to extract content from
        mode: Extraction mode — 'fit' (readability, default), 'raw' (full DOM),
              'bm25' (relevance-filtered, requires query)
        query: Optional query for bm25 mode filtering

    Returns:
        Dict with url, markdown content, metadata, and success status.
    """
    client = await get_client()
    result = await _crawl_with_retry(client, url, mode, query)

    return {
        "url": url,
        "markdown": result["markdown"],
        "success": result["success"],
        "metadata": result.get("metadata", {}),
    }


# ---------------------------------------------------------------------------
# Tool: search_and_read
# ---------------------------------------------------------------------------
@mcp.tool()
async def search_and_read(
    query: str,
    max_results: int = 3,
    mode: str = "fit",
    include_domains: Optional[list[str]] = None,
    exclude_domains: Optional[list[str]] = None,
    backend: str = "auto",
) -> list[dict]:
    """Search the web and automatically extract markdown from top results.

    Combines search (SearXNG, DeGoog, or donsetch) with crawl4ai content extraction in one call.
    Results are fetched in parallel for speed.

    Args:
        query: Search query string
        max_results: Number of top results to crawl (default 3)
        mode: Extraction mode for crawl4ai — 'fit', 'raw', 'bm25'
        include_domains: Only crawl results from these domains
        exclude_domains: Exclude results from these domains
        backend: "auto" (server default), "local" (private/donsetch), or "exa" (general).
                 "local" escalates to Exa when donsetch returns nothing.

    Returns:
        List of results with title, url, snippet, and extracted markdown.
    """
    # Step 1: search
    client = await get_client()

    eff = backend if backend in ("local", "exa", "searxng", "degoog") else SEARCH_BACKEND
    if eff == "local":
        results, _diag = await _search_donsetch(query, max_results)
        if not results and LOCAL_FALLBACK_EXA and _exa_keys():
            results = await _search_exa(query, max_results, allow_donsetch_fallback=False)
            for r in results:
                r["fallback"] = "exa_after_local_empty"
    elif eff == "exa":
        results = await _search_exa(query, max_results)
    elif SEARCH_BACKEND == "searxng":
        resp = await client.get(
            f"{SEARXNG_URL}/search",
            params={"q": query, "format": "json"},
        )
        resp.raise_for_status()
        data = resp.json()
        raw_results = data.get("results", [])

        # Normalize SearXNG results to trawl format
        results = []
        for r in raw_results:
            results.append({
                "title": r.get("title", ""),
                "url": r.get("url", ""),
                "snippet": r.get("content", ""),
                "source": ", ".join(r.get("engines", [])),
                "score": r.get("score", 0),
                "domain": _extract_domain(r.get("url", "")),
            })
    else:
        # DeGoog backend
        resp = await client.get(
            f"{DEGOOG_URL}/search",
            params={"q": query},
        )
        resp.raise_for_status()
        data = resp.json()
        results = data.get("results", [])

        # Enrich with domain
        for r in results:
            r["domain"] = _extract_domain(r.get("url", ""))

    # Enrich, dedup, filter
    results = _dedup_results(results)
    results = _filter_by_domains(results, include_domains, exclude_domains)
    results = results[:max_results]

    if not results:
        return []

    # Step 2: crawl all results in parallel
    async def _crawl(result: dict) -> dict:
        url = result.get("url", "")
        crawl_result = await _crawl_with_retry(client, url, mode)

        return {
            "title": result.get("title", ""),
            "url": url,
            "snippet": result.get("snippet", ""),
            "source": result.get("source", ""),
            "score": result.get("score", 0),
            "domain": result.get("domain", ""),
            "markdown": crawl_result["markdown"],
            "success": crawl_result["success"],
            "metadata": crawl_result.get("metadata", {}),
        }

    return await asyncio.gather(*[_crawl(r) for r in results])

# ---------------------------------------------------------------------------
# Tool: map
# ---------------------------------------------------------------------------
@mcp.tool()
async def map(
    url: str,
    include_external: bool = False,
    max_links: int = 50,
    include_pattern: Optional[str] = None,
    exclude_pattern: Optional[str] = None,
) -> dict:
    """Discover all links on a page.

    Crawls the page and extracts all internal (and optionally external) links.
    Useful for sitemap generation, content auditing, and crawl planning.

    Args:
        url: The URL to discover links from
        include_external: Include links to external domains (default False)
        max_links: Maximum number of links to return (default 50)
        include_pattern: Regex pattern — only include URLs matching this
        exclude_pattern: Regex pattern — exclude URLs matching this

    Returns:
        Dict with url, links list (url + text), and internal/external counts.
    """
    import re

    client = await get_client()
    base_domain = _extract_domain(url)

    # Use execute_js to extract all links from the page
    js_code = """
    const links = [];
    document.querySelectorAll('a[href]').forEach(a => {
        const href = a.getAttribute('href');
        const text = (a.textContent || '').trim().substring(0, 100);
        if (href && !href.startsWith('#') && !href.startsWith('javascript:')) {
            links.push({ href, text });
        }
    });
    return JSON.stringify(links);
    """

    try:
        resp = await client.post(
            f"{CRAWL4AI_URL}/execute_js",
            json={"url": url, "script": js_code},
        )
        resp.raise_for_status()
        data = resp.json()

        # Parse the result — execute_js returns the JS return value as a string
        raw_links = data.get("result", data.get("output", "[]"))
        if isinstance(raw_links, str):
            import json
            raw_links = json.loads(raw_links)
    except Exception as e:
        # Fallback: extract links from markdown
        try:
            md_resp = await client.post(
                f"{CRAWL4AI_URL}/md",
                json={"url": url, "f": "raw"},
            )
            md_resp.raise_for_status()
            md_data = md_resp.json()
            markdown = md_data.get("markdown", "")

            # Extract markdown links: [text](url)
            raw_links = []
            for match in re.finditer(r'\[([^\]]*)\]\(([^)]+)\)', markdown):
                raw_links.append({"text": match.group(1), "href": match.group(2)})
        except Exception:
            return {
                "url": url,
                "links": [],
                "error": f"Failed to extract links: {e}",
                "internal_count": 0,
                "external_count": 0,
            }

    # Resolve and classify links
    from urllib.parse import urljoin
    links = []
    seen = set()

    for link in raw_links:
        href = link.get("href", "")
        text = link.get("text", "").strip()

        # Resolve relative URLs
        full_url = urljoin(url, href)

        # Normalize for dedup
        normalized = full_url.rstrip("/").split("#")[0]
        if normalized in seen:
            continue
        seen.add(normalized)

        # Classify internal vs external
        link_domain = _extract_domain(full_url)
        is_internal = link_domain == base_domain or link_domain.endswith("." + base_domain)

        if not is_internal and not include_external:
            continue

        # Apply patterns
        if include_pattern and not re.search(include_pattern, full_url):
            continue
        if exclude_pattern and re.search(exclude_pattern, full_url):
            continue

        links.append({
            "url": full_url,
            "text": text[:200],
            "internal": is_internal,
        })

        if len(links) >= max_links:
            break

    internal_count = sum(1 for l in links if l["internal"])
    external_count = sum(1 for l in links if not l["internal"])

    return {
        "url": url,
        "links": links,
        "internal_count": internal_count,
        "external_count": external_count,
        "total": len(links),
    }


# ---------------------------------------------------------------------------
# Screenshot serving
# ---------------------------------------------------------------------------
SCREENSHOT_DIR = "/data/screenshots"
os.makedirs(SCREENSHOT_DIR, exist_ok=True)


# ---------------------------------------------------------------------------
# Run
# ---------------------------------------------------------------------------
if __name__ == "__main__":
    import uvicorn
    from starlette.staticfiles import StaticFiles
    from starlette.routing import Mount

    # Get the MCP Starlette app and add static files route
    app = mcp.streamable_http_app()
    app.routes.insert(
        0,
        Mount("/screenshots", app=StaticFiles(directory=SCREENSHOT_DIR), name="screenshots"),
    )

    uvicorn.run(app, host="0.0.0.0", port=8000)
