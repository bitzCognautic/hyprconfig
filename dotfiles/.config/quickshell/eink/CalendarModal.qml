import QtQuick
import QtQuick.Layouts

Item {
    id: root

    property var theme
    signal requestClose()

    // Month being displayed
    property int shownYear: (new Date()).getFullYear()
    property int shownMonth: (new Date()).getMonth() // 0-11

    readonly property var today: new Date()
    readonly property int todayYear: today.getFullYear()
    readonly property int todayMonth: today.getMonth()
    readonly property int todayDay: today.getDate()

    function daysInMonth(year, month) {
        return new Date(year, month + 1, 0).getDate()
    }

    // 0=Sunday ... 6=Saturday
    function firstWeekday(year, month) {
        return new Date(year, month, 1).getDay()
    }

    function monthTitle(year, month) {
        const names = ["January","February","March","April","May","June","July","August","September","October","November","December"]
        return names[month] + " " + year
    }

    function prevMonth() {
        if (root.shownMonth === 0) {
            root.shownMonth = 11
            root.shownYear = root.shownYear - 1
        } else {
            root.shownMonth = root.shownMonth - 1
        }
    }

    function nextMonth() {
        if (root.shownMonth === 11) {
            root.shownMonth = 0
            root.shownYear = root.shownYear + 1
        } else {
            root.shownMonth = root.shownMonth + 1
        }
    }

    function resetToday() {
        root.shownYear = root.todayYear
        root.shownMonth = root.todayMonth
    }

    implicitWidth: 360
    implicitHeight: Math.round(content.implicitHeight + 8)

    Rectangle {
        anchors.fill: parent
        radius: 22
        color: Qt.rgba(0.08, 0.08, 0.08, 0.97)
        border.width: 1
        border.color: Qt.rgba(root.theme.outline.r, root.theme.outline.g, root.theme.outline.b, 0.35)
    }

    ColumnLayout {
        id: content
        anchors.fill: parent
        anchors.margins: 14
        spacing: 12

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Rectangle {
                width: 34
                height: 34
                radius: 12
                color: Qt.rgba(root.theme.surfaceAlt.r, root.theme.surfaceAlt.g, root.theme.surfaceAlt.b, 0.95)
                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.prevMonth()
                }
                Text {
                    anchors.centerIn: parent
                    text: "‹"
                    color: root.theme.text
                    font.family: root.theme.fontFamily
                    font.pixelSize: 18
                    font.weight: Font.DemiBold
                }
            }

            Text {
                text: root.monthTitle(root.shownYear, root.shownMonth)
                color: root.theme.text
                font.family: root.theme.fontFamily
                font.pixelSize: 14
                font.weight: Font.DemiBold
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                horizontalAlignment: Text.AlignHCenter
            }

            Rectangle {
                width: 34
                height: 34
                radius: 12
                color: Qt.rgba(root.theme.surfaceAlt.r, root.theme.surfaceAlt.g, root.theme.surfaceAlt.b, 0.95)
                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.nextMonth()
                }
                Text {
                    anchors.centerIn: parent
                    text: "›"
                    color: root.theme.text
                    font.family: root.theme.fontFamily
                    font.pixelSize: 18
                    font.weight: Font.DemiBold
                }
            }

            Rectangle {
                width: 34
                height: 34
                radius: 12
                color: Qt.rgba(root.theme.surfaceAlt.r, root.theme.surfaceAlt.g, root.theme.surfaceAlt.b, 0.95)
                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.requestClose()
                }
                Text {
                    anchors.centerIn: parent
                    text: "×"
                    color: root.theme.text
                    font.family: root.theme.fontFamily
                    font.pixelSize: 16
                    font.weight: Font.DemiBold
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Rectangle {
                Layout.fillWidth: true
                height: 30
                radius: 14
                color: Qt.rgba(root.theme.surfaceAlt.r, root.theme.surfaceAlt.g, root.theme.surfaceAlt.b, 0.72)
                border.width: 1
                border.color: Qt.rgba(root.theme.outline.r, root.theme.outline.g, root.theme.outline.b, 0.18)
                Text {
                    anchors.centerIn: parent
                    text: "Today"
                    color: root.theme.text
                    font.family: root.theme.fontFamily
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                }
                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.resetToday()
                }
            }
        }

        GridLayout {
            id: cal
            Layout.fillWidth: true
            columns: 7
            columnSpacing: 6
            rowSpacing: 6

            readonly property int cellSize: 40
            readonly property int leadingBlanks: root.firstWeekday(root.shownYear, root.shownMonth)
            readonly property int monthDays: root.daysInMonth(root.shownYear, root.shownMonth)
            readonly property int totalCells: 42
            readonly property int firstCellDay: 1 - leadingBlanks

            Repeater {
                model: ["Su","Mo","Tu","We","Th","Fr","Sa"]
                delegate: Text {
                    text: modelData
                    color: Qt.rgba(root.theme.text.r, root.theme.text.g, root.theme.text.b, 0.78)
                    font.family: root.theme.fontFamily
                    font.pixelSize: 10
                    font.weight: Font.DemiBold
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    Layout.preferredWidth: cal.cellSize
                    Layout.preferredHeight: 16
                }
            }

            Repeater {
                model: cal.totalCells
                delegate: Rectangle {
                    readonly property int cellIndex: index
                    readonly property int dayNum: cal.firstCellDay + cellIndex
                    readonly property bool inMonth: (dayNum >= 1 && dayNum <= cal.monthDays)
                    readonly property bool isToday: inMonth &&
                        (root.shownYear === root.todayYear) &&
                        (root.shownMonth === root.todayMonth) &&
                        (dayNum === root.todayDay)

                    Layout.preferredWidth: cal.cellSize
                    Layout.preferredHeight: cal.cellSize
                    radius: 14
                    color: isToday
                        ? Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.92)
                        : Qt.rgba(root.theme.surfaceAlt.r, root.theme.surfaceAlt.g, root.theme.surfaceAlt.b, inMonth ? 0.55 : 0.18)
                    border.width: 1
                    border.color: Qt.rgba(root.theme.outline.r, root.theme.outline.g, root.theme.outline.b, inMonth ? 0.18 : 0.10)

                    Text {
                        anchors.centerIn: parent
                        text: inMonth ? String(dayNum) : ""
                        color: isToday ? root.theme.onAccent : root.theme.text
                        font.family: root.theme.fontFamily
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                        opacity: inMonth ? 1.0 : 0.0
                    }
                }
            }
        }

        Item { Layout.preferredHeight: 8 }
    }
}

