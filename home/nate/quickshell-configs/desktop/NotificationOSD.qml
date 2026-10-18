import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Notifications

// Notification toasts — motion stolen from Unit-3's player reveal:
//   1. the card enters as a solid slab sliding in from the right (OutExpo)
//   2. the curtain wipes away, revealing the text (summary slides in + fades)
//   3. on dismiss the curtain wipes shut first, then the slab slides back out
//      (InExpo) and the stack slot collapses.
// Cards are sized to their content (12px padding + summary + optional body).
// Stack height is published to the window only at discrete sync points
// (spawn / collapse finished) — resizing the layer surface every frame during
// the collapse made the upward shift look stuttery ("low hz").
PanelWindow {
    id: window
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
    implicitHeight: column.children.length > 0 ? _stackH : 0
    implicitWidth: column.children.length > 0 ? 350 : 0
    exclusiveZone: 0

    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "omarchy-notification"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    visible: true

    // Published stack height — updated only at sync points, not per animation frame.
    property real _stackH: 0

    function syncStackHeight() {
        var kids = column.children;
        var n = 0, sum = 0;
        for (var i = 0; i < kids.length; i++) {
            var h = kids[i].height;
            if (h <= 0.5) continue;          // collapsed / dying rows don't count
            n++; sum += h;
        }
        window._stackH = n > 0 ? sum + 6 * (n - 1) + 16 : 0;
    }

    NotificationServer {
        id: server
        keepOnReload: true
        bodySupported: true
        bodyMarkupSupported: true
        actionsSupported: true

        onNotification: (notification) => {
            notification.tracked = true;
            window.playNotifSound(notification);
            window.spawnNotif(notification);
        }
    }

    // Invisible probes — exact content sizing, no post-hoc corrections.
    Text { id: probeSummary; opacity: 0; text: "Ag"
           font.family: window.root.mono; font.pixelSize: 14; font.weight: Font.Bold }
    // Wrapped-body probe: same wrap settings as the real body Text, so its
    // implicitHeight IS the height the card's body will get.
    Text {
        id: bodyProbe
        opacity: 0
        width: window._textWidth
        wrapMode: Text.Wrap
        maximumLineCount: 3
        elide: Text.ElideRight
        font.family: window.root.mono
        font.pixelSize: 12
    }

    readonly property real _textWidth: 310   // 350 window − 16 margins − 24 card padding

    // ── Notification sound ──
    // Quickshell itself never plays sounds — this does. Ships with the config
    // (deployed to quickshell/desktop/sounds/). Apps can override
    // per-notification via the freedesktop "sound-file" hint, or silence with
    // "suppress-sound".
    readonly property string notifSound: Qt.resolvedUrl("sounds/nier_automata_mail.mp3").toString().replace("file://", "")

    function playNotifSound(notification) {
        var hintFile = "";
        try {
            var hints = notification.hints;
            if (hints) {
                if (hints["suppress-sound"]) return;
                if (hints["sound-file"]) hintFile = String(hints["sound-file"]);
            }
        } catch (e) { hintFile = ""; }
        var f = hintFile !== "" ? hintFile : window.notifSound;
        if (f !== "") Quickshell.execDetached(["timeout", "5", "pw-play", "--volume=1", f]);
    }

    // Exact card height — probed from real wraps, so the slab never resizes
    // mid-entrance (that read as notifications "growing vertically").
    function cardHeight(summary, body) {
        var hasS = summary.length > 0;
        var hasB = body.length > 0;
        var h = 24;
        if (hasS) h += Math.ceil(probeSummary.height);
        if (hasB) {
            bodyProbe.text = body;
            if (hasS) h += 3;
            h += Math.ceil(bodyProbe.implicitHeight);
        }
        return h;
    }

    function spawnNotif(notification) {
        if (column.children.length >= 5) {
            dismissCard(column.children[0]);
        }
        var summary = notification.summary ?? "";
        var body = notification.body ?? "";
        var card = notifCard.createObject(column, {
            "appName": notification.appName ?? "",
            "summary": summary,
            "body": body,
            "notifHeight": cardHeight(summary, body)
        });
        window.syncStackHeight();
        card.playEnter();
        autoDismiss.createObject(card, { "delay": 4500 });
    }

    function dismissCard(card) {
        if (!card || card.dismissing) return;
        card.dismissing = true;
        card.playExit();
    }

    Component {
        id: notifCard
        Item {
            id: cardItem
            property string appName: ""
            property string summary: ""
            property string body: ""
            property real notifHeight: 0
            property bool dismissing: false
            property int _kickTries: 0

            width: column.width
            height: notifHeight
            clip: true

            // First notification of a session: the surface resize may not have
            // propagated yet, so wait for a real width before animating.
            Timer {
                id: kickTimer
                interval: 16
                repeat: true
                onTriggered: {
                    if (cardItem.width > 0 || ++cardItem._kickTries > 30) {
                        stop();
                        enterAnim.start();
                    }
                }
            }

            function playEnter() {
                window.syncStackHeight();
                if (cardItem.width > 0) enterAnim.start();
                else kickTimer.start();
            }

            function playExit() {
                enterAnim.stop();
                exitAnim.start();
            }

            Item {
                id: wipeHost
                width: cardItem.width
                height: cardItem.height
                clip: true
                visible: false
                x: 0

                Rectangle {
                    id: cardBg
                    anchors.fill: parent
                    color: Qt.rgba(window.root.paper.r * 0.5, window.root.paper.g * 0.5, window.root.paper.b * 0.5,
                                   window.root.focusMode ? 1.0 : 0.98)
                    border.color: window.root.sep
                    border.width: 1
                    radius: window.root.cornerRadius
                    clip: true

                    // NieR top hairline — sepia gradient, fades at both ends.
                    Rectangle {
                        anchors { left: parent.left; right: parent.right; top: parent.top; topMargin: 1 }
                        height: 1
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0.0;  color: "transparent" }
                            GradientStop { position: 0.18; color: Qt.rgba(window.root.inkDeep.r, window.root.inkDeep.g, window.root.inkDeep.b, 0.10) }
                            GradientStop { position: 0.82; color: Qt.rgba(window.root.inkDeep.r, window.root.inkDeep.g, window.root.inkDeep.b, 0.10) }
                            GradientStop { position: 1.0;  color: "transparent" }
                        }
                    }

                    Column {
                        id: contentCol
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 3

                        Text {
                            id: summaryText
                            text: cardItem.summary
                            visible: text.length > 0
                            color: window.root.ink
                            font.family: window.root.mono
                            font.pixelSize: 14
                            font.weight: Font.Bold
                            font.letterSpacing: 0.6
                            elide: Text.ElideRight
                            width: parent.width
                        }

                        Text {
                            id: bodyText
                            text: cardItem.body
                            visible: text.length > 0
                            color: window.root.ink
                            font.family: window.root.mono
                            font.pixelSize: 12
                            width: parent.width
                            wrapMode: Text.Wrap
                            maximumLineCount: 3
                            elide: Text.ElideRight
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: window.dismissCard(cardItem)
                    }
                }

                Rectangle {
                    id: curtain
                    z: 10
                    x: 0
                    width: 0
                    color: window.root.inkDeep
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom

                    // Scanline texture on the slab.
                    Canvas {
                        anchors.fill: parent
                        enabled: false
                        onPaint: {
                            var ctx = getContext("2d");
                            ctx.clearRect(0, 0, width, height);
                            ctx.fillStyle = "rgba(0,0,0,0.04)";
                            for (var y = 1; y < height; y += 4)
                                ctx.fillRect(0, y, width, 1);
                        }
                        Component.onCompleted: requestPaint()
                        onWidthChanged: requestPaint()
                        onHeightChanged: requestPaint()
                    }
                }
            }

            // ── Enter: slab slides in, curtain wipes away, text settles ──
            SequentialAnimation {
                id: enterAnim
                onStarted: {
                    wipeHost.visible = true;
                    wipeHost.x = wipeHost.width + 12;
                    curtain.x = 0;
                    curtain.width = wipeHost.width;
                    summaryText.opacity = 0;
                    bodyText.opacity = 0;
                    summaryText.x = -12;
                }
                NumberAnimation {
                    target: wipeHost; property: "x"
                    from: wipeHost.width + 12; to: 0
                    duration: window.root.focusMode ? 0 : 320; easing.type: Easing.OutExpo
                }
                NumberAnimation {
                    target: curtain; property: "width"
                    from: wipeHost.width; to: 0
                    duration: window.root.focusMode ? 0 : 240; easing.type: Easing.OutExpo
                }
                ParallelAnimation {
                    NumberAnimation {
                        target: summaryText; property: "x"
                        from: -12; to: 0
                        duration: window.root.focusMode ? 0 : 260; easing.type: Easing.OutCubic
                    }
                    NumberAnimation {
                        target: summaryText; property: "opacity"
                        from: 0; to: 1
                        duration: window.root.focusMode ? 0 : 200
                    }
                    NumberAnimation {
                        target: bodyText; property: "opacity"
                        from: 0; to: 1
                        duration: window.root.focusMode ? 0 : 280; easing.type: Easing.OutQuad
                    }
                }
            }

            // ── Exit: curtain wipes shut while the slab slides out (one motion),
            //    then the stack slot collapses ──
            SequentialAnimation {
                id: exitAnim
                ParallelAnimation {
                    NumberAnimation {
                        target: curtain; property: "width"
                        to: wipeHost.width
                        duration: window.root.focusMode ? 0 : 180; easing.type: Easing.InOutQuad
                    }
                    NumberAnimation {
                        target: wipeHost; property: "x"
                        to: wipeHost.width + 12
                        duration: window.root.focusMode ? 0 : 300; easing.type: Easing.InExpo
                    }
                }
                NumberAnimation {
                    target: cardItem; property: "notifHeight"
                    to: 0
                    duration: window.root.focusMode ? 0 : 180; easing.type: Easing.OutQuad
                }
                onFinished: {
                    cardItem.destroy();
                    window.syncStackHeight();
                }
            }
        }
    }

    Component {
        id: autoDismiss
        Timer {
            property int delay: 4500
            running: true
            repeat: false
            interval: delay
            onTriggered: window.dismissCard(parent)
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
