FROM python:3.12-slim
RUN pip install --no-cache-dir pymupdf fastapi uvicorn httpx python-multipart
COPY server.py /app/server.py
WORKDIR /app
CMD ["uvicorn", "server:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "1"]
