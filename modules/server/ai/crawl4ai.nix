# crawl4ai — web crawler/scraping with LLM extraction
# Single container replacement for Firecrawl (MIT license, 1 container vs 6)
# Includes built-in Playwright, Redis, and MCP server
# Security: cap-drop ALL, no-new-privileges
# Egress: patched pinning proxy dials through gluetun (NordVPN) upstream.
{ pkgs, lib, config, ... }:

let
  docker = "${pkgs.docker}/bin/docker";
  egressProxy = pkgs.writeText "egress_proxy.py" ''"""
egress_proxy.py - localhost pinning forward-proxy for the browser.

context.route() sees URLs, not IPs, so it cannot stop DNS rebinding: Chromium
resolves the target host itself at connect time, and an attacker can answer
"public" to our up-front validation and "169.254.169.254" to the browser.

This proxy is the real control. Chromium is pointed at it (proxy_config), so it
never resolves the target itself - it asks us to CONNECT host:port. We run the
single egress rule (egress_broker.resolve_and_pin: resolve once, reject any
non-global IP, pin one IP), dial the PINNED IP ourselves, and splice raw bytes.
TLS stays end-to-end (we tunnel ciphertext; Chromium verifies the cert/SNI
against the real host - no MITM).

Bound to 127.0.0.1 on an ephemeral port; started at server boot.

CRAWL4AI_UPSTREAM_PROXY (optional): if set (e.g. http://gluetun:8888), the
pinned target is dialed THROUGH that HTTP forward proxy instead of directly.
SSRF pinning is unchanged - resolve_and_pin still rejects non-global IPs before
anything is dialed; only the transport path goes via the upstream proxy.
"""

from __future__ import annotations

import asyncio
import logging
import os
from urllib.parse import urlsplit

from egress_broker import EgressBlocked, resolve_and_pin

logger = logging.getLogger("crawl4ai.egress")

_CONNECT_OK = b"HTTP/1.1 200 Connection established\r\n\r\n"
_BLOCKED = b"HTTP/1.1 403 Forbidden\r\nContent-Length: 11\r\n\r\nURL blocked"
_BAD = b"HTTP/1.1 400 Bad Request\r\nContent-Length: 11\r\n\r\nBad Request"
_MAX_HEADER_BYTES = 64 * 1024

# Optional upstream HTTP forward-proxy (e.g. gluetun VPN proxy). When set, the
# pinning proxy dials THIS proxy and tunnels the pinned target through it.
UPSTREAM_PROXY = os.environ.get("CRAWL4AI_UPSTREAM_PROXY", "").strip()


def _upstream_hostport() -> tuple[str, int] | None:
    """Return (host, port) of the upstream proxy, or None if unset."""
    if not UPSTREAM_PROXY:
        return None
    sp = urlsplit(UPSTREAM_PROXY)
    host = sp.hostname
    if not host:
        return None
    return host, sp.port or 80


