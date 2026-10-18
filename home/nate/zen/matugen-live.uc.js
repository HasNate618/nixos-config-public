// ==UserScript==
// @name           matugen-live
// @description    Live transparency theming from skwd-wall matugen output. Outside focus mode the tint is warmth-compensated; in focus mode (marked css) the raw scheme colour is applied at full alpha so the chrome matches the flat wallpaper. No Marionette.
// @author         nate
// @version        1.8
// @onlyonce
// ==/UserScript==

(async function () {
  const chromeDir = Services.dirsvc.get("UChrm", Ci.nsIFile).path;
  const cssPath = `${chromeDir}/zen-themes/matugen-transparency/chrome.css`;

  let lastColor = null;
  let lastMain = null;
  let windowCount = 0;

  function extractColor(text) {
    const m = text.match(/--mod-sameerasw-zen_transparency_color:\s*(#[0-9A-Fa-f]{6,8})/);
    if (!m) return null;
    return m[1].length === 9 ? m[1] : m[1] + "CC";
  }

  // Opaque path: --zen-main-browser-background is painted DIRECTLY by the
  // chrome — no compositing — so it gets the css value RAW. The warmth
  // transform (R*2/5, G/B*10/13) is a heavy darkening curve calibrated for
  // the transparent tint, where Gecko composites over the wallpaper; applied
  // to an opaque fill it just darkens the chrome ~33% below the flat focus
  // wallpaper (#181616 -> #091010), which is exactly the "Zen looks darker"
  // report. Raw keeps chrome == wallpaper, so the focused desktop is uniform.
  // The tint below stays compensated (user-calibrated; see zen-red-scale.py).
  function extractMainText(text) {
    const m = text.match(/--zen-main-browser-background:\s*(#[0-9A-Fa-f]{6,8})/);
    return m ? m[1] : null;
  }

  // Zen warmth compensation — MIRROR of zen-red-scale.py (keep in sync!).
  // Gecko renders matugen colours warmer (more red) than GTK/foot on this
  // display, so the colour applied to Zen is pre-scaled: R*2/5, G/B*10/13.
  // Pure function of the raw file value — never compounds.
  function compensate(hex) {
    const m = hex.match(/^#([0-9a-f]{2})([0-9a-f]{2})([0-9a-f]{2})([0-9a-f]{2})?$/i);
    if (!m) return hex;
    const f = (v, num, den) =>
      Math.floor((parseInt(v, 16) * num) / den).toString(16).padStart(2, "0");
    return "#" + f(m[1], 2, 5) + f(m[2], 10, 13) + f(m[3], 10, 13) + (m[4] || "");
  }

  function applyToWindow(docEl, color, mainBg) {
    docEl.style.setProperty("--mod-sameerasw-zen_transparency_color", color, "important");
    docEl.style.setProperty("--zen-transparency-color", color, "important");
    if (mainBg) {
      // Inline !important on purpose: legacy stylesheets (colors.css etc.)
      // also declare this with !important — inline wins over all of them.
      docEl.style.setProperty("--zen-main-browser-background", mainBg, "important");
    } else {
      docEl.style.removeProperty("--zen-main-browser-background");
    }
    docEl.style.setProperty("--zen-themed-toolbar-bg-transparent", "transparent", "important");
  }

  function applyToAll(color, mainBg) {
    let n = 0;
    const e = Services.wm.getEnumerator("navigator:browser");
    while (e.hasMoreElements()) {
      const w = e.getNext();
      if (w && w.document && w.document.documentElement) {
        applyToWindow(w.document.documentElement, color, mainBg);
        n++;
      }
    }
    return n;
  }

  async function poll() {
    try {
      const text = await IOUtils.readUTF8(cssPath);
      let color = extractColor(text);
      if (!color) return;
      const mainRaw = extractMainText(text);

      // Focus mode: focus-theme-render wrote this file, and the flat
      // wallpaper IS the scheme colour — so the chrome must be that colour
      // too, not matugen's warmth-compensated (darker) version, and opaque
      // rather than the mod's 20% tint. The renderer marks its output.
      const focusMode = text.indexOf("focus-mode: raw") !== -1;
      let mainBg;
      if (focusMode) {
        color = color.slice(0, 7) + "ff"; // full alpha, no compensation
        mainBg = mainRaw ? mainRaw.slice(0, 7) : null;
      } else {
        color = compensate(color);
        mainBg = mainRaw || null; // RAW — see the opaque-path note above.
      }

      // Count windows to detect new ones
      let count = 0;
      const e = Services.wm.getEnumerator("navigator:browser");
      while (e.hasMoreElements()) {
        const w = e.getNext();
        if (w && w.document) count++;
      }

      const newWindow = count > windowCount;
      windowCount = count;

      if (color !== lastColor || mainBg !== lastMain) {
        // Wallpaper changed — apply to ALL windows
        lastColor = color;
        lastMain = mainBg;
        const n = applyToAll(color, mainBg);
        console.log(`[matugen-live] theme changed → ${color} / ${mainBg} to ${n} windows`);
      } else if (newWindow) {
        // New window opened — Zen's theme engine will re-theme all windows,
        // so we need to re-apply AFTER a short delay to override it.
        const pushColor = color;
        const pushMain = mainBg;
        setTimeout(() => {
          const n = applyToAll(pushColor, pushMain);
          console.log(`[matugen-live] new window catchup → ${pushColor} to ${n} windows`);
        }, 300);
        // Also apply immediately to the new window
        const n = applyToAll(color, mainBg);
        console.log(`[matugen-live] new window → ${color} to ${n} windows`);
      }
    } catch (e) {
      console.error("[matugen-live] poll error:", e);
    }
  }

  setInterval(poll, 1500);
  await poll();
  console.log("[matugen-live] loaded, watching", cssPath);
})();
