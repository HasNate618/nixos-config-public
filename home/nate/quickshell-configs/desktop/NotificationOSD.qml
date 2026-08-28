import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Notifications

PanelWindow {
    id: window
    required property var root

    color: "transparent"
    anchors { top: true; right: true }
    implicitHeight: column.children.length > 0 ? 340 : 0
    implicitWidth: column.children.length > 0 ? 350 : 0
    exclusiveZone: 0

    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "omarchy-notification"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    visible: true

    NotificationServer {
        id: server
        keepOnReload: true
        bodySupported: true
        bodyMarkupSupported: true
        actionsSupported: true

        onNotification: (notification) => {
            console.log("NOTIFICATION RECEIVED:", notification.summary, notification.body);
            notification.tracked = true;
            window.spawnNotif(notification);
        }
    }

    function spawnNotif(notification) {
        if (column.children.length >= 5) {
            dismissCard(column.children[0]);
        }
        var card = notifCard.createObject(column, {
            "appName": notification.appName ?? "",
            "summary": notification.summary ?? "",
            "body": notification.body ?? ""
        });
        card.notifHeight = 56;
        Qt.callLater(function() { card.opacity = 1; });
        autoDismiss.createObject(card, { "delay": 4000 });
    }

    function dismissCard(card) {
        if (!card) return;
        card.opacity = 0;
        card.notifHeight = 0;
        collapse.createObject(card);
    }

    Component {
        id: notifCard
        Rectangle {
            property string appName: ""
            property string summary: ""
            property string body: ""
            property real notifHeight: 56

            width: column.width
            height: notifHeight
            opacity: 0
            color: Qt.rgba(window.root.paper.r * 0.5, window.root.paper.g * 0.5, window.root.paper.b * 0.5, 1.0)
            border.color: window.root.sep
            border.width: 1
            radius: window.root.cornerRadius
            clip: true

            Behavior on height {
                NumberAnimation { duration: 200; easing.type: Easing.OutQuad }
            }
            Behavior on opacity {
                NumberAnimation { duration: 200; easing.type: Easing.OutQuad }
            }

            Column {
                anchors.fill: parent
                anchors.margins: 12
                spacing: body.length > 0 ? 3 : 0

                Text {
                    text: summary
                    color: window.root.ink
                    font.family: window.root.mono
                    font.pixelSize: 14
                    font.weight: Font.Bold
                    elide: Text.ElideRight
                    width: parent.width
                }

                Text {
                    text: body
                    color: window.root.ink
                    font.family: window.root.mono
                    font.pixelSize: 12
                    elide: Text.ElideRight
                    width: parent.width
                    visible: text.length > 0
                    maximumLineCount: 1
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: window.dismissCard(parent)
            }
        }
    }

    Component {
        id: autoDismiss
        Timer {
            property int delay: 4000
            running: true
            repeat: false
            interval: delay
            onTriggered: window.dismissCard(parent)
        }
    }

    Component {
        id: collapse
        Timer {
            running: true
            repeat: false
            interval: 250
            onTriggered: parent.destroy()
        }
    }

    Column {
        id: column
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: 8
        anchors.leftMargin: 8
        anchors.rightMargin: 8
        spacing: 6
    }
}
