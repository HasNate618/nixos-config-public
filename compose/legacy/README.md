# Legacy PDF stack (superseded — retained as rollback only)

Archived 2026-09-28. Neither service is routed to any consumer; both are
stopped. `pdf-parse` (Cohere Parse v5.0) replaced them.

| Dir | Was | Replaced by |
|---|---|---|
| `pdf-extractor/` | Orchestrator: VLM/cloud vs local routing, job dashboard UI | `pdf-parse` |
| `pdf-parser/` | Docling + PP-OCRv6 local OCR engine (built the 23.4 GB image) | `pdf-parse` + PyMuPDF fallback |

Kept so the 23.4 GB Docling/PP-OCRv6 image is rebuildable without re-deriving
it. The `pdf-ocr.nix` module still references `pdf-parser-pdf-parser:latest`.

**Do not re-enable without reading the reasoning:** the local path was
unreliable — 34-page pathological scans wedged the single worker for 8+ hours,
Paddle oneDNN infinite-looped on mixed-script pages, and 4 GB cgroup OOM'd.
Docling on CUDA is fast (16 s for the 12-page midterm) but Parse is both
faster and higher quality, with no local failure modes to debug.
