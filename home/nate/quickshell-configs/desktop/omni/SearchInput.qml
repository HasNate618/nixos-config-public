import QtQuick

// Search row: magnifier glyph, current query (or mode-specific
// placeholder), and a blinking caret. Hidden entirely in quickMode -
// the tile grid is its own input surface.
Item {
    id: input
    required property var omni

    visible: !omni.quickMode
    width: parent ? parent.width : 0
    height: visible ? 34 : 0

    Text {
        id: searchPrompt
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        text: input.omni.fileMode ? "󰉖"
              : input.omni.ghMode ? "󰊤"
              : input.omni.procMode ? "󰍛"
              : input.omni.themeMode ? "󰸌"
              : "󰍉"
        color: input.omni.seal
        font.family: input.omni.mono
        font.pixelSize: 16 * input.omni.fontScale
    }

    Text {
        id: queryText
        anchors.left: searchPrompt.right
        anchors.leftMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        text: {
            const o = input.omni;
            if (o.query.length > 0) return o.query;
            if (o.fileMode)  return "Type to search files in ~ …";
            if (o.ghMode)    return "Your PRs · type to search GitHub repos";
            if (o.procMode)  return "Type to filter processes by name, user, pid…";
            if (o.themeMode) return "Type to filter themes…";
            return "Search…";
        }
        color: input.omni.query.length === 0 ? input.omni.inkDeep : input.omni.ink
        opacity: input.omni.query.length === 0 ? 0.5 : 1.0
        font.family: input.omni.mono
        font.pixelSize: 12 * input.omni.fontScale
        font.letterSpacing: 1
    }

}
