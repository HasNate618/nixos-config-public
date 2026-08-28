# Trawl — MCP server for web search + content extraction
# Bundles DeGoog/SearXNG search with crawl4ai content extraction
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
      ExecStartPre = pkgs.writeShellScript "trawl-pre-start" ''
        ${docker} pull trawl:latest || true
      '';
      ExecStart = pkgs.writeShellScript "trawl-start" ''
        ${docker} rm -f trawl 2>/dev/null || true
        exec ${docker} run -d --name trawl \
          --restart unless-stopped \
          --network proxy \
          --cap-drop ALL \
          --security-opt no-new-privileges \
          --memory 256m \
          --cpus 1.0 \
          --pids-limit 100 \
          -p 127.0.0.1:11236:8000 \
          -e SEARCH_BACKEND=searxng \
          -e DEGOOG_URL=http://degoog:4444/api \
          -e SEARXNG_URL=http://searxng:8080 \
          -e CRAWL4AI_API_TOKEN=$(cat ${config.sops.secrets."crawl4ai-api-token".path}) \
          trawl:latest
      '';
      ExecStop = "${docker} stop trawl";
    };
  };
}
