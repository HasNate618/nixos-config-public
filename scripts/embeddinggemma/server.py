"""EmbeddingGemma 2 embedding server — full multimodal (text, image, audio, video).

OpenAI-compatible text + image endpoint:
  POST /v1/embeddings   accepts:
      - input: str | [str]                       (plain text)
      - input: [{content:[{type:"text",...},
                          {type:"image_url",image_url:{url:data:...|https://...}},
                          {type:"video_url",video_url:{url:data:...|https://...}}]}]
        A mixed item (e.g. video frame + text) becomes ONE combined embedding.
      -> data[].embedding (768-d by default; dimensions truncates via MRL)

Extension endpoint (all four modalities, per item):
  POST /v1/embed        {input: [{type: text|image|audio|video, ...}]}
                        -> one vector per item (shared 768-d space)
    image/audio/video items take b64 or url (data: URL or http(s)).
    video is decoded to RGB frames via PyAV.
"""
import base64
import io
import os
import re
import threading
import time
import urllib.request

import numpy as np
import torch
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field
from sentence_transformers import SentenceTransformer
from PIL import Image

MODEL_ID = os.environ.get("EMBED_MODEL", "google/embeddinggemma-2")
DEVICE = os.environ.get("EMBED_DEVICE", "cuda")
BATCH = int(os.environ.get("EMBED_BATCH", "2"))  # 2 GB VRAM: keep small
MAX_LEN = int(os.environ.get("EMBED_MAX_LEN", "8192"))
# video: cap sampled frames so a long clip fits the 2 GB card
VIDEO_MAX_FRAMES = int(os.environ.get("EMBED_VIDEO_MAX_FRAMES", "4"))
VIDEO_FRAME_SIZE = int(os.environ.get("EMBED_VIDEO_FRAME_SIZE", "112"))

app = FastAPI(title="embeddinggemma2")
_model = None
_lock = threading.Lock()  # one forward pass at a time on a 2 GB card
_load_error = None


def get_model():
    global _model, _load_error
    if _model is None and _load_error is None:
        with _lock:
            if _model is None and _load_error is None:
                try:
                    m = SentenceTransformer(MODEL_ID, device=DEVICE,
                                            model_kwargs={"torch_dtype": torch.float16})
                    if next(m.parameters()).dtype != torch.float16:
                        m = m.to(torch.float16)
                    m.max_seq_length = MAX_LEN
                    m.encode(["warmup"], normalize_embeddings=True)  # kernel selection
                    _model = m
                except Exception as e:  # surface load failure, don't crash-loop silently
                    _load_error = f"{type(e).__name__}: {e}"
    return _model


class EmbRequest(BaseModel):
    model: str | None = None
    input: str | list
    dimensions: int | None = None  # MRL truncation, 128..768
    encoding_format: str | None = None  # accepted (OpenAI shape); float only
    input_type: str | None = None  # Cohere-style hint (unused)


class Item(BaseModel):
    type: str  # text | image | audio | video
    text: str | None = None
    url: str | None = None
    b64: str | None = None
    media_type: str | None = None


class MMRequest(BaseModel):
    model: str | None = None
    input: list[Item] = Field(default_factory=list)


def _data_url_to_b64(url: str) -> str:
    """Extract base64 payload from a data: URL, else fetch the http(s) URL."""
    if url.startswith("data:"):
        m = re.match(r"data:[^;,]*(;base64)?,(.*)$", url, re.S)
        if not m:
            raise HTTPException(400, "malformed data: URL")
        return m.group(2)
    if url.startswith("http://") or url.startswith("https://"):
        with urllib.request.urlopen(url, timeout=60) as r:
            return base64.b64encode(r.read()).decode()
    raise HTTPException(400, "url must be a data: URL or http(s) URL")


def _encode(items, truncate_dim: int | None = None):
    """Encode a list of (str | PIL.Image | np.ndarray | list-of-frames) -> (vectors, ms)."""
    t0 = time.time()
    with _lock:
        try:
            v = _model.encode(items, normalize_embeddings=True, batch_size=1,
                              truncate_dim=truncate_dim or None)
            torch.cuda.synchronize()
        except torch.cuda.OutOfMemoryError:
            torch.cuda.empty_cache()
            raise HTTPException(503, "GPU out of memory; retry one item at a time")
    return np.asarray(v), (time.time() - t0) * 1000


