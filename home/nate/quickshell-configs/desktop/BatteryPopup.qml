import QtQuick

CardWindow {
    id: batteryPopup
    required property var root

    theme: root
    revealed: root.batteryVisible
    cardWidth: 420
    layerNamespace: "omarchy-battery"
    footer: "←→ NUDGE  ·  1 2 3 PWR  ·  ESC"

    anchorEdge: batteryPopup.root.barEdge
    anchorBarX: batteryPopup.root.popupAnchorX
    anchorBarY: batteryPopup.root.popupAnchorY

    title: "BATTERY"
    subtitle: batteryPopup.root.batVal + "%"
              + "  ·  " + batteryPopup.root.batState.toUpperCase()
              + (batteryPopup.root.batPower >= 0.05
                  ? "  ·  " + batteryPopup.root.batPower.toFixed(1) + "W"
                  : "")

    onDismiss: batteryPopup.root.batteryVisible = false
    onKeyPressed: function(event) {
        var r = batteryPopup.root;
        var k = event.key;
        if (k === Qt.Key_Q || k === Qt.Key_Escape) {
            r.batteryVisible = false;
        } else if (k === Qt.Key_1) {
            r.setPowerProfile("performance");
        } else if (k === Qt.Key_2) {
            r.setPowerProfile("balanced");
        } else if (k === Qt.Key_3) {
            r.setPowerProfile("quiet");
        } else if (k === Qt.Key_Left || k === Qt.Key_H) {
            var v = Math.max(40, r.batChargeLimit - 5);
            r.setBatteryLimit(v);
        } else if (k === Qt.Key_Right || k === Qt.Key_L) {
            var v = Math.min(100, r.batChargeLimit + 5);
            r.setBatteryLimit(v);
        } else {
            return;
        }
        event.accepted = true;
    }

    function _profileGlyph(p) {
        if (p === "performance") return batteryPopup.root.icoPerf;
        if (p === "quiet")       return batteryPopup.root.icoQuiet;
        return batteryPopup.root.icoBal;  // balanced
    }

    Column {
        width: parent.width
        spacing: 12

        Rectangle { width: parent.width; height: 1; color: batteryPopup.root.sep }

        // Charge limit slider
        Item {
            width: parent.width
            height: 36

            Text {
                anchors.left: parent.left
                anchors.top: parent.top
                text: "CHARGE LIMIT"
                color: batteryPopup.root.inkDeep
                font.family: batteryPopup.root.mono
                font.pixelSize: 10
                font.letterSpacing: 2
            }
            Text {
                anchors.right: parent.right
                anchors.top: parent.top
                text: batteryPopup.root.batChargeLimit + "%"
                color: batteryPopup.root.ink
                font.family: batteryPopup.root.mono
                font.pixelSize: 10
                font.letterSpacing: 2
                font.weight: Font.Medium
            }

            Rectangle {
                id: limitTrack
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 3
                color: Qt.rgba(batteryPopup.root.ink.r, batteryPopup.root.ink.g, batteryPopup.root.ink.b, 0.12)
                antialiasing: true

                Rectangle {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: parent.width * Math.max(0, Math.min(1,
                        (batteryPopup.root.batChargeLimit - 40) / 60))
                    color: batteryPopup.root.seal
                    antialiasing: true
                    Behavior on width { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                }

                Rectangle {
                    width: 2; height: 11; y: -4
                    color: batteryPopup.root.seal
                    antialiasing: true
                    x: Math.max(0, Math.min(parent.width - width,
                        parent.width * Math.max(0, Math.min(1,
                            (batteryPopup.root.batChargeLimit - 40) / 60)) - width / 2))
                    Behavior on x { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                }

                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -6
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onPressed: function(e) {
                        var ratio = Math.max(0, Math.min(1, e.x / parent.width));
                        var raw = 40 + ratio * 60;
                        var snapped = Math.round(raw / 5) * 5;
                        batteryPopup.root.setBatteryLimit(Math.max(40, Math.min(100, snapped)));
                    }
                }
            }
        }

        Rectangle { width: parent.width; height: 1; color: batteryPopup.root.sep }

        // Power profile buttons
        Item {
            width: parent.width
            height: 48

            Text {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.topMargin: 2
                text: "POWER PROFILE"
                color: batteryPopup.root.inkDeep
                font.family: batteryPopup.root.mono
                font.pixelSize: 10
                font.letterSpacing: 2
            }

            Row {
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                spacing: 8

                Repeater {
                    model: ["performance", "balanced", "quiet"]
                    delegate: QuickButton {
                        required property string modelData
                        required property int index
                        root: batteryPopup.root
                        glyph: batteryPopup._profileGlyph(modelData)
                        label: modelData.toUpperCase()
                        selected: batteryPopup.root.powerProfile === modelData
                        onClicked: batteryPopup.root.setPowerProfile(modelData)
                    }
                }
            }
        }
    }
}
