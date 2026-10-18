import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: bar
    required property var root
    color: "transparent"
    // Anchors track barEdge — three sides anchored, the side opposite
    // the bar's edge is left free for the bar's thickness to extend.
    anchors {
        top:    bar.root.barEdge !== "bottom"
        bottom: bar.root.barEdge !== "top"
        left:   bar.root.barEdge !== "right"
        right:  bar.root.barEdge !== "left"
    }
    // Cloud mode: horizontal+round only. Vertical bars keep the original
    // slab geometry to avoid breaking the proven layout.
    readonly property int cloudPad: 2
    readonly property int cloudAir: 5
    readonly property int cloudInnerAir: 2
    readonly property bool cloudMode: bar.root.round && bar.root.isHorizontal
    readonly property int extraThickness: cloudMode ? 2 * cloudPad + cloudAir + cloudInnerAir : 0
    // innerSign tells which side gets the extra outer air (away from screen).
    readonly property int innerSign: bar.root.barEdge === "top" ? 1 : (bar.root.barEdge === "bottom" ? -1 : 0)

    implicitHeight: bar.root.isHorizontal ? bar.root.barHeight + extraThickness : 0
    implicitWidth:  bar.root.isHorizontal ? 0 : bar.root.barHeight
    exclusiveZone:  bar.root.isHorizontal ? bar.root.barHeight + extraThickness : bar.root.barHeight

    function updateBatPos() {
        if (typeof batRow === "undefined" || !batRow) return;
        var p = batRow.mapToItem(null, batRow.width/2, batRow.height/2);
        root.batteryPopX = p.x;
        root.batteryPopY = p.y;
    }

    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "omarchy-menu"

    // In cloud mode the slab bg is replaced by a single rounded backdrop
    // sized to match the inner bar (barHeight tall, with cloudAir margins
    // on each side along the bar axis, sliding toward the inner edge so
    // outer-side air sits between cloud and screen edge).
    Rectangle {
        visible: bar.cloudMode
        x: bar.cloudAir
        y: bar.innerSign === 1 ? bar.cloudAir : bar.cloudInnerAir
        width: parent.width - 2 * bar.cloudAir
        height: bar.root.barHeight + 2 * bar.cloudPad
        radius: bar.root.cornerRadius
        color: bar.root.bg
        opacity: 1.0
        Behavior on opacity {
            NumberAnimation {
                duration: bar.root.focusMode ? 0 : 60
                easing.type: Easing.OutQuad
            }
        }
        z: 0
    }

    // Container for clock + modules + hairlines. In cloud mode the bg
    // becomes transparent so the cloud rectangle above shows through;
    // in slab mode this acts as the bar background.
    Rectangle {
        anchors.fill: parent
        color: bar.cloudMode ? "transparent" : bar.root.bg
        opacity: bar.cloudMode ? 1.0 : 1.0
        Behavior on opacity {
            NumberAnimation {
                duration: bar.root.focusMode ? 0 : 60
                easing.type: Easing.OutQuad
            }
        }

        // 尼 frame line — sepia hairline along the bar's inner edge.
        Rectangle {
            visible: !bar.cloudMode && bar.root.isHorizontal && bar.root.barEdge === "top" && !bar.root.focusMode
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: 1
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0;  color: "transparent" }
                GradientStop { position: 0.12; color: Qt.rgba(bar.root.inkDeep.r, bar.root.inkDeep.g, bar.root.inkDeep.b, 0.10) }
                GradientStop { position: 0.88; color: Qt.rgba(bar.root.inkDeep.r, bar.root.inkDeep.g, bar.root.inkDeep.b, 0.10) }
                GradientStop { position: 1.0;  color: "transparent" }
            }
        }

        // 静 (stillness) mark, parked in the bar's trailing corner.
        Text {
            visible: !bar.cloudMode
            anchors.right:  bar.root.isHorizontal ? parent.right  : undefined
            anchors.bottom: bar.root.isHorizontal ? undefined     : parent.bottom
            anchors.rightMargin:  bar.root.isHorizontal ? 8 : 0
            anchors.bottomMargin: bar.root.isHorizontal ? 0 : 8
            anchors.verticalCenter:   bar.root.isHorizontal ? parent.verticalCenter   : undefined
            anchors.horizontalCenter: bar.root.isHorizontal ? undefined : parent.horizontalCenter
            text: "静"
            color: Qt.rgba(bar.root.ink.r, bar.root.ink.g, bar.root.ink.b, 0.07)
            font.family: bar.root.serif
            font.pixelSize: bar.root.barHeight + 6
            font.weight: Font.Light
            z: 0
        }

        // Inner-edge hairline (facing the rest of the screen). Hidden in
        // cloud mode — the rounded backdrop replaces it visually.
        Rectangle {
            visible: !bar.cloudMode && bar.root.isHorizontal && !bar.root.focusMode
            anchors.left:   parent.left
            anchors.right:  parent.right
            anchors.top:    bar.root.barEdge === "bottom" ? parent.top    : undefined
            anchors.bottom: bar.root.barEdge === "top"    ? parent.bottom : undefined
            height: 1
            color: bar.root.sep
        }
        Rectangle {
            visible: !bar.cloudMode && !bar.root.isHorizontal && !bar.root.focusMode
            anchors.top:    parent.top
            anchors.bottom: parent.bottom
            anchors.right:  bar.root.barEdge === "left"  ? parent.right : undefined
            anchors.left:   bar.root.barEdge === "right" ? parent.left  : undefined
            width: 1
            color: bar.root.sep
        }

        // Centre cluster: clock only, clickable. Horizontal bars show
        // "HH:MM" on one line; vertical bars stack HH and MM.
        Item {
            id: clockItem
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter:   parent.verticalCenter
            z: 10
            Component.onCompleted: bar.root.calendarAnchors[bar.screen.name] = clockItem

            implicitWidth:  bar.root.isHorizontal
                            ? clockRow.implicitWidth + 14
                            : Math.max(clockHH.implicitWidth, clockMM.implicitWidth) + 8
            implicitHeight: bar.root.isHorizontal
                            ? clockRow.implicitHeight + 8
                            : (clockHH.implicitHeight + clockMM.implicitHeight + 6)

            Bloom { id: clockBloom; root: bar.root }

            // Single tracked mono line (same as the rest of the bar) with one
            // NieR accent: dim date, tiny seal square, bright time.
            RowLayout {
                id: clockRow
                visible: bar.root.isHorizontal
                anchors.centerIn: parent
                anchors.verticalCenterOffset: -1
                spacing: 0
                Text {
                    text: "「"
                    color: clockMouse.containsMouse ? bar.root.seal : bar.root.ink
                    font.family: bar.root.serifCJK
                    font.pixelSize: 18
                    font.weight: Font.Normal
                    Layout.rightMargin: 7
                }
                Text {
                    id: clockDate
                    text: bar.root.dd + " " + bar.root.dow
                    color: clockMouse.containsMouse ? bar.root.seal : bar.root.ink
                    font.family: bar.root.mono
                    font.pixelSize: 14
                    font.letterSpacing: 2
                    font.weight: Font.Light
                    Layout.rightMargin: 5
                    Behavior on color { ColorAnimation { duration: bar.root.focusMode ? 0 : 180 } }
                }
                Rectangle {
                    Layout.alignment: Qt.AlignVCenter
                    width: 3
                    height: 3
                    color: bar.root.seal
                    opacity: 0.55
                    Layout.rightMargin: 8
                }
                Text {
                    id: clockTimeLine
                    text: bar.root.hh + ":" + bar.root.mm + " " + bar.root.ap
                    color: clockMouse.containsMouse ? bar.root.seal : bar.root.ink
                    font.family: bar.root.mono
                    font.pixelSize: 14
                    font.letterSpacing: 2
                    font.weight: Font.Light
                    Layout.rightMargin: 4
                    Behavior on color { ColorAnimation { duration: bar.root.focusMode ? 0 : 180 } }
                }
                Text {
                    text: "」"
                    color: clockMouse.containsMouse ? bar.root.seal : bar.root.ink
                    font.family: bar.root.serifCJK
                    font.pixelSize: 18
                    font.weight: Font.Normal
                }
            }
            Text {
                id: clockHH
                visible: !bar.root.isHorizontal
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.verticalCenter
                anchors.bottomMargin: 1
                text: "[" + bar.root.hh
                color: clockMouse.containsMouse ? bar.root.seal : bar.root.ink
                font.family: bar.root.mono
                font.pixelSize: 11
                font.weight: Font.Light
                Behavior on color { ColorAnimation { duration: bar.root.focusMode ? 0 : 180 } }
            }
            Text {
                id: clockMM
                visible: !bar.root.isHorizontal
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.verticalCenter
                anchors.topMargin: 1
                text: bar.root.mm + "]"
                color: clockMouse.containsMouse ? bar.root.seal : bar.root.ink
                font.family: bar.root.mono
                font.pixelSize: 11
                font.weight: Font.Light
                Behavior on color { ColorAnimation { duration: bar.root.focusMode ? 0 : 180 } }
            }

            Timer {
                id: clockTipDelay
                interval: 320
                onTriggered: {
                    const p = clockItem.mapToItem(null, clockItem.width / 2, clockItem.height / 2);
                    bar.root.showTooltip("Calendar", p.x, p.y);
                }
            }

            MouseArea {
                id: clockMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: { clockBloom.fire(mouseX, mouseY); clockTipDelay.restart(); }
                onExited:  { clockTipDelay.stop(); bar.root.hideTooltip("Calendar"); }
                onClicked: {
                    clockTipDelay.stop();
                    bar.root.hideTooltip("Calendar");
                    if (bar.root.calendarVisible) bar.root.calendarVisible = false;
                    else {
                        var p = clockItem.mapToItem(null, clockItem.width / 2, clockItem.height / 2);
                        bar.root.popupAnchorX = p.x;
                        bar.root.popupAnchorY = p.y;
                        bar.root.popupScreen = bar.screen;
                        bar.root.openCalendar();
                    }
                }
            }
        }

        GridLayout {
            anchors.fill: parent
            anchors.leftMargin:   bar.root.isHorizontal ? (bar.cloudMode ? bar.cloudAir + bar.cloudPad : 10) : 0
            anchors.rightMargin:  bar.root.isHorizontal
                                  ? (bar.cloudMode ? bar.cloudAir + bar.cloudPad : 10)
                                  : 0
            anchors.topMargin:    bar.root.isHorizontal
                                  ? (bar.cloudMode
                                     ? (bar.root.barEdge === "top" ? bar.cloudAir + bar.cloudPad : bar.cloudInnerAir + bar.cloudPad)
                                     : 0)
                                  : 10
            anchors.bottomMargin: bar.root.isHorizontal
                                  ? (bar.cloudMode
                                     ? (bar.root.barEdge === "top" ? bar.cloudInnerAir + bar.cloudPad : bar.cloudAir + bar.cloudPad)
                                     : 0)
                                  : 10
            flow: bar.root.isHorizontal ? GridLayout.LeftToRight : GridLayout.TopToBottom
            rowSpacing: 4
            columnSpacing: 4
            columns: bar.root.isHorizontal ? -1 : 1
            rows:    bar.root.isHorizontal ? 1  : -1

            Module {
                root: bar.root
                glyph: bar.root.icoNixos
                tooltip: "Menu"
                color: bar.root.seal
                fontFamily: bar.root.mono
                fontSize: 18
                onActivated: bar.root.paletteToggleRequested()
                onRightActivated: bar.root.run("xdg-terminal-exec")
            }

            Separator { root: bar.root }

            Repeater {
                model: 10
                delegate: Workspace {
                    required property int index
                    root: bar.root
                    wsId: index + 1
                    label: bar.root.indexKanji(index + 1)
                    active: bar.root.activeWs === (index + 1)
                    present: bar.root.existingWs.indexOf(index + 1) !== -1
                    onActivated: bar.root.run("hypr-ws-focus " + (index + 1))
                }
            }

            // Now-playing pill, sits between workspaces and the spacer.
            Item {
                id: musicItem
                visible: bar.root.isHorizontal && bar.root.musicTitle.length > 0
                Layout.alignment: Qt.AlignVCenter
                Layout.leftMargin: 12
                Layout.preferredWidth: musicPill.width + 12
                Layout.preferredHeight: bar.root.barHeight

                readonly property string tipText: bar.root.musicArtist.length > 0
                                                  ? bar.root.musicTitle + " - " + bar.root.musicArtist
                                                  : bar.root.musicTitle

                Item {
                    id: musicPill
                    anchors.centerIn: parent
                    width: musicRow.width + 20
                    height: 16

                    property color bracketColor: musicMouse.containsMouse
                        ? Qt.rgba(bar.root.inkDeep.r, bar.root.inkDeep.g, bar.root.inkDeep.b, 0.85)
                        : Qt.rgba(bar.root.inkDeep.r, bar.root.inkDeep.g, bar.root.inkDeep.b, 0.45)
                    Behavior on bracketColor { ColorAnimation { duration: bar.root.focusMode ? 0 : 160 } }
                    // 「 corner mark (top-left): vertical + top stroke only
                    Item {
                        anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                        width: 5; height: 14
                        Rectangle { anchors { left: parent.left; top: parent.top; bottom: parent.bottom } width: 1; color: musicPill.bracketColor }
                        Rectangle { anchors { left: parent.left; top: parent.top } width: 5; height: 1; color: musicPill.bracketColor }
                    }
                    // 」 corner mark (bottom-right): vertical + bottom stroke only
                    Item {
                        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                        width: 5; height: 14
                        Rectangle { anchors { right: parent.right; top: parent.top; bottom: parent.bottom } width: 1; color: musicPill.bracketColor }
                        Rectangle { anchors { right: parent.right; bottom: parent.bottom } width: 5; height: 1; color: musicPill.bracketColor }
                    }
                    Row {
                        id: musicRow
                        anchors.centerIn: parent
                        spacing: 5
                        Text {
                            id: musicIcon
                            anchors.verticalCenter: parent.verticalCenter
                            text: bar.root.musicPlaying
                                  ? String.fromCodePoint(0xf04c)   // pause (playing → click pauses)
                                  : String.fromCodePoint(0xf04b)   // play
                            color: bar.root.inkDeep
                            font.family: bar.root.mono
                            font.pixelSize: 9
                        }
                        Text {
                            id: musicLabel
                            anchors.verticalCenter: parent.verticalCenter
                            // Cap the visible label at 40 chars; the full
                            // title + artist stay available in the hover
                            // tooltip (musicItem.tipText).
                            text: bar.root.musicTitle.length > 40
                                  ? bar.root.musicTitle.slice(0, 40) + "\u2026"
                                  : bar.root.musicTitle
                            color: bar.root.inkDeep
                            font.family: bar.root.mono
                            font.pixelSize: 10
                            font.weight: Font.Medium
                            elide: Text.ElideRight
                        }
                    }
                }

                Timer {
                    id: musicTipDelay
                    interval: 320
                    onTriggered: {
                        const p = musicItem.mapToItem(null, musicItem.width / 2, musicItem.height / 2);
                        bar.root.showTooltip(musicItem.tipText, p.x, p.y);
                    }
                }

                MouseArea {
                    id: musicMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                    cursorShape: Qt.PointingHandCursor
                    onEntered: musicTipDelay.restart()
                    onExited:  { musicTipDelay.stop(); bar.root.hideTooltip(musicItem.tipText); }
                    onClicked: (e) => {
                        musicTipDelay.stop();
                        bar.root.hideTooltip(musicItem.tipText);
                        if (e.button === Qt.RightButton)       bar.root.musicNext();
                        else if (e.button === Qt.MiddleButton) bar.root.musicPrev();
                        else                                    bar.root.musicToggle();
                    }
                }
            }

            // Absorbs leftover width so left items stay tightly packed
            // (cluster is right-anchored separately).
            Item {
                Layout.fillWidth:  bar.root.isHorizontal
                Layout.fillHeight: !bar.root.isHorizontal
            }
        }
            // ── Right cluster ──
            // Each stat sits in a StatFrame (two opposing L-corners, Tsugumori
            // bar motif) — the frames double as the separators, so spacing
            // between widgets is uniform by construction.
            RowLayout {
                id: rightCluster
                anchors.right: parent.right
                anchors.rightMargin: bar.cloudMode ? bar.cloudAir + bar.cloudPad : 10
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8

                // Weather
                StatFrame {
                    id: weatherItem
                    root: bar.root
                    Layout.alignment: Qt.AlignVCenter
                    Component.onCompleted: bar.root.weatherAnchors[bar.screen.name] = weatherItem
                    Text { text: bar.root.weatherUnavailable ? "󰼷" : (bar.root.weatherLoaded ? bar.root.weatherIcon : "·"); color: bar.root.weatherUnavailable ? bar.root.inkDeep : bar.root.tintCorne; font.family: bar.root.mono; font.pixelSize: 13 }
                    Text { text: bar.root.weatherLoaded ? Math.round(bar.root.weatherTempC) + "°" : ""; color: bar.root.weatherUnavailable ? bar.root.inkDeep : bar.root.ink; font.family: bar.root.mono; font.pixelSize: 13 }
                    MouseArea {
                        anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onEntered: { const p = parent.mapToItem(null, parent.width/2, parent.height/2); let tip = bar.root.weatherUnavailable ? "Weather offline" : (bar.root.weatherLoaded ? bar.root.weatherTempC + "°C" : "Weather…"); bar.root.showTooltip(tip, p.x, p.y); }
                        onExited: bar.root.hideTooltip("Weather")
                        onClicked: (e) => {
                            if (e.button === Qt.RightButton) { bar.root.refreshWeather(); return; }
                            if (bar.root.weatherVisible) bar.root.weatherVisible = false;
                            else { var p = parent.mapToItem(null, parent.width/2, parent.height/2); bar.root.popupAnchorX = p.x; bar.root.popupAnchorY = p.y; bar.root.popupScreen = bar.screen; bar.root.openWeather(); }
                        }
                    }
                }

                // Corne keyboard battery (SVG icons): *60 70*
                StatFrame {
                    root: bar.root
                    Layout.alignment: Qt.AlignVCenter
                    visible: bar.root.corneLeft >= 0 || bar.root.corneRight >= 0
                    Canvas {
                        width: 16; height: 16
                        property color cc: bar.root.tintCorne
                        onCcChanged: requestPaint()
                        onPaint: {
                            const ctx = getContext("2d");
                            ctx.reset();
                            ctx.scale(16 / 24, 16 / 24);
                            ctx.strokeStyle = cc;
                            ctx.lineWidth = 1.5;
                            ctx.lineCap = "round";
                            ctx.lineJoin = "round";
                            ctx.beginPath();
                            bar.root.cornePath(ctx);
                            ctx.stroke();
                        }
                        Component.onCompleted: requestPaint()
                    }
                    Text { text: bar.root.corneLeft >= 0 ? (bar.root.corneLeft < 10 ? "0" : "") + bar.root.corneLeft.toString() : "?"; color: bar.root.ink; font.family: bar.root.mono; font.pixelSize: 13 }
                    Text { Layout.leftMargin: 2; text: bar.root.corneRight >= 0 ? (bar.root.corneRight < 10 ? "0" : "") + bar.root.corneRight.toString() : "?"; color: bar.root.ink; font.family: bar.root.mono; font.pixelSize: 13 }
                    Canvas {
                        width: 16; height: 16
                        property color cc: bar.root.tintCorne
                        onCcChanged: requestPaint()
                        onPaint: {
                            const ctx = getContext("2d");
                            ctx.reset();
                            ctx.scale(16 / 24, 16 / 24);
                            ctx.translate(24, 0);
                            ctx.scale(-1, 1);
                            ctx.strokeStyle = cc;
                            ctx.lineWidth = 1.5;
                            ctx.lineCap = "round";
                            ctx.lineJoin = "round";
                            ctx.beginPath();
                            bar.root.cornePath(ctx);
                            ctx.stroke();
                        }
                        Component.onCompleted: requestPaint()
                    }
                    MouseArea {
                        anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.LeftButton | Qt.RightButton; cursorShape: Qt.PointingHandCursor
                        onEntered: { const p = parent.mapToItem(null, parent.width/2, parent.height/2); bar.root.showTooltip("Corne battery", p.x, p.y); }
                        onExited: bar.root.hideTooltip("Corne battery")
                        onClicked: (e) => { if (e.button === Qt.RightButton) bar.root.refreshCorneBattery(); }
                    }
                }

                // CPU
                StatFrame {
                    root: bar.root
                    Layout.alignment: Qt.AlignVCenter
                    Text { text: bar.root.icoCpu; color: bar.root.tintCpu; font.family: bar.root.mono; font.pixelSize: 13 }
                    Text { text: (Math.round(bar.root.cpuVal) < 10 ? "0" : "") + Math.round(bar.root.cpuVal) + "% " + bar.root.cpuTemp + "°"; color: bar.root.ink; font.family: bar.root.mono; font.pixelSize: 14 }
                    MouseArea {
                        anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onEntered: { const p = parent.mapToItem(null, parent.width/2, parent.height/2); bar.root.showTooltip("CPU " + Math.round(bar.root.cpuVal) + "% · " + bar.root.cpuTemp + "°C", p.x, p.y); }
                        onExited: bar.root.hideTooltip("CPU")
                        onClicked: bar.root.run("omarchy-launch-or-focus-tui btop")
                    }
                }

                // MEM
                StatFrame {
                    root: bar.root
                    Layout.alignment: Qt.AlignVCenter
                    Text { text: bar.root.icoRam; color: bar.root.tintRam; font.family: bar.root.mono; font.pixelSize: 13 }
                    Text { text: (bar.root.memUsedGB < 10 ? bar.root.memUsedGB.toFixed(1) : Math.round(bar.root.memUsedGB)) + "G"; color: bar.root.ink; font.family: bar.root.mono; font.pixelSize: 14 }
                    MouseArea {
                        anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onEntered: { const p = parent.mapToItem(null, parent.width/2, parent.height/2); bar.root.showTooltip("MEM " + bar.root.memUsedGB + "/" + bar.root.memTotalGB + " GB (" + Math.round(bar.root.memVal) + "%)", p.x, p.y); }
                        onExited: bar.root.hideTooltip("MEM")
                        onClicked: bar.root.run("omarchy-launch-or-focus-tui btop")
                    }
                }

                // VOL
                StatFrame {
                    root: bar.root
                    Layout.alignment: Qt.AlignVCenter
                    Text { text: bar.root.volIcon; color: bar.root.tintVol; font.family: bar.root.mono; font.pixelSize: 13 }
                    Text { text: (bar.root.audioMuted || bar.root.audioVol === 0) ? "--" : (bar.root.audioVol < 10 ? "0" : "") + bar.root.audioVol + "%"; color: bar.root.ink; font.family: bar.root.mono; font.pixelSize: 14 }
                    MouseArea {
                        anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.LeftButton | Qt.RightButton; cursorShape: Qt.PointingHandCursor
                        onEntered: { const p = parent.mapToItem(null, parent.width/2, parent.height/2); let tip = bar.root.audioMuted ? "Audio muted · " + bar.root.audioVol + "%" : "Audio " + bar.root.audioVol + "%"; bar.root.showTooltip(tip, p.x, p.y); }
                        onExited: bar.root.hideTooltip("VOL")
                        onClicked: (e) => { if (e.button === Qt.RightButton) bar.root.run("pamixer -t"); else bar.root.run("omarchy-launch-audio"); }
                    }
                }

                // BAT — frame doubles as the popup anchor (id kept for updateBatPos)
                StatFrame {
                    id: batRow
                    root: bar.root
                    Layout.alignment: Qt.AlignVCenter
                    innerSpacing: 3
                    Component.onCompleted: bar.updateBatPos()
                    onXChanged: bar.updateBatPos()
                    onYChanged: bar.updateBatPos()
                    onWidthChanged: bar.updateBatPos()
                    onHeightChanged: bar.updateBatPos()
                    Text { text: bar.root.profileIcon; color: bar.root.tintBat; font.family: bar.root.mono; font.pixelSize: 13 }
                    Text { text: bar.root.batIcon; color: bar.root.tintBat; font.family: bar.root.mono; font.pixelSize: 13 }
                    Text { text: (bar.root.batVal < 10 ? "0" : "") + bar.root.batVal + "%" + (bar.root.batTime ? " " + bar.root.batTime : ""); color: bar.root.ink; font.family: bar.root.mono; font.pixelSize: 14 }
                    MouseArea {
                        anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onEntered: {
                            const p = parent.mapToItem(null, parent.width/2, parent.height/2);
                            let s = "Battery " + bar.root.batVal + "%";
                            if (bar.root.batPower >= 0.05) { const sign = bar.root.batState === "Charging" ? "+" : bar.root.batState === "Discharging" ? "-" : ""; s += "  " + sign + bar.root.batPower.toFixed(1) + " W"; }
                            bar.root.showTooltip(s, p.x, p.y);
                        }
                        onExited: bar.root.hideTooltip("BAT")
                        onClicked: {
                            if (bar.root.batteryVisible) bar.root.batteryVisible = false;
                            else { var p = parent.mapToItem(null, parent.width/2, parent.height/2); bar.root.popupAnchorX = p.x; bar.root.popupAnchorY = p.y; bar.root.batteryPopX = p.x; bar.root.batteryPopY = p.y; bar.root.popupScreen = bar.screen; bar.root.openBattery(); }
                        }
                    }
                }

                // Power — bare seal button, outside the stat frames (Tsugumori
                // keeps the power key unframed too).
                Module {
                    Layout.alignment: Qt.AlignVCenter
                    glyphYOffset: 0
                    root: bar.root
                    glyph: bar.root.icoPower
                    tooltip: "Power"
                    color: bar.root.seal
                    fontFamily: bar.root.mono
                    fontSize: 22
                    onActivated: bar.root.powerMenuRequested()
                }
            }
    }
}
