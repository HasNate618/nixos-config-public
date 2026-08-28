.pragma library

// Sentinel values for the search/state drills.
const clipCategory = "Clipboard";
const emojiCategory = "Emoji";

// fd already respects .gitignore, the global ignore file, and skips
// hidden files by default. These excludes catch build dirs that
// aren't always gitignored.
const fdExcludes = [
    "node_modules", "target", "dist", "build", ".cache",
    ".venv", "__pycache__", ".tox", ".next", ".nuxt"
];

const imageExts = [
    "png", "jpg", "jpeg", "webp", "gif", "bmp", "ico", "avif", "svg"
];

const textExts = [
    "md", "txt", "qml", "lua", "toml", "sh", "bash", "zsh", "fish",
    "py", "js", "mjs", "cjs", "ts", "tsx", "jsx", "json", "jsonc",
    "yaml", "yml", "rs", "go", "c", "h", "cpp", "hpp", "cc", "hh",
    "html", "css", "scss", "conf", "ini", "cfg", "log", "csv", "xml",
    "rb", "java", "kt", "swift", "php", "sql", "vim", "el", "tex",
    "gitignore", "gitconfig", "dockerfile", "makefile", "env"
];

const fileIcons = {
    "png": "󰋩", "jpg": "󰋩", "jpeg": "󰋩", "webp": "󰋩", "gif": "󰋩",
    "bmp": "󰋩", "ico": "󰋩", "avif": "󰋩", "svg": "󰜡", "tiff": "󰋩",
    "mp4": "󰕧", "mkv": "󰕧", "webm": "󰕧", "mov": "󰕧", "avi": "󰕧",
    "m4v": "󰕧", "flv": "󰕧",
    "mp3": "󰝚", "flac": "󰝚", "ogg": "󰝚", "wav": "󰝚", "m4a": "󰝚",
    "opus": "󰝚", "aac": "󰝚",
    "pdf": "󰈦", "epub": "󰂺", "djvu": "󰈦",
    "doc": "󰈬", "docx": "󰈬", "odt": "󰈬", "rtf": "󰈬",
    "xls": "󰈛", "xlsx": "󰈛", "ods": "󰈛",
    "ppt": "󰈧", "pptx": "󰈧", "odp": "󰈧",
    "zip": "󰗄", "tar": "󰗄", "gz": "󰗄", "xz": "󰗄", "bz2": "󰗄",
    "7z": "󰗄", "rar": "󰗄", "zst": "󰗄",
    "md": "󰍔", "txt": "󰈙", "log": "󰦪", "csv": "󰈛",
    "json": "󰘦", "jsonc": "󰘦", "yaml": "󰈙", "yml": "󰈙",
    "toml": "󰈙", "xml": "󰗀", "ini": "󰒓", "cfg": "󰒓",
    "conf": "󰒓", "env": "󰒓",
    "sh": "󱆃", "bash": "󱆃", "zsh": "󱆃", "fish": "󰈺",
    "lua": "󰢱", "vim": "",
    "html": "󰌝", "css": "󰌜", "scss": "󰌜", "sass": "󰌜",
    "py": "󰌠", "js": "󰌞", "mjs": "󰌞", "cjs": "󰌞",
    "ts": "󰛦", "tsx": "󰜈", "jsx": "󰜈",
    "rs": "󱘗", "go": "󰟓", "java": "󰬷", "kt": "󱈙",
    "swift": "󰛥", "rb": "󰴭", "php": "󰌟",
    "c": "󰙱", "h": "󰙱", "cpp": "󰙲", "hpp": "󰙲", "cc": "󰙲", "hh": "󰙲",
    "qml": "󰢫", "sql": "󰆼", "el": "", "tex": "",
    "gitignore": "", "gitconfig": "",
    "dockerfile": "󰡨", "makefile": "󰣪"
};

