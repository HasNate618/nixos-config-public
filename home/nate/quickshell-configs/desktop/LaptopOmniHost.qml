import QtQuick
import Quickshell
import Quickshell.Wayland

// Laptop-only omni host (1.25× eDP). Separate overlay layer so the bar
// keeps its exclusive zone and input region; avoids expanding the bar surface.
PanelWindow {
    id: host
    required property var omni

    visible: host.omni.useBarEmbed
    color: Qt.rgba(host.omni.paper.r, host.omni.paper.g, host.omni.paper.b, 0.80)
    implicitWidth: host.omni.useBarEmbed ? (host.omni.previewActive ? 1100 : 720) : 0
    implicitHeight: host.omni.useBarEmbed ? Math.round(Math.min(host.screen ? host.screen.height * 0.72 : 1080, 900)) : 0
    width: implicitWidth
    height: implicitHeight
    exclusionMode: ExclusionMode.Ignore
    exclusiveZone: 0
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "omni-menu"
    WlrLayershell.keyboardFocus: host.omni.visible_ ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    screen: {
        var s = Quickshell.screens;
        var i = host.omni.activeScreenIndex;
        if (i >= 0 && i < s.length) return s[i];
        return s.length > 0 ? s[0] : null;
    }

    function focusOmniCard() {
        focusRoot.forceActiveFocus();
        const item = omniLoader.item;
        if (!item) return;
        const stack = [item];
        while (stack.length > 0) {
            const node = stack.pop();
            if (node.objectName === "omniCard" && node.forceActiveFocus) {
                node.forceActiveFocus();
                return;
            }
            const kids = node.children;
            if (kids) {
                for (let i = 0; i < kids.length; i++)
                    stack.push(kids[i]);
            }
        }
    }

    Timer {
        id: embedFocusTimer
        interval: 16
        repeat: false
        onTriggered: host.focusOmniCard()
    }

    FocusScope {
        id: focusRoot
        anchors.fill: parent
        focus: host.visible

        Item {
            anchors.fill: parent
            visible: host.omni.visible_
            opacity: host.omni.visible_ ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 50; easing.type: Easing.OutCubic } }

            Loader {
                id: omniLoader
                anchors.fill: parent
                active: true
                sourceComponent: host.omni.omniCardContent
                onLoaded: embedFocusTimer.restart()
            }
        }
    }

    Connections {
        target: host.omni
        function onVisibleChanged() {
            if (host.omni.visible_ && host.omni.useBarEmbed)
                embedFocusTimer.restart();
        }
        function onUseBarEmbedChanged() {
            if (host.omni.visible_ && host.omni.useBarEmbed)
                embedFocusTimer.restart();
        }
        function onPaletteFocusHook() {
            embedFocusTimer.restart();
        }
    }
}
