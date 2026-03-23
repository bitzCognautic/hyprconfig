import QtQuick
import QtQuick.Layouts
import Quickshell.Io 0.0

Item {
    id: root

    property var theme
    signal requestClose()

    implicitWidth: 520
    implicitHeight: Math.round(content.implicitHeight + 8)

    StdioCollector { id: out; waitForEnd: true }
    StdioCollector { id: err; waitForEnd: true }

    Process {
        id: cmd
        stdout: out
        stderr: err
        onExited: function() { cmd.running = false }
    }

    function execSh(script) {
        if (cmd.running) return
        out.waitForEnd = true
        err.waitForEnd = true
        cmd.command = ["sh", "-lc", script]
        cmd.running = true
    }

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

            Text {
                text: "Power"
                color: root.theme.text
                font.family: root.theme.fontFamily
                font.pixelSize: 14
                font.weight: Font.DemiBold
                Layout.fillWidth: true
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
                EinkSymbol {
                    anchors.centerIn: parent
                    symbol: String.fromCodePoint(0xF0156) // nf-md-close
                    fallbackSymbol: "close"
                    fontFamily: root.theme.iconFontFamily
                    fontFamilyFallback: root.theme.iconFontFamilyFallback
                    color: root.theme.text
                    size: 18
                }
            }
        }

        GridLayout {
            Layout.fillWidth: true
            columns: 2
            columnSpacing: 10
            rowSpacing: 10

            function card(symbol, fallbackSymbol, label, command) {
                return {
                    symbol,
                    fallbackSymbol,
                    label,
                    command
                }
            }

            Repeater {
                model: [
                    ({
                        symbol: String.fromCodePoint(0xF033E), fallbackSymbol: "lock", label: "Lock",
                        command:
                            // Prefer system session lock (works with logind/elogind); fall back to hyprlock.
                            "if command -v hyprlock >/dev/null 2>&1; then hyprlock; exit 0; fi; " +
                            "command -v loginctl >/dev/null 2>&1 && loginctl lock-session"
                    }),
                    ({
                        symbol: String.fromCodePoint(0xF0A1B), fallbackSymbol: "monitor", label: "Screen Off",
                        command: "hyprctl dispatch dpms off"
                    }),
                    ({
                        symbol: String.fromCodePoint(0xF055E), fallbackSymbol: "bedtime", label: "Sleep",
                        command:
                            // systemctl is most common; loginctl works on some setups too.
                            "if command -v systemctl >/dev/null 2>&1; then systemctl suspend; " +
                            "elif command -v loginctl >/dev/null 2>&1; then loginctl suspend; " +
                            "fi"
                    }),
                    ({ symbol: String.fromCodePoint(0xF0709), fallbackSymbol: "refresh", label: "Restart", command: "systemctl reboot" }),
                    ({ symbol: String.fromCodePoint(0xF0425), fallbackSymbol: "power_settings_new", label: "Power Off", command: "systemctl poweroff" }),
                    ({ symbol: String.fromCodePoint(0xF0341), fallbackSymbol: "logout", label: "Logout", command: "hyprctl dispatch exit" }),
                ]
                delegate: Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 58
                    radius: 18
                    color: Qt.rgba(root.theme.surfaceAlt.r, root.theme.surfaceAlt.g, root.theme.surfaceAlt.b, 0.72)
                    border.width: 1
                    border.color: Qt.rgba(root.theme.outline.r, root.theme.outline.g, root.theme.outline.b, 0.22)

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 10

                        EinkSymbol {
                            symbol: modelData.symbol
                            fallbackSymbol: modelData.fallbackSymbol
                            fontFamily: root.theme.iconFontFamily
                            fontFamilyFallback: root.theme.iconFontFamilyFallback
                            color: root.theme.text
                            size: 18
                            Layout.alignment: Qt.AlignVCenter
                        }

                        Text {
                            text: modelData.label
                            color: root.theme.text
                            font.family: root.theme.fontFamily
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                        }

                        Rectangle {
                            width: 92
                            height: 30
                            radius: 14
                            color: Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.92)
                            Text {
                                anchors.centerIn: parent
                                text: "Run"
                                color: root.theme.onAccent
                                font.family: root.theme.fontFamily
                                font.pixelSize: 11
                                font.weight: Font.DemiBold
                            }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            // Close UI first, then run the action.
                            root.execSh("(sleep 0.05; " + modelData.command + ") >/dev/null 2>&1 &")
                            root.requestClose()
                        }
                    }
                }
            }
        }

        // Bottom padding (avoid a cramped last row against the modal edge).
        Item { Layout.preferredHeight: 10 }
    }
}
