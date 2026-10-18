import QtQuick
import Quickshell
import Quickshell.Io

// Focus-mode colour-scheme picker — opened from SUPER+CTRL+SPACE while
// focus mode is on (hypr-skwd-toggle routes to IPC target "schemes"
// instead of launching the skwd-wall picker). A two-column grid of scheme
// tiles; each tile previews the scheme's full 16-colour terminal palette
// as a 2x8 chip grid (regular0-7 on the first row, bright0-7 on the
// second). Click a tile or press Enter to apply; arrows / h-j-k-l move
// the keyboard cursor; Esc closes (handled by CardWindow).
CardWindow {
    id: picker
    required property var root

    theme: root
    revealed: root.focusSchemesVisible
    cardWidth: 560
    revealStyle: "scale"
    // Focus mode is a flat, motionless mode — the picker appears and
    // disappears on the same frame (no scale/fade).
    revealAnimated: false
    layerNamespace: "omarchy-focus-schemes"

    title: "FOCUS SCHEMES"
    subtitle: picker.active.length > 0
              ? picker.schemes.length + " AVAILABLE  ·  ACTIVE " + picker.active.toUpperCase()
              : ""

    onDismiss: picker.root.focusSchemesVisible = false

    property var schemes: []
    property string active: ""
    // Keyboard cursor. Independent of `active`: the active scheme keeps
    // its seal marker while the cursor can sit on any tile.
    property int cursor: 0
    // Hover is armed a beat AFTER the surface maps. Qt sends synthetic
    // hover events at the tile under a resting cursor while the scene is
    // settling (same class as the OmniMenu phantom selection), which
    // would otherwise steal the cursor from the active scheme on open.
    // Once armed, entering a tile sets the cursor; a pointer that never
    // moves does not re-fire onEntered, so the active tile keeps it.
    property bool hoverArmed: false
    property bool _cursorPrimed: false

    readonly property int gridColumns: 2
    readonly property real tileWidth: (grid.width - grid.spacing) / gridColumns

    // Absolute path: the quickshell service environment does not resolve
    // ~/.local/bin by bare name (cf. the omarchy-update-available warning).
    readonly property string focusCmd: "/home/nate/.local/bin/focus-scheme"

    function reload() {
        // Disarm hover across the model rebuild: reassigning `schemes`
        // re-creates the tiles, and Qt's frame-synchronous synthetic
        // hover would otherwise re-target the tile under a resting
        // pointer and yank the keyboard cursor after every apply.
        picker.hoverArmed = false;
        listProc.running = false;
        listProc.running = true;
    }

    function apply(slug) {
        applyProc.command = [picker.focusCmd, slug];
        applyProc.running = true;
    }

    function applyCurrent() {
        if (picker.cursor >= 0 && picker.cursor < picker.schemes.length)
            picker.apply(picker.schemes[picker.cursor].slug);
    }

    // Straight index arithmetic: left/right = column +/-1, up/down =
    // row +/-1 = index +/-2. Clamped, never wrapped.
    function moveCursor(delta) {
        const n = picker.schemes.length;
        if (n === 0) return;
        picker.cursor = Math.max(0, Math.min(n - 1, picker.cursor + delta));
    }

    // First load after reveal: park the cursor on the ACTIVE scheme.
    function primeCursor() {
        if (picker._cursorPrimed || picker.schemes.length === 0) return;
        let idx = 0;
        for (let i = 0; i < picker.schemes.length; i++) {
            if (picker.schemes[i].active) { idx = i; break; }
        }
        picker.cursor = idx;
        picker._cursorPrimed = true;
    }

    onRevealedChanged: {
        if (revealed) {
            picker._cursorPrimed = false;
            picker.reload();
        } else {
            picker.hoverArmed = false;
        }
    }

    // Restart the hover arm from the frame the surface actually maps, not
    // from the state flip — layer-surface creation can lag a little.
    onVisibleChanged: {
        if (visible) hoverArm.restart();
        else { picker.hoverArmed = false; hoverArm.stop(); }
    }

    Timer {
        id: hoverArm
        interval: 250
        repeat: false
        onTriggered: picker.hoverArmed = true
    }

    Process {
        id: listProc
        command: [picker.focusCmd, "--json"]
        stdout: StdioCollector {
            onStreamFinished: {
                let rows = [];
                try { rows = JSON.parse(this.text || "[]"); } catch (e) { rows = []; }
                picker.schemes = rows;
                let a = "";
                for (let i = 0; i < rows.length; i++) if (rows[i].active) a = rows[i].slug;
                picker.active = a;
                picker.primeCursor();
                // Re-arm only after the rebuilt grid has settled.
                if (picker.visible) hoverArm.restart();
            }
        }
    }

    Process {
        id: applyProc
        command: ["/bin/true"]
        onExited: picker.reload()
    }

    // CardWindow keeps the surface focused while revealed and routes all
    // non-Esc keys here (Esc is intercepted by CardWindow itself and
    // dismissed through onDismiss above).
    onKeyPressed: function(event) {
        const key = event.key;
        if (key === Qt.Key_Left || key === Qt.Key_H) {
            picker.moveCursor(-1);
        } else if (key === Qt.Key_Right || key === Qt.Key_L) {
            picker.moveCursor(1);
        } else if (key === Qt.Key_Up || key === Qt.Key_K) {
            picker.moveCursor(-picker.gridColumns);
        } else if (key === Qt.Key_Down || key === Qt.Key_J) {
            picker.moveCursor(picker.gridColumns);
        } else if (key === Qt.Key_Return || key === Qt.Key_Enter) {
            picker.applyCurrent();
        } else {
            return;
        }
        event.accepted = true;
    }

    Column {
        width: parent.width
        spacing: 8

        Text {
            visible: picker.schemes.length === 0
            width: parent.width
            text: "NO SCHEMES IN ~/.config/focus-mode/schemes"
            color: picker.root.inkDeep
            font.family: picker.root.mono
            font.pixelSize: 11
            font.letterSpacing: 2
        }

        Grid {
            id: grid
            visible: picker.schemes.length > 0
            width: parent.width
            columns: picker.gridColumns
            spacing: 7
            height: childrenRect.height

            Repeater {
                model: picker.schemes
                delegate: Rectangle {
                    id: tile
                    required property var modelData
                    required property int index

                    readonly property bool isActive: modelData.active === true
                    readonly property bool isCursor: picker.cursor === index

                    width: picker.tileWidth
                    height: 62
                    radius: 0
                    color: isCursor
                           ? Qt.rgba(picker.root.ink.r, picker.root.ink.g,
                                     picker.root.ink.b, 0.07)
                           : "transparent"
                    border.width: isCursor ? 1 : 0
                    border.color: Qt.rgba(picker.root.ink.r, picker.root.ink.g,
                                          picker.root.ink.b, 0.45)

                    // ACTIVE marker — seal bar down the left edge. Kept
                    // separate from the cursor wash/outline so both read
                    // at once when they land on the same tile.
                    Rectangle {
                        visible: tile.isActive
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: 3
                        color: picker.root.seal
                    }

                    Text {
                        id: name
                        anchors.left: parent.left
                        anchors.leftMargin: 11
                        anchors.right: parent.right
                        anchors.rightMargin: 9
                        anchors.top: parent.top
                        anchors.topMargin: 9
                        text: tile.modelData.slug.toUpperCase()
                        color: tile.isActive ? picker.root.seal : picker.root.ink
                        font.family: picker.root.mono
                        font.pixelSize: 12
                        font.letterSpacing: 2
                        font.weight: tile.isActive ? Font.Medium : Font.Normal
                        elide: Text.ElideRight
                    }

                    // Full 16-colour terminal palette, 2 rows x 8 chips:
                    // regular0-7 on top, bright0-7 below (same order as
                    // the scheme files / focus-scheme --json).
                    Grid {
                        id: swatches
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: 11
                        anchors.rightMargin: 11
                        anchors.top: name.bottom
                        anchors.topMargin: 6
                        columns: 8
                        columnSpacing: 2
                        rowSpacing: 2
                        height: 2 * chipHeight + rowSpacing

                        readonly property real chipWidth: (width - 7 * columnSpacing) / 8
                        readonly property int chipHeight: 11

                        Repeater {
                            model: tile.modelData.swatch
                            delegate: Rectangle {
                                required property string modelData
                                width: swatches.chipWidth
                                height: swatches.chipHeight
                                radius: 0
                                color: modelData
                            }
                        }
                    }

                    MouseArea {
                        id: tileHover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: {
                            if (picker.hoverArmed)
                                picker.cursor = tile.index;
                        }
                        onClicked: {
                            picker.cursor = tile.index;
                            picker.apply(tile.modelData.slug);
                        }
                    }
                }
            }
        }
    }
}
