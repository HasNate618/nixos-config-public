import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import Quickshell.Io

// Rare-but-loud battery feedback. Crossings of 20% / 10% drip a teardrop
// down the right edge of the bar. A transition to Full (or plug-in already
// near full) fills a small battery outline with a rising sinusoidal wave.
// Both effects sit at the top-right where the navbar conventionally puts
// its battery glyph, so they read as "the battery itself is reacting".
// Overlay layer, click-through, themed off the omarchy palette.
ShellRoot {
    id: root

    // ---------- Theme paths (same source the navbar reads) ----------
    readonly property string colorsPath: Quickshell.env("HOME") + "/.config/quickshell/colors.toml"
    // theme.name beacon not needed — we write colors.toml in-place, so
    // paletteFile.watchChanges catches every edit directly.

    // ---------- Palette ----------
    // seal  = color1  (alert / drip tint)
    // indigo = accent (info / wave tint)
    // ink   = foreground (battery outline)
    property color paper:  "#181616"
    property color ink:    "#c5c9c5"
    property color indigo: "#658594"
    property color seal:   "#c4746e"

    readonly property color tearColor: seal
    readonly property color waveColor: indigo
    readonly property color shellColor: ink

    // Suppress the first batch of triggers — at startup the previous-state
    // bookkeeping is empty so any threshold would look like a fresh cross.
    property bool armed: false
    Timer { interval: 1500; running: true; onTriggered: root.armed = true }

    function parseColors(text) {
        const want = { background: null, foreground: null, accent: null, color1: null };
        const re = /^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*"([^"]+)"/;
        const lines = text.split("\n");
        for (let i = 0; i < lines.length; i++) {
            const m = lines[i].match(re);
            if (m && (m[1] in want)) want[m[1]] = m[2];
        }
        if (want.background) root.paper  = want.background;
        if (want.foreground) root.ink    = want.foreground;
        if (want.accent)     root.indigo = want.accent;
        if (want.color1)     root.seal   = want.color1;
    }

    FileView {
        id: paletteFile
        path: root.colorsPath
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.parseColors(paletteFile.text())
    }

    // ---------- Battery state ----------
    property int    batVal:    -1
    property string batState:  "Unknown"
    property int    lastBat:   -1
    property string lastState: ""

    Process {
        id: batProbe
        running: false
        command: ["bash", "-lc",
            "bat=-1; bst=Unknown; "
            + "for d in /sys/class/power_supply/BAT0 /sys/class/power_supply/BAT1; do "
            + "  if [ -d \"$d\" ]; then "
            + "    bat=$(cat \"$d/capacity\" 2>/dev/null || echo -1); "
            + "    bst=$(cat \"$d/status\" 2>/dev/null || echo Unknown); "
            + "    break; "
            + "  fi; "
            + "done; "
            + "printf '%d|%s' \"$bat\" \"$bst\""]
        stdout: StdioCollector {
            onStreamFinished: {
                const p = this.text.split("|");
                if (p.length !== 2) return;
                const v = parseInt(p[0]);
                const s = p[1] || "Unknown";
                if (v < 0) return;

                const prevV = root.lastBat;
                const prevS = root.lastState;
                root.batVal = v;
                root.batState = s;
                root.lastBat = v;
                root.lastState = s;

                if (!root.armed || prevV < 0) return;

                const onBattery = s !== "Charging" && s !== "Full";

                // Discharging crossings — prefer the most severe one if a
                // long sleep made us skip both thresholds at once.
                if (onBattery) {
                    if (prevV > 10 && v <= 10)      drip.fire(true);
                    else if (prevV > 20 && v <= 20) drip.fire(false);
                }

                // Full / plug-in-near-full transitions.
                if (prevS !== s) {
                    const reachedFull   = s === "Full" && prevS !== "Full";
                    const plugInAtFull  = s === "Charging" && prevS !== "Charging" && v >= 95;
                    if (reachedFull || plugInAtFull) wave.fire();
                }
            }
        }
    }
    Timer { interval: 3000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: { batProbe.running = false; batProbe.running = true; } }

    // Manual trigger for testing:
    //   qs -p ~/.config/quickshell/battery-drip/shell.qml ipc call battery drip
    //   qs -p ~/.config/quickshell/battery-drip/shell.qml ipc call battery dripCrit
    //   qs -p ~/.config/quickshell/battery-drip/shell.qml ipc call battery wave
    IpcHandler {
        target: "battery"
        function drip():     void { drip.fire(false); }
        function dripCrit(): void { drip.fire(true); }
        function wave():     void { wave.fire(); }
    }

    // ---------- Overlay ----------
    PanelWindow {
        id: surface
        color: "transparent"
        anchors { top: true; left: true; right: true; bottom: true }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "battery-drip"
        mask: Region {}  // fully click-through

        readonly property int barHeight: 28
        // Mirrors the navbar's battery cell: rightmost Module, 24px wide,
        // with the RowLayout's rightMargin: 10. Centre lands ~22px in.
        readonly property int batCenterX: width - 22
        readonly property int batCenterY: barHeight / 2

        // ---------- Drip ----------
        Item {
            id: drip
            anchors.fill: parent

            property bool critical: false

            function fire(crit) {
                drip.critical = crit;
                dropAnim.stop();
                dropAnim.start();
            }

            Shape {
                id: droplet
                width: 10
                height: 14
                x: surface.batCenterX - width / 2
                y: surface.barHeight - 4

                // grow   : 0..1 birth/exit scale, uniform
                // elong  : y stretch during fall (1 = neutral)
                // squish : x narrow during fall (1 = neutral)
                // fallY  : vertical translate
                property real op:     0
                property real grow:   0
                property real elong:  1.0
                property real squish: 1.0
                property real fallY:  0

                opacity: op
                // Scale around the top tip (y=1) so stretching extends the
                // drop downward rather than ballooning around its centre.
                transform: [
                    Scale {
                        origin.x: droplet.width / 2
                        origin.y: 1
                        xScale: droplet.grow * droplet.squish
                        yScale: droplet.grow * droplet.elong
                    },
                    Translate { y: droplet.fallY }
                ]

                ShapePath {
                    fillColor: drip.critical ? root.tearColor
                              : Qt.rgba(root.tearColor.r, root.tearColor.g, root.tearColor.b, 0.78)
                    strokeWidth: 0

                    // Pointed top, quadratic curves out to the widest point
                    // at y=9, then a clockwise half-circle around the bottom
                    // (bulges downward through y=14) and back up the mirror.
                    startX: 5; startY: 0
                    PathQuad { x: 10; y: 9; controlX: 10; controlY: 4 }
                    PathArc  { x: 0;  y: 9; radiusX: 5; radiusY: 5
                               direction: PathArc.Clockwise }
                    PathQuad { x: 5;  y: 0; controlX: 0;  controlY: 4 }
                }
            }

            SequentialAnimation {
                id: dropAnim

                ScriptAction { script: {
                    droplet.fallY  = 0;
                    droplet.elong  = 1.0;
                    droplet.squish = 1.0;
                    droplet.grow   = 0;
                    droplet.op     = 0;
                } }

                // Form: drop materializes and swells to full size with a
                // touch of overshoot to mimic surface-tension recoil.
                ParallelAnimation {
                    NumberAnimation { target: droplet; property: "op";
                        to: 1; duration: 220; easing.type: Easing.OutCubic }
                    NumberAnimation { target: droplet; property: "grow";
                        to: 1; duration: 320; easing.type: Easing.OutBack }
                }

                // Hang: surface tension holds on for a beat.
                PauseAnimation { duration: 160 }

                // Fall: stretch and narrow continuously across the whole
                // descent — accelerating, lengthening, slimming the whole
                // way. Critical drops fall further and faster.
                ParallelAnimation {
                    NumberAnimation { target: droplet; property: "fallY"
                        to: drip.critical ? 170 : 115
                        duration: drip.critical ? 1500 : 1900
                        easing.type: Easing.InQuad }
                    NumberAnimation { target: droplet; property: "elong";
                        to: 1.85
                        duration: drip.critical ? 1500 : 1900
                        easing.type: Easing.InCubic }
                    NumberAnimation { target: droplet; property: "squish";
                        to: 0.72
                        duration: drip.critical ? 1500 : 1900
                        easing.type: Easing.InCubic }
                }

                // Fade out near terminal y.
                NumberAnimation { target: droplet; property: "op";
                    to: 0; duration: 280; easing.type: Easing.InCubic }
            }
        }

        // ---------- Wave fill ----------
        // Renders our own battery outline at the navbar's battery slot so
        // we can mask the wave to its interior. The navbar's nerd-font
        // glyph stays untouched underneath; the outline overlays it during
        // the animation and fades out, leaving the glyph as the final
        // resting state.
        Item {
            id: wave
            anchors.fill: parent

            function fire() {
                waveAnim.stop();
                waveAnim.start();
            }

            Item {
                id: cell
                width: 22
                height: 12
                x: surface.batCenterX - 9
                y: surface.batCenterY - height / 2

                property real op: 0
                opacity: op

                // Battery body outline.
                Rectangle {
                    id: body
                    width: 18
                    height: 10
                    y: 1
                    color: "transparent"
                    border.color: root.shellColor
                    border.width: 1
                    radius: 1.5
                }

                // Terminal nubbin on the right.
                Rectangle {
                    x: 18
                    y: 4
                    width: 2
                    height: 4
                    color: root.shellColor
                    radius: 0.5
                }

                // Wave fill — clipped to the body's interior.
                Item {
                    x: body.x + 1.5
                    y: body.y + 1.5
                    width:  body.width  - 3
                    height: body.height - 3
                    clip: true

                    Canvas {
                        id: waveCanvas
                        anchors.fill: parent
                        antialiasing: true

                        property real level: 0  // 0..1, fill progress
                        property real phase: 0  // sin crest phase

                        onLevelChanged: requestPaint()
                        onPhaseChanged: requestPaint()
                        onPaint: {
                            const ctx = getContext("2d");
                            ctx.reset();
                            ctx.fillStyle = root.waveColor;
                            const waterY = height * (1 - level);
                            ctx.beginPath();
                            ctx.moveTo(0, height);
                            ctx.lineTo(0, waterY);
                            const segs = Math.max(8, Math.floor(width));
                            for (let i = 0; i <= segs; i++) {
                                const x = i * (width / segs);
                                const y = waterY + Math.sin(
                                    (i / segs) * Math.PI * 2 * 1.3 + phase
                                ) * 0.9;
                                ctx.lineTo(x, y);
                            }
                            ctx.lineTo(width, height);
                            ctx.closePath();
                            ctx.fill();
                        }

                        NumberAnimation on phase {
                            id: phaseAnim
                            from: 0; to: Math.PI * 2
                            duration: 1400
                            loops: Animation.Infinite
                            running: waveAnim.running
                        }
                    }
                }
            }

            SequentialAnimation {
                id: waveAnim

                ScriptAction { script: {
                    cell.op = 0;
                    waveCanvas.level = 0;
                } }

                NumberAnimation { target: cell; property: "op";
                    from: 0; to: 1; duration: 260; easing.type: Easing.OutCubic }

                NumberAnimation { target: waveCanvas; property: "level";
                    from: 0; to: 1; duration: 1500; easing.type: Easing.OutCubic }

                PauseAnimation { duration: 500 }

                NumberAnimation { target: cell; property: "op";
                    to: 0; duration: 480; easing.type: Easing.InCubic }
            }
        }
    }
}
