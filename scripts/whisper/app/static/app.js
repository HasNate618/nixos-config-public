const uploadZone = document.getElementById("upload-zone");
const fileInput = document.getElementById("file-input");
const jobsBody = document.getElementById("jobs-body");
const jobsTable = document.getElementById("jobs-table");
const jobsEmpty = document.getElementById("jobs-empty");
const clearDoneBtn = document.getElementById("clear-done-btn");
const toast = document.getElementById("toast");
const deviceBadge = document.getElementById("device-badge");
const modelSection = document.getElementById("model-section");
const modelBoxes = document.getElementById("model-boxes");

let jobs = [];
let currentModel = "small";

// --- Upload ---

uploadZone.addEventListener("click", () => fileInput.click());

uploadZone.addEventListener("dragover", (e) => {
  e.preventDefault();
  uploadZone.classList.add("drag-over");
});

uploadZone.addEventListener("dragleave", () => {
  uploadZone.classList.remove("drag-over");
});

uploadZone.addEventListener("drop", (e) => {
  e.preventDefault();
  uploadZone.classList.remove("drag-over");
  handleFiles(e.dataTransfer.files);
});

fileInput.addEventListener("change", () => {
  handleFiles(fileInput.files);
  fileInput.value = "";
});

async function handleFiles(fileList) {
  const audio = Array.from(fileList).filter(f => {
    const ext = f.name.split(".").pop().toLowerCase();
    return ["mp3", "wav", "m4a", "ogg", "flac", "aac", "wma", "opus", "webm", "mp4"].includes(ext);
  });
  if (audio.length === 0) {
    showToast("No supported audio files found", true);
    return;
  }

  const form = new FormData();
  for (const f of audio) {
    form.append("files", f);
  }

  try {
    const res = await fetch("/api/upload", { method: "POST", body: form });
    const data = await res.json();
    showToast(`Queued ${data.job_ids.length} file(s)`);
    await refreshJobs();
  } catch (err) {
    showToast("Upload failed: " + err.message, true);
  }
}

// --- Job Polling ---

async function refreshJobs() {
  try {
    const res = await fetch("/api/jobs");
    jobs = await res.json();
    renderJobs();
  } catch (_) {}
}

function renderJobs() {
  if (jobs.length === 0) {
    jobsTable.hidden = true;
    jobsEmpty.hidden = false;
    clearDoneBtn.hidden = true;
    return;
  }

  jobsTable.hidden = false;
  jobsEmpty.hidden = true;
  const hasDone = jobs.some(j => j.status === "done" || j.status === "failed");
  clearDoneBtn.hidden = !hasDone;

  jobsBody.innerHTML = jobs.map(j => {
    const progressHtml = j.status === "processing"
      ? `<div class="progress-bar"><div class="progress-fill indeterminate"></div></div>${j.segments_done > 0 ? `<span class="seg-count">${j.segments_done} segments</span>` : ""}`
      : j.status === "done"
      ? `<span class="badge badge-done">done</span>`
      : `<span class="badge badge-${j.status}">${j.status}</span>`;

    const lang = j.language || "—";
    const dur = j.duration_seconds ? formatDuration(j.duration_seconds) : "—";

    const clickFile = j.status === "done" ? ` onclick="viewContent('${j.id}')" class="clickable"` : "";
    return `<tr class="job-row">
      <td class="col-file" title="${escapeHtml(j.filename)}"${clickFile}>${escapeHtml(truncate(j.filename, 35))}</td>
      <td class="col-lang">${escapeHtml(lang)}</td>
      <td class="col-dur">${dur}</td>
      <td class="col-time">${formatTime(j.processing_time_seconds)}</td>
      <td class="col-status">${progressHtml}${j.error ? `<span class="error-msg" title="${escapeHtml(j.error)}">!</span>` : ""}</td>
      <td class="col-actions">${actionButtons(j)}</td>
    </tr>`;
  }).join("");
}

function actionButtons(j) {
  let html = "";
  if (j.status === "done") {
    html += `<button class="btn btn-sm btn-view" data-id="${j.id}" title="Preview"><svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z"/><circle cx="12" cy="12" r="3"/></svg></button>`;
    html += `<button class="btn btn-sm btn-copy" data-id="${j.id}" title="Copy transcript"><svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="9" y="9" width="13" height="13" rx="2"/><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"/></svg></button>`;
    html += `<button class="btn btn-sm btn-dl" data-id="${j.id}" title="Download transcript"><svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="7 10 12 15 17 10"/><line x1="12" y1="15" x2="12" y2="3"/></svg></button>`;
  }
  html += `<button class="btn btn-sm btn-del" data-id="${j.id}" title="Delete"><svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polyline points="3 6 5 6 21 6"/><path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"/></svg></button>`;
  return html;
}

// --- Event delegation for action buttons ---

jobsBody.addEventListener("click", async (e) => {
  const btn = e.target.closest("button");
  if (!btn) return;
  const id = btn.dataset.id;

  if (btn.classList.contains("btn-view")) {
    await viewContent(id);
  } else if (btn.classList.contains("btn-copy")) {
    await copyContent(id);
  } else if (btn.classList.contains("btn-dl")) {
    await downloadContent(id);
  } else if (btn.classList.contains("btn-del")) {
    await deleteJob(id);
  }
});

