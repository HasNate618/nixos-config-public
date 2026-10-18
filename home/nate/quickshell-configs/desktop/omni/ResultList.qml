import QtQuick
import QtQuick.Effects

// Vertical result list. Row delegate handles icon resolution (image
// fallback to glyph), title with drill-in chevron, favourite star, and
// category label. list is aliased so the parent's key handler can
// call positionViewAtIndex without reaching through child ids.
Item {
    id: rl

    required property var omni
    required property var bookmarks

    property alias list: resultList

    ListView {
        id: resultList
        anchors.fill: parent
        model: rl.omni.filteredItems.length > rl.omni._visibleCount
            ? rl.omni.filteredItems.slice(0, rl.omni._visibleCount)
            : rl.omni.filteredItems
        currentIndex: rl.omni.selectedIndex
        highlightFollowsCurrentItem: false
        boundsBehavior: Flickable.StopAtBounds
        // Disable built-in Flickable wheel scrolling so our MouseArea
        // below can handle it with a faster multiplier.
        interactive: false
        cacheBuffer: 80
        // Snap pixel-perfect so the row outline doesn't shimmer during
        // arrow-key scroll.
        pixelAligned: true
        // On every index change (arrow nav, query filter, category switch)
        // scroll the viewport to keep the selected item visible.
        onCurrentIndexChanged: {
            if (currentIndex < 0) return;
            positionViewAtIndex(currentIndex, ListView.Contain);
        }

        delegate: Item {
            id: row
            required property var modelData
            required property int index
            width: ListView.view.width
            height: index < rl.omni._visibleCount ? 32 : 0
            visible: index < rl.omni._visibleCount
            readonly property bool isSelected: rl.omni.selectedIndex === index

            Rectangle {
                anchors.fill: parent
                color: row.isSelected ? rl.omni.rowSel
                                      : (rowMouse.containsMouse && !rl.omni._mouseBlocked) ? rl.omni.rowHi
                                                               : "transparent"
                Behavior on color { ColorAnimation { duration: rl.omni.theme.focusMode ? 0 : 40 } }
            }
            // Selection frame: corner brackets on all four corners
            // (8px arms / 2px strokes). Animated on selection change —
            // fade in + slide from a small inset.
            Item {
                id: selFrame
                anchors.fill: parent
                opacity: row.isSelected ? 1 : 0
                property real inset: row.isSelected ? 0 : 3
                Behavior on opacity { NumberAnimation { duration: rl.omni.theme.focusMode ? 0 : 110; easing.type: Easing.OutCubic } }
                Behavior on inset { NumberAnimation { duration: rl.omni.theme.focusMode ? 0 : 150; easing.type: Easing.OutCubic } }
                Rectangle { anchors { left: parent.left; top: parent.top; leftMargin: selFrame.inset; topMargin: selFrame.inset } width: 2; height: 8; color: rl.omni.seal }
                Rectangle { anchors { left: parent.left; top: parent.top; leftMargin: selFrame.inset; topMargin: selFrame.inset } width: 8; height: 2; color: rl.omni.seal }
                Rectangle { anchors { right: parent.right; top: parent.top; rightMargin: selFrame.inset; topMargin: selFrame.inset } width: 2; height: 8; color: rl.omni.seal }
                Rectangle { anchors { right: parent.right; top: parent.top; rightMargin: selFrame.inset; topMargin: selFrame.inset } width: 8; height: 2; color: rl.omni.seal }
                Rectangle { anchors { left: parent.left; bottom: parent.bottom; leftMargin: selFrame.inset; bottomMargin: selFrame.inset } width: 2; height: 8; color: rl.omni.seal }
                Rectangle { anchors { left: parent.left; bottom: parent.bottom; leftMargin: selFrame.inset; bottomMargin: selFrame.inset } width: 8; height: 2; color: rl.omni.seal }
                Rectangle { anchors { right: parent.right; bottom: parent.bottom; rightMargin: selFrame.inset; bottomMargin: selFrame.inset } width: 2; height: 8; color: rl.omni.seal }
                Rectangle { anchors { right: parent.right; bottom: parent.bottom; rightMargin: selFrame.inset; bottomMargin: selFrame.inset } width: 8; height: 2; color: rl.omni.seal }
            }

            // Icon slot: tinted .desktop image when one resolves,
            // nerd-font glyph fallback otherwise.
            Item {
                id: iconText
                anchors.left: parent.left
                anchors.leftMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                width: 24
                height: 24

                readonly property string iconUrl: rl.omni.resolveIconUrl(row.modelData.rawIcon)
                readonly property bool hasImageIcon: appImg.status === Image.Ready && iconUrl !== ""
                readonly property color tint: row.isSelected ? rl.omni.seal : rl.omni.inkDeep

                Text {
                    anchors.centerIn: parent
                    visible: !iconText.hasImageIcon
                    text: row.modelData.icon || "\u00b7"
                    color: iconText.tint
                    font.family: rl.omni.mono
                    font.pixelSize: 13 * rl.omni.fontScale
                }

                Image {
                    id: appImg
                    anchors.centerIn: parent
                    width: 20
                    height: 20
                    visible: false
                    source: iconText.iconUrl
                    sourceSize.width: 36
                    sourceSize.height: 36
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                    asynchronous: true
                    cache: true
                    layer.enabled: iconText.hasImageIcon
                }
                MultiEffect {
                    anchors.fill: appImg
                    visible: iconText.hasImageIcon
                    source: appImg
                    colorization: 1.0
                    colorizationColor: iconText.tint
                    Behavior on colorizationColor { ColorAnimation { duration: rl.omni.theme.focusMode ? 0 : 40 } }
                }
            }
            Text {
                id: titleText
                anchors.left: iconText.right
                anchors.leftMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                text: row.modelData.isCategory
                      ? row.modelData.title + "  \u203a"
                      : row.modelData.title
                color: row.isSelected ? rl.omni.ink : rl.omni.fg
                font.family: rl.omni.mono
                font.pixelSize: 13 * rl.omni.fontScale
                font.weight: row.isSelected ? Font.Medium : Font.Light
                font.letterSpacing: 1
                elide: Text.ElideRight
                width: catText.x - titleText.x - 10
            }
            Text {
                id: starText
                anchors.right: catText.left
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                visible: false
                text: "\uf4ce"
                color: rl.omni.seal
                font.family: rl.omni.mono
                font.pixelSize: 11 * rl.omni.fontScale
            }
            Text {
                id: catText
                visible: true
                anchors.right: parent.right
                anchors.rightMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                text: row.modelData.rawCategory
                      ? (row.modelData.category || "")
                      : (row.modelData.category || "").toUpperCase()
                color: row.isSelected ? rl.omni.seal : rl.omni.inkDeep
                opacity: row.isSelected ? 0.95 : 0.65
                font.family: rl.omni.mono
                font.pixelSize: 10 * rl.omni.fontScale
                font.letterSpacing: row.modelData.rawCategory ? 0 : 2
                elide: Text.ElideLeft
                horizontalAlignment: Text.AlignRight
                width: row.modelData.rawCategory
                       ? Math.min(implicitWidth, row.width * 0.45)
                       : implicitWidth
            }

            MouseArea {
                id: rowMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onPositionChanged: { if (!rl.omni._mouseBlocked) rl.omni.selectedIndex = row.index; }
                onClicked: rl.omni.activate(row.modelData)
            }
        }

        Text {
            anchors.centerIn: parent
            visible: resultList.count === 0
            text: {
                const o = rl.omni;
                if (o.emojiMode) return o.query.length === 0 ? "TYPE TO FIND EMOJI" : "NO EMOJI MATCH";
                return o.appsLoaded ? "NOTHING MATCHES" : "INDEXING APPS...";
            }
            color: rl.omni.inkDeep
            font.family: rl.omni.mono
            font.pixelSize: 11 * rl.omni.fontScale
            font.letterSpacing: 3
            opacity: 0.6
        }
    }
    // Fast wheel scrolling
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.NoButton
        onWheel: (event) => {
            const f = resultList;
            const max = Math.max(0, f.contentHeight - f.height);
            f.contentY = Math.max(0, Math.min(max,
                f.contentY - event.angleDelta.y * 1.2));
        }
    }
}