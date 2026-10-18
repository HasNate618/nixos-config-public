# EmbeddingGemma 2 — local multimodal embedding server (Docker, GPU)
# Image built from repo source (scripts/embeddinggemma) so it's reproducible.
# Serves OpenAI-compatible POST /v1/embeddings (text) plus POST /v1/embed
# (text + image + audio in one 768-d space) on 127.0.0.1:8081.
#
# NOT behind Bifrost: Bifrost's embedding route is the OpenAI text-only shape;
# multimodal input cannot pass through it. Callers that need image/audio
# embeddings hit this service directly (Docker network `proxy`:
# http://embeddinggemma:8081, or host 127.0.0.1:8081).
#
# GPU: the GTX 960 is Maxwell (sm_52). The container image pins torch to the
# cu126 build (last line with sm_50 support) and the run uses the CDI device
# flag (--device nvidia.com/gpu=all); `--gpus all` is broken on this host
# ("AMD CDI spec not found").
{ pkgs, lib, config, ... }:

let
  docker = "${pkgs.docker}/bin/docker";
  srcDir = "/etc/nixos/scripts/embeddinggemma";
  image = "embeddinggemma:latest";
in
{
  systemd.tmpfiles.rules = [
    "d /var/lib/embeddinggemma 0755 root root -"
    "d /var/lib/embeddinggemma/hf-cache 0755 root root -"
  ];

  systemd.services.embeddinggemma = {
    description = "EmbeddingGemma 2 embedding server (Docker, built from repo source)";
    # CDI spec must exist before `--device nvidia.com/gpu=all`, else docker
    # run fails with "CDI spec not found" at boot (seen with `--gpus all`)
    after = [ "network.target" "docker.service"
              "nvidia-container-toolkit-cdi-generator.service" ];
    requires = [ "docker.service" ];
    wants = [ "nvidia-container-toolkit-cdi-generator.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      # || true keeps the last good image if the build fails (needs shell wrapper)
      ExecStartPre = "${pkgs.bash}/bin/bash -c '${docker} build -t ${image} ${srcDir} || true'";
      ExecStart = pkgs.writeScript "embeddinggemma-start" ''
        #!${pkgs.bash}/bin/bash
        ${docker} rm -f embeddinggemma 2>/dev/null || true
        exec ${docker} run -d --name embeddinggemma \
          --restart unless-stopped \
          --network proxy \
          -p 127.0.0.1:8081:8081 \
          --device nvidia.com/gpu=all \
          --memory 6g \
          --cpus 3.0 \
          --pids-limit 512 \
          --security-opt no-new-privileges \
          -v /var/lib/embeddinggemma/hf-cache:/cache/huggingface \
          ${image}
      '';
      ExecStop = "${docker} stop embeddinggemma";
    };
  };
}
