import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

// Unified OSD — volume, screen brightness, keyboard brightness.
// Entrance: grow + fade (scale 0.90→1.0, opacity 0→1) with the slider doing a
// gauge sweep 0→value. Repeat key presses while visible skip all of that and
// just step the slider; an interrupted exit snaps back in instantly.
// Every duration below is gated on root.focusMode: focus mode is a flat,
// animation-free desktop, so the OSD appears and disappears instantly there.
// Only the DURATION changes — the start/end values are untouched, so the
// resting state is identical in both modes.
// The frame is four explicit 1px rectangles (a Rectangle border stroke on a
// 1.25-scaled output can lose individual edges to rasterization).
PanelWindow {
    id: osd
    screen: {
        var fm = Hyprland.focusedMonitor;
        var s = Quickshell.screens;
        if (fm) for (var i = 0; i < s.length; i++)
            if (s[i].name === fm.name) return s[i];
        return s.length > 0 ? s[0] : null;
    }
    required property var root

    color: "transparent"
    anchors { top: true; right: true }
    implicitHeight: 60
    implicitWidth: 320
    exclusiveZone: 0

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "omarchy-osd"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    // Click-through via empty mask
    mask: Region {}

    property string _mode: "volume"  // "volume", "brightness", "kbd"
    property bool _shown: false      // panel at full scale/opacity (or entering)
    property real _fillRatio: 1      // entry sweep: fill = min(value, _fillRatio)

    visible: true

    Timer {
        id: hideTimer
        interval: 1500
        onTriggered: osd.hide()
    }

    Connections {
        target: osd.root
        function onAudioVolChanged()      { osd._mode = "volume";     osd.show(); }
        function onAudioMutedChanged()    { osd._mode = "volume";     osd.show(); }
        function onBrightnessPctChanged() { osd._mode = "brightness"; osd.show(); }
        function onKbdBrightnessChanged() { osd._mode = "kbd";        osd.show(); }
    }

    function show() {
        hideTimer.restart();
        if (enterAnim.running || _shown) return;  // on screen / entering: value update only
        if (exitAnim.running) {                   // interrupted exit: snap back in
            exitAnim.stop();
            snapIn();
            _shown = true;
            return;
        }
        _shown = true;
        enterAnim.start();
    }

    function hide() {
        if (!_shown || exitAnim.running) return;
        _shown = false;
        enterAnim.stop();
        exitAnim.start();
    }

    function snapIn() {
        slideHost.visible = true;
        slideHost.scale = 1;
        slideHost.opacity = 1;
        _fillRatio = 1;
    }

    readonly property real _value: {
        if (_mode === "volume") return osd.root.audioVol / 100;
        if (_mode === "brightness") return osd.root.brightnessPct / 100;
        // kbd: 0-3 levels mapped to 0.0-1.0
        return osd.root.kbdBrightnessMax > 0
            ? osd.root.kbdBrightness / osd.root.kbdBrightnessMax
            : 0;
    }

    // Two-digit padded percent ("07%", "45%", "100%").
    function _pct(v) {
        var s = String(Math.max(0, Math.min(100, Math.round(v))));
        while (s.length < 2) s = "0" + s;
        return s + "%";
    }

    readonly property string _label: {
        if (_mode === "volume") return osd.root.audioMuted ? "MUTE" : osd._pct(osd.root.audioVol);
        if (_mode === "brightness") return osd._pct(osd.root.brightnessPct);
        var k = osd.root.kbdBrightness;
        if (k <= 0) return "OFF";
        if (k === 1) return "LOW";
        if (k === 2) return "MED";
        return "HIGH";
    }

    readonly property string _icon: {
        if (_mode === "volume") return osd.root.audioMuted ? osd.root.icoMute : osd.root.audioIcon;
        if (_mode === "brightness") return osd._brightnessIcon;
        return osd._kbdIcon;
    }

    // ── Panel ──
    Item {
        id: slideHost
        anchors.fill: parent
        transformOrigin: Item.Center
        visible: false
        opacity: 1
        scale: 1

        Rectangle {
            id: bg
            anchors.fill: parent
            anchors.margins: 10
            color: Qt.rgba(osd.root.paper.r * 0.4, osd.root.paper.g * 0.4, osd.root.paper.b * 0.4,
                           osd.root.focusMode ? 1.0 : 0.98)
            radius: osd.root.cornerRadius
            clip: true

            // Explicit frame — four 1px edges.
            Rectangle {
                anchors { left: parent.left; right: parent.right; top: parent.top }
                height: 1
                color: osd.root.sep
                antialiasing: false
            }
            Rectangle {
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                height: 1
                color: osd.root.sep
                antialiasing: false
            }
            Rectangle {
                anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                width: 1
                color: osd.root.sep
                antialiasing: false
            }
            Rectangle {
                anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
                width: 1
                color: osd.root.sep
                antialiasing: false
            }

            RowLayout {
                id: content
                anchors.centerIn: parent
                spacing: 8

                Text {
                    Layout.alignment: Qt.AlignVCenter
                    Layout.preferredWidth: 18
                    Layout.rightMargin: 6
                    horizontalAlignment: Text.AlignHCenter
                    text: osd._icon
                    color: osd.root.ink
                    font.family: osd.root.mono
                    font.pixelSize: 15
                }

                Rectangle {
                    Layout.alignment: Qt.AlignVCenter
                    width: 190
                    height: 8
                    radius: 0
                    color: osd.root.sep

                    Rectangle {
                        id: fillBar
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: parent.width * Math.min(1, Math.min(osd._value, osd._fillRatio))
                        radius: 0
                        color: osd.root.seal

                        Behavior on width {
                            NumberAnimation {
                                duration: osd.root.focusMode ? 0 : 80
                                easing.type: Easing.OutQuad
                            }
                        }
                    }
                }

                Text {
                    Layout.alignment: Qt.AlignVCenter
                    Layout.preferredWidth: 36
                    horizontalAlignment: Text.AlignRight
                    text: osd._label
                    color: osd.root.ink
                    font.family: osd.root.mono
                    font.pixelSize: 14
                    font.weight: Font.Medium
                }
            }
        }
    }

    // ── Enter: grow + fade, with a gauge sweep on the slider ──
    ParallelAnimation {
        id: enterAnim
        NumberAnimation {
            target: slideHost; property: "scale"
            from: 0.90; to: 1.0
            duration: osd.root.focusMode ? 0 : 180; easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: slideHost; property: "opacity"
            from: 0; to: 1
            duration: osd.root.focusMode ? 0 : 150; easing.type: Easing.OutQuad
        }
        SequentialAnimation {
            PauseAnimation { duration: osd.root.focusMode ? 0 : 60 }
            NumberAnimation {
                target: osd; property: "_fillRatio"
                from: 0; to: 1
                duration: osd.root.focusMode ? 0 : 260; easing.type: Easing.OutCubic
            }
        }
        onStarted: { slideHost.visible = true; }
    }

    // ── Exit: shrink + fade ──
    ParallelAnimation {
        id: exitAnim
        NumberAnimation {
            target: slideHost; property: "scale"
            from: 1.0; to: 0.95
            duration: osd.root.focusMode ? 0 : 110; easing.type: Easing.InQuad
        }
        NumberAnimation {
            target: slideHost; property: "opacity"
            from: 1; to: 0
            duration: osd.root.focusMode ? 0 : 110; easing.type: Easing.InQuad
        }
        onFinished: {
            slideHost.visible = false;
            slideHost.scale = 1;
            slideHost.opacity = 1;
        }
    }

    // Screen brightness icon — sun symbols
    readonly property string _brightnessIcon: osd.root.brightnessPct <= 0
        ? String.fromCodePoint(0xf00d)   // off
        : osd.root.brightnessPct < 33
        ? String.fromCodePoint(0xf186)   // dim
        : String.fromCodePoint(0xf185)   // bright

    // Keyboard brightness icon — keyboard symbols
    readonly property string _kbdIcon: osd.root.kbdBrightness <= 0
        ? String.fromCodePoint(0xf00d)   // X = off
        : String.fromCodePoint(0xf11c)   // keyboard = on (any level)
}
