import QtQuick

CardWindow {
    id: calendarPopup
    required property var root

    theme: root
    revealed: root.calendarVisible
    cardWidth: 322
    layerNamespace: "omarchy-calendar"
    title: calendarPopup.root.calendarMonthName
    subtitle: calendarPopup.root.calendarYear

    anchorEdge: calendarPopup.root.barEdge
    anchorBarX: calendarPopup.root.popupAnchorX
    anchorBarY: calendarPopup.root.popupAnchorY

    headerRight: Row {
        spacing: 12
        CalendarChevron {
            root: calendarPopup.root
            text: "‹"
            onTriggered: { calendarPopup.root.calendarMonthOffset--; calendarPopup.root.calendarTick++; calendarPopup.root.selectedDay = 0; }
        }
        CalendarChevron {
            root: calendarPopup.root
            text: "•"
            restColor: calendarPopup.root.inkDeep
            font.pixelSize: 19
            onTriggered: { calendarPopup.root.calendarMonthOffset = 0; calendarPopup.root.calendarTick++; calendarPopup.root.selectedDay = (new Date()).getDate(); }
        }
        CalendarChevron {
            root: calendarPopup.root
            text: "›"
            onTriggered: { calendarPopup.root.calendarMonthOffset++; calendarPopup.root.calendarTick++; calendarPopup.root.selectedDay = 0; }
        }
    }

    onDismiss: calendarPopup.root.calendarVisible = false
    onKeyPressed: function(event) {
        if (event.key === Qt.Key_Q) {
            calendarPopup.root.calendarVisible = false;
            event.accepted = true;
        }
    }

    Column {
        width: parent.width
        spacing: 12

        Rectangle {
            width: parent.width
            height: 1
            color: calendarPopup.root.sep
        }

        // Weekday row (Monday first). Sat/Sun tinted seal so the week's
        // shape is readable at a glance.
        Row {
            width: parent.width
            spacing: 0

            Repeater {
                model: ["MO","TU","WE","TH","FR","SA","SU"]
                delegate: Item {
                    required property string modelData
                    required property int index
                    width: parent.width / 7
                    height: 22
                    Text {
                        anchors.centerIn: parent
                        text: modelData
                        color: index >= 5 ? calendarPopup.root.seal : calendarPopup.root.inkDeep
                        opacity: index >= 5 ? 0.85 : 0.7
                        font.family: calendarPopup.root.mono
                        font.pixelSize: 12
                        font.letterSpacing: 2
                    }
                }
            }
        }

        // 6 rows of 7. Today is a filled chip with theme-aware contrast
        // text. Inactive (leading/trailing month) days fade to maintain
        // the grid silhouette.
        Grid {
            columns: 7
            rowSpacing: 2
            columnSpacing: 0
            width: parent.width

            Repeater {
                model: calendarPopup.root.calendarCells
                delegate: Item {
                    id: dayCell
                    required property var modelData
                    required property int index
                    width: parent.width / 7
                    height: 34

                    readonly property int  dayOfWeek: index % 7
                    readonly property bool isWeekend: dayOfWeek >= 5
                    readonly property bool isCurrentMonth: modelData.day !== 0
                    readonly property bool isToday: modelData.today
                    readonly property bool isHoliday: modelData.holiday !== ""
                    readonly property bool isSelected: isCurrentMonth && calendarPopup.root.selectedDay === modelData.day

                    readonly property color textColor: {
                        if (isToday) return calendarPopup.root.seal.hsvValue < 0.5 ? calendarPopup.root.ink : calendarPopup.root.paper;
                        if (!isCurrentMonth) return calendarPopup.root.inkDeep;
                        return (isWeekend || isHoliday) ? calendarPopup.root.seal : calendarPopup.root.ink;
                    }

                    Rectangle {
                        anchors.centerIn: parent
                        width: 29; height: 29; radius: 14
                        color: calendarPopup.root.seal
                        visible: dayCell.isToday
                        antialiasing: true
                    }

                    Rectangle {
                        anchors.centerIn: parent
                        width: 29; height: 29; radius: 14
                        color: Qt.rgba(calendarPopup.root.ink.r, calendarPopup.root.ink.g, calendarPopup.root.ink.b, 0.08)
                        visible: dayMouse.containsMouse && !dayCell.isToday && dayCell.isCurrentMonth
                        antialiasing: true
                        Behavior on opacity { NumberAnimation { duration: 120 } }
                    }

                    Rectangle {
                        anchors.centerIn: parent
                        width: 29; height: 29; radius: 14
                        color: "transparent"
                        border.color: calendarPopup.root.seal
                        border.width: 1
                        visible: dayCell.isSelected && !dayCell.isToday
                        antialiasing: true
                    }

                    Text {
                        anchors.centerIn: parent
                        text: dayCell.modelData.day === 0 ? "" : dayCell.modelData.day
                        color: dayCell.textColor
                        opacity: dayCell.isCurrentMonth ? 1.0 : 0.35
                        font.family: calendarPopup.root.mono
                        font.pixelSize: 15
                        font.weight: dayCell.isToday ? Font.Medium : Font.Light
                    }

                    MouseArea {
                        id: dayMouse
                        anchors.fill: parent
                        hoverEnabled: dayCell.isCurrentMonth
                        enabled: dayCell.isCurrentMonth
                        cursorShape: dayCell.isCurrentMonth
                                     ? Qt.PointingHandCursor
                                     : Qt.ArrowCursor
                        onClicked: calendarPopup.root.selectedDay = dayCell.modelData.day
                    }
                }
            }
        }

        Rectangle {
            width: parent.width
            height: 1
            color: calendarPopup.root.sep
            visible: calendarPopup.root.selectedDay > 0
        }

        Text {
            width: parent.width
            visible: calendarPopup.root.selectedDay > 0
            text: calendarPopup.root.selectedDayDetail
            color: calendarPopup.root.ink
            font.family: calendarPopup.root.mono
            font.pixelSize: 11
            font.letterSpacing: 2
        }

        Text {
            width: parent.width
            visible: calendarPopup.root.selectedDayHoliday.length > 0
            text: calendarPopup.root.selectedDayHoliday.toUpperCase()
            color: calendarPopup.root.seal
            font.family: calendarPopup.root.mono
            font.pixelSize: 11
            font.letterSpacing: 2
        }
    }
}
