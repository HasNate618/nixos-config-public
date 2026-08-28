# Uptime Kuma — Self-hosted uptime monitoring with alerts
# Docker container, port 3001 (localhost only, behind Caddy)
{ pkgs, lib, ... }:

let
  docker = "${pkgs.docker}/bin/docker";
in
{
  systemd.tmpfiles.rules = [
    "d /var/lib/uptime-kuma 0755 root root -"
  ];

  systemd.services.uptime-kuma = {
    description = "Uptime Kuma — Uptime Monitoring (Docker)";
    after = [ "network-online.target" "docker.service" ];
    wants = [ "network-online.target" ];
    requires = [ "docker.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      Restart = "on-failure";
      RestartSec = "5s";
      ExecStartPre = "${pkgs.bash}/bin/bash -c '${docker} pull louislam/uptime-kuma:latest || true'";
      ExecStart = pkgs.writeScript "uptime-kuma-start" ''
        #!${pkgs.bash}/bin/bash
        ${docker} rm -f uptime-kuma 2>/dev/null || true
        exec ${docker} run -d --name uptime-kuma \
          --restart unless-stopped \
          --network proxy \
          --cap-drop ALL \
          --cap-add NET_BIND_SERVICE \
          --cap-add SETGID \
          --cap-add SETUID \
          --cap-add DAC_OVERRIDE \
          --security-opt no-new-privileges \
          --memory 256m \
          --cpus 0.5 \
          --pids-limit 50 \
          -p 127.0.0.1:3002:3001 \
          -v /var/lib/uptime-kuma:/app/data \
          -e TZ=America/Toronto \
          louislam/uptime-kuma:latest
      '';
      ExecStop = "${docker} stop uptime-kuma";
    };
  };
}