class PinningProxy:
    """Async HTTP forward-proxy that connects only to pinned, global IPs."""

    def __init__(self, host: str = "127.0.0.1", port: int = 0):
        self._host = host
        self._port = port
        self._server: asyncio.AbstractServer | None = None
        self.bound_host: str | None = None
        self.bound_port: int | None = None

    @property
    def url(self) -> str | None:
        if self.bound_port is None:
            return None
        return f"http://{self.bound_host}:{self.bound_port}"

    async def start(self) -> str:
        self._server = await asyncio.start_server(self._handle, self._host, self._port)
        sock = self._server.sockets[0]
        self.bound_host, self.bound_port = sock.getsockname()[:2]
        logger.info("egress pinning proxy listening on %s", self.url)
        if UPSTREAM_PROXY:
            logger.info("egress upstream proxy: %s", UPSTREAM_PROXY)
        return self.url

    async def stop(self) -> None:
        if self._server is not None:
            self._server.close()
            try:
                await self._server.wait_closed()
            except Exception:
                pass

    # ─────────────────────────── connection handling ───────────────────────────
    async def _handle(self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter):
        try:
            request_line = await asyncio.wait_for(reader.readline(), timeout=30)
            if not request_line:
                return
            parts = request_line.split()
            if len(parts) < 3:
                await self._reply(writer, _BAD)
                return
            method = parts[0].decode("latin-1", "replace").upper()
            target = parts[1].decode("latin-1", "replace")

            if method == "CONNECT":
                await self._handle_connect(target, reader, writer)
            else:
                await self._handle_absolute(method, target, request_line, reader, writer)
        except asyncio.TimeoutError:
            await self._reply(writer, _BAD)
        except Exception as e:
            logger.debug("proxy connection error: %s", e)
            await self._safe_close(writer)

    async def _dial(self, host: str, port: int) -> tuple[asyncio.StreamReader, asyncio.StreamWriter]:
        """Open the outbound connection - directly, or via the upstream proxy."""
        up = _upstream_hostport()
        if up is None:
            return await asyncio.wait_for(
                asyncio.open_connection(host, port), timeout=30
            )
        # Dial the upstream proxy, then CONNECT the pinned target through it.
        up_reader, up_writer = await asyncio.wait_for(
            asyncio.open_connection(up[0], up[1]), timeout=30
        )
        connect_line = f"CONNECT {host}:{port} HTTP/1.1\r\nHost: {host}:{port}\r\n\r\n".encode("latin-1")
        up_writer.write(connect_line)
        await up_writer.drain()
        # Read the proxy's response head until blank line.
        status_line = await asyncio.wait_for(up_reader.readline(), timeout=30)
        if not status_line.startswith(b"HTTP/1.1 200") and not status_line.startswith(b"HTTP/1.0 200"):
            raise ConnectionError(f"upstream CONNECT failed: {status_line!r}")
        while True:
            line = await asyncio.wait_for(up_reader.readline(), timeout=30)
            if line in (b"\r\n", b"\n", b""):
                break
        return up_reader, up_writer

    async def _handle_connect(self, target, client_reader, client_writer):
        # target is "host:port"
        host, _, port_s = target.rpartition(":")
        if not host or not port_s.isdigit():
            await self._reply(client_writer, _BAD)
            return
        try:
            pin = resolve_and_pin(f"https://{host}:{port_s}")
        except EgressBlocked:
            await self._reply(client_writer, _BLOCKED)
            return

        # Drain the rest of the client's CONNECT headers.
        await self._drain_headers(client_reader)

        try:
            up_reader, up_writer = await self._dial(pin.ip, int(port_s))
        except Exception:
            await self._reply(client_writer, _BLOCKED)
            return

        client_writer.write(_CONNECT_OK)
        await client_writer.drain()
        await self._splice(client_reader, client_writer, up_reader, up_writer)

    async def _handle_absolute(self, method, target, request_line, client_reader, client_writer):
        # Plain HTTP proxying: target is an absolute URI "http://host/path".
        sp = urlsplit(target)
        if sp.scheme != "http" or not sp.hostname:
            await self._reply(client_writer, _BAD)
            return
        port = sp.port or 80
        try:
            pin = resolve_and_pin(f"http://{sp.hostname}:{port}")
        except EgressBlocked:
            await self._reply(client_writer, _BLOCKED)
            return

        headers = await self._read_headers(client_reader)
        path = sp.path or "/"
        if sp.query:
            path += "?" + sp.query
        try:
            if _upstream_hostport() is not None:
                # Via upstream: send the request in ABSOLUTE form (RFC 7230) so
                # the upstream proxy knows which host to tunnel to.
                out = f"{method} {target} HTTP/1.1\r\n".encode("latin-1")
                out += b"Host: " + sp.hostname.encode("latin-1")
                if sp.port:
                    out += f":{sp.port}".encode("latin-1")
                out += b"\r\n" + headers + b"\r\n"
                up_reader, up_writer = await self._dial(sp.hostname, port)
            else:
                up_reader, up_writer = await asyncio.wait_for(
                    asyncio.open_connection(pin.ip, port), timeout=30
                )
                # Re-issue in origin form with Host preserved.
                out = f"{method} {path} HTTP/1.1\r\n".encode("latin-1")
                out += b"Host: " + sp.hostname.encode("latin-1")
                if sp.port:
                    out += f":{sp.port}".encode("latin-1")
                out += b"\r\n" + headers + b"\r\n"
        except Exception:
            await self._reply(client_writer, _BLOCKED)
            return
        up_writer.write(out)
        await up_writer.drain()
        await self._splice(client_reader, client_writer, up_reader, up_writer)

    # ─────────────────────────── helpers ───────────────────────────
    async def _drain_headers(self, reader):
        read = 0
        while True:
            line = await asyncio.wait_for(reader.readline(), timeout=30)
            read += len(line)
            if line in (b"\r\n", b"\n", b""):
                return
            if read > _MAX_HEADER_BYTES:
                return

    async def _read_headers(self, reader) -> bytes:
        buf = b""
        while True:
            line = await asyncio.wait_for(reader.readline(), timeout=30)
            if line in (b"\r\n", b"\n", b""):
                break
            buf += line
            if len(buf) > _MAX_HEADER_BYTES:
                break
        # strip any proxy-only / connection headers
        kept = []
        for ln in buf.split(b"\r\n"):
            name = ln.split(b":", 1)[0].strip().lower()
            if name in (b"proxy-connection", b"proxy-authorization", b"host"):
                continue
            if ln:
                kept.append(ln)
        return (b"\r\n".join(kept) + b"\r\n") if kept else b""

    async def _splice(self, c_reader, c_writer, u_reader, u_writer):
        async def pipe(src, dst):
            try:
                while True:
                    data = await src.read(65536)
                    if not data:
                        break
                    dst.write(data)
                    await dst.drain()
            except Exception:
                pass
            finally:
                await self._safe_close(dst)

        await asyncio.gather(
            pipe(c_reader, u_writer),
            pipe(u_reader, c_writer),
        )

    async def _reply(self, writer, payload: bytes):
        try:
            writer.write(payload)
            await writer.drain()
        except Exception:
            pass
        await self._safe_close(writer)

    @staticmethod
    async def _safe_close(writer):
        try:
            if not writer.is_closing():
                writer.close()
        except Exception:
            pass
