import QtQuick
import Quickshell

ShellRoot {
    id: root
    Theme { id: theme }

    Navbar {
        id: nav
        theme: theme
        onPaletteToggleRequested: omni.toggle()
        onPowerMenuRequested: { omni.categoryFilter = "System"; omni.open(); }
    }
    OmniMenu { id: omni; theme: theme }
    OSD { root: nav }
    NotificationOSD { root: nav }
    LaptopOmniHost { omni: omni }

    function assignBar(bar, index) {
        var s = Quickshell.screens;
        if (index < s.length) {
            bar.visible = true;
            bar.screen = s[index];
            bar.visible = true;
        } else {
            bar.visible = false;
        }
    }

    function assignAllBars() {
        root.assignBar(bar0, 0);
        root.assignBar(bar1, 1);
        root.assignBar(bar2, 2);
        root.assignBar(bar3, 3);
    }

    Bar { id: bar0; root: nav; visible: false; Component.onCompleted: root.assignBar(bar0, 0) }
    Bar { id: bar1; root: nav; visible: false; Component.onCompleted: root.assignBar(bar1, 1) }
    Bar { id: bar2; root: nav; visible: false; Component.onCompleted: root.assignBar(bar2, 2) }
    Bar { id: bar3; root: nav; visible: false; Component.onCompleted: root.assignBar(bar3, 3) }

    Connections {
        target: Quickshell
        function onScreensChanged() { root.assignAllBars() }
    }
}
