const uploadZone = document.getElementById("upload-zone");
const fileInput = document.getElementById("file-input");
const pasteBtn = document.getElementById("paste-btn");
const jobsBody = document.getElementById("jobs-body");
const jobsTable = document.getElementById("jobs-table");
const jobsEmpty = document.getElementById("jobs-empty");
const clearDoneBtn = document.getElementById("clear-done-btn");
const toast = document.getElementById("toast");
const deviceBadge = document.getElementById("device-badge");
const vlmSection = document.getElementById("vlm-section");
const vlmBoxes = vlmSection.querySelectorAll(".vlm-box");

let jobs = [];
const API = window.location.pathname.startsWith("/docling") ? "/docling" : "";

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

// --- Paste ---

let _pasteWait = false;

pasteBtn.addEventListener("click", (e) => {
  e.stopPropagation();
  document.body.focus();
  _pasteWait = true;
  showToast("Paste with Ctrl+V now");
  setTimeout(() => { _pasteWait = false; }, 3000);
});

document.addEventListener("paste", (e) => {
  if (!_pasteWait && (document.activeElement?.tagName === "INPUT" || document.activeElement?.tagName === "TEXTAREA")) return;
  _pasteWait = false;
  const items = e.clipboardData?.items;
  if (!items) return;
  const files = [];
  for (const item of items) {
    if (item.type.startsWith("image/")) {
      const f = item.getAsFile();
      if (f) files.push(f);
    } else if (item.type === "text/html") {
      item.getAsString(s => {
        const m = s.match(/src=["']([^"']+)["']/);
        if (m && m[1]) {
          fetch(m[1]).then(r => r.blob()).then(b => {
            const ext = b.type.split("/")[1] || "png";
            handleFiles([new File([b], "pasted." + ext, {type: b.type})]);
          }).catch(() => {});
        }
      });
    } else if (item.type === "text/plain") {
      item.getAsString(s => {
        const m = s.match(/https?:\/\/[^\s]+\.(png|jpg|jpeg|gif|webp)/i);
        if (m) {
          fetch(m[0]).then(r => r.blob()).then(b => {
            handleFiles([new File([b], "pasted." + m[1], {type: b.type})]);
          }).catch(() => {});
        }
      });
    }
  }
  if (files.length > 0) {
    e.preventDefault();
    handleFiles(files);
  }
});

async function handleFiles(fileList) {
  const docs = Array.from(fileList).filter(f => f.name.includes("."));
  if (docs.length === 0) {
    showToast("No valid files found");
    return;
  }

  const form = new FormData();
  for (const f of docs) {
    form.append("files", f);
  }

  try {
    const res = await fetch(API + "/api/upload", { method: "POST", body: form });
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
    const res = await fetch(API + "/api/jobs");
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
    const pct = j.pages_total > 0 ? Math.round((j.pages_done / j.pages_total) * 100) : 0;
    const progressHtml = j.status === "processing"
      ? `<div class="progress-bar"><div class="progress-fill indeterminate"></div></div>`
      : j.status === "done"
      ? `<span class="pages">${j.pages_total} pages</span>`
      : `<span class="pages">—</span>`;

    let badgeClass = "badge-" + j.status;

    const clickFile = j.status === "done" ? ` onclick="viewContent('${j.id}')"` : "";
    return `<tr class="job-row">
      <td class="col-file${j.status === "done" ? " clickable" : ""}" title="${escapeHtml(j.filename)}"${clickFile}>${escapeHtml(truncate(j.filename, 40))}</td>
      <td class="col-progress">${progressHtml}</td>
      <td class="col-time">${formatTime(j.processing_time_seconds)}</td>
      <td class="col-status"><span class="badge ${badgeClass}">${j.status}</span>${j.error ? `<span class="error-msg" title="${escapeHtml(j.error)}">!</span>` : ""}</td>
      <td class="col-actions">${actionButtons(j)}</td>
    </tr>`;
  }).join("");
}

