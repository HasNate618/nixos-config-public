{
  # Server module aggregator — mirrors modules/nixos/default.nix
  # but imports only server-relevant modules (no desktop/gaming)
  imports = [
    # Infrastructure — core system, networking, DNS, secrets, security
    ./infra/core.nix
    ./infra/networking.nix
    ./infra/services.nix
    ./infra/packages.nix
    ./infra/infrastructure.nix
    ./infra/dns.nix
    ./infra/secrets.nix
    ./infra/security.nix
    ./infra/docker-networks.nix
    ./infra/alx-fix.nix

    # Access — reverse proxy, git forge, passwords, files
    ./access/proxy.nix
    ./access/forgejo.nix
    ./access/nextcloud.nix
    ./access/collabora.nix
    ./access/vaultwarden.nix
    ./access/filebrowser.nix

    # AI / LLM — chat, gateway, search, crawl, agents
    ./ai/bifrost.nix
    ./pdf-extractor.nix
    ./pdf-ocr.nix
    ./pdf-parse.nix
    ./bentopdf.nix
    ./ai/crawl4ai.nix
    ./ai/open-webui.nix
    ./ai/open-terminal.nix
    ./ai/degoog.nix
    ./ai/trawl.nix
    ./ai/whisper.nix
    ./ai/searxng.nix
    ./ai/excalidraw.nix
    ./ai/excalidraw-mcp.nix
    ./ai/brightspace-mcp.nix
    ./ai/campus.nix
    ./ai/embeddinggemma.nix

    # Media — Jellyfin, *arr stack, Immich
    ./media/jellyfin.nix
    ./media/arr-stack.nix
    ./media/immich.nix

    # Monitoring — dashboards, alerts, notifications
    ./monitor/glance.nix
    ./monitor/uptime-kuma.nix
    ./monitor/netdata.nix
    ./monitor/ntfy.nix

    # Games — self-hosted private game servers
    ./games/lunar-tear.nix
  ];
}
