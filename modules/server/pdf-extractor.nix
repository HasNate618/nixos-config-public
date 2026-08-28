# PDF Extractor — web UI + VLM extraction via Bifrost + OCRmyPDF fallback
{ pkgs, lib, config, ... }:

let
  docker = "${pkgs.docker}/bin/docker";
in
{
  systemd.tmpfiles.rules = [
    "d /var/lib/pdf-extractor 0755 root root -"
  ];

  systemd.services.pdf-extractor = {
    description = "PDF Extractor — VLM + OCR (Docker)";
    after = [ "network.target" "docker.service" ];
    requires = [ "docker.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeScript "pdf-extractor-start" ''
        #!${pkgs.bash}/bin/bash
        ${docker} rm -f pdf-extractor 2>/dev/null || true
        exec ${docker} run -d --name pdf-extractor \
          --restart unless-stopped \
          --network proxy \
          -p 127.0.0.1:8001:8000 \
          --memory 2g \
          --cpus 2.0 \
          -v /var/lib/pdf-extractor:/data/jobs \
          -e PDF_ENGINE=auto \
          -e BIFROST_URL=http://bifrost:8080 \
          -e VISION_MODEL=cohere/command-a-vision-07-2025 \
          -e MAX_CONCURRENT=3 \
          pdf-extractor:latest
      '';
      ExecStop = "${docker} stop pdf-extractor";
    };
  };
}
