import QtQuick
import QtQuick.Layouts
import Quickshell.Io 0.0

Item {
    id: root

    property var theme
    signal requestClose()

    implicitWidth: 520
    implicitHeight: Math.round(content.implicitHeight + 16)

    StdioCollector { id: out; waitForEnd: true }
    StdioCollector { id: err; waitForEnd: true }

    Process {
        id: cmd
        stdout: out
        stderr: err
        onExited: function() {
            cmd.running = false
            const cb = root._pendingCb
            root._pendingCb = null
            if (cb) cb((out.text ?? "").trim(), (err.text ?? "").trim())
        }
    }

    Process { id: detached }

    property var _pendingCb: null

    function execSh(script, cb) {
        if (cmd.running) return
        root._pendingCb = cb || null
        out.waitForEnd = true
        err.waitForEnd = true
        cmd.command = ["sh", "-lc", script]
        cmd.running = true
    }

    property bool recording: false

    function startRecording(fullscreen, audio) {
        const kind = fullscreen ? "full" : "region"
        const aud = audio ? "_audio" : ""
        const script =
            "dir=\"$HOME/Videos/Recordings\"; mkdir -p \"$dir\";\n" +
            "file=\"$dir/$(date +%Y-%m-%d_%H-%M-%S)_" + kind + aud + ".mp4\";\n" +
            (fullscreen ? "" : "geom=\"$(slurp)\"; [ -z \"$geom\" ] && exit 0;\n") +
            "nohup wf-recorder " + (audio ? "-a " : "") +
            (fullscreen ? "" : "-g \"$geom\" ") +
            "-f \"$file\" >/tmp/eink-recorder.log 2>&1 &\n" +
            "sleep 0.05; ~/.local/bin/eink-notify \"Recording started\" \"Saved to: $file\" || true\n"

        // Region selection (slurp) can be blocked by our layer if we keep it open.
        // Start it detached and close the modal immediately.
        if (!fullscreen) {
            detached.command = ["sh", "-lc", script]
            detached.startDetached()
            root.requestClose()
            // Give it a moment, then refresh our local state.
            root.execSh("sleep 0.15; pgrep -x wf-recorder >/dev/null 2>&1 && echo 1 || echo 0", function(o) {
                recording = (String(o).trim() === "1")
            })
            return
        }

        root.execSh(script, function() {
            root.refresh()
            root.requestClose()
        })
    }

    function stopRecording() {
        root.execSh("pkill -INT wf-recorder >/dev/null 2>&1 || true; ~/.local/bin/eink-notify \"Recording stopped\" \"\" || true", function() {
            root.refresh()
        })
    }

    function refresh() {
        execSh("pgrep -x wf-recorder >/dev/null 2>&1 && echo 1 || echo 0", function(o) {
            recording = (String(o).trim() === "1")
        })
    }

    Component.onCompleted: refresh()

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
                text: "Screen recording"
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

        Rectangle {
            Layout.fillWidth: true
            height: 1
            radius: 1
            color: Qt.rgba(root.theme.outline.r, root.theme.outline.g, root.theme.outline.b, 0.35)
        }

        Text {
            text: recording ? "Recording: On" : "Recording: Off"
            color: root.theme.textMuted
            font.family: root.theme.fontFamily
            font.pixelSize: 12
            Layout.fillWidth: true
        }

        GridLayout {
            Layout.fillWidth: true
            columns: 2
            columnSpacing: 10
            rowSpacing: 10

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 54
                radius: 18
                color: Qt.rgba(root.theme.surfaceAlt.r, root.theme.surfaceAlt.g, root.theme.surfaceAlt.b, 0.72)
                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 10
                    EinkSymbol {
                        symbol: String.fromCodePoint(0xF03E8) // nf-md-video
                        fallbackSymbol: "videocam"
                        fontFamily: root.theme.iconFontFamily
                        fontFamilyFallback: root.theme.iconFontFamilyFallback
                        color: root.theme.text
                        size: 18
                    }
                    Text { text: "Fullscreen"; color: root.theme.text; font.family: root.theme.fontFamily; font.pixelSize: 12; font.weight: Font.DemiBold; Layout.fillWidth: true }
                    Text { text: "No audio"; color: root.theme.textMuted; font.family: root.theme.fontFamily; font.pixelSize: 11; font.weight: Font.DemiBold }
                }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; enabled: !recording; onClicked: root.startRecording(true, false) }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 54
                radius: 18
                color: Qt.rgba(root.theme.surfaceAlt.r, root.theme.surfaceAlt.g, root.theme.surfaceAlt.b, 0.72)
                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 10
                    EinkSymbol {
                        symbol: String.fromCodePoint(0xF03E8) // nf-md-video
                        fallbackSymbol: "videocam"
                        fontFamily: root.theme.iconFontFamily
                        fontFamilyFallback: root.theme.iconFontFamilyFallback
                        color: root.theme.text
                        size: 18
                    }
                    Text { text: "Fullscreen"; color: root.theme.text; font.family: root.theme.fontFamily; font.pixelSize: 12; font.weight: Font.DemiBold; Layout.fillWidth: true }
                    Text { text: "Audio"; color: root.theme.textMuted; font.family: root.theme.fontFamily; font.pixelSize: 11; font.weight: Font.DemiBold }
                }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; enabled: !recording; onClicked: root.startRecording(true, true) }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 54
                radius: 18
                color: Qt.rgba(root.theme.surfaceAlt.r, root.theme.surfaceAlt.g, root.theme.surfaceAlt.b, 0.72)
                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 10
                    EinkSymbol {
                        symbol: String.fromCodePoint(0xF03E8) // nf-md-video
                        fallbackSymbol: "videocam"
                        fontFamily: root.theme.iconFontFamily
                        fontFamilyFallback: root.theme.iconFontFamilyFallback
                        color: root.theme.text
                        size: 18
                    }
                    Text { text: "Region"; color: root.theme.text; font.family: root.theme.fontFamily; font.pixelSize: 12; font.weight: Font.DemiBold; Layout.fillWidth: true }
                    Text { text: "No audio"; color: root.theme.textMuted; font.family: root.theme.fontFamily; font.pixelSize: 11; font.weight: Font.DemiBold }
                }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; enabled: !recording; onClicked: root.startRecording(false, false) }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 54
                radius: 18
                color: Qt.rgba(root.theme.surfaceAlt.r, root.theme.surfaceAlt.g, root.theme.surfaceAlt.b, 0.72)
                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 10
                    EinkSymbol {
                        symbol: String.fromCodePoint(0xF03E8) // nf-md-video
                        fallbackSymbol: "videocam"
                        fontFamily: root.theme.iconFontFamily
                        fontFamilyFallback: root.theme.iconFontFamilyFallback
                        color: root.theme.text
                        size: 18
                    }
                    Text { text: "Region"; color: root.theme.text; font.family: root.theme.fontFamily; font.pixelSize: 12; font.weight: Font.DemiBold; Layout.fillWidth: true }
                    Text { text: "Audio"; color: root.theme.textMuted; font.family: root.theme.fontFamily; font.pixelSize: 11; font.weight: Font.DemiBold }
                }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; enabled: !recording; onClicked: root.startRecording(false, true) }
            }
        }

        Item { Layout.preferredHeight: 0 }
    }
}
