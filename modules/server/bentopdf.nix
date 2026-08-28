# BentoPDF — privacy-first client-side PDF toolkit (merge, split, edit, sign, OCR, convert)
# All processing happens in the user's browser via WASM; the container is a static nginx file server.
# No volumes, no state — nothing to back up. Image runs non-root (nginx-unprivileged, UID 101, port 8080).
{ pkgs, lib, config, ... }:

let
  docker = "${pkgs.docker}/bin/docker";
in
{
  systemd.services.bentopdf = {
    description = "BentoPDF — client-side PDF toolkit (Docker)";
    after = [ "network.target" "docker.service" ];
    requires = [ "docker.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeScript "bentopdf-start" ''
        #!${pkgs.bash}/bin/bash
        ${docker} rm -f bentopdf 2>/dev/null || true
        exec ${docker} run -d --name bentopdf \
          --restart unless-stopped \
          -p 127.0.0.1:8095:8080 \
          --memory 512m \
          ghcr.io/alam00000/bentopdf-simple:latest
      '';
      ExecStop = "${docker} stop bentopdf";
    };
  };
}
