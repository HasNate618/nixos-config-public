import os
import logging
import subprocess
import json as _json
import asyncio
from pathlib import Path

logger = logging.getLogger(__name__)

CO_API_KEY = os.environ.get("CO_API_KEY", "")
CO_API_URL = "https://api.cohere.com/v2/audio/transcriptions"

MODELS = {
    "cohere-transcribe-03-2026": {
        "params": "Cloud API",
        "vram": "0 MB (cloud)",
        "quality": "Best",
        "label": "Cohere Transcribe",
    },
}


class Transcriber:
    def __init__(self, device: str = "cuda", model_name: str = "cohere-transcribe-03-2026"):
        self.device = device
        self.model_name = model_name
        self._ready = True

    async def warmup(self):
        logger.info("Cohere Transcribe ready (cloud API)")

    @property
    def info(self) -> dict:
        return {
            "device": "cohere-api",
            "model": self.model_name,
            "ready": self._ready,
            "models": MODELS,
        }

    async def transcribe(self, audio_path: Path, output_path: Path, model_name: str | None = None, on_progress=None) -> tuple[str, str, float]:
        """Transcribe audio file via Cohere API. Returns (text, language, duration)."""
        import httpx

        # Get duration with ffprobe
        duration = 0.0
        try:
            result = subprocess.run(
                ["ffprobe", "-v", "quiet", "-print_format", "json", "-show_format", str(audio_path)],
                capture_output=True, text=True, timeout=10,
            )
            info = _json.loads(result.stdout)
            duration = float(info.get("format", {}).get("duration", 0))
        except Exception:
            pass

        # Upload to Cohere — fields must appear before file in multipart
        model = model_name or self.model_name
        async with httpx.AsyncClient(timeout=300.0) as client:
            with open(audio_path, "rb") as f:
                # httpx sends fields in order since Python 3.7+ dict insertion order
                files = [
                    ("model", (None, model, None)),
                    ("language", (None, "en", None)),
                    ("file", (audio_path.name, f, _mime_type(audio_path.suffix))),
                ]
                resp = await client.post(
                    CO_API_URL,
                    headers={"Authorization": f"Bearer {CO_API_KEY}"},
                    files=files,
                )

            if resp.status_code != 200:
                error_detail = resp.text[:500]
                logger.error("Cohere API error %d: %s", resp.status_code, error_detail)
                raise RuntimeError(f"Cohere API error {resp.status_code}: {error_detail}")

            data = resp.json()
            text = data.get("text", "")
            lang = data.get("language", "en")

        # Write clean transcript
        header = f"Language: {lang}\n"
        header += f"Duration: {duration:.1f}s\n"
        header += f"Model: {model}\n"
        header += "=" * 60 + "\n\n"

        transcript = header + text.strip()
        output_path.write_text(transcript, encoding="utf-8")

        if on_progress:
            on_progress(1)

        return text.strip(), lang, duration

    def _load_model(self, model_name: str):
        self.model_name = model_name
        self._ready = True


def _mime_type(ext: str) -> str:
    return {
        ".mp3": "audio/mpeg",
        ".wav": "audio/wav",
        ".m4a": "audio/mp4",
        ".ogg": "audio/ogg",
        ".flac": "audio/flac",
        ".aac": "audio/aac",
        ".opus": "audio/opus",
        ".webm": "audio/webm",
        ".mp4": "audio/mp4",
    }.get(ext.lower(), "application/octet-stream")
