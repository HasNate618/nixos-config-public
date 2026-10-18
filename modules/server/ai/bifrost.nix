# Bifrost — LLM gateway/proxy for multiple backends
# Running as Docker container on NixOS
# Security: cap-drop ALL, no-new-privileges, read-only rootfs
{ pkgs, lib, config, ... }:

let
  docker = "${pkgs.docker}/bin/docker";
in
{
  systemd.tmpfiles.rules = [
    "d /var/lib/bifrost 0755 1000 1000 -"
  ];

  systemd.services.bifrost = {
    description = "Bifrost LLM Gateway (Docker)";
    after = [ "network.target" "docker.service" ];
    requires = [ "docker.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStartPre = "${pkgs.bash}/bin/bash -c '${docker} pull bifrost-fork:session-affinity || true'";  # pinned: v1.6.6
      ExecStart = pkgs.writeScript "bifrost-start" ''
        #!${pkgs.bash}/bin/bash
        ${docker} rm -f bifrost 2>/dev/null || true
        exec ${docker} run -d --name bifrost \
          --restart unless-stopped \
          --network proxy \
          -p 127.0.0.1:18081:8080 \
          --cap-drop ALL \
          --security-opt no-new-privileges \
          --tmpfs /tmp:rw,noexec,nosuid,size=64m \
          -v /var/lib/bifrost:/app/data \
          --memory 512m \
          --cpus 1.0 \
          --pids-limit 100 \
          -e APP_PORT=8080 \
          -e APP_HOST=0.0.0.0 \
          -e LOG_LEVEL=info \
          bifrost-fork:session-affinity
      '';
      ExecStop = "${docker} stop bifrost";
    };
  };
}
