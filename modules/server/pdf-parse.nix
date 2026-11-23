{ config, pkgs, lib, ... }:
let
  docker = "${pkgs.docker}/bin/docker";
in
{
  systemd.services.pdf-parse = {
    description = "PDF Parser — Cohere Parse + PyMuPDF fallback";
    wantedBy = [ "multi-user.target" ];
    after = [ "docker.service" ];
    requires = [ "docker.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeScript "pdf-parse-start" ''
        #!${pkgs.bash}/bin/bash
        set -e
        ${docker} rm -f pdf-parse 2>/dev/null || true

        # Build image from the source committed in this repo
        ${docker} build -t pdf-parse:latest /etc/nixos/compose/pdf-parse

        CO_KEY=$(${docker} exec whisper printenv CO_API_KEY 2>/dev/null || echo "")

        exec ${docker} run -d --name pdf-parse \
          --restart unless-stopped \
          -v /var/lib/pdf-parse:/data \
          --network proxy \
          -p 127.0.0.1:8003:8000 \
          -e COHERE_API_KEY="$CO_KEY" \
          -e PARSE_MODEL=parse-v5.0 \
          -e MAX_PAGES=200 \
          -e PARSE_RETRIES=3 \
          -e RETRY_BACKOFF=1.5 \
          -e PARSE_CONCURRENCY=20 \
          pdf-parse:latest
      '';
      ExecStop = "${docker} stop pdf-parse";
    };
  };
}
