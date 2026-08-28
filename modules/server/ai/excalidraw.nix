# Excalidraw — virtual whiteboard for sketching hand-drawn diagrams
# Official Docker image, analytics-free, client-only (no collab)
# Access: http://excalidraw.home.lab (via Caddy)
{ pkgs, lib, config, ... }:

let
  docker = "${pkgs.docker}/bin/docker";
in
{
  systemd.tmpfiles.rules = [
    "d /var/lib/excalidraw 0755 root root -"
  ];

  systemd.services.excalidraw = {
    description = "Excalidraw Whiteboard (Docker)";
    after = [ "network.target" "docker.service" ];
    requires = [ "docker.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStartPre = pkgs.writeShellScript "excalidraw-pre-start" ''
        ${docker} pull excalidraw/excalidraw:latest || true
      '';
      ExecStart = pkgs.writeShellScript "excalidraw-start" ''
        ${docker} rm -f excalidraw 2>/dev/null || true
        exec ${docker} run -d --name excalidraw \
          --restart unless-stopped \
          --cap-drop ALL \
          --cap-add CHOWN \
          --cap-add SETUID \
          --cap-add SETGID \
          --cap-add NET_BIND_SERVICE \
          --security-opt no-new-privileges \
          --memory 256m \
          --cpus 1.0 \
          --pids-limit 100 \
          -p 127.0.0.1:11237:80 \
          excalidraw/excalidraw:latest
      '';
      ExecStop = "${docker} stop excalidraw";
    };
  };
}