function actionButtons(j) {
  let html = "";
  if (j.status === "done") {
    html += `<button class="btn btn-sm btn-view" data-id="${j.id}" title="Preview"><svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z"/><circle cx="12" cy="12" r="3"/></svg></button>`;
    html += `<button class="btn btn-sm btn-copy" data-id="${j.id}" title="Copy markdown"><svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="9" y="9" width="13" height="13" rx="2"/><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"/></svg></button>`;
    html += `<button class="btn btn-sm btn-dl" data-id="${j.id}" title="Download markdown"><svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="7 10 12 15 17 10"/><line x1="12" y1="15" x2="12" y2="3"/></svg></button>`;
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
    const res = await fetch(API + `/api/jobs/${id}/content`);
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
  try {
    document.execCommand("copy");
  } catch (_) {}
  document.body.removeChild(ta);
}

async function downloadContent(id) {
  window.open(API + `/api/jobs/${id}/download`, "_blank");
}

async function deleteJob(id) {
  await fetch(API + `/api/jobs/${id}`, { method: "DELETE" });
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
    const res = await fetch(API + `/api/jobs/${id}/content`);
    const data = await res.json();
    const job = jobs.find(j => j.id === id);
    modalTitle.textContent = job ? job.filename : "Preview";
    modalBody.innerHTML = renderMarkdown(data.content);
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

function renderMarkdown(md) {
  let html = escapeHtml(md);
  html = html.replace(/```(\w*)\n?([\s\S]*?)```/g, (_, lang, code) => {
    return `<pre><code>${escapeHtml(code.trim())}</code></pre>`;
  });
  html = html.replace(/`([^`]+)`/g, "<code>$1</code>");
  html = html.replace(/\*\*([^*]+)\*\*/g, "<strong>$1</strong>");
  html = html.replace(/\*([^*]+)\*/g, "<em>$1</em>");
  html = html.replace(/^### (.+)$/gm, "<h4>$1</h4>");
  html = html.replace(/^## (.+)$/gm, "<h3>$1</h3>");
  html = html.replace(/^# (.+)$/gm, "<h2>$1</h2>");
  html = html.replace(/^- (.+)$/gm, "<li>$1</li>");
  html = html.replace(/(<li>[\s\S]*?<\/li>)\n(?=<li>|$)/g, (m) => `<ul>${m}</ul>`);
  html = html.replace(/\n\n/g, "</p><p>");
  html = html.replace(/\n/g, "<br>");
  html = `<p>${html}</p>`;
  return html;
}

clearDoneBtn.addEventListener("click", async () => {
  for (const j of jobs) {
    if (j.status === "done" || j.status === "failed") {
      await fetch(API + `/api/jobs/${j.id}`, { method: "DELETE" });
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

function truncate(s, n) {
  return s.length > n ? s.slice(0, n) + "…" : s;
}

function escapeHtml(s) {
  const div = document.createElement("div");
  div.textContent = s;
  return div.innerHTML;
}

// --- Init ---

document.body.focus();
setInterval(refreshJobs, 2000);
refreshJobs();

// Warmup check
fetch(API + "/api/jobs").then(() => {
  deviceBadge.textContent = "connected";
  deviceBadge.classList.add("badge-done");
}).catch(() => {
  deviceBadge.textContent = "offline";
  deviceBadge.classList.add("badge-failed");
});

// --- VLM Model selector ---

async function loadVlmConfig() {
  try {
    const res = await fetch(API + "/api/vlm/config");
    const cfg = await res.json();
    vlmBoxes.forEach(box => {
      const inp = box.querySelector("input");
      if (inp.value === cfg.provider) {
        inp.checked = true;
        box.classList.add("active");
      } else {
        box.classList.remove("active");
      }
    });
  } catch (_) {}
}

vlmSection.addEventListener("change", async (e) => {
  const inp = e.target;
  if (inp.name !== "vlm") return;
  const provider = inp.value;
  vlmSection.classList.add("switching");
  try {
    const res = await fetch(API + "/api/vlm/config", {
      method: "POST",
      headers: {"Content-Type": "application/json"},
      body: JSON.stringify({provider}),
    });
    if (res.ok) {
      const cfg = await res.json();
      vlmBoxes.forEach(box => {
        box.classList.toggle("active", box.querySelector("input").checked);
      });
      showToast("VLM switched to " + cfg.label);
    }
  } catch (err) {
    showToast("Failed to switch VLM: " + err.message, true);
    await loadVlmConfig();
  }
  vlmSection.classList.remove("switching");
});

loadVlmConfig();
