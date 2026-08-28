import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

// Unified OSD — volume, screen brightness, keyboard brightness.
// Shows whichever changed last. Background styled like OmniMenu.
PanelWindow {
    id: osd
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

    property bool _showing: false
    property real _opacity: 0
    property string _mode: "volume"  // "volume", "brightness", "kbd"

    visible: true

    Behavior on _opacity {
        NumberAnimation { duration: 150; easing.type: Easing.OutQuad }
    }

    Timer {
        id: hideTimer
        interval: 1500
        onTriggered: { osd._showing = false; osd._opacity = 0; }
    }

    Connections {
        target: osd.root
        function onAudioVolChanged() {
            osd._mode = "volume";
            osd.show();
        }
        function onAudioMutedChanged() {
            osd._mode = "volume";
            osd.show();
        }
        function onBrightnessPctChanged() {
            osd._mode = "brightness";
            osd.show();
        }
        function onKbdBrightnessChanged() {
            osd._mode = "kbd";
            osd.show();
        }
    }

    function show() {
        _showing = true;
        _opacity = 1;
        hideTimer.restart();
    }

    // Current values based on mode
    readonly property real _value: {
        if (_mode === "volume") return osd.root.audioVol / 100;
        if (_mode === "brightness") return osd.root.brightnessPct / 100;
        // kbd: 0-3 levels mapped to 0.0-1.0
        return osd.root.kbdBrightnessMax > 0
            ? osd.root.kbdBrightness / osd.root.kbdBrightnessMax
            : 0;
    }

    readonly property string _label: {
        if (_mode === "volume") return osd.root.audioMuted ? "MUTE" : osd.root.audioVol + "%";
        if (_mode === "brightness") return osd.root.brightnessPct + "%";
        // kbd: named levels
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

    // Background — OmniMenu style
    Rectangle {
        anchors.fill: parent
        anchors.margins: 10
        color: Qt.rgba(osd.root.paper.r * 0.4, osd.root.paper.g * 0.4, osd.root.paper.b * 0.4, 0.99)
        border.color: osd.root.sep
        border.width: 1
        radius: osd.root.cornerRadius
        opacity: osd._opacity

        Row {
            anchors.centerIn: parent
            spacing: 14

            // Fixed-width icon
            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: 18
                horizontalAlignment: Text.AlignHCenter
                text: osd._icon
                color: osd.root.seal
                font.family: osd.root.mono
                font.pixelSize: 18
            }

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 180
                height: 8
                radius: 3
                color: osd.root.sep

                Rectangle {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: parent.width * Math.min(1, osd._value)
                    radius: 3
                    color: osd.root.seal

                    Behavior on width {
                        NumberAnimation { duration: 80; easing.type: Easing.OutQuad }
                    }
                }
            }

            // Fixed-width label
            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: 40
                horizontalAlignment: Text.AlignRight
                text: osd._label
                color: osd.root.ink
                font.family: osd.root.mono
                font.pixelSize: 14
                font.weight: Font.Medium
            }
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
