FROM python:3.12-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    tesseract-ocr \
    tesseract-ocr-eng \
    poppler-utils \
    libgl1 \
    libglib2.0-0 \
    && rm -rf /var/lib/apt/lists/*

# Upgrade pip/setuptools first
RUN pip install --no-cache-dir --upgrade pip setuptools wheel

# Install CUDA PyTorch (for docling layout models), docling, FastAPI deps
RUN pip install --no-cache-dir torch torchvision --index-url https://download.pytorch.org/whl/cu126
RUN pip install --no-cache-dir "docling[ocr]>=2.0"
RUN pip install --no-cache-dir fastapi uvicorn jinja2 python-multipart aiofiles Pillow

# Install GPU PaddlePaddle FIRST, then PaddleOCR, then force-reinstall GPU
# to prevent paddleocr from pulling in CPU paddlepaddle
RUN pip install --no-cache-dir paddlepaddle-gpu==3.2.1 \
      -i https://www.paddlepaddle.org.cn/packages/stable/cu126/ && \
    pip install --no-cache-dir "paddleocr>=3.7.0" && \
    pip install --no-cache-dir --force-reinstall --no-deps \
      paddlepaddle-gpu==3.2.1 \
      -i https://www.paddlepaddle.org.cn/packages/stable/cu126/

# Install the PP-OCRv6 docling plugin (no paddle deps — handled above)
COPY app/plugins/ /tmp/plugins/
RUN pip install --no-cache-dir /tmp/plugins/ && rm -rf /tmp/plugins/

# Copy application code
COPY app/ /app
WORKDIR /app

ENV PADDLE_PDX_DISABLE_MODEL_SOURCE_CHECK=True

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
