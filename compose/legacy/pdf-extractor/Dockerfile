FROM python:3.11-slim

WORKDIR /app

# System deps for local OCR mode
RUN apt-get update && apt-get install -y --no-install-recommends \
    tesseract-ocr tesseract-ocr-eng ghostscript qpdf \
    && rm -rf /var/lib/apt/lists/*

RUN pip install --no-cache-dir pymupdf ocrmypdf fastapi uvicorn[standard] httpx python-multipart

COPY server.py .

ENV PDF_ENGINE=cloud
ENV BIFROST_URL=http://bifrost:8080
ENV VISION_MODELS=cohere/command-a-vision-07-2025,opencode-go/mimo-v2.5
ENV MAX_CONCURRENT=3
ENV JOBS_DIR=/data/jobs

VOLUME /data/jobs
EXPOSE 8000
CMD ["uvicorn", "server:app", "--host", "0.0.0.0", "--port", "8000"]