// Synthetic rows at root level. Activating one sets the categoryFilter
// instead of executing a command. `target` matches against item.category;
// "App" is the bucket all .desktop entries land in. fileCategory and
// ghCategory route to their respective search drills.
const categoryNav = [
    { title: "Apps",    icon: "󰀻", category: "Browse", isCategory: true, target: "App",         keywords: "apps applications launcher programs software desktop" },    { title: "System",  icon: "󰐥", category: "Browse", isCategory: true, target: "System",      keywords: "system lock suspend hibernate logout restart reboot shutdown power" },    { title: "Clipboard", icon: "󰅎", category: "Browse", isCategory: true, target: clipCategory,  keywords: "clipboard clip history paste copy cliphist recent entries" },
    { title: "Emoji",    icon: "󰞅",  category: "Browse", isCategory: true, target: emojiCategory, keywords: "emoji emoticon smiley kaomoji picker selector" }
];

// Every leaf action is flattened here with a synonym list so search hits
// non-obvious terms. `exec` is the bash run verbatim; `tui` (when set) is
// the wrapper command name that prefixes exec so the launch lands in a
// real terminal.
const omarchyItems = [
    // ----- System -----
    { title: "Lock Screen",         icon: "󰌾", category: "System", keywords: "lock screen security hyprlock password",                                       exec: "hyprlock" },
    { title: "Suspend",             icon: "󰒲", category: "System", keywords: "suspend sleep power down ram s3",                                              exec: "systemctl suspend" },
    { title: "Hibernate",           icon: "󰤁", category: "System", keywords: "hibernate disk power down s4 swap",                                            exec: "systemctl hibernate" },
    { title: "Logout",              icon: "󰍃", category: "System", keywords: "logout signout exit session end",                                              exec: "pkill Hyprland" },
    { title: "Restart Computer",    icon: "󰜉", category: "System", keywords: "restart reboot reset power cycle",                                             exec: "systemctl reboot" },
    { title: "Shutdown",            icon: "󰐥", category: "System", keywords: "shutdown poweroff off halt turn off",                                          exec: "systemctl poweroff" },
    { title: "Reboot → Default",    icon: "󰜉", category: "System", keywords: "default reboot restart normal boot",                                             exec: "sudo -n to-default --now" },
    { title: "Reboot → Battery",    icon: "󰌪", category: "System", keywords: "battery reboot restart power save optimus",                                        exec: "sudo -n to-battery --now" },
    { title: "Schedule → Default (next boot)",  icon: "󰜉", category: "System", keywords: "default schedule later next boot",                                        exec: "sudo -n to-default && notify-send -u low 'Boot' 'Default scheduled for next boot'" },
    { title: "Schedule → Battery (next boot)",  icon: "󰌪", category: "System", keywords: "battery schedule later next boot power save",                              exec: "sudo -n to-battery && notify-send -u low 'Boot' 'Battery scheduled for next boot'" },
];

// Pre-lowercases `title`/`keywords`/`category` onto `_t`/`_k`/`_c` so the
// per-keystroke scoring loop doesn't re-lowercase the same strings on
// every character.
function annotate(items) {
    const out = new Array(items.length);
    for (let i = 0; i < items.length; i++) {
        const it = items[i];
        out[i] = Object.assign({}, it, {
            _t: (it.title || "").toLowerCase(),
            _k: (it.keywords || "").toLowerCase(),
            _c: (it.category || "").toLowerCase()
        });
    }
    return out;
}

function basename(p) {
    const s = p.lastIndexOf("/");
    return s >= 0 ? p.substring(s + 1) : p;
}
function dirname(p) {
    const s = p.lastIndexOf("/");
    return s >= 0 ? p.substring(0, s) : "";
}
function tildify(p, homeDir) {
    return (homeDir && p.indexOf(homeDir) === 0)
        ? "~" + p.substring(homeDir.length)
        : p;
}
function fileExt(path) {
    const name = basename(path);
    const dot = name.lastIndexOf(".");
    if (dot <= 0) return name.toLowerCase(); // dotless name (Makefile)
    return name.substring(dot + 1).toLowerCase();
}
function fileIcon(path) {
    return fileIcons[fileExt(path)] || "";
}
function openUrl(url) {
    return "xdg-open " + JSON.stringify(url);
}
function formatStars(n) {
    if (n >= 1000000) return (n / 1000000).toFixed(1) + "m";
    if (n >= 1000)    return (n / 1000).toFixed(1) + "k";
    return "" + n;
}

// Stable identity per item — path wins (files, repos, PRs), exec next
// (apps, omarchy actions), title+category last (synthetic rows).
function itemKey(item) {
    if (!item) return "";
    return item.path || item.exec || (item.title + "|" + item.category);
}