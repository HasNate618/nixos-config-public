import QtQuick
import Quickshell
import Quickshell.Io
import "Data.js" as Data

// cliphist-backed clipboard history. Lists recent clipboard entries with
// truncated previews; selecting one copies it back to the clipboard.
// Images are decoded to a temp file and displayed in the preview pane.
Item {
    id: clipSearch

    required property bool active
    required property var selectedItem

    property var items: []
    property string previewText: ""   // decoded text content
    property string previewKind: ""   // "text" | "image"
    property string previewPath: ""   // temp file path for images
    readonly property bool running: listProc.running || decodeProc.running

    // Tracks previous temp path for cleanup on new selection
    property string _oldPath: ""

    function clear() {
        clipSearch.items = [];
        clipSearch.previewText = "";
        clipSearch.previewKind = "";
        clipSearch._cleanupPath(clipSearch.previewPath);
        clipSearch.previewPath = "";
    }

    function _cleanupPath(path) {
        if (path && path.length > 0) {
            // async best-effort delete; ignore failure
            Qt.callLater(function() {
                const cmd = ["sh", "-c", "rm -f " + path + " 2>/dev/null"];
            });
        }
    }

    function refresh() {
        listProc.command = ["sh", "-c",
            "cliphist list 2>/dev/null | head -100"];
        listProc.running = false;
        listProc.running = true;
    }

    function ingest(text) {
        const lines = text.split("\n");
        const out = [];
        // cliphist list outputs: <id>\t<preview text>
        for (let i = 0; i < lines.length; i++) {
            const ln = lines[i].trim();
            if (!ln) continue;
            const tab = ln.indexOf("\t");
            if (tab < 0) continue;
            const clipId = ln.substring(0, tab).trim();
            const preview = ln.substring(tab + 1).trim();
            // Truncate preview for display
            const disp = preview.length > 120 ? preview.substring(0, 117) + "…" : preview;
            const isImage = preview.indexOf("[IMAGE") >= 0 || preview.indexOf("��") >= 0 || preview.indexOf("[[ binary data") >= 0;
            out.push({
                title: isImage ? "🖼️ " + (clipId + ": " + preview.substring(0, 40)) : disp,
                category: "Clipboard",
                keywords: (preview + " " + clipId + " clipboard").toLowerCase(),
                icon: isImage ? "󰋩" : "󰅎",
                exec: "sh -c 'cliphist decode " + clipId + " | wl-copy 2>/dev/null'",
                clipId: clipId,
                clipPreview: preview,
                isClip: true,
                rawCategory: true,
                _t: disp.toLowerCase(),
                _k: (preview + " " + clipId + " clipboard").toLowerCase(),
                _c: "clipboard"
            });
        }
        clipSearch.items = out;
    }

    function updatePreview() {
        if (!clipSearch.active) return;
        const it = clipSearch.selectedItem;
        if (!it || !it.clipId) {
            clipSearch.previewText = "";
            clipSearch.previewKind = "";
            clipSearch._cleanupPath(clipSearch.previewPath);
            clipSearch.previewPath = "";
            return;
        }

        // Clean up previous temp image
        clipSearch._cleanupPath(clipSearch.previewPath);

        const tmpPath = "/tmp/cliphist-" + it.clipId;
        clipSearch.previewText = "Loading…";
        clipSearch.previewKind = "";
        clipSearch.previewPath = "";

        decodeProc.command = ["sh", "-c",
            "id=" + it.clipId + "; "
            + "out=/tmp/cliphist-$id; "
            + "cliphist decode $id 2>/dev/null > \"$out\"; "
            + "sz=$(stat -c%s \"$out\" 2>/dev/null || echo 0); "
            + "if [ \"$sz\" -gt 5242880 ]; then "
            + "  rm -f \"$out\"; "
            + "  echo 'KIND=text'; "
            + "  echo '---'; "
            + "  echo '[Content too large — >5 MB]'; "
            + "  exit; "
            + "fi; "
            + "mime=$(file -b --mime-type \"$out\" 2>/dev/null); "
            + "case \"$mime\" in "
            + "  image/png|image/jpeg|image/webp|image/gif|image/bmp) "
            + "    echo 'KIND=image'; "
            + "    echo PATH=/tmp/cliphist-$id; "
            + "    ;; "
            + "  *) "
            + "    echo 'KIND=text'; "
            + "    echo '---'; "
            + "    cat \"$out\" 2>/dev/null | head -200; "
            + "    rm -f \"$out\"; "
            + "    ;; "
            + "esac"];
        decodeProc.running = false;
        decodeProc.running = true;
    }

    function ingestPreview(text) {
        if (!text) {
            clipSearch.previewText = "";
            clipSearch.previewKind = "";
            clipSearch.previewPath = "";
            return;
        }
        const lines = text.split("\n");
        const kindLine = lines[0] || "";
        if (kindLine === "KIND=image") {
            clipSearch.previewKind = "image";
            clipSearch.previewPath = lines[1] && lines[1].indexOf("PATH=") === 0
                ? lines[1].substring(5) : "";
            clipSearch.previewText = ""; // image path drives preview
        } else {
            clipSearch.previewKind = "text";
            clipSearch.previewPath = "";
            // Skip "KIND=text" and "---" lines
            const content = lines.filter(l =>
                l !== "KIND=text" && l !== "---"
            ).join("\n");
            clipSearch.previewText = content.substring(0, 2000);
        }
    }

    onActiveChanged: {
        if (clipSearch.active) clipSearch.refresh();
        else clipSearch.clear();
    }
    onSelectedItemChanged: {
        if (clipSearch.active && clipSearch.selectedItem) clipSearch.updatePreview();
    }

    Process {
        id: listProc
        running: false
        command: ["true"]
        stdout: StdioCollector {
            onStreamFinished: { clipSearch.ingest(this.text || ""); clipSearch.updatePreview(); }
        }
    }

    Process {
        id: decodeProc
        running: false
        command: ["true"]
        stdout: StdioCollector {
            onStreamFinished: { clipSearch.ingestPreview(this.text || ""); }
        }
    }
}
