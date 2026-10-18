# ntfy — Self-hosted push notifications
# Docker container, port 8085 (localhost only, behind Caddy)
{ pkgs, lib, ... }:

let
  docker = "${pkgs.docker}/bin/docker";
in
{
  systemd.tmpfiles.rules = [
    "d /var/lib/ntfy 0755 root root -"
  ];

  systemd.services.ntfy = {
    description = "ntfy — Push Notifications (Docker)";
    after = [ "network-online.target" "docker.service" ];
    wants = [ "network-online.target" ];
    requires = [ "docker.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      Restart = "on-failure";
      RestartSec = "5s";
      ExecStartPre = "${pkgs.bash}/bin/bash -c '${docker} pull binwiederhier/ntfy:latest || true'";
      ExecStart = pkgs.writeScript "ntfy-start" ''
        #!${pkgs.bash}/bin/bash
        ${docker} rm -f ntfy 2>/dev/null || true
        exec ${docker} run -d --name ntfy \
          --restart unless-stopped \
          --network proxy \
          --cap-drop ALL \
          --security-opt no-new-privileges \
          --memory 64m \
          --cpus 0.25 \
          --pids-limit 25 \
          -p 127.0.0.1:8085:80 \
          -v /var/lib/ntfy:/var/cache/ntfy \
          -e TZ=UTC \
          -e NTFY_BASE_URL=http://ntfy.home.lab \
          binwiederhier/ntfy:latest serve
      '';
      ExecStop = "${docker} stop ntfy";
    };
  };
}