'';
in
{
  systemd.tmpfiles.rules = [
    "d /var/lib/crawl4ai 0755 root root -"
  ];

  systemd.services.crawl4ai = {
    description = "crawl4ai Web Crawler (Docker)";
    after = [ "network.target" "docker.service" ];
    requires = [ "docker.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      Restart = "on-failure";
      RestartSec = "5s";
      ExecStartPre = "${pkgs.bash}/bin/bash -c '${docker} pull unclecode/crawl4ai:latest || true'";
      ExecStart = pkgs.writeScript "crawl4ai-start" ''
        #!${pkgs.bash}/bin/bash
        ${docker} rm -f crawl4ai 2>/dev/null || true
        exec ${docker} run -d --name crawl4ai \
          --restart unless-stopped \
          --network proxy \
          -p 127.0.0.1:11235:11235 \
          --shm-size=1g \
          --cap-drop ALL \
          --security-opt no-new-privileges \
          --memory 2g \
          --cpus 2.0 \
          --pids-limit 500 \
          -v /var/lib/crawl4ai:/app/data \
          -e CRAWL4AI_API_TOKEN=$(cat ${config.sops.secrets."crawl4ai-api-token".path}) \
          -e CRAWL4AI_HOST=0.0.0.0 \
          -e CRAWL4AI_BROWSER_TIMEOUT=30000 \
          -e CRAWL4AI_MAX_PAGES_PER_CRAWL=100 \
          -e CRAWL4AI_UPSTREAM_PROXY=http://gluetun:8888 \
          -v ${egressProxy}:/app/egress_proxy.py:ro \
          unclecode/crawl4ai:latest
      '';
      # Ensure Playwright Chromium is installed after container starts
      # (image doesn't ship headless-shell binary, needed by crawl4ai API)
      ExecStartPost = pkgs.writeScript "crawl4ai-post-start" ''
        #!${pkgs.bash}/bin/bash
        sleep 3
        ${docker} exec crawl4ai playwright install chromium 2>&1 || true
      '';
      ExecStop = "${docker} stop crawl4ai";
    };
  };

  # crawl4ai restart timer — prevent Playwright browser memory leaks
  systemd.services.crawl4ai-restart = {
    description = "Restart crawl4ai to prevent Playwright browser memory leaks";
    after = [ "docker.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.docker}/bin/docker restart crawl4ai";
    };
  };

  systemd.timers.crawl4ai-restart = {
    description = "Restart crawl4ai every 4 hours";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 00,04,08,12,16,20:00:00";
      Persistent = true;
    };
  };

}
