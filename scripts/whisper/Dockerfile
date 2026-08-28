FROM python:3.12-slim

RUN pip install --no-cache-dir --upgrade pip setuptools wheel
RUN pip install --no-cache-dir fastapi uvicorn jinja2 python-multipart aiofiles httpx

COPY app/ /app
WORKDIR /app

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8086"]
