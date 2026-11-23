"""
Docling OCR plugin for PaddleOCR PP-OCRv6.

Replaces the default RapidOCR (PP-OCRv4) with PP-OCRv6 for better
accuracy and 50-language support.

Usage:
    from docling_ppocr_v6.ocr_engine import PpOcrV6Options
    pipeline_options.ocr_options = PpOcrV6Options(lang="en")
"""

from __future__ import annotations

import logging
import os
import tempfile
from pathlib import Path
from typing import ClassVar, Iterable, Optional, Type

import numpy as np
from PIL import Image

from docling_core.types.doc import BoundingBox, CoordOrigin
from docling_core.types.doc.page import TextCell
from docling.datamodel.accelerator_options import AcceleratorOptions
from docling.datamodel.base_models import Page
from docling.datamodel.document import ConversionResult
from docling.datamodel.pipeline_options import OcrOptions
from docling.datamodel.settings import settings
from docling.models.base_ocr_model import BaseOcrModel
from docling.utils.profiling import TimeRecorder

_log = logging.getLogger(__name__)


class PpOcrV6Options(OcrOptions):
    """Configuration for PaddleOCR PP-OCRv6."""

    kind: ClassVar[str] = "ppocrv6"
    lang: str = "en"
    use_doc_orientation_classify: bool = False
    use_doc_unwarping: bool = False
    use_textline_orientation: bool = False
    force_full_page_ocr: bool = True