def _decode_image_from_b64(b64: str) -> Image.Image:
    try:
        return Image.open(io.BytesIO(base64.b64decode(b64))).convert("RGB")
    except Exception as e:
        raise HTTPException(400, f"cannot decode image: {e}")


def _decode_audio_from_b64(b64: str) -> np.ndarray:
    try:
        import soundfile as sf
        audio, sr = sf.read(io.BytesIO(base64.b64decode(b64)), dtype="float32")
        if audio.ndim > 1:
            audio = audio.mean(axis=1)
        if sr != 16000:  # model expects 16 kHz mono
            idx = (np.arange(int(len(audio) * 16000 / sr)) * sr / 16000).astype(np.int64)
            audio = audio[np.clip(idx, 0, len(audio) - 1)]
        return audio
    except Exception as e:
        raise HTTPException(400, f"cannot decode audio: {e}")


def _decode_video_from_b64(b64: str) -> dict:
    """Decode a video (base64 mp4/etc.) into the in-memory array form
    sentence-transformers expects for video:

        {"video": {"array": frames[H,W,3], "video_metadata": {...}}}

    Frames are decoded with PyAV, downscaled to VIDEO_FRAME_SIZE and capped at
    VIDEO_MAX_FRAMES -- on the 2 GB card a large frame batch OOMs in the vision
    encoder, so video is necessarily low-res / few-frame here. This path does
    NOT use torchcodec (whose current build needs CUDA 13 / libnvrtc.so.13)."""
    try:
        import av
    except Exception:
        raise HTTPException(500, "video support not installed (PyAV missing)")
    try:
        raw = base64.b64decode(b64)
        container = av.open(io.BytesIO(raw))
        stream = container.streams.video[0]
        fps = float(stream.average_rate) if stream.average_rate else 8.0
        raw_frames = [f.to_ndarray(format="rgb24") for f in container.decode(stream)]
        if not raw_frames:
            raise HTTPException(400, "video decoded to zero frames")
        if len(raw_frames) > VIDEO_MAX_FRAMES:
            idx = np.linspace(0, len(raw_frames) - 1, VIDEO_MAX_FRAMES).astype(int)
            raw_frames = [raw_frames[i] for i in idx]
        size = VIDEO_FRAME_SIZE
        small = [np.asarray(Image.fromarray(f).resize((size, size)))
                 for f in raw_frames]
        frames = np.stack(small)
        return {"video": {"array": frames,
                          "video_metadata": {"fps": fps,
                                             "total_num_frames": len(frames)}}}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(400, f"cannot decode video: {e}")


def _b64_or_url(item, field_hint):
    """Resolve an item's media to base64 from b64 or url."""
    if item.b64:
        return item.b64
    if item.url and item.url.startswith(("data:", "http")):
        return _data_url_to_b64(item.url)
    raise HTTPException(400, f"{field_hint} item needs 'b64' or a data:/http(s) 'url'")


