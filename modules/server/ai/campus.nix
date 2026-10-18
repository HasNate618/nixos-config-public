# Campus — school sync engine + agent harness (Docker)
# Runs sync/agent/extract/auth CLIs; code mounts from /home/nate/campus (ro)
# so no image rebuild is needed on code changes. Web app binds :8000 in Phase 3.
# Runs as nate (uid 1000) — cap-drop ALL removes CAP_DAC_OVERRIDE, so the
# container needs to run as the owner of the mounted paths, not root.
{ pkgs, lib, config, ... }:

let
  docker = "${pkgs.docker}/bin/docker";
in
{
  systemd.tmpfiles.rules = [
    "d /srv/homelab/school 0755 nate users -"
  ];

  systemd.services.campus = {
    description = "Campus — school sync + agent (Docker)";
    after = [ "network.target" "docker.service" "docker-networks.service" ];
    requires = [ "docker.service" "docker-networks.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      Restart = "on-failure";
      RestartSec = "5s";
      ExecStartPre = pkgs.writeShellScript "campus-pre-start" ''
        ${docker} build -t campus:latest /home/nate/campus || true
      '';
      ExecStart = pkgs.writeShellScript "campus-start" ''
        ${docker} rm -f campus 2>/dev/null || true
        exec ${docker} run -d --name campus \
          --restart unless-stopped \
          --network proxy \
          --cap-drop ALL \
          --security-opt no-new-privileges \
          --memory 1g \
          --cpus 1.0 \
          --pids-limit 200 \
          -p 127.0.0.1:8087:8000 \
          --user 1000:100 \
          -e HOME=/home/nate \
          -v /srv/homelab/school:/srv/homelab/school:rw \
          -v /home/nate/campus:/app:ro \
          -v /home/nate/campus/data:/app/data:rw \
          -v /home/nate/.hippocampus:/home/nate/.hippocampus:rw \
          -v /home/nate/.campus:/home/nate/.campus:rw \
          -e CAMPUS_LLM_URL=http://bifrost:8080/v1 \
          -e CAMPUS_PDF_EXTRACTOR_URL=http://pdf-parse:8000 \
          -e CAMPUS_NTFY_URL=http://ntfy:80 \
          -e CAMPUS_TRAWL_URL=http://trawl:8000/mcp \
          -e CAMPUS_DATA_ROOT=/srv/homelab/school \
          -e CAMPUS_TOKEN_DIR=/home/nate/.hippocampus \
          -e CAMPUS_BRIGHTSPACE_PASSWORD=$(cat ${config.sops.secrets."campus_brightspace_password".path}) \
          campus:latest
      '';
      ExecStop = "${docker} stop campus";
    };
  };

  sops.secrets."campus_brightspace_password" = {};
}