class PpOcrV6Model(BaseOcrModel):
    """PaddleOCR PP-OCRv6 OCR engine for docling."""

    def __init__(
        self,
        enabled: bool,
        artifacts_path: Optional[Path],
        options: PpOcrV6Options,
        accelerator_options: AcceleratorOptions,
    ):
        self._accelerator_options = accelerator_options
        self._artifacts_path = artifacts_path
        super().__init__(
            enabled=enabled,
            artifacts_path=artifacts_path,
            options=options,
            accelerator_options=accelerator_options,
        )
        self.options: PpOcrV6Options = options
        self.scale = 3  # multiplier for 72 dpi == 216 dpi
        self._engine = None

        if self.enabled:
            self._init_engine()

    def _init_engine(self):
        """Initialize PaddleOCR engine."""
        from paddleocr import PaddleOCR

        device = "cpu"  # PaddleOCR GPU returns empty on GTX 960 (Maxwell)
        _log.info(
            "Initializing PaddleOCR PP-OCRv6 (lang=%s, device=%s)",
            self.options.lang,
            device,
        )

        self._engine = PaddleOCR(
            lang=self.options.lang,
            device=device,
            use_doc_orientation_classify=self.options.use_doc_orientation_classify,
            use_doc_unwarping=self.options.use_doc_unwarping,
            use_textline_orientation=self.options.use_textline_orientation,
        )

    @classmethod
    def get_options_type(cls) -> Type[OcrOptions]:
        return PpOcrV6Options

    def __call__(
        self, conv_res: ConversionResult, page_batch: Iterable[Page]
    ) -> Iterable[Page]:
        if not self.enabled:
            yield from page_batch
            return

        for page in page_batch:
            assert page._backend is not None
            if not page._backend.is_valid():
                yield page
            else:
                with TimeRecorder(conv_res, "ocr"):
                    all_ocr_cells = []

                    if self.options.force_full_page_ocr:
                        # Full-page OCR — run on entire page image
                        high_res_image = page._backend.get_page_image(
                            scale=self.scale
                        )
                        cells = self._run_ocr_on_image(high_res_image)
                        # Scale coordinates back to page coordinates
                        for cell in cells:
                            cell.rect = self._scale_rect(cell.rect, self.scale)
                        all_ocr_cells.extend(cells)
                        del high_res_image
                    else:
                        # Selective OCR — only OCR bitmap regions
                        ocr_rects = self.get_ocr_rects(page)
                        for ocr_rect in ocr_rects:
                            if ocr_rect.area() == 0:
                                continue
                            high_res_image = page._backend.get_page_image(
                                scale=self.scale, cropbox=ocr_rect
                            )
                            cells = self._run_ocr_on_image(high_res_image)
                            # Adjust coordinates for crop offset and scale
                            for cell in cells:
                                cell.rect = self._offset_and_scale_rect(
                                    cell.rect, ocr_rect, self.scale
                                )
                            all_ocr_cells.extend(cells)
                            del high_res_image

                    # Post-process: combine with existing cells
                    self.post_process_cells(all_ocr_cells, page)

                yield page

    def _run_ocr_on_image(self, pil_image: Image.Image) -> list[TextCell]:
        """Run PaddleOCR on a PIL image and return TextCell objects."""
        cells = []

        # Save to temp file (PaddleOCR v3.7 expects file path)
        tmp_path = None
        try:
            with tempfile.NamedTemporaryFile(suffix=".png", delete=False) as tmp:
                pil_image.save(tmp.name)
                tmp_path = tmp.name

            ocr_result = self._engine.ocr(tmp_path)
        except Exception as e:
            _log.warning("PaddleOCR failed: %s", e)
            return cells
        finally:
            if tmp_path and os.path.exists(tmp_path):
                os.unlink(tmp_path)

        if not ocr_result or len(ocr_result) == 0:
            return cells

        page_result = ocr_result[0]
        rec_texts = page_result.get("rec_texts", [])
        rec_scores = page_result.get("rec_scores", [])
        rec_polys = page_result.get("rec_polys", [])

        for i, text in enumerate(rec_texts):
            confidence = rec_scores[i] if i < len(rec_scores) else 0.0
            poly = rec_polys[i] if i < len(rec_polys) else None

            if poly is not None:
                # rec_polys is numpy array of shape (4, 2) — polygon points
                xs = [float(p[0]) for p in poly]
                ys = [float(p[1]) for p in poly]
                from docling_core.types.doc import BoundingRectangle
                rect = BoundingRectangle(
                    r_x0=xs[0], r_y0=ys[0],
                    r_x1=xs[1], r_y1=ys[1],
                    r_x2=xs[2], r_y2=ys[2],
                    r_x3=xs[3], r_y3=ys[3],
                    coord_origin=CoordOrigin.TOPLEFT,
                )
            else:
                continue

            cells.append(
                TextCell(
                    index=i,
                    text=text,
                    orig=text,
                    from_ocr=True,
                    confidence=confidence,
                    rect=rect,
                )
            )

        return cells

    @staticmethod
    def _scale_rect(rect, scale: float):
        """Scale a BoundingRectangle by dividing coordinates by scale factor."""
        from docling_core.types.doc import BoundingRectangle

        return BoundingRectangle(
            r_x0=rect.r_x0 / scale,
            r_y0=rect.r_y0 / scale,
            r_x1=rect.r_x1 / scale,
            r_y1=rect.r_y1 / scale,
            r_x2=rect.r_x2 / scale,
            r_y2=rect.r_y2 / scale,
            r_x3=rect.r_x3 / scale,
            r_y3=rect.r_y3 / scale,
            coord_origin=CoordOrigin.TOPLEFT,
        )

    @staticmethod
    def _offset_and_scale_rect(rect, offset: BoundingBox, scale: float):
        """Offset by crop box and scale by factor."""
        from docling_core.types.doc import BoundingRectangle

        return BoundingRectangle(
            r_x0=rect.r_x0 / scale + offset.l,
            r_y0=rect.r_y0 / scale + offset.t,
            r_x1=rect.r_x1 / scale + offset.l,
            r_y1=rect.r_y1 / scale + offset.t,
            r_x2=rect.r_x2 / scale + offset.l,
            r_y2=rect.r_y2 / scale + offset.t,
            r_x3=rect.r_x3 / scale + offset.l,
            r_y3=rect.r_y3 / scale + offset.t,
            coord_origin=CoordOrigin.TOPLEFT,
        )


def get_ocr_engines():
    """Return (ModelClass, OptionsClass) for docling plugin registration."""
    return {"ocr_engines": [PpOcrV6Model]}


# Module-level attribute for docling plugin discovery
def ocr_engines():
    return get_ocr_engines()
