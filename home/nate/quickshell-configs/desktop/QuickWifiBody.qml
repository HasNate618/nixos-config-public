import QtQuick

// Wi-Fi detail — radio toggle + scan + network list. iwd does all the
// heavy lifting; the panel just reads `wifiNetworks` and asks iwctl to
// connect by SSID. Saved networks reconnect silently; first-time
// connects need a passphrase iwctl can't pull from here (run iwctl
// manually for those). Keyboard: arrow up/down moves through header
// buttons and network rows, Enter activates.
Item {
    id: body
    required property var root
    required property var nav
    width: parent ? parent.width : 0

    signal close()

    implicitHeight: col.implicitHeight + 8

    Component.onCompleted: if (body.nav) body.nav.refreshWifi()

    // 0 = RADIO toggle, 1 = SCAN, 2..N+1 = network rows.
    property int kbdIndex: 2
    readonly property int _headerCount: 2
    readonly property var _visibleNets: body.nav && body.nav.wifiRadioOn
                                        ? body.nav.wifiNetworks.slice(0, 8)
                                        : []
    readonly property int _kbdMax: _headerCount + _visibleNets.length

    function kbdHandle(event) {
        const k = event.key;
        const n = body._kbdMax;
        if (n === 0) return false;
        if (k === Qt.Key_Up) {
            body.kbdIndex = Math.max(0, body.kbdIndex - 1);
            return true;
        }
        if (k === Qt.Key_Down || k === Qt.Key_Tab) {
            body.kbdIndex = Math.min(n - 1, body.kbdIndex + 1);
            return true;
        }
        if (k === Qt.Key_Left) {
            // Up-arrow analogue at the header
            body.kbdIndex = Math.max(0, body.kbdIndex - 1);
            return true;
        }
        if (k === Qt.Key_Right) {
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
        if (i === 0) { if (body.nav) body.nav.toggleWifiRadio(); return; }
        if (i === 1) { if (body.nav) body.nav.refreshWifi(); return; }
        const net = body._visibleNets[i - body._headerCount];
        if (!net || !body.nav) return;
        if (net.inUse) body.nav.disconnectWifi();
        else body.nav.connectWifi(net.ssid);
    }


    Column {
        id: col
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: 6
        spacing: 10

        // Header: state + radio toggle + scan
        Item {
            width: parent.width
            height: 28

            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: body.nav && body.nav.wifiRadioOn
                      ? (body.nav.wifiScanning ? "SCANNING…"
                         : (body.nav.wifiNetworks.length + " NETWORKS"))
                      : "RADIO OFF"
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
                    label: body.nav && body.nav.wifiRadioOn ? "RADIO OFF" : "RADIO ON"
                    selected: body.kbdIndex === 0
                    onClicked: if (body.nav) body.nav.toggleWifiRadio()
                }
                QuickButton {
                    root: body.root
                    glyph: body.nav ? body.nav.icoRefresh : ""
                    label: "SCAN"
                    selected: body.kbdIndex === 1
                    onClicked: if (body.nav) body.nav.refreshWifi()
                }
            }
        }

        Rectangle { width: parent.width; height: 1; color: body.root.sep }

        Repeater {
            model: body._visibleNets
            delegate: Rectangle {
                required property var modelData
                required property int index
                readonly property bool kbdFocused: body.kbdIndex === (index + body._headerCount)
                width: col.width
                height: 32
                radius: body.root.cornerRadius
                color: modelData.inUse || kbdFocused
                       ? body.root.rowSel
                       : netMouse.containsMouse
                           ? body.root.rowHi
                           : "transparent"
                border.color: modelData.inUse || kbdFocused ? body.root.seal : body.root.sep
                border.width: kbdFocused ? 2 : 1
                Behavior on color        { ColorAnimation { duration: 120 } }
                Behavior on border.color { ColorAnimation { duration: 120 } }
                Behavior on border.width { NumberAnimation { duration: 120 } }

                Text {
                    id: barsIcon
                    anchors.left: parent.left
                    anchors.leftMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    text: body.nav.wifiBarsGlyph(modelData.signal)
                    color: modelData.inUse ? body.root.seal : body.root.ink
                    font.family: body.root.mono
                    font.pixelSize: 14
                }
                Text {
                    anchors.left: barsIcon.right
                    anchors.right: secTag.left
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData.ssid
                    elide: Text.ElideRight
                    color: modelData.inUse ? body.root.ink : body.root.fg
                    font.family: body.root.mono
                    font.pixelSize: 11
                    font.weight: modelData.inUse ? Font.Medium : Font.Normal
                }
                Text {
                    id: secTag
                    anchors.right: sigText.left
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData.security && modelData.security.length > 0
                          && modelData.security !== "open" ? "󰌾" : ""
                    color: body.root.inkDeep
                    font.family: body.root.mono
                    font.pixelSize: 11
                }
                Text {
                    id: sigText
                    anchors.right: parent.right
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData.signal + "%"
                    color: body.root.inkDeep
                    font.family: body.root.mono
                    font.pixelSize: 10
                    font.letterSpacing: 1
                }
                MouseArea {
                    id: netMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: body._activateAt(index + body._headerCount)
                }
            }
        }

        Text {
            visible: body.nav && body.nav.wifiRadioOn && body.nav.wifiNetworks.length === 0 && !body.nav.wifiScanning
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: "NO NETWORKS FOUND"
            color: body.root.inkDeep
            font.family: body.root.mono
            font.pixelSize: 10
            font.letterSpacing: 2
            opacity: 0.6
        }
    }
}
