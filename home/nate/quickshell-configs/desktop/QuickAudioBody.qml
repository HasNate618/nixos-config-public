import QtQuick
import QtQuick.Layouts

// Audio detail — mute toggle + volume slider + output sink picker.
// Sinks come from `wpctl status`; switching uses `wpctl set-default`.
// Keyboard: 0 = mute, 1 = slider (left/right adjust ±5%), 2..N+1 sinks.
// Enter activates the focused control (toggle, or set sink).
Item {
    id: body
    required property var root
    required property var nav
    width: parent ? parent.width : 0

    signal close()

    implicitHeight: col.implicitHeight + 8

    Component.onCompleted: if (body.nav) body.nav.refreshAudioSinks()

    property int kbdIndex: 1   // start on the slider — most common adjust
    readonly property int _headerCount: 2
    readonly property var _sinks: body.nav ? body.nav.audioSinks : []
    readonly property int _kbdMax: _headerCount + _sinks.length

    function kbdHandle(event) {
        const k = event.key;
        const n = body._kbdMax;
        if (n === 0) return false;
        if (body.kbdIndex === 1
            && (k === Qt.Key_Left || k === Qt.Key_Right)) {
            // Slider adjust by ±5%.
            const delta = (k === Qt.Key_Left) ? -5 : 5;
            const cur = body.nav ? body.nav.audioVol : 0;
            if (body.nav) body.nav.setVolume(cur + delta);
            return true;
        }
        if (k === Qt.Key_Up || k === Qt.Key_Left) {
            body.kbdIndex = Math.max(0, body.kbdIndex - 1);
            return true;
        }
        if (k === Qt.Key_Down || k === Qt.Key_Right || k === Qt.Key_Tab) {
            body.kbdIndex = Math.min(n - 1, body.kbdIndex + 1);
            return true;
        }
        if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) {
            // 0 = mute button, 1 = slider (Enter toggles mute as a
            // shortcut), 2..N+1 = sink rows.
            if (body.kbdIndex < body._headerCount) {
                if (body.nav) body.nav.toggleMute();
                return true;
            }
            const sink = body._sinks[body.kbdIndex - body._headerCount];
            if (sink && body.nav) body.nav.setDefaultSink(sink.id);
            return true;
        }
        return false;
    }

    Column {
        id: col
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: 6
        spacing: 12

        Item {
            width: parent.width
            height: 28

            QuickButton {
                id: muteBtn
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                root: body.root
                glyph: body.nav && body.nav.audioMuted
                       ? body.nav.icoMute
                       : (body.nav ? body.nav.audioIcon : "󰕾")
                label: body.nav && body.nav.audioMuted ? "UNMUTE" : "MUTE"
                selected: body.kbdIndex === 0
                onClicked: if (body.nav) body.nav.toggleMute()
            }
            QuickSlider {
                anchors.left: muteBtn.right
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: 12
                root: body.root
                value: body.nav ? body.nav.audioVol : 0
                min: 0; max: 150
                onCommitted: (v) => { if (body.nav) body.nav.setVolume(v); }
                label: body.nav && body.nav.audioMuted ? "MUTED"
                       : (body.nav ? body.nav.audioVol + "%" : "—")
            }
        }

        // Slider focus indicator (a thin underline under the track when
        // kbdIndex === 1, since the QuickSlider doesn't have a selected
        // prop of its own).
        Rectangle {
            visible: body.kbdIndex === 1
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: 90
            anchors.rightMargin: 60
            height: 1
            color: body.root.seal
            opacity: 0.6
        }

        Item {
            visible: body._sinks.length > 0
            width: parent.width
            height: visible ? sinkCol.implicitHeight : 0

            Column {
                id: sinkCol
                width: parent.width
                spacing: 6

                Text {
                    text: "OUTPUT"
                    color: body.root.inkDeep
                    font.family: body.root.mono
                    font.pixelSize: 10
                    font.letterSpacing: 2
                }
                Column {
                    width: parent.width
                    spacing: 4
                    Repeater {
                        model: body._sinks
                        delegate: Rectangle {
                            required property var modelData
                            required property int index
                            readonly property bool kbdFocused: body.kbdIndex === (index + body._headerCount)
                            width: parent.width
                            height: 30
                            radius: body.root.cornerRadius
                            color: modelData.isDefault || kbdFocused
                                   ? body.root.rowSel
                                   : sinkMouse.containsMouse
                                       ? body.root.rowHi
                                       : "transparent"
                            border.color: modelData.isDefault || kbdFocused ? body.root.seal : body.root.sep
                            border.width: kbdFocused ? 2 : 1
                            Behavior on color { ColorAnimation { duration: 120 } }
                            Behavior on border.color { ColorAnimation { duration: 120 } }
                            Behavior on border.width { NumberAnimation { duration: 120 } }

                            Text {
                                anchors.left: parent.left
                                anchors.leftMargin: 10
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.isDefault ? "✓" : " "
                                color: body.root.seal
                                font.family: body.root.mono
                                font.pixelSize: 11
                                font.weight: Font.Medium
                            }
                            Text {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.leftMargin: 26
                                anchors.rightMargin: 10
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.name
                                elide: Text.ElideRight
                                color: modelData.isDefault ? body.root.ink : body.root.fg
                                font.family: body.root.mono
                                font.pixelSize: 11
                            }
                            MouseArea {
                                id: sinkMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    body.kbdIndex = index + body._headerCount;
                                    if (body.nav) body.nav.setDefaultSink(modelData.id);
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
