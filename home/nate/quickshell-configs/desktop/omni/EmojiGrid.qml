import QtQuick

// Emoji grid display. Renders a search-filtered emoji list in a
// Flow layout. Supports keyboard navigation: arrows move grid-wise,
// Enter picks the selected emoji.
Item {
    id: root

    required property var omni
    property var model: []

    property int cellSize: 56

    /// Currently selected index in the model (or -1 when empty).
    property int selectedIndex: -1

    signal picked(string emoji, string name)

    /// Number of columns the Flow resolves to at the current width.
    readonly property int columns: Math.max(1,
        Math.floor((flow.width + flow.spacing) / (cellSize + flow.spacing)))

    onModelChanged: {
        selectedIndex = model.length > 0 ? 0 : -1;
    }

    /// Move selection by `delta` positions. Positive = forward/right/down,
    /// negative = backward/left/up. For row-wise moves (left/right) pass ±1;
    /// for column-wise moves (up/down) pass ±columns.
    function moveSelection(delta) {
        if (model.length === 0) return;
        var next = Math.max(0, Math.min(model.length - 1, root.selectedIndex + delta));
        root.selectedIndex = next;

        // Scroll Flickable to keep the selected cell visible
        var col = next % root.columns;
        var row = Math.floor(next / root.columns);
        var cellPitch = root.cellSize + flow.spacing;
        var cellX = col * cellPitch;
        var cellY = row * cellPitch;

        // Horizontal scroll (contentWidth == flick.width, no horizontal scroll needed)
        // Vertical scroll
        if (cellY < flick.contentY) {
            flick.contentY = cellY;
        } else if (cellY + root.cellSize > flick.contentY + flick.height) {
            flick.contentY = cellY + root.cellSize + flow.spacing - flick.height;
        }
    }

    Flickable {
        id: flick
        anchors.fill: parent
        anchors.margins: 4
        contentWidth: width - 8
        contentHeight: flow.height + 8
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Flow {
            id: flow
            width: parent.width
            spacing: 4

            Repeater {
                model: root.model

                Rectangle {
                    id: cell
                    required property var modelData
                    required property int index
                    width: root.cellSize
                    height: root.cellSize
                    radius: 0
                    color: index === root.selectedIndex
                        ? (root.omni ? root.omni.rowSel : "#60ffffff")
                        : (cellMouse.containsMouse
                            ? (root.omni ? root.omni.rowHi : "#40ffffff")
                            : "transparent")

                    // Selection frame: corner brackets on all four corners
                    // (8px arms / 2px strokes), animated on selection change.
                    Item {
                        id: selFrame
                        anchors.fill: parent
                        z: 2
                        opacity: index === root.selectedIndex ? 1 : 0
                        property real inset: index === root.selectedIndex ? 0 : 3
                        Behavior on opacity { NumberAnimation { duration: root.omni.theme.focusMode ? 0 : 110; easing.type: Easing.OutCubic } }
                        Behavior on inset { NumberAnimation { duration: root.omni.theme.focusMode ? 0 : 150; easing.type: Easing.OutCubic } }
                        property color lineColor: root.omni ? root.omni.seal : "#88ffffff"
                        Rectangle { anchors { left: parent.left; top: parent.top; leftMargin: selFrame.inset; topMargin: selFrame.inset } width: 2; height: 8; color: selFrame.lineColor }
                        Rectangle { anchors { left: parent.left; top: parent.top; leftMargin: selFrame.inset; topMargin: selFrame.inset } width: 8; height: 2; color: selFrame.lineColor }
                        Rectangle { anchors { right: parent.right; top: parent.top; rightMargin: selFrame.inset; topMargin: selFrame.inset } width: 2; height: 8; color: selFrame.lineColor }
                        Rectangle { anchors { right: parent.right; top: parent.top; rightMargin: selFrame.inset; topMargin: selFrame.inset } width: 8; height: 2; color: selFrame.lineColor }
                        Rectangle { anchors { left: parent.left; bottom: parent.bottom; leftMargin: selFrame.inset; bottomMargin: selFrame.inset } width: 2; height: 8; color: selFrame.lineColor }
                        Rectangle { anchors { left: parent.left; bottom: parent.bottom; leftMargin: selFrame.inset; bottomMargin: selFrame.inset } width: 8; height: 2; color: selFrame.lineColor }
                        Rectangle { anchors { right: parent.right; bottom: parent.bottom; rightMargin: selFrame.inset; bottomMargin: selFrame.inset } width: 2; height: 8; color: selFrame.lineColor }
                        Rectangle { anchors { right: parent.right; bottom: parent.bottom; rightMargin: selFrame.inset; bottomMargin: selFrame.inset } width: 8; height: 2; color: selFrame.lineColor }
                    }

                    Text {
                        anchors.centerIn: parent
                        text: cell.modelData ? cell.modelData.e : ""
                        font.pixelSize: 38
                    }

                    // Tooltip on hover
                    Rectangle {
                        visible: cellMouse.containsMouse || index === root.selectedIndex
                        anchors.bottom: parent.top
                        anchors.bottomMargin: 4
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: tipText.implicitWidth + 8
                        height: tipText.implicitHeight + 4
                        radius: 0
                        color: "#dd333333"
                        z: 10
                        Text {
                            id: tipText
                            anchors.centerIn: parent
                            text: cell.modelData ? cell.modelData.n : ""
                            color: "#fff"
                            font.pixelSize: 10
                        }
                    }

                    MouseArea {
                        id: cellMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            root.selectedIndex = cell.index;
                            if (cell.modelData && cell.modelData.e)
                                root.picked(cell.modelData.e, cell.modelData.n || "");
                        }
                        onEntered: { if (!root.omni || !root.omni._mouseBlocked) root.selectedIndex = cell.index; }
                    }
                }
            }
        }
    }
}
