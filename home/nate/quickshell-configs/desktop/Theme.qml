import QtQuick
import Quickshell
import Quickshell.Io
import "Palette.js" as Palette

// `seal` rides `driftAmount` (200ms rise, 2.8s taper) so each theme swap
// reads as a breath rather than a hard cut. The 1.55s lead-in lets
// theme-wash's animation exit first.
Item {
    id: theme

    readonly property string colorsPath: Quickshell.env("HOME") + "/.config/quickshell/colors.toml"

    property int cornerRadius: 0
    readonly property bool round: cornerRadius > 0

    // Focus mode: true while the focus-mode toggle owns the palette and
    // suppresses animations. The palette itself arrives via focusPalette()
    // (see focus-apply-scheme); while this is true the matugen apply()
    // path is muted so the flat-wallpaper pipeline cannot clobber the
    // scheme colours.
    property bool focusMode: false

    function setFocusMode(on: bool): void {
        theme.focusMode = on;
    }


    property color paper:   "#181616"
    property color ink:     "#c5c9c5"
    property color inkDeep: "#c8c093"
    property color sumi:    "#a6a69c"
    property color indigo:  "#658594"
    property color sealRaw: "#c4746e"
    // Per-widget accent colours for the bar readouts. Focus mode pushes one
    // distinct scheme hue per widget (see focus-apply-scheme a1..a5); when
    // unset — the normal matugen path — they fall back to the seal-derived
    // tint, so the bar looks exactly as before outside focus mode.
    // Empty string = "not supplied" (the normal matugen path).
    property string a1: ""
    property string a2: ""
    property string a3: ""
    property string a4: ""
    property string a5: ""
    // Red, reserved for genuine warnings; "" outside focus mode, where the
    // bar falls back to its seal-derived behaviour.
    property string alert: ""
    property real  driftAmount: 0

    readonly property color seal: Qt.hsva(
        sealRaw.hsvHue,
        Math.min(1, sealRaw.hsvSaturation + driftAmount * 0.05),
        sealRaw.hsvValue,
        sealRaw.a
    )

    readonly property string serif: "serif"
    readonly property string serifCJK: "Noto Serif CJK JP"
    readonly property string mono:  "JetBrainsMono Nerd Font"

    // Bar/surface opacity: fully opaque in focus mode so the scheme
    // background renders exactly (translucency is only wanted over the
    // live wallpaper).
    readonly property color bg:     Qt.rgba(paper.r, paper.g, paper.b,
                                            theme.focusMode ? 1.0 : @BAR_OPACITY@)
    readonly property color fg:     ink
    readonly property color muted:  sumi
    readonly property color accent: seal
    readonly property color warn:   seal
    readonly property color sep:    Qt.rgba(ink.r, ink.g, ink.b, 0.18)
    readonly property color rowHi:  Qt.rgba(ink.r, ink.g, ink.b, 0.06)
    readonly property color rowSel: Qt.rgba(seal.r, seal.g, seal.b, 0.18)

    // Name of the last theme applied via IPC. Used to suppress the drift
    // animation when the hook pushes the same theme twice or races the
    // startup FileView read.
    property string lastAppliedName: ""

    // watchChanges: false — `omarchy theme set` does an atomic rm+mv on
    // the theme dir, which would race an inotify watch. The hook tells us
    // when to reload instead.
    FileView {
        id: paletteFile
        path: theme.colorsPath
        watchChanges: true
    }

    Timer {
        id: driftDelay
        interval: 1550
        repeat: false
        onTriggered: {
            if (!theme.focusMode) driftAnim.restart()
        }
    }

    SequentialAnimation {
        id: driftAnim
        NumberAnimation {
            target: theme; property: "driftAmount"
            from: 0; to: 1
            duration: 200
            easing.type: Easing.OutQuad
        }
        NumberAnimation {
            target: theme; property: "driftAmount"
            to: 0
            duration: 2800
            easing.type: Easing.OutCubic
        }
    }

    // Startup restore: if a shell (re)starts while focus mode is active,
    // the guard file carries the palette payload (written by
    // focus-apply-scheme); re-apply it so the bar does not fall back to
    // defaults mid-focus.
    Process {
        id: focusRestore
        running: false
        command: ["bash", "-c",
            "f=\"$HOME/.cache/focus-mode\"; [ -s \"$f\" ] && cat \"$f\" || true"]
        stdout: StdioCollector {
            onStreamFinished: {
                const t = this.text.trim();
                if (t === "") return;
                let p;
                try { p = JSON.parse(t); }
                catch (e) { console.warn("theme: focus restore: bad payload —", e); return; }
                Palette.apply(theme, p);
                theme.focusMode = true;
            }
        }
        Component.onCompleted: running = true
    }

    IpcHandler {
        target: "theme"
        function apply(payload: string): void {
            let p;
            try { p = JSON.parse(payload); }
            catch (e) { console.warn("theme.apply: bad payload —", e); return; }
            if (!p || !p.colors) return;
            // Focus mode owns the palette: ignore matugen pushes until it
            // exits. Without this, applying the black wallpaper would run
            // the pipeline and immediately overwrite the static focus
            // colours the moment it regenerated.
            if (theme.focusMode) return;
            Palette.apply(theme, Palette.mapKeys(p.colors));
            if (p.name && p.name !== theme.lastAppliedName) {
                theme.lastAppliedName = p.name;
                if (!theme.focusMode) driftDelay.restart();
            }
        }
        function reload(): void {
            paletteFile.reload();
            if (!theme.focusMode) driftDelay.restart();
        }
        function focus(on: bool): void {
            theme.setFocusMode(on);
            if (!on) {
                // Clear focus-only accent slots so the bar falls back to its
                // seal-derived tints. Without this, the matugen push on exit
                // updates paper/ink/etc. but skips a1..a5/alert, leaving the
                // bar stuck on focus colours.
                theme.a1 = "";
                theme.a2 = "";
                theme.a3 = "";
                theme.a4 = "";
                theme.a5 = "";
                theme.alert = "";
            }
        }
        // Focus-mode palette, applied verbatim. Separate from apply()
        // because that path is muted while focus mode owns the palette;
        // this one also sets focusMode, so a payload alone is enough.
        function focusPalette(payload: string): void {
            let p;
            try { p = JSON.parse(payload); }
            catch (e) { console.warn("theme.focusPalette: bad payload —", e); return; }
            if (!p) return;
            theme.focusMode = true;
            Palette.apply(theme, p);
        }
    }
}