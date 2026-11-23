import QtQuick

// Footer line: exec of the current selection. Keeps the bottom of
// the card alive and doubles as a "what will Enter do" check before
// firing. Truncates only when the command exceeds the box width.
Item {
    id: footer
    required property var omni

    width: parent ? parent.width : 0
    height: 22

    Text {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        elide: Text.ElideRight
        text: {
            const it = footer.omni.filteredItems[footer.omni.selectedIndex];
            if (!it) return "";
            if (it.isCategory)  return "→ open " + it.target.toLowerCase();
            if (it.isProcess)   return "↵ kill " + (it.pid || "");
            if (it.isTheme)     return "↵ omarchy-theme-set " + (it.themeName || "");
            if (!it.exec)       return "";
            return "$ " + it.exec;
        }
        color: footer.omni.inkDeep
        font.family: footer.omni.mono
        font.pixelSize: 10 * footer.omni.fontScale
        font.letterSpacing: 1
        opacity: 0.65
    }

}
