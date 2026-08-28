# Glance — self-hosted dashboard
# Running as Docker container, port 8083 (localhost only, behind Caddy)
# Docker socket mounted for container monitoring widget
{ pkgs, lib, config, ... }:

let
  docker = "${pkgs.docker}/bin/docker";
in
{
  systemd.tmpfiles.rules = [
    "d /var/lib/glance 0755 root root -"
    "d /var/lib/glance/config 0755 root root -"
    "d /var/lib/glance/assets 0755 root root -"
  ];

  systemd.services.glance = {
    description = "Glance dashboard (Docker)";
    after = [ "network-online.target" "docker.service" "adguardhome.service" ];
    wants = [ "network-online.target" ];
    requires = [ "docker.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      Restart = "on-failure";
      RestartSec = "5s";
      ExecStartPre = "${pkgs.bash}/bin/bash -c '${docker} pull glanceapp/glance:latest || true'";
      ExecStart = pkgs.writeScript "glance-start" ''
        #!${pkgs.bash}/bin/bash
        ${docker} rm -f glance 2>/dev/null || true
        exec ${docker} run -d --name glance \
          --restart unless-stopped \
          --network host \
          --cap-drop ALL \
          --security-opt no-new-privileges \
          --memory 256m \
          --cpus 0.5 \
          --pids-limit 50 \
          -v /var/run/docker.sock:/var/run/docker.sock:ro \
          -v /var/lib/glance/config:/app/config \
          -v /var/lib/glance/assets:/app/assets \
          -e TAILSCALE_API_KEY=$(cat ${config.sops.secrets."tailscale-api-key".path}) \
          glanceapp/glance:latest
      '';
      ExecStop = "${docker} stop glance";
    };
  };
}
