# PDF Local OCR — PP-OCRv6 (accurate CPU OCR) as the local engine backend
# Runs the prebuilt pdf-parser image with ocr_engine=ppocrv6 as default.
# GPU devices are mounted ONLY so paddle can import (OCR itself runs on CPU).
{ pkgs, lib, config, ... }:

let
  docker = "${pkgs.docker}/bin/docker";
  nvidiaLibs = "${config.hardware.nvidia.package}/lib";
in
{
  systemd.tmpfiles.rules = [
    "d /var/lib/pdf-ocr 0755 root root -"
  ];

  systemd.services.pdf-ocr = {
    description = "PDF Local OCR — PP-OCRv6 (Docker)";
    # Disabled 2026-09-28 — superseded by pdf-parse (Cohere Parse v5.0).
    # Nothing routes here. Unit + source retained for rollback:
    #   systemctl start pdf-extractor   (or pdf-ocr)
    # Source vendored at compose/legacy/.
    enable = false;
    after = [ "network.target" "docker.service" ];
    requires = [ "docker.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeScript "pdf-ocr-start" ''
        #!${pkgs.bash}/bin/bash
        ${docker} rm -f pdf-ocr 2>/dev/null || true
        # Default config: PP-OCRv6 engine, no VLM (local only)
        mkdir -p /var/lib/pdf-ocr
        cat > /var/lib/pdf-ocr/config.json << 'CFG'
        {
          "ocr_engine": "ppocrv6",
          "vlm_provider": "none"
        }
        CFG
        exec ${docker} run -d --name pdf-ocr \
          --restart unless-stopped \
          --network proxy \
          -p 127.0.0.1:8000:8000 \
          --memory 8g \
          --memory-swap 12g \
          --cpus 2.0 \
          --device /dev/nvidia0 \
          --device /dev/nvidiactl \
          --device /dev/nvidia-modeset \
          --device /dev/nvidia-uvm \
          --device /dev/nvidia-uvm-tools \
          -v /var/lib/pdf-ocr:/data \
          -v ${nvidiaLibs}:/opt/nvidia/lib:ro \
          -e HF_HOME=/data/cache \
          -e DOCLING_DEVICE=cuda \
          -e LD_LIBRARY_PATH=/opt/nvidia/lib \
          -e VLM_PROVIDER=none \
          pdf-parser-pdf-parser:latest
      '';
      ExecStartPost = pkgs.writeShellScript "pdf-ocr-patch" ''
        sleep 8
        # Force PP-OCRv6 to CPU (GTX 960 2GB too small for GPU OCR)
        ${docker} exec pdf-ocr sed -i \
          's/device = "gpu"/device = "cpu"  # GTX 960 2GB too small for GPU OCR/' \
          /usr/local/lib/python3.12/site-packages/docling_ppocr_v6/ocr_engine.py 2>/dev/null || true
        ${docker} exec pdf-ocr sed -i \
          's/device = "gpu"/device = "cpu"  # GTX 960 2GB too small for GPU OCR/' \
          /app/plugins/docling_ppocr_v6/ocr_engine.py 2>/dev/null || true
        # Pin formula enrichment OFF (flips on with vlm_provider != none; was OOM culprit)
        ${docker} exec pdf-ocr sed -i \
          's/do_formula_enrichment=self._vlm_provider != "none",/do_formula_enrichment=False,/' \
          /app/parser.py 2>/dev/null || true
        # Disable paddle oneDNN/MKLDNN — causes infinite hang on some PDFs (ReduceMeanCheckIfOneDNNSupport)
        ${docker} exec pdf-ocr sed -i \
          's|        from paddleocr import PaddleOCR|        import paddle\n        paddle.set_flags({\"FLAGS_use_mkldnn\": False})\n        from paddleocr import PaddleOCR|' \
          /usr/local/lib/python3.12/site-packages/docling_ppocr_v6/ocr_engine.py 2>/dev/null || true
        # pymupdf needed by text-layer detection + normalization (not in image)
        ${docker} exec pdf-ocr pip install -q pymupdf 2>/dev/null || true
        # Apply all runtime patches (patch_all.py is idempotent, lives in /data volume)
        ${docker} exec pdf-ocr python3 /data/patch_all.py 2>/dev/null || true
        # Clear Python cache
        ${docker} exec pdf-ocr rm -rf \
          /usr/local/lib/python3.12/site-packages/docling_ppocr_v6/__pycache__ \
          /app/plugins/docling_ppocr_v6/__pycache__ 2>/dev/null || true
        # Set engine to ppocrv6 via config file (belt and suspenders)
        ${docker} exec pdf-ocr python3 -c "
import json
from pathlib import Path
p = Path('/data/config.json')
cfg = json.loads(p.read_text()) if p.exists() else {}
cfg['ocr_engine'] = 'ppocrv6'
cfg['vlm_provider'] = 'none'
p.write_text(json.dumps(cfg))
print('config set:', cfg)
" 2>/dev/null || true
        # Restart so uvicorn loads the patched code (patches applied post-start)
        ${docker} restart pdf-ocr 2>/dev/null || true
        echo "pdf-ocr patches applied"
      '';
      ExecStop = "${docker} stop pdf-ocr";
    };
  };
}
