import QtQuick
import QtQuick.Layouts

// Two opposing L-corners around a stat reading — Tsugumori bar motif:
// top-left 「 + bottom-right 」 (5px arms, 1px strokes). The frame both
// delimits the reading and acts as the separator between widgets, so
// frame-to-frame gaps stay uniform by construction (unlike glyph-ink
// gaps, which drift with Nerd Font side bearings).
Item {
    id: frame
    required property var root
    default property alias content: inner.data
    property real innerSpacing: 5
    property color lineColor: Qt.rgba(root.seal.r, root.seal.g, root.seal.b, 0.55)

    implicitWidth: inner.implicitWidth + 20
    implicitHeight: inner.implicitHeight + 6

    RowLayout {
        id: inner
        anchors.centerIn: parent
        spacing: frame.innerSpacing
    }

    // 「 top-left corner
    Rectangle { anchors { left: parent.left; top: parent.top } width: 1; height: 5; color: frame.lineColor }
    Rectangle { anchors { left: parent.left; top: parent.top } width: 5; height: 1; color: frame.lineColor }
    // 」 bottom-right corner
    Rectangle { anchors { right: parent.right; bottom: parent.bottom } width: 1; height: 5; color: frame.lineColor }
    Rectangle { anchors { right: parent.right; bottom: parent.bottom } width: 5; height: 1; color: frame.lineColor }
}
