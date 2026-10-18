# Trawl — MCP server for web search + content extraction
# Backends: exa (default/general, multi-key failover), local (donsetch/private fallback)
# Bundles DeGoog/SearXNG search with crawl4ai content extraction
# Exa: EXA_API_KEYS pool, drained key cooled down and next key tried automatically
{ pkgs, lib, config, ... }:

let
  docker = "${pkgs.docker}/bin/docker";
in
{
  systemd.tmpfiles.rules = [
    "d /var/lib/trawl 0755 root root -"
  ];

  systemd.services.trawl = {
    description = "Trawl MCP Server (Docker)";
    after = [ "network.target" "docker.service" ];
    requires = [ "docker.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      # server.py is bind-mounted rather than baked into the image. The build
      # step used to layer it onto a local-only `trawl-base:latest`, which can be
      # pruned away; the build then failed under `|| true` and the container kept
      # running stale code with no visible error. Mounting makes an edit take
      # effect on restart, with no image rebuild in the path at all.
      ExecStart = pkgs.writeShellScript "trawl-start" ''
        ${docker} rm -f trawl 2>/dev/null || true
        exec ${docker} run -d --name trawl \
          --restart unless-stopped \
          --network proxy \
          --dns 127.0.0.11 \
          --dns 1.1.1.1 \
          --cap-drop ALL \
          --security-opt no-new-privileges \
          --memory 256m \
          --cpus 1.0 \
          --pids-limit 100 \
          -p 127.0.0.1:11236:8000 \
          -v /etc/nixos/scripts/trawl-donsetch/server.py:/app/server.py:ro \
          -e SEARCH_BACKEND=exa \
          -e LOCAL_FALLBACK_EXA=1 \
          -e EXA_API_KEYS=$(cat ${config.sops.secrets."exa-api-key".path}),$(cat ${config.sops.secrets."exa-api-key-secondary".path}) \
          -e EXA_KEY_COOLDOWN=1800 \
          -e EXA_SEARCH_TYPE=auto \
          -e EXA_NUM_RESULTS=5 \
          -e DEGOOG_URL=http://degoog:4444/api \
          -e DONSEETCH_URL=http://donsetch-shim:8899 \
          -e SEARXNG_URL=http://searxng:8080 \
          -e CRAWL4AI_API_TOKEN=$(cat ${config.sops.secrets."crawl4ai-api-token".path}) \
          trawl-donsetch:latest
      '';
      ExecStop = "${docker} stop trawl";
    };
  };
}
