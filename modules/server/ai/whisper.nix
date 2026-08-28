# Whisper Transcriber — audio-to-text via Cohere API
# Image built from repo source (scripts/whisper) so it's reproducible
# Proxied at whisper.home.lab → 127.0.0.1:8086
{ pkgs, lib, config, ... }:

let
  docker = "${pkgs.docker}/bin/docker";
  srcDir = "/etc/nixos/scripts/whisper";
in
{
  systemd.tmpfiles.rules = [
    "d /var/lib/whisper 0755 root root -"
    "d /var/lib/whisper/cache 0755 root root -"
    "d /var/lib/whisper/jobs 0755 root root -"
  ];

  systemd.services.whisper = {
    description = "Whisper transcriber (Docker, built from repo source)";
    after = [ "network.target" "docker.service" ];
    requires = [ "docker.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStartPre = "${pkgs.bash}/bin/bash -c '${docker} build -t whisper-whisper ${srcDir} || true'";
      ExecStart = pkgs.writeScript "whisper-start" ''
        #!${pkgs.bash}/bin/bash
        ${docker} rm -f whisper 2>/dev/null || true
        exec ${docker} run -d --name whisper \
          --restart unless-stopped \
          --network host \
          --cap-drop ALL \
          --security-opt no-new-privileges \
          --memory 512m \
          --cpus 1.0 \
          --pids-limit 100 \
          -e CO_API_KEY=$(cat ${config.sops.secrets."cohere-api-key".path}) \
          -v /var/lib/whisper:/data \
          whisper-whisper
      '';
      ExecStop = "${docker} stop whisper";
    };
  };
}
