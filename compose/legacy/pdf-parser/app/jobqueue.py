import json
import time
import shutil
from pathlib import Path


def _input_name(filename: str) -> str:
    ext = Path(filename).suffix.lower()
    if ext in (".pdf", ".docx", ".pptx", ".png", ".jpg", ".jpeg", ".csv", ".xlsx", ".html", ".md", ".xml", ".txt"):
        return f"input{ext}"
    return "input.bin"


class Job:
    def __init__(self, job_id: str, filename: str, input_path: Path, output_path: Path):
        self.id = job_id
        self.filename = filename
        self.input_path = input_path
        self.output_path = output_path
        self.status = "queued"
        self.pages_total = 0
        self.pages_done = 0
        self.error = None
        self.created_at = time.time()
        self.finished_at = None

    @property
    def dir(self) -> Path:
        return self.input_path.parent

    @property
    def processing_time_seconds(self):
        if not self.finished_at or not self.created_at:
            return None
        from datetime import datetime
        finished = datetime.fromisoformat(self.finished_at).timestamp() if isinstance(self.finished_at, str) else self.finished_at
        secs = finished - self.created_at
        return round(secs, 1)

    def to_dict(self):
        return {
            "id": self.id,
            "filename": self.filename,
            "status": self.status,
            "pages_total": self.pages_total,
            "pages_done": self.pages_done,
            "error": self.error,
            "created_at": self.created_at,
            "finished_at": self.finished_at,
            "processing_time_seconds": self.processing_time_seconds,
        }

    @classmethod
    def from_dict(cls, d: dict, job_dir: Path):
        j = cls(d["id"], d["filename"], job_dir / _input_name(d["filename"]), job_dir / "output.md")
        j.status = d["status"]
        j.pages_total = d.get("pages_total", 0)
        j.pages_done = d.get("pages_done", 0)
        j.error = d.get("error")
        j.created_at = d.get("created_at", 0)
        j.finished_at = d.get("finished_at")
        return j


class JobQueue:
    def __init__(self, jobs_dir: Path):
        self.jobs_dir = Path(jobs_dir)
        self.jobs_dir.mkdir(parents=True, exist_ok=True)

    def _job_dir(self, job_id: str) -> Path:
        return self.jobs_dir / job_id

    def _meta_path(self, job_id: str) -> Path:
        return self._job_dir(job_id) / "job.json"

    def create(self, job_id: str, filename: str, content: bytes) -> Job:
        job_dir = self._job_dir(job_id)
        job_dir.mkdir(parents=True, exist_ok=True)
        input_path = job_dir / _input_name(filename)
        input_path.write_bytes(content)
        output_path = job_dir / "output.md"
        job = Job(job_id, filename, input_path, output_path)
        self._save(job)
        return job

    def _save(self, job: Job):
        self._meta_path(job.id).write_text(json.dumps(job.to_dict(), indent=2))

    def _load(self, job_id: str) -> Job | None:
        meta = self._meta_path(job_id)
        if not meta.exists():
            return None
        d = json.loads(meta.read_text())
        return Job.from_dict(d, meta.parent)

    def all(self) -> list[Job]:
        if not self.jobs_dir.exists():
            return []
        jobs = []
        for d in sorted(self.jobs_dir.iterdir()):
            if d.is_dir():
                j = self._load(d.name)
                if j:
                    jobs.append(j)
        return sorted(jobs, key=lambda j: j.created_at, reverse=True)

    def dequeue(self) -> Job | None:
        for d in sorted(self.jobs_dir.iterdir()):
            if not d.is_dir():
                continue
            meta = d / "job.json"
            if not meta.exists():
                continue
            data = json.loads(meta.read_text())
            if data["status"] == "queued":
                job = Job.from_dict(data, d)
                return job
        return None

    def save(self, job: Job):
        self._save(job)

    def remove(self, job_id: str):
        job_dir = self._job_dir(job_id)
        if job_dir.exists():
            shutil.rmtree(job_dir)

    def reset_stuck(self):
        for job in self.all():
            if job.status == "processing":
                job.status = "queued"
                job.error = "reset on restart"
                self._save(job)