def _parse_content_list(content: list):
    """OpenAI chat-style content parts -> a single sentence-transformers object.

    Supported parts:
      {"type":"text", "text": "..."}
      {"type":"image_url", "image_url": {"url": data:...|https://...}}
      {"type":"video_url", "video_url": {"url": data:...|https://...}}

    Single modality -> a bare string / PIL.Image / video-dict.
    Multiple modalities in one item -> one multimodal dict, e.g.
      {"text": "...", "image": <PIL>} or {"text": "...", "video": {...}}
    so mixed content becomes ONE combined embedding over the shared space.
    (A list of separate inputs is also accepted by _encode, but per-item
    multimodal dict is how text+video/image fuse into a single vector.)
    """
    if not isinstance(content, list):
        raise HTTPException(400, "'content' must be a list of parts")
    collected = {}   # modality key -> value
    order = []
    for part in content:
        if not isinstance(part, dict):
            raise HTTPException(400, "content parts must be objects")
        ptype = part.get("type")
        if ptype == "text":
            if "text" not in part:
                raise HTTPException(400, "text part needs 'text'")
            collected["text"] = part["text"]; order.append("text")
        elif ptype == "image_url":
            iu = part.get("image_url") or {}
            url = iu.get("url")
            if not url:
                raise HTTPException(400, "image_url part needs 'url'")
            collected["image"] = _decode_image_from_b64(_data_url_to_b64(url)); order.append("image")
        elif ptype == "video_url":
            vu = part.get("video_url") or {}
            url = vu.get("url")
            if not url:
                raise HTTPException(400, "video_url part needs 'url'")
            # _decode_video_from_b64 returns {"video": {...}}; merge its inner dict
            vobj = _decode_video_from_b64(_data_url_to_b64(url))
            collected["video"] = vobj["video"]; order.append("video")
        else:
            raise HTTPException(400, f"unsupported content part type {ptype!r}")
    if not collected:
        raise HTTPException(400, "empty content list")
    if len(order) == 1:
        # single modality: unwrap to the bare value
        key = order[0]
        return collected[key]
    # multimodal dict, preserving first-seen order
    return {k: collected[k] for k in order}


@app.get("/health")
def health():
    if _load_error:
        return {"status": "error", "detail": _load_error}, 500
    m = get_model()
    if m is None:
        return {"status": "loading"}, 503
    free, total = torch.cuda.mem_get_info()
    return {"status": "ok", "model": MODEL_ID, "device": DEVICE,
            "vram_free_mb": free // 1024 // 1024, "vram_total_mb": total // 1024 // 1024}


@app.get("/v1/models")
def models():
    return {"object": "list", "data": [
        {"id": MODEL_ID, "object": "model", "owned_by": "google"}]}


@app.post("/v1/embeddings")
def embeddings(req: EmbRequest):
    m = get_model()
    if m is None:
        raise HTTPException(503, _load_error or "model loading, retry")
    raw = req.input
    if isinstance(raw, str):
        items = [raw]
    elif isinstance(raw, list) and raw and all(isinstance(x, str) for x in raw):
        items = list(raw)
    elif isinstance(raw, list) and raw and all(isinstance(x, dict) for x in raw):
        # OpenAI chat-style content items
        items = [_parse_content_list(x.get("content") or []) for x in raw]
    else:
        raise HTTPException(
            400, "input must be a string, a list of strings, "
                "or a list of {content:[...]} items")
    vecs, ms = _encode(items, truncate_dim=req.dimensions)
    data = [{"object": "embedding", "index": i, "embedding": [float(x) for x in v]}
            for i, v in enumerate(vecs)]
    return {"object": "list", "model": req.model or MODEL_ID, "data": data,
            "usage": {"prompt_tokens": 0, "total_tokens": 0},
            "latency_ms": round(ms, 1)}


def load_item(item: Item):
    if item.type == "text":
        if not item.text:
            raise HTTPException(400, "text item needs 'text'")
        return item.text
    if item.type == "image":
        return _decode_image_from_b64(_b64_or_url(item, "image"))
    if item.type == "audio":
        return _decode_audio_from_b64(_b64_or_url(item, "audio"))
    if item.type == "video":
        return _decode_video_from_b64(_b64_or_url(item, "video"))
    raise HTTPException(400, f"unknown input type {item.type!r}")


@app.post("/v1/embed")
def embed_mm(req: MMRequest):
    m = get_model()
    if m is None:
        raise HTTPException(503, _load_error or "model loading, retry")
    if not req.input:
        raise HTTPException(400, "input must be a non-empty list")
    objects = [load_item(it) for it in req.input]
    vecs, ms = _encode(objects)
    if vecs.ndim == 1:
        vecs = vecs[None, :]
    return {"object": "list", "model": req.model or MODEL_ID,
            "data": [{"object": "embedding", "index": i,
                      "embedding": [float(x) for x in vec]}
                     for i, vec in enumerate(vecs)],
            "latency_ms": round(ms, 1)}
