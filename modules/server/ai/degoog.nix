# DeGoog — privacy-focused search engine frontend
# Running as Docker container on NixOS
# Custom plugins, themes, and AI summary from existing homelab
{ pkgs, lib, config, ... }:

let
  docker = "${pkgs.docker}/bin/docker";
  customDir = "/var/lib/degoog-custom";
in
{
  systemd.tmpfiles.rules = [
    "d /var/lib/degoog 0755 1000 1000 -"
  ];

  systemd.services.degoog = {
    description = "DeGoog Privacy Search Engine (Docker)";
    after = [ "network.target" "docker.service" ];
    requires = [ "docker.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      Restart = "on-failure";
      RestartSec = "5s";
      ExecStartPre = "${pkgs.bash}/bin/bash -c '${docker} pull ghcr.io/degoog-org/degoog:latest || true'";
      ExecStart = pkgs.writeScript "degoog-start" ''
        #!${pkgs.bash}/bin/bash
        ${docker} rm -f degoog 2>/dev/null || true
        exec ${docker} run -d --name degoog \
          --restart unless-stopped \
          --network proxy \
          -p 127.0.0.1:18082:4444 \
          --cap-drop ALL \
          --cap-add SETUID \
          --cap-add SETGID \
          --cap-add CHOWN \
          --security-opt no-new-privileges \
          --tmpfs /tmp:rw,noexec,nosuid,size=16m \
          -v /var/lib/degoog:/app/data \
          -v ${customDir}/plugins:/app/data/plugins \
          -v ${customDir}/themes:/app/data/themes \
          --memory 512m \
          --cpus 1.0 \
          --pids-limit 100 \
          -e PUID=1000 \
          -e PGID=1000 \
          -e DEGOOG_BASE_URL=/ \
          -e DEGOOG_DISTRUST_PROXY=0 \
          -e DEGOOG_DANGEROUSLY_NO_PASSWORD=true \
          ghcr.io/degoog-org/degoog:latest
      '';
      ExecStop = "${docker} stop degoog";
    };
  };
}
