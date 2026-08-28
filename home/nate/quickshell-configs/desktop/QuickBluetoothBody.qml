import QtQuick

// Bluetooth detail — power toggle, scan, paired/known device list with
// connect/disconnect. bluez-tools backed (bt-adapter / bt-device).
// Keyboard: arrows / Tab move through header buttons and devices,
// Enter activates.
Item {
    id: body
    required property var root
    required property var nav
    width: parent ? parent.width : 0

    signal close()

    implicitHeight: col.implicitHeight + 8

    Component.onCompleted: if (body.nav) body.nav.refreshBluetooth()

    property int kbdIndex: 2
    readonly property int _headerCount: 2
    readonly property var _visibleDevs: body.nav && body.nav.btPowered
                                        ? body.nav.btDevices.slice(0, 8)
                                        : []
    readonly property int _kbdMax: _headerCount + _visibleDevs.length

    function kbdHandle(event) {
        const k = event.key;
        const n = body._kbdMax;
        if (n === 0) return false;
        if (k === Qt.Key_Up || k === Qt.Key_Left) {
            body.kbdIndex = Math.max(0, body.kbdIndex - 1);
            return true;
        }
        if (k === Qt.Key_Down || k === Qt.Key_Right || k === Qt.Key_Tab) {
            body.kbdIndex = Math.min(n - 1, body.kbdIndex + 1);
            return true;
        }
        if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) {
            body._activateAt(body.kbdIndex);
            return true;
        }
        return false;
    }

    function _activateAt(i) {
        body.kbdIndex = i;
        if (i === 0) { if (body.nav) body.nav.btTogglePower(); return; }
        if (i === 1) { if (body.nav) body.nav.btToggleScan(); return; }
        const dev = body._visibleDevs[i - body._headerCount];
        if (!dev || !body.nav) return;
        if (dev.connected) body.nav.btDisconnect(dev.mac);
        else body.nav.btConnect(dev.mac);
    }

    Column {
        id: col
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: 6
        spacing: 10

        Item {
            width: parent.width
            height: 28
            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: !body.nav ? "—"
                      : !body.nav.btPowered ? "POWER OFF"
                      : (body.nav.btDevices.length + " DEVICES"
                         + (body.nav.btCount > 0
                            ? "  ·  " + body.nav.btCount + " CONN"
                            : "")
                         + (body.nav.btScanning ? "  ·  SCANNING" : ""))
                color: body.root.inkDeep
                font.family: body.root.mono
                font.pixelSize: 10
                font.letterSpacing: 2
            }
            Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8
                QuickButton {
                    root: body.root
                    label: body.nav && body.nav.btPowered ? "POWER OFF" : "POWER ON"
                    selected: body.kbdIndex === 0
                    onClicked: if (body.nav) body.nav.btTogglePower()
                }
                QuickButton {
                    root: body.root
                    label: body.nav && body.nav.btScanning ? "SCANNING" : "SCAN"
                    selected: body.kbdIndex === 1 || (body.nav && body.nav.btScanning)
                    onClicked: if (body.nav) body.nav.btToggleScan()
                }
            }
        }

        Rectangle { width: parent.width; height: 1; color: body.root.sep }

        Repeater {
            model: body._visibleDevs
            delegate: Rectangle {
                required property var modelData
                required property int index
                readonly property bool kbdFocused: body.kbdIndex === (index + body._headerCount)
                width: col.width
                height: 32
                radius: body.root.cornerRadius
                color: modelData.connected || kbdFocused
                       ? body.root.rowSel
                       : devMouse.containsMouse
                           ? body.root.rowHi
                           : "transparent"
                border.color: modelData.connected || kbdFocused ? body.root.seal : body.root.sep
                border.width: kbdFocused ? 2 : 1
                Behavior on color        { ColorAnimation { duration: 120 } }
                Behavior on border.color { ColorAnimation { duration: 120 } }
                Behavior on border.width { NumberAnimation { duration: 120 } }

                Text {
                    id: devIcon
                    anchors.left: parent.left
                    anchors.leftMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData.connected ? "󰂱" : (modelData.paired ? "󰂯" : "󰂲")
                    color: modelData.connected ? body.root.seal : body.root.ink
                    font.family: body.root.mono
                    font.pixelSize: 14
                }
                Text {
                    anchors.left: devIcon.right
                    anchors.right: tag.left
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData.name
                    elide: Text.ElideRight
                    color: modelData.connected ? body.root.ink : body.root.fg
                    font.family: body.root.mono
                    font.pixelSize: 11
                    font.weight: modelData.connected ? Font.Medium : Font.Normal
                }
                Text {
                    id: tag
                    anchors.right: parent.right
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData.connected ? "CONNECTED"
                           : modelData.paired ? "PAIRED"
                                              : (modelData.trusted ? "TRUSTED" : "")
                    color: body.root.inkDeep
                    font.family: body.root.mono
                    font.pixelSize: 9
                    font.letterSpacing: 1.5
                }
                MouseArea {
                    id: devMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        body._activateAt(index + body._headerCount);
                    }
                }
            }
        }

        Text {
            visible: body.nav && body.nav.btPowered && body.nav.btDevices.length === 0
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: "NO DEVICES — TAP SCAN"
            color: body.root.inkDeep
            font.family: body.root.mono
            font.pixelSize: 10
            font.letterSpacing: 2
            opacity: 0.6
        }
    }
}
