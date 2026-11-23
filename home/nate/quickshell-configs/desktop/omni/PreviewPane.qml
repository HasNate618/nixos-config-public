import QtQuick
import "../Data.js" as Data

// Right-side preview pane. Shown when clipboard mode is active.
// Surfaces a header (name + path), a hairline, and then clipboard
// content: image or text.
Item {
    id: pp

    required property var omni

    // Seal square mark — same separator language as the bar clock.
    Text {
        id: nameMark
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.topMargin: 3
        visible: pp.omni.clipMode
        text: "\u25aa"
        color: pp.omni.seal
        font.family: pp.omni.mono
        font.pixelSize: 10 * pp.omni.fontScale
    }

    Text {
        id: previewName
        anchors.top: parent.top
        anchors.left: nameMark.right
        anchors.leftMargin: 6
        anchors.right: parent.right
        text: {
            const o = pp.omni;
            const it = o.filteredItems[o.selectedIndex];
            if (o.clipMode) return it ? (it.clipPreview || 'clip #' + (it.clipId || '')) : "Clipboard";
            return "";
        }
        color: pp.omni.ink
        font.family: pp.omni.mono
        font.pixelSize: 13 * pp.omni.fontScale
        font.weight: Font.Medium
        font.letterSpacing: 1
        wrapMode: Text.WrapAnywhere
        maximumLineCount: 2
        elide: Text.ElideRight
    }
    Text {
        id: previewDir
        anchors.top: previewName.bottom
        anchors.topMargin: 2
        anchors.left: parent.left
        anchors.right: parent.right
        text: {
            const o = pp.omni;
            const it = o.filteredItems[o.selectedIndex];
            if (o.clipMode) return it ? ("clip #" + (it.clipId || "") + "  \u25aa  \u21b5 copies to clipboard") : "";
            return "";
        }
        color: pp.omni.inkDeep
        font.family: pp.omni.mono
        font.pixelSize: 10 * pp.omni.fontScale
        font.letterSpacing: 1
        elide: Text.ElideLeft
        opacity: 0.75
    }
    Rectangle {
        id: previewSep
        anchors.top: previewDir.bottom
        anchors.topMargin: 8
        anchors.left: parent.left
        anchors.right: parent.right
        height: 1
        color: pp.omni.sep
        visible: pp.omni.previewHasContent
    }

    Item {
        id: previewBody
        anchors.top: previewSep.bottom
        anchors.topMargin: 10
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        clip: true

        Text {
            anchors.centerIn: parent
            visible: !pp.omni.previewHasContent
            text: {
                const o = pp.omni;
                if (o.clipMode) return "SELECT A CLIPBOARD ENTRY";
                return "PREVIEW APPEARS HERE";
            }
            color: pp.omni.inkDeep
            font.family: pp.omni.mono
            font.pixelSize: 10 * pp.omni.fontScale
            font.letterSpacing: 3
            opacity: 0.5
        }

        // Clipboard preview: actual image for entries, text for text entries.
        Image {
            id: clipImg
            anchors.fill: parent
            anchors.margins: 4
            visible: pp.omni.clipMode && pp.omni.clipPreviewKind === "image"
            source: pp.omni.clipPreviewKind === "image" && pp.omni.clipPreviewPath !== ""
                    ? "file://" + pp.omni.clipPreviewPath
                    : ""
            sourceSize.width: 1024
            sourceSize.height: 1024
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            smooth: true
        }
        Text {
            anchors.fill: parent
            visible: pp.omni.clipMode && pp.omni.clipPreviewKind !== "image" && pp.omni.clipPreviewText !== ""
            text: pp.omni.clipPreviewText
            color: pp.omni.ink
            font.family: pp.omni.mono
            font.pixelSize: 10 * pp.omni.fontScale
            lineHeight: 1.4
            wrapMode: Text.Wrap
            textFormat: Text.PlainText
            elide: Text.ElideRight
            maximumLineCount: Math.max(1, Math.floor(previewBody.height / 13))
        }
    }
}