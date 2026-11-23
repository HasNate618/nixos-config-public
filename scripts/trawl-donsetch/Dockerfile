# trawl-donsetch — trawl MCP with the donsetch (keyless/local) backend and
# local->Exa escalation on empty results.
#
# Rebase is intentional: upstream `trawl:latest` is a prebuilt image with no
# registry we control, so our patch is layered onto the base tag we preserve
# locally (`trawl-base:latest`). server.py is the only file we own.
FROM trawl-base:latest
COPY server.py /app/server.py