async function copyContent(id) {
  try {
    const res = await fetch(`/api/jobs/${id}/content`);
    const data = await res.json();
    copyToClipboard(data.content);
    showToast("Copied to clipboard");
  } catch (err) {
    showToast("Copy failed: " + err.message, true);
  }
}

function copyToClipboard(text) {
  if (navigator.clipboard && navigator.clipboard.writeText) {
    navigator.clipboard.writeText(text).catch(() => fallbackCopy(text));
  } else {
    fallbackCopy(text);
  }
}

function fallbackCopy(text) {
  const ta = document.createElement("textarea");
  ta.value = text;
  ta.style.position = "fixed";
  ta.style.opacity = "0";
  ta.style.pointerEvents = "none";
  document.body.appendChild(ta);
  ta.select();
  try { document.execCommand("copy"); } catch (_) {}
  document.body.removeChild(ta);
}

async function downloadContent(id) {
  window.open(`/api/jobs/${id}/download`, "_blank");
}

async function deleteJob(id) {
  await fetch(`/api/jobs/${id}`, { method: "DELETE" });
  showToast("Deleted");
  await refreshJobs();
}

// --- Modal / Preview ---

const modalOverlay = document.getElementById("modal-overlay");
const modalBody = document.getElementById("modal-body");
const modalTitle = document.getElementById("modal-title");
const modalClose = document.getElementById("modal-close");

async function viewContent(id) {
  try {
    const res = await fetch(`/api/jobs/${id}/content`);
    const data = await res.json();
    const job = jobs.find(j => j.id === id);
    modalTitle.textContent = job ? job.filename : "Preview";
    modalBody.textContent = data.content;
    modalOverlay.hidden = false;
    document.body.style.overflow = "hidden";
  } catch (err) {
    showToast("Preview failed: " + err.message, true);
  }
}

function closeModal() {
  modalOverlay.hidden = true;
  document.body.style.overflow = "";
}

modalOverlay.addEventListener("click", (e) => {
  if (e.target === modalOverlay) closeModal();
});
modalClose.addEventListener("click", closeModal);
document.addEventListener("keydown", (e) => {
  if (e.key === "Escape" && !modalOverlay.hidden) closeModal();
});

clearDoneBtn.addEventListener("click", async () => {
  for (const j of jobs) {
    if (j.status === "done" || j.status === "failed") {
      await fetch(`/api/jobs/${j.id}`, { method: "DELETE" });
    }
  }
  showToast("Cleared completed jobs");
  await refreshJobs();
});

// --- Toast ---

function showToast(msg, isError = false) {
  toast.textContent = msg;
  toast.className = "toast show" + (isError ? " toast-error" : "");
  clearTimeout(toast._timer);
  toast._timer = setTimeout(() => { toast.className = "toast"; }, 3000);
}

// --- Helpers ---

function formatTime(secs) {
  if (secs == null) return "—";
  if (secs < 60) return secs + "s";
  const m = Math.floor(secs / 60);
  const s = Math.round(secs % 60);
  return m + "m " + s + "s";
}

function formatDuration(secs) {
  const m = Math.floor(secs / 60);
  const s = Math.round(secs % 60);
  if (m > 0) return m + "m " + s + "s";
  return s + "s";
}

function truncate(s, n) {
  return s.length > n ? s.slice(0, n) + "…" : s;
}

function escapeHtml(s) {
  const div = document.createElement("div");
  div.textContent = s;
  return div.innerHTML;
}

// --- Model Selector ---

async function loadConfig() {
  try {
    const res = await fetch("/api/config");
    const cfg = await res.json();
    currentModel = cfg.model;
    renderModelBoxes(cfg);
    deviceBadge.textContent = `${cfg.device} · ${cfg.model}`;
    deviceBadge.classList.add(cfg.ready ? "badge-done" : "badge-processing");
  } catch (_) {
    deviceBadge.textContent = "offline";
    deviceBadge.classList.add("badge-failed");
  }
}

function renderModelBoxes(cfg) {
  const models = cfg.models;
  modelBoxes.innerHTML = Object.entries(models).map(([name, info]) => {
    const active = name === currentModel ? " active" : "";
    return `<label class="model-box${active}" data-model="${name}">
      <input type="radio" name="model" value="${name}" ${name === currentModel ? "checked" : ""}>
      <span class="model-box-title">${name}</span>
      <span class="model-box-sub">${info.vram_fp16} · ${info.quality}</span>
    </label>`;
  }).join("");
}

modelBoxes.addEventListener("change", async (e) => {
  const inp = e.target;
  if (inp.name !== "model") return;
  const model = inp.value;
  modelBoxes.querySelectorAll(".model-box").forEach(b => b.classList.add("switching"));
  try {
    const res = await fetch("/api/config/model", {
      method: "POST",
      headers: {"Content-Type": "application/json"},
      body: JSON.stringify({model}),
    });
    if (res.ok) {
      const cfg = await res.json();
      currentModel = cfg.model;
      renderModelBoxes(cfg);
      deviceBadge.textContent = `${cfg.device} · ${cfg.model}`;
      showToast(`Model switched to ${cfg.model}`);
    } else {
      const err = await res.json();
      showToast("Failed: " + (err.detail || "unknown error"), true);
    }
  } catch (err) {
    showToast("Failed: " + err.message, true);
  }
  modelBoxes.querySelectorAll(".model-box").forEach(b => b.classList.remove("switching"));
});

// --- Init ---

document.body.focus();
setInterval(refreshJobs, 2000);
refreshJobs();
loadConfig();
