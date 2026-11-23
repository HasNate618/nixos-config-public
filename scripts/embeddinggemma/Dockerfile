# EmbeddingGemma 2 embedding server
# Image built from repo source (scripts/embeddinggemma) so it's reproducible.
# torch is pinned to the cu126 build: it is the LAST PyTorch line with sm_50
# (Maxwell) support, and the homelab GPU is a GTX 960 (sm_52). cu130 default
# wheels drop it, and the host driver (535) cannot run CUDA 13.
# Multimodal: text + image + audio in one 768-d space (direct calls, NOT via
# Bifrost - its OpenAI /v1/embeddings shape is text only).
FROM pytorch/pytorch:2.5.1-cuda12.4-cudnn9-runtime
RUN pip uninstall -y torchaudio || true
RUN pip install -q torch==2.14.1 --index-url https://download.pytorch.org/whl/cu126
RUN pip install -q -U transformers sentence-transformers pillow
RUN pip install -q torchvision --index-url https://download.pytorch.org/whl/cu126
RUN pip install -q fastapi uvicorn soundfile av

# Weights live in the mounted HF cache, not the image
ENV EMBED_MODEL=google/embeddinggemma-2 \
    EMBED_DEVICE=cuda \
    EMBED_BATCH=2 \
    EMBED_MAX_LEN=8192 \
    PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True \
    HF_HOME=/cache/huggingface

COPY server.py /app/server.py
WORKDIR /app

EXPOSE 8081
HEALTHCHECK --interval=30s --timeout=15s --start-period=180s --retries=3 \
  CMD python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8081/health', timeout=10).status==200 else 1)"

CMD ["uvicorn", "server:app", "--host", "0.0.0.0", "--port", "8081", "--workers", "1"]
