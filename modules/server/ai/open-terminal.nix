# Open Terminal — gives Open WebUI AI a sandboxed shell to execute commands
# Docker container on proxy network, reachable by Open WebUI as "open-terminal:8000"
{ pkgs, lib, config, ... }:

let
  docker = "${pkgs.docker}/bin/docker";
in
{
  systemd.tmpfiles.rules = [
    "d /var/lib/open-terminal 0755 1000 1000 -"
  ];

  systemd.services.open-terminal = {
    description = "Open Terminal (Docker) — AI shell for Open WebUI";
    after = [ "network.target" "docker.service" ];
    requires = [ "docker.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      Restart = "on-failure";
      RestartSec = "5s";
      ExecStartPre = "${pkgs.bash}/bin/bash -c '${docker} pull ghcr.io/open-webui/open-terminal:latest || true'";
      ExecStart = pkgs.writeScript "open-terminal-start" ''
        #!${pkgs.bash}/bin/bash
        ${docker} rm -f open-terminal 2>/dev/null || true
        exec ${docker} run -d --name open-terminal \
          --restart unless-stopped \
          --network proxy \
          -p 127.0.0.1:18083:8000 \
          --tmpfs /tmp:rw,size=128m \
          -v /var/lib/open-terminal:/home/user \
          --memory 2g \
          --cpus 2.0 \
          --pids-limit 200 \
          -e OPEN_TERMINAL_API_KEY=$(cat ${config.sops.secrets."open-terminal-api-key".path}) \
          -e OPEN_TERMINAL_FILE_BROWSER_ROOT="home" \
          ghcr.io/open-webui/open-terminal:latest
      '';
      ExecStop = "${docker} stop open-terminal";
    };
  };
}
