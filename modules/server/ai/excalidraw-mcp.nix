# Excalidraw MCP App Server — streams interactive diagrams in chat
# Built from source: github.com/excalidraw/excalidraw-mcp
# Access via Caddy: http://excalidraw-mcp.home.lab/mcp
# Access via Docker: http://excalidraw-mcp:3001/mcp (proxy network)
{ pkgs, lib, config, ... }:

let
  docker = "${pkgs.docker}/bin/docker";
in
{
  systemd.tmpfiles.rules = [
    "d /var/lib/excalidraw-mcp 0755 root root -"
  ];

  systemd.services.excalidraw-mcp = {
    description = "Excalidraw MCP App Server (Docker)";
    after = [ "network.target" "docker.service" ];
    requires = [ "docker.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "excalidraw-mcp-start" ''
        ${docker} rm -f excalidraw-mcp 2>/dev/null || true
        exec ${docker} run -d --name excalidraw-mcp \
          --restart unless-stopped \
          --network proxy \
          --cap-drop ALL \
          --security-opt no-new-privileges \
          --memory 512m \
          --cpus 1.0 \
          --pids-limit 100 \
          -p 127.0.0.1:11238:3001 \
          excalidraw-mcp:latest
      '';
      ExecStop = "${docker} stop excalidraw-mcp";
    };
  };
}
