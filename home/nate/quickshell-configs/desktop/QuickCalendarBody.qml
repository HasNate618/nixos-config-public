import QtQuick

// Calendar detail — month grid + day detail. Keyboard: arrow keys move
// the selected day across the grid (±1 within a row, ±7 between rows),
// Page Up/Down jumps a month, Enter does nothing (selection is the
// gesture itself).
Item {
    id: body
    required property var root
    required property var nav
    width: parent ? parent.width : 0

    signal close()

    implicitHeight: col.implicitHeight + 8

    // selectedDay (1..31) lives on nav; kbdHandle moves it.
    function kbdHandle(event) {
        if (!body.nav) return false;
        const r = body.nav;
        const k = event.key;
        const cells = r.calendarCells;
        // Build a list of valid days in this month for clamping.
        const days = [];
        for (let i = 0; i < cells.length; i++)
            if (cells[i].day !== 0) days.push(cells[i].day);
        if (days.length === 0) return false;
        const cur = r.selectedDay > 0 ? r.selectedDay : days[0];
        if (k === Qt.Key_Left) {
            r.selectedDay = Math.max(days[0], cur - 1);
            return true;
        }
        if (k === Qt.Key_Right) {
            r.selectedDay = Math.min(days[days.length - 1], cur + 1);
            return true;
        }
        if (k === Qt.Key_Up) {
            r.selectedDay = Math.max(days[0], cur - 7);
            return true;
        }
        if (k === Qt.Key_Down || k === Qt.Key_Tab) {
            r.selectedDay = Math.min(days[days.length - 1], cur + 7);
            return true;
        }
        if (k === Qt.Key_PageUp) {
            r.calendarMonthOffset--; r.calendarTick++; r.selectedDay = 0;
            return true;
        }
        if (k === Qt.Key_PageDown) {
            r.calendarMonthOffset++; r.calendarTick++; r.selectedDay = 0;
            return true;
        }
        if (k === Qt.Key_Home) {
            r.calendarMonthOffset = 0; r.calendarTick++;
            r.selectedDay = (new Date()).getDate();
            return true;
        }
        return false;
    }

    Column {
        id: col
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: 6
        spacing: 10

        Item {
            width: parent.width
            height: 24
            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: (body.nav ? body.nav.calendarMonthName : "")
                      + "  ·  " + (body.nav ? body.nav.calendarYear : "")
                color: body.root.ink
                font.family: body.root.mono
                font.pixelSize: 12
                font.letterSpacing: 2
                font.weight: Font.Medium
            }
            Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 14
                CalendarChevron {
                    root: body.root
                    text: "‹"
                    onTriggered: {
                        if (!body.nav) return;
                        body.nav.calendarMonthOffset--;
                        body.nav.calendarTick++;
                        body.nav.selectedDay = 0;
                    }
                }
                CalendarChevron {
                    root: body.root
                    text: "•"
                    restColor: body.root.inkDeep
                    font.pixelSize: 19
                    onTriggered: {
                        if (!body.nav) return;
                        body.nav.calendarMonthOffset = 0;
                        body.nav.calendarTick++;
                        body.nav.selectedDay = (new Date()).getDate();
                    }
                }
                CalendarChevron {
                    root: body.root
                    text: "›"
                    onTriggered: {
                        if (!body.nav) return;
                        body.nav.calendarMonthOffset++;
                        body.nav.calendarTick++;
                        body.nav.selectedDay = 0;
                    }
                }
            }
        }

        Rectangle { width: parent.width; height: 1; color: body.root.sep }

        Row {
            width: parent.width
            Repeater {
                model: ["MO","TU","WE","TH","FR","SA","SU"]
                delegate: Item {
                    required property string modelData
                    required property int index
                    width: parent.width / 7
                    height: 20
                    Text {
                        anchors.centerIn: parent
                        text: modelData
                        color: index >= 5 ? body.root.seal : body.root.inkDeep
                        opacity: index >= 5 ? 0.85 : 0.7
                        font.family: body.root.mono
                        font.pixelSize: 11
                        font.letterSpacing: 2
                    }
                }
            }
        }

        Grid {
            columns: 7
            rowSpacing: 2
            columnSpacing: 0
            width: parent.width
            Repeater {
                model: body.nav ? body.nav.calendarCells : []
                delegate: Item {
                    id: dayCell
                    required property var modelData
                    required property int index
                    width: parent.width / 7
                    height: 30

                    readonly property int  dayOfWeek: index % 7
                    readonly property bool isWeekend: dayOfWeek >= 5
                    readonly property bool isCurrentMonth: modelData.day !== 0
                    readonly property bool isToday: modelData.today
                    readonly property bool isHoliday: modelData.holiday !== ""
                    readonly property bool isSelected: isCurrentMonth
                                                       && body.nav
                                                       && body.nav.selectedDay === modelData.day

                    readonly property color textColor: {
                        if (isToday) return body.root.seal.hsvValue < 0.5 ? body.root.ink : body.root.paper;
                        if (!isCurrentMonth) return body.root.inkDeep;
                        return (isWeekend || isHoliday) ? body.root.seal : body.root.ink;
                    }

                    Rectangle {
                        anchors.centerIn: parent
                        width: 26; height: 26; radius: 13
                        color: body.root.seal
                        visible: dayCell.isToday
                        antialiasing: true
                    }
                    Rectangle {
                        anchors.centerIn: parent
                        width: 26; height: 26; radius: 13
                        color: Qt.rgba(body.root.ink.r, body.root.ink.g, body.root.ink.b, 0.08)
                        visible: dayMouse.containsMouse && !dayCell.isToday && dayCell.isCurrentMonth
                        antialiasing: true
                    }
                    Rectangle {
                        anchors.centerIn: parent
                        width: 26; height: 26; radius: 13
                        color: "transparent"
                        border.color: body.root.seal
                        border.width: 1
                        visible: dayCell.isSelected && !dayCell.isToday
                        antialiasing: true
                    }
                    Text {
                        anchors.centerIn: parent
                        text: dayCell.modelData.day === 0 ? "" : dayCell.modelData.day
                        color: dayCell.textColor
                        opacity: dayCell.isCurrentMonth ? 1.0 : 0.35
                        font.family: body.root.mono
                        font.pixelSize: 13
                        font.weight: dayCell.isToday ? Font.Medium : Font.Light
                    }
                    MouseArea {
                        id: dayMouse
                        anchors.fill: parent
                        hoverEnabled: dayCell.isCurrentMonth
                        enabled: dayCell.isCurrentMonth
                        cursorShape: dayCell.isCurrentMonth ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: if (body.nav) body.nav.selectedDay = dayCell.modelData.day
                    }
                }
            }
        }

        Rectangle {
            width: parent.width
            height: 1
            color: body.root.sep
            visible: body.nav && body.nav.selectedDay > 0
        }
        Text {
            width: parent.width
            visible: body.nav && body.nav.selectedDay > 0
            text: body.nav ? body.nav.selectedDayDetail : ""
            color: body.root.ink
            font.family: body.root.mono
            font.pixelSize: 11
            font.letterSpacing: 2
        }
        Text {
            width: parent.width
            visible: body.nav && body.nav.selectedDayHoliday.length > 0
            text: body.nav ? body.nav.selectedDayHoliday.toUpperCase() : ""
            color: body.root.seal
            font.family: body.root.mono
            font.pixelSize: 11
            font.letterSpacing: 2
        }
    }
}
