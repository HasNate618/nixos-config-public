import os
import re
import asyncio
import logging
import tempfile
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor

from PIL import Image as PILImage

from docling.document_converter import DocumentConverter, PdfFormatOption
from docling.datamodel.base_models import InputFormat
from docling.datamodel.pipeline_options import (
    PdfPipelineOptions,
    AcceleratorOptions,
    PictureDescriptionApiOptions,
)

logger = logging.getLogger(__name__)


VLM_PROVIDERS = {
    "local": {
        "label": "Local VLM (Qwen3-VL)",
        "url": "http://llama-cpp-vlm:8083/v1/chat/completions",
        "model": "qwen3-vl-2b-instruct",
    },
    "cohere": {
        "label": "Cohere via Bifrost",
        "url": "http://bifrost:8080/v1/chat/completions",
        "model": "cohere/command-a-vision-07-2025",
    },
    "none": {
        "label": "None",
        "url": "",
        "model": "",
    },
}


class PDFParser:
    def __init__(self, cache_dir: Path, device: str = "cpu", provider: str = "local", ocr_engine: str = "rapid"):
        self.device = device
        self._vlm_provider = provider
        self._ocr_engine = ocr_engine
        os.environ.setdefault("HF_HOME", str(cache_dir / "hf"))
        hf_cache = Path(os.environ["HF_HOME"])
        hf_cache.mkdir(parents=True, exist_ok=True)
        self._executor = ThreadPoolExecutor(max_workers=1)
        self._converter = None

    @property
    def vlm_provider(self) -> str:
        return self._vlm_provider

    @vlm_provider.setter
    def vlm_provider(self, provider: str):
        if provider not in VLM_PROVIDERS:
            raise ValueError(f"Unknown VLM provider: {provider}")
        self._vlm_provider = provider
        self._converter = None
        try:
            import torch
            torch.cuda.empty_cache()
        except ImportError:
            pass

    @property
    def ocr_engine(self) -> str:
        return self._ocr_engine

    @ocr_engine.setter
    def ocr_engine(self, engine: str):
        if engine not in ("rapid", "ppocrv6"):
            raise ValueError(f"Unknown OCR engine: {engine}")
        self._ocr_engine = engine
        self._converter = None

    @property
    def vlm_config(self) -> dict:
        return {"provider": self._vlm_provider, **VLM_PROVIDERS[self._vlm_provider]}

    def _init_converter(self) -> DocumentConverter:
        accelerator = AcceleratorOptions(
            device=self.device,
            num_threads=4,
        )
        prov = VLM_PROVIDERS[self._vlm_provider]

        kwargs = dict(
            do_picture_description=self._vlm_provider != "none",
            do_table_structure=True,
            do_formula_enrichment=True,
            enable_remote_services=True,
            accelerator_options=accelerator,
            layout_batch_size=1,
            ocr_batch_size=1,
            table_batch_size=1,
        )

        # Select OCR engine
        if self._ocr_engine == "ppocrv6":
            from docling_ppocr_v6.ocr_engine import PpOcrV6Options
            kwargs["do_ocr"] = True
            kwargs["allow_external_plugins"] = True
            kwargs["ocr_options"] = PpOcrV6Options(
                lang="en",
                force_full_page_ocr=True,
            )
            logger.info("Using PP-OCRv6 OCR engine")
        # else: RapidOCR is the default (no need to set)

        if prov["url"]:
            kwargs["picture_description_options"] = PictureDescriptionApiOptions(
                url=prov["url"],
                prompt="Describe this image or diagram concisely.",
                timeout=120,
                concurrency=2,
                params={"model": prov["model"]},
            )

        pipeline_opts = PdfPipelineOptions(**kwargs)
        return DocumentConverter(
            format_options={
                InputFormat.PDF: PdfFormatOption(pipeline_options=pipeline_opts),
            }
        )

    async def warmup(self):
        loop = asyncio.get_event_loop()
        await loop.run_in_executor(self._executor, self._init_converter)

    async def parse(self, input_path: Path, output_path: Path) -> int:
        loop = asyncio.get_event_loop()

        img_exts = {".png", ".jpg", ".jpeg", ".gif", ".webp", ".bmp", ".tiff"}
        doc_path = input_path
        if input_path.suffix.lower() in img_exts:
            pdf_path = input_path.with_suffix(".pdf")

            def _to_pdf():
                img = PILImage.open(input_path)
                if img.mode != "RGB":
                    img = img.convert("RGB")
                img.save(pdf_path, "PDF", resolution=100)

            await loop.run_in_executor(self._executor, _to_pdf)
            doc_path = pdf_path

        try:
            if self._converter is None:
                self._converter = await loop.run_in_executor(
                    self._executor, self._init_converter
                )
        except Exception as e:
            logger.warning("GPU init failed (%s), falling back to CPU", e)
            self.device = "cpu"
            self._converter = await loop.run_in_executor(
                self._executor, self._init_converter
            )

        result = await loop.run_in_executor(
            self._executor, self._converter.convert, str(doc_path)
        )

        markdown = result.document.export_to_markdown()
        if self._vlm_provider == "none":
            markdown = re.sub(r'<!--\s*image\s*-->', '', markdown, flags=re.IGNORECASE)
            markdown = re.sub(r'\n{3,}', '\n\n', markdown).strip()
        output_path.write_text(markdown, encoding="utf-8")

        page_count = len(result.document.pages) if result.document.pages else 1
        return page_count
