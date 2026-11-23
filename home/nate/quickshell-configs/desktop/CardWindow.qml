import QtQuick
import Quickshell
import Quickshell.Wayland

// Tier-B popup chrome. Full-screen overlay PanelWindow + centered card with
// the OmniMenu visual language: mono-caps header (title + status subtitle),
// scale-from-center reveal, click-outside dismiss, Esc dismiss, optional
// footer hint line. Widgets put their own body inside as default children
// and listen to keyPressed() for widget-specific keyboard nav.
//
// Usage:
//   CardWindow {
//       theme: root
//       revealed: root.aetherVisible
//       onDismiss: root.aetherVisible = false
//       onKeyPressed: function(event) { ... widget keys ... }
//       title: "AETHER"
//       subtitle: "12 BLUEPRINTS"
//       footer: "↵ APPLY  ·  ESC CLOSE"
//       Item { ... body ... }
//   }
PanelWindow {
    id: card

    required property var theme

    property bool revealed: false
    // Reveal motion: "scale" (default — scale from the anchor) or "nier"
    // (notification-style slab slide from the right + curtain wipe).
    property string revealStyle: "scale"
    // When false, the "scale" reveal is instant: the _reveal Behavior is
    // disabled so the card opens/closes on one frame. Used by surfaces in
    // focus mode, which is a flat, motionless mode. No effect on "nier".
    property bool revealAnimated: true
    property real _slideX: 0
    property bool _nierShown: false
    property real cardWidth: 460
    // -1 -> auto-size from content implicit height; otherwise fixed.
    property real cardHeight: -1
    property string title: ""
    property string subtitle: ""
    property string footer: ""
    property string layerNamespace: "omarchy-card"
    // Right-side header content (chevrons, refresh buttons, etc.). The
    // inline Component is instantiated as a Loader child; lexical scope
    // means ids declared in the popup file are reachable from inside.
    property Component headerRight: null

    // Anchored placement. anchorEdge "" (default) centres the card; "top"/
    // "bottom"/"left"/"right" hugs the bar's inner edge and centres on
    // (anchorBarX, anchorBarY) along the parallel axis, clamped on-screen.
    // The Scale origin tracks the trigger so a clamped card still feels
    // rooted in the icon the user clicked.
    property string anchorEdge: ""
    property real   anchorBarX: 0
    property real   anchorBarY: 0
    property real   anchorGap: 8
    readonly property bool _anchored: anchorEdge === "top"  || anchorEdge === "bottom"
                                   || anchorEdge === "left" || anchorEdge === "right"

    signal dismiss()
    signal keyPressed(var event)

    default property alias bodyData: bodyContainer.data

    visible: revealed || _nierShown || _reveal > 0.001
    color: "transparent"
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: layerNamespace
    WlrLayershell.keyboardFocus: revealed ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // Same "hidden create" screen assignment as Bar.qml:
    // reveal makes the window visible on the default screen, then
    // onRevealedChanged switches to the triggering bar's screen.
    onRevealedChanged: {
        if (revealed && theme && theme.popupScreen) {
            // visible=true creates native window, screen= moves it,
            // visible=true confirms — same pattern as Bar init.
            card.screen = theme.popupScreen;
        }
        if (card.revealStyle !== "nier") return;
        if (revealed) {
            card._nierShown = true;
            nierExit.stop();
            nierEnter.start();
        } else if (card._nierShown) {
            nierEnter.stop();
            nierExit.start();
        }
    }

    // Bind to the triggering bar's screen so the popup appears on the
    // correct monitor.  Set by Bar.qml via root.popupScreen before opening.

    property real _reveal: revealed ? 1 : 0
    Behavior on _reveal {
        enabled: card.revealAnimated
        NumberAnimation {
            duration: card.revealed ? 220 : 140
            easing.type: card.revealed ? Easing.OutCubic : Easing.InCubic
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: card.dismiss()
    }

    Rectangle {
        id: surface
        width: card.cardWidth
        height: card.cardHeight > 0 ? card.cardHeight : (bodyCol.implicitHeight + 34)
        color: card.theme.focusMode
               ? card.theme.paper
               : Qt.rgba(card.theme.paper.r * 0.5, card.theme.paper.g * 0.5, card.theme.paper.b * 0.5, 0.98)
        border.color: card.theme.sep
        border.width: 1
        radius: card.theme.cornerRadius

        x: {
            if (!card._anchored) return (parent.width - width) / 2;
            if (card.anchorEdge === "left")  return card.theme.barHeight + card.anchorGap;
            if (card.anchorEdge === "right") return parent.width - card.theme.barHeight - width - card.anchorGap;
            return Math.max(card.anchorGap,
                            Math.min(parent.width - width - card.anchorGap,
                                     card.anchorBarX - width / 2));
        }
        y: {
            if (!card._anchored) return (parent.height - height) / 2;
            if (card.anchorEdge === "top")    return card.theme.barHeight + card.anchorGap;
            if (card.anchorEdge === "bottom") return parent.height - card.theme.barHeight - height - card.anchorGap;
            return Math.max(card.anchorGap,
                            Math.min(parent.height - height - card.anchorGap,
                                     card.anchorBarY - height / 2));
        }

        transform: [
            Translate { x: card._slideX },
            Scale {
            origin.x: {
                if (!card._anchored) return surface.width / 2;
                if (card.anchorEdge === "left")  return 0;
                if (card.anchorEdge === "right") return surface.width;
                return Math.max(0, Math.min(surface.width, card.anchorBarX - surface.x));
            }
            origin.y: {
                if (!card._anchored) return surface.height / 2;
                if (card.anchorEdge === "top")    return 0;
                if (card.anchorEdge === "bottom") return surface.height;
                return Math.max(0, Math.min(surface.height, card.anchorBarY - surface.y));
            }
            xScale: card.revealStyle === "nier" ? 1 : card._reveal
            yScale: card.revealStyle === "nier" ? 1 : card._reveal
            }
        ]

        // Swallow clicks so the dismiss MouseArea doesn't fire on body taps.
        MouseArea { anchors.fill: parent }

        focus: card.revealed
        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) {
                card.dismiss();
                event.accepted = true;
                return;
            }
            card.keyPressed(event);
        }

        Column {
            id: bodyCol
            anchors.fill: parent
            anchors.margins: 17
            spacing: 12

            Item {
                width: parent.width
                height: 43
                visible: card.title.length > 0 || card.subtitle.length > 0 || card.headerRight !== null

                Column {
                    anchors.left: parent.left
                    anchors.right: headerRightLoader.left
                    anchors.rightMargin: card.headerRight ? 12 : 0
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    Text {
                        visible: card.title.length > 0
                        text: card.title
                        color: card.theme.ink
                        font.family: card.theme.mono
                        font.pixelSize: 19
                        font.letterSpacing: 4
                        font.weight: Font.Medium
                    }
                    Text {
                        visible: card.subtitle.length > 0
                        width: parent.width
                        elide: Text.ElideRight
                        text: card.subtitle
                        color: card.theme.inkDeep
                        font.family: card.theme.mono
                        font.pixelSize: 11
                        font.letterSpacing: 2
                    }
                }

                Loader {
                    id: headerRightLoader
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    sourceComponent: card.headerRight
                }
            }

            Rectangle {
                visible: card.title.length > 0 || card.subtitle.length > 0
                width: parent.width
                height: 1
                color: card.theme.sep
            }

            Item {
                id: bodyContainer
                width: parent.width
                height: childrenRect.height
            }

            Rectangle {
                visible: card.footer.length > 0
                width: parent.width
                height: 1
                color: card.theme.sep
                opacity: 0.5
            }

            Text {
                visible: card.footer.length > 0
                width: parent.width
                text: card.footer
                color: card.theme.inkDeep
                font.family: card.theme.mono
                font.pixelSize: 10
                font.letterSpacing: 2
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                opacity: 0.7
            }
        }

        // NieR reveal curtain — covers the card while it slides/wipes shut.
        Rectangle {
            id: curtain
            visible: card.revealStyle === "nier"
            anchors { top: parent.top; bottom: parent.bottom; left: parent.left }
            width: 0
            color: card.theme.inkDeep
            z: 99

            // Scanline texture on the slab — same as the notification curtain.
            // Plain rectangles (no Canvas): a canvas buffer can go stale
            // between opens and showed far stronger lines on re-open.
            Item {
                anchors.fill: parent
                enabled: false
                Repeater {
                    model: Math.max(0, Math.ceil(parent.height / 4))
                    Rectangle {
                        x: 0; y: index * 4 + 1
                        width: parent.width; height: 1
                        color: Qt.rgba(0, 0, 0, 0.02)
                    }
                }
            }
        }
    }

    // ── NieR reveal choreography (revealStyle === "nier") ──
    SequentialAnimation {
        id: nierEnter
        onStarted: {
            card._slideX = surface.width + 12;
            curtain.width = surface.width;
            bodyCol.opacity = 0;
        }
        NumberAnimation {
            target: card; property: "_slideX"
            from: surface.width + 12; to: 0
            duration: card.theme.focusMode ? 0 : 320; easing.type: Easing.OutExpo
        }
        NumberAnimation {
            target: curtain; property: "width"
            from: surface.width; to: 0
            duration: card.theme.focusMode ? 0 : 240; easing.type: Easing.OutExpo
        }
        NumberAnimation {
            target: bodyCol; property: "opacity"
            from: 0; to: 1
            duration: card.theme.focusMode ? 0 : 140; easing.type: Easing.OutQuad
        }
    }

    SequentialAnimation {
        id: nierExit
        ParallelAnimation {
            NumberAnimation {
                target: curtain; property: "width"
                to: surface.width
                duration: card.theme.focusMode ? 0 : 180; easing.type: Easing.InOutQuad
            }
            NumberAnimation {
                target: card; property: "_slideX"
                to: surface.width + 12
                duration: card.theme.focusMode ? 0 : 300; easing.type: Easing.InExpo
            }
        }
        onFinished: {
            card._nierShown = false;
            card._slideX = 0;
            curtain.width = 0;
        }
    }
}
