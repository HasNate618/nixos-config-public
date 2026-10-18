.pragma library

// WANTED is the single source of truth for which raw colors.toml keys map
// onto this shell's semantic slots. Both the startup FileView read and the
// IPC push path translate through it.
const WANTED = {
    background: "paper",
    foreground: "ink",
    color7:     "inkDeep",
    color8:     "sumi",
    color1:     "indigo",
    accent:     "sealRaw",
    // Per-widget accents. Focus mode supplies these as a1..a5 (see
    // focus-apply-scheme); the normal matugen path does not, so they stay
    // unset and the bar falls back to its seal-derived tints.
    a1:         "a1",
    a2:         "a2",
    a3:         "a3",
    a4:         "a4",
    a5:         "a5",
    alert:      "alert",
};

const LINE = /^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*"([^"]+)"/;

function parseAll(text) {
    const out = {};
    if (!text) return out;
    const lines = text.split("\n");
    for (let i = 0; i < lines.length; i++) {
        const m = lines[i].match(LINE);
        if (m) out[m[1].toLowerCase()] = m[2];
    }
    return out;
}

function mapKeys(raw) {
    const out = {};
    if (!raw) return out;
    for (const key in WANTED) {
        if (raw[key]) out[WANTED[key]] = raw[key];
    }
    return out;
}

function parse(text) {
    return mapKeys(parseAll(text));
}

// Write a parsed palette onto a Theme.qml instance. Missing slots are left
// at their current value so a partial palette never blanks the live theme.
function apply(theme, palette) {
    if (palette.paper)   theme.paper   = palette.paper;
    if (palette.ink)     theme.ink     = palette.ink;
    if (palette.inkDeep) theme.inkDeep = palette.inkDeep;
    if (palette.sumi)    theme.sumi    = palette.sumi;
    if (palette.indigo)  theme.indigo  = palette.indigo;
    if (palette.sealRaw) theme.sealRaw = palette.sealRaw;
    if (palette.a1) theme.a1 = palette.a1;
    if (palette.a2) theme.a2 = palette.a2;
    if (palette.a3) theme.a3 = palette.a3;
    if (palette.a4) theme.a4 = palette.a4;
    if (palette.a5) theme.a5 = palette.a5;
    if (palette.alert) theme.alert = palette.alert;
}
