import QtQuick
import QtQuick.Layouts

// Power detail panel — six native actions, no omarchy-menu indirection.
// Lock uses hyprlock directly; the rest go through systemctl (login +
// power) and Hyprland's IPC for logout. Keyboard: arrows / Tab cycle
// the buttons, Enter activates the focused one.
Item {
    id: body
    required property var root
    required property var nav
    width: parent ? parent.width : 0

    signal close()

    implicitHeight: col.implicitHeight + 8

    property int kbdIndex: 0
    readonly property var _actions: [
        { glyph: "󰌾", label: "LOCK",      cmd: "hyprlock" },
        { glyph: "󰤄", label: "SUSPEND",   cmd: "systemctl suspend" },
        { glyph: "󰋊", label: "HIBERNATE", cmd: "systemctl hibernate" },
        { glyph: "󰗽", label: "LOGOUT",    cmd: "hyprctl dispatch exit" },
        { glyph: "󰜉", label: "REBOOT",    cmd: "systemctl reboot" },
        { glyph: "󰐥", label: "SHUTDOWN",  cmd: "systemctl poweroff" }
    ]

    function kbdHandle(event) {
        const k = event.key;
        const n = body._actions.length;
        if (k === Qt.Key_Left || k === Qt.Key_Up) {
            body.kbdIndex = (body.kbdIndex - 1 + n) % n;
            return true;
        }
        if (k === Qt.Key_Right || k === Qt.Key_Down || k === Qt.Key_Tab) {
            body.kbdIndex = (body.kbdIndex + 1) % n;
            return true;
        }
        if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) {
            body._fire(body._actions[body.kbdIndex]);
            return true;
        }
        return false;
    }
    function _fire(a) {
        if (body.nav && a && a.cmd) body.nav.run(a.cmd);
        body.close();
    }

    Column {
        id: col
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: 6
        spacing: 10

        Text {
            text: "POWER · " + (body.nav ? body.nav.batVal + "%" : "")
                  + (body.nav && body.nav.batState !== "Unknown"
                      ? "  ·  " + body.nav.batState.toUpperCase()
                      : "")
            color: body.root.inkDeep
            font.family: body.root.mono
            font.pixelSize: 10
            font.letterSpacing: 2
        }

        Flow {
            width: parent.width
            spacing: 8
            Repeater {
                model: body._actions
                delegate: QuickButton {
                    required property var modelData
                    required property int index
                    root: body.root
                    glyph: modelData.glyph
                    label: modelData.label
                    selected: body.kbdIndex === index
                    onClicked: body._fire(modelData)
                }
            }
        }
    }
}
