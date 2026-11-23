import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

// Volume OSD — bar at top-right, auto-hides after changes.
// Background styled like OmniMenu: paper*0.4 with border.
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
    WlrLayershell.namespace: "omarchy-volume-osd"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    // Click-through via empty mask
    mask: Region {}

    property bool _showing: false
    property real _opacity: 0

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
        function onAudioVolChanged() { osd.show() }
        function onAudioMutedChanged() { osd.show() }
    }

    function show() {
        _showing = true;
        _opacity = 1;
        hideTimer.restart();
    }

    // Background — OmniMenu style: paper*0.4, border, corner radius
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

            // Fixed-width icon to prevent layout shifts between glyph sizes
            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: 18
                horizontalAlignment: Text.AlignHCenter
                text: osd.root.audioMuted ? osd.root.icoMute : osd.root.audioIcon
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
                    width: parent.width * Math.min(1, osd.root.audioVol / 100)
                    radius: 3
                    color: osd.root.seal

                    Behavior on width {
                        NumberAnimation { duration: 80; easing.type: Easing.OutQuad }
                    }
                }
            }

            // Fixed-width label to prevent layout shifts
            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: 40
                horizontalAlignment: Text.AlignRight
                text: osd.root.audioMuted ? "MUTE" : osd.root.audioVol + "%"
                color: osd.root.ink
                font.family: osd.root.mono
                font.pixelSize: 14
                font.weight: Font.Medium
            }
        }
    }
}
