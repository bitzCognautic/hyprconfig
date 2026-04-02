import QtQuick
import QtQuick.Layouts
import Qt.labs.folderlistmodel

import Quickshell.Io 0.0

Item {
    id: root

    property var theme
    property var settings
    property bool active: true

    signal requestClose()

    implicitWidth: 520
    implicitHeight: 420

    property int sectionIndex: 0 // 0 = General, 1 = Wallpapers, 2 = System

    // Accent is static (no dynamic wallpaper colors).

    property int cpuPct: 0
    property int ramPct: 0
    property int diskPct: 0
    property int gpuPct: -1
    property string diskLabel: "/"
    property int _cpuPrevTotal: -1
    property int _cpuPrevIdle: -1
    property var cpuHist: ([] )
    property var gpuHist: ([] )
    property var ramHist: ([] )
    property var diskHist: ([] )
    readonly property int historyMax: 80

    function _clampPct(v) {
        const n = parseInt(v, 10)
        if (!isFinite(n)) return 0
        return Math.max(0, Math.min(100, n))
    }

    function _setPct(prop, v) {
        root[prop] = _clampPct(v)
    }

    function _appendHistory(prop, v) {
        const arr = (root[prop] ?? ([] ))
        const next = arr.concat([v]).slice(-root.historyMax)
        root[prop] = next
    }

    function refreshSystemStats() {
        if (!root.active) return
        if (sysGet.running) return
        sysOut.waitForEnd = true
        sysErr.waitForEnd = true
        sysGet.command = ["sh", "-lc",
            // Outputs:
            // CPU_TOTAL_IDLE="<total> <idle>"
            // MEM_KB="<totalKb> <availKb>"
            // DISK_KB="<totalKb> <usedKb>"
            // GPU_PCT="<util>" (optional)
            "awk '/^cpu /{print \"CPU_TOTAL_IDLE=\" ($2+$3+$4+$5+$6+$7+$8+$9) \" \" $5; exit}' /proc/stat 2>/dev/null; " +
            "awk 'BEGIN{t=0;a=0} /MemTotal/{t=$2} /MemAvailable/{a=$2} END{print \"MEM_KB=\" t \" \" a}' /proc/meminfo 2>/dev/null; " +
            "df -P / 2>/dev/null | awk 'NR==2{print \"DISK_KB=\" $2 \" \" $3}'; " +
            "gpu=\"\"; for f in /sys/class/drm/card*/device/gpu_busy_percent; do [ -r \"$f\" ] && gpu=$(cat \"$f\" 2>/dev/null) && break; done; " +
            "if [ -z \"$gpu\" ] && command -v nvidia-smi >/dev/null 2>&1; then gpu=$(nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits 2>/dev/null | head -n1); fi; " +
            "echo \"GPU_PCT=$gpu\""
        ]
        sysGet.running = true
    }

    StdioCollector { id: sysOut; waitForEnd: true }
    StdioCollector { id: sysErr; waitForEnd: true }

    Process {
        id: sysGet
        stdout: sysOut
        stderr: sysErr
        onExited: function(exitCode, exitStatus) {
            sysGet.running = false
            const raw = ((sysOut.text ?? "") + "\n" + (sysErr.text ?? "")).trim()
            if (exitCode !== 0 || raw.length === 0) return

            const lines = raw.split("\n").map(s => s.trim()).filter(s => s.length > 0)
            const kv = ({})
            for (const line of lines) {
                const idx = line.indexOf("=")
                if (idx === -1) continue
                kv[line.slice(0, idx)] = line.slice(idx + 1).trim()
            }

            const cpuParts = (kv.CPU_TOTAL_IDLE ?? "").split(/\s+/).filter(Boolean)
            if (cpuParts.length >= 2) {
                const total = parseInt(cpuParts[0], 10)
                const idle = parseInt(cpuParts[1], 10)
                if (isFinite(total) && isFinite(idle)) {
                    if (root._cpuPrevTotal >= 0 && root._cpuPrevIdle >= 0) {
                        const dTotal = total - root._cpuPrevTotal
                        const dIdle = idle - root._cpuPrevIdle
                        if (dTotal > 0 && dIdle >= 0) {
                            const used = Math.round((1 - (dIdle / dTotal)) * 100)
                            root.cpuPct = root._clampPct(used)
                            root._appendHistory("cpuHist", root.cpuPct)
                        }
                    }
                    root._cpuPrevTotal = total
                    root._cpuPrevIdle = idle
                }
            }

            const memParts = (kv.MEM_KB ?? "").split(/\s+/).filter(Boolean)
            if (memParts.length >= 2) {
                const totalKb = parseInt(memParts[0], 10)
                const availKb = parseInt(memParts[1], 10)
                if (isFinite(totalKb) && totalKb > 0 && isFinite(availKb) && availKb >= 0) {
                    root.ramPct = root._clampPct(Math.round((1 - (availKb / totalKb)) * 100))
                    root._appendHistory("ramHist", root.ramPct)
                }
            }

            const diskParts = (kv.DISK_KB ?? "").split(/\s+/).filter(Boolean)
            if (diskParts.length >= 2) {
                const totalKb = parseInt(diskParts[0], 10)
                const usedKb = parseInt(diskParts[1], 10)
                if (isFinite(totalKb) && totalKb > 0 && isFinite(usedKb) && usedKb >= 0) {
                    root.diskPct = root._clampPct(Math.round((usedKb / totalKb) * 100))
                    root._appendHistory("diskHist", root.diskPct)
                }
            }

            const gpuRaw = (kv.GPU_PCT ?? "").trim()
            if (gpuRaw.length === 0) {
                root.gpuPct = -1
                root._appendHistory("gpuHist", -1)
            } else {
                const g = parseInt(gpuRaw, 10)
                root.gpuPct = isFinite(g) ? root._clampPct(g) : -1
                root._appendHistory("gpuHist", root.gpuPct)
            }
        }
    }

    Timer {
        id: sysPoll
        interval: 1500
        repeat: true
        running: root.active && root.sectionIndex === 2
        triggeredOnStart: true
        onTriggered: root.refreshSystemStats()
    }

    onSectionIndexChanged: if (root.active && root.sectionIndex === 2) root.refreshSystemStats()

    function stepInt(key, cur, delta, minVal, maxVal) {
        const next = Math.max(minVal, Math.min(maxVal, Math.round(cur + delta)))
        const obj = ({})
        obj[key] = next
        root.settings.save(obj)
    }

    function stepReal(key, cur, delta, minVal, maxVal) {
        const next = Math.max(minVal, Math.min(maxVal, Math.round((cur + delta) * 100) / 100))
        const obj = ({})
        obj[key] = next
        root.settings.save(obj)
    }

	    Rectangle {
	        anchors.fill: parent
	        radius: 22
	        color: Qt.rgba(0.08, 0.08, 0.08, 0.97)
	        border.width: 1
	        border.color: Qt.rgba(root.theme.outline.r, root.theme.outline.g, root.theme.outline.b, 0.35)
	    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 14

	                        RowLayout {
	                            Layout.fillWidth: true
	                            spacing: 10

            Text {
                text: "Settings"
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
                    // Nerd Font Material Design: nf-md-close (f0156)
                    symbol: String.fromCodePoint(0xF0156)
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

        // Section tabs
        Rectangle {
            Layout.fillWidth: true
            height: 36
            radius: 14
            color: Qt.rgba(root.theme.surfaceAlt.r, root.theme.surfaceAlt.g, root.theme.surfaceAlt.b, 0.75)

            RowLayout {
                anchors.fill: parent
                anchors.margins: 4
                spacing: 4

                Rectangle {
                    Layout.fillWidth: true
                    height: 28
                    radius: 12
                    color: root.sectionIndex === 0
                        ? Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.92)
                        : "transparent"
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.sectionIndex = 0 }
                    Text {
                        anchors.centerIn: parent
                        text: "General"
                        color: root.sectionIndex === 0 ? root.theme.onAccent : root.theme.text
                        font.family: root.theme.fontFamily
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 28
                    radius: 12
                    color: root.sectionIndex === 1
                        ? Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.92)
                        : "transparent"
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.sectionIndex = 1 }
                    Text {
                        anchors.centerIn: parent
                        text: "Wallpapers"
                        color: root.sectionIndex === 1 ? root.theme.onAccent : root.theme.text
                        font.family: root.theme.fontFamily
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 28
                    radius: 12
                    color: root.sectionIndex === 2
                        ? Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.92)
                        : "transparent"
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.sectionIndex = 2 }
                    Text {
                        anchors.centerIn: parent
                        text: "System"
                        color: root.sectionIndex === 2 ? root.theme.onAccent : root.theme.text
                        font.family: root.theme.fontFamily
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                    }
                }
            }
        }

        StackLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: root.sectionIndex

            // General
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Flickable {
                    anchors.fill: parent
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    contentWidth: width
                    contentHeight: generalContent.implicitHeight

                    ColumnLayout {
                        id: generalContent
                        width: parent.width
                        spacing: 14

                    // Top bar
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        Text {
                            text: "Top bar"
                            color: root.theme.textMuted
                            font.family: root.theme.fontFamily
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10

                            Text {
                                text: "Top margin"
                                color: root.theme.text
                                font.family: root.theme.fontFamily
                                font.pixelSize: 12
                                Layout.fillWidth: true
                            }

                            Rectangle {
                                width: 44
                                height: 30
                                radius: 12
                                color: Qt.rgba(root.theme.surfaceAlt.r, root.theme.surfaceAlt.g, root.theme.surfaceAlt.b, 0.95)
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.stepInt("pillTopMargin", root.settings.pillTopMargin, -1, 0, 40) }
                                Text { anchors.centerIn: parent; text: "–"; color: root.theme.text; font.pixelSize: 16; font.family: root.theme.fontFamily }
                            }

                            Text {
                                text: "" + root.settings.pillTopMargin
                                color: root.theme.text
                                font.family: root.theme.fontFamily
                                font.pixelSize: 12
                                width: 34
                                horizontalAlignment: Text.AlignHCenter
                            }

                            Rectangle {
                                width: 44
                                height: 30
                                radius: 12
                                color: Qt.rgba(root.theme.surfaceAlt.r, root.theme.surfaceAlt.g, root.theme.surfaceAlt.b, 0.95)
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.stepInt("pillTopMargin", root.settings.pillTopMargin, 1, 0, 40) }
                                Text { anchors.centerIn: parent; text: "+"; color: root.theme.text; font.pixelSize: 16; font.family: root.theme.fontFamily }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10

                            Text {
                                text: "Height"
                                color: root.theme.text
                                font.family: root.theme.fontFamily
                                font.pixelSize: 12
                                Layout.fillWidth: true
                            }

                            Rectangle {
                                width: 44
                                height: 30
                                radius: 12
                                color: Qt.rgba(root.theme.surfaceAlt.r, root.theme.surfaceAlt.g, root.theme.surfaceAlt.b, 0.95)
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.stepInt("pillHeight", root.settings.pillHeight, -1, 24, 60) }
                                Text { anchors.centerIn: parent; text: "–"; color: root.theme.text; font.pixelSize: 16; font.family: root.theme.fontFamily }
                            }

                            Text {
                                text: "" + root.settings.pillHeight
                                color: root.theme.text
                                font.family: root.theme.fontFamily
                                font.pixelSize: 12
                                width: 34
                                horizontalAlignment: Text.AlignHCenter
                            }

                            Rectangle {
                                width: 44
                                height: 30
                                radius: 12
                                color: Qt.rgba(root.theme.surfaceAlt.r, root.theme.surfaceAlt.g, root.theme.surfaceAlt.b, 0.95)
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.stepInt("pillHeight", root.settings.pillHeight, 1, 24, 60) }
                                Text { anchors.centerIn: parent; text: "+"; color: root.theme.text; font.pixelSize: 16; font.family: root.theme.fontFamily }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10

                            Text {
                                text: "Time format"
                                color: root.theme.text
                                font.family: root.theme.fontFamily
                                font.pixelSize: 12
                                Layout.fillWidth: true
                            }

                            Rectangle {
                                width: 140
                                height: 30
                                radius: 12
                                color: Qt.rgba(root.theme.surfaceAlt.r, root.theme.surfaceAlt.g, root.theme.surfaceAlt.b, 0.75)

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: 3
                                    spacing: 3

                                    Rectangle {
                                        Layout.fillWidth: true
                                        height: 24
                                        radius: 10
                                        color: !root.settings.time24h
                                            ? Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.92)
                                            : "transparent"
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.settings.save(({ time24h: false }))
                                        }
                                        Text {
                                            anchors.centerIn: parent
                                            text: "12h"
                                            color: !root.settings.time24h ? root.theme.onAccent : root.theme.text
                                            font.family: root.theme.fontFamily
                                            font.pixelSize: 11
                                            font.weight: Font.DemiBold
                                        }
                                    }

                                    Rectangle {
                                        Layout.fillWidth: true
                                        height: 24
                                        radius: 10
                                        color: root.settings.time24h
                                            ? Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.92)
                                            : "transparent"
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.settings.save(({ time24h: true }))
                                        }
                                        Text {
                                            anchors.centerIn: parent
                                            text: "24h"
                                            color: root.settings.time24h ? root.theme.onAccent : root.theme.text
                                            font.family: root.theme.fontFamily
                                            font.pixelSize: 11
                                            font.weight: Font.DemiBold
                                        }
                                    }
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10

                            Text {
                                text: "Horizontal padding"
                                color: root.theme.text
                                font.family: root.theme.fontFamily
                                font.pixelSize: 12
                                Layout.fillWidth: true
                            }

                            Rectangle {
                                width: 44
                                height: 30
                                radius: 12
                                color: Qt.rgba(root.theme.surfaceAlt.r, root.theme.surfaceAlt.g, root.theme.surfaceAlt.b, 0.95)
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.stepInt("pillHPadding", root.settings.pillHPadding, -2, -1, 80) }
                                Text { anchors.centerIn: parent; text: "–"; color: root.theme.text; font.pixelSize: 16; font.family: root.theme.fontFamily }
                            }

                            Text {
                                text: "" + root.settings.pillHPadding
                                color: root.theme.text
                                font.family: root.theme.fontFamily
                                font.pixelSize: 12
                                width: 34
                                horizontalAlignment: Text.AlignHCenter
                            }

                            Rectangle {
                                width: 44
                                height: 30
                                radius: 12
                                color: Qt.rgba(root.theme.surfaceAlt.r, root.theme.surfaceAlt.g, root.theme.surfaceAlt.b, 0.95)
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.stepInt("pillHPadding", root.settings.pillHPadding, 2, -1, 80) }
                                Text { anchors.centerIn: parent; text: "+"; color: root.theme.text; font.pixelSize: 16; font.family: root.theme.fontFamily }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10

                            Text {
                                text: "Opacity"
                                color: root.theme.text
                                font.family: root.theme.fontFamily
                                font.pixelSize: 12
                                Layout.fillWidth: true
                            }

                            Rectangle {
                                width: 44
                                height: 30
                                radius: 12
                                color: Qt.rgba(root.theme.surfaceAlt.r, root.theme.surfaceAlt.g, root.theme.surfaceAlt.b, 0.95)
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.stepReal("pillOpacity", root.settings.pillOpacity, -0.05, 0.15, 1.0) }
                                Text { anchors.centerIn: parent; text: "–"; color: root.theme.text; font.pixelSize: 16; font.family: root.theme.fontFamily }
                            }

                            Text {
                                text: Math.round(root.settings.pillOpacity * 100) + "%"
                                color: root.theme.text
                                font.family: root.theme.fontFamily
                                font.pixelSize: 12
                                width: 52
                                horizontalAlignment: Text.AlignHCenter
                            }

                            Rectangle {
                                width: 44
                                height: 30
                                radius: 12
                                color: Qt.rgba(root.theme.surfaceAlt.r, root.theme.surfaceAlt.g, root.theme.surfaceAlt.b, 0.95)
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.stepReal("pillOpacity", root.settings.pillOpacity, 0.05, 0.15, 1.0) }
                                Text { anchors.centerIn: parent; text: "+"; color: root.theme.text; font.pixelSize: 16; font.family: root.theme.fontFamily }
                            }
	                        }
	                    }

	                    // Idle (hypridle)
	                    ColumnLayout {
	                        Layout.fillWidth: true
	                        spacing: 10

	                        Text {
	                            text: "Idle"
	                            color: root.theme.textMuted
	                            font.family: root.theme.fontFamily
	                            font.pixelSize: 11
	                            font.weight: Font.DemiBold
	                        }

	                        RowLayout {
	                            Layout.fillWidth: true
	                            spacing: 10

		                            Text {
		                                text: "Screen off after"
	                                color: root.theme.text
	                                font.family: root.theme.fontFamily
	                                font.pixelSize: 12
	                                Layout.fillWidth: true
	                            }

		                            Text {
		                                text: Math.round(root.settings.idleScreenOffSeconds) + "s"
	                                color: root.theme.textMuted
	                                font.family: root.theme.fontFamily
	                                font.pixelSize: 12
	                                font.weight: Font.DemiBold
	                            }

	                            Rectangle {
	                                width: 44
	                                height: 30
	                                radius: 12
	                                color: Qt.rgba(root.theme.surfaceAlt.r, root.theme.surfaceAlt.g, root.theme.surfaceAlt.b, 0.95)
		                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { root.stepInt("idleScreenOffSeconds", root.settings.idleScreenOffSeconds, -15, 0, 7200); root.settings.applyIdle() } }
	                                Text { anchors.centerIn: parent; text: "–"; color: root.theme.text; font.pixelSize: 16; font.family: root.theme.fontFamily }
	                            }

	                            Rectangle {
	                                width: 44
	                                height: 30
	                                radius: 12
	                                color: Qt.rgba(root.theme.surfaceAlt.r, root.theme.surfaceAlt.g, root.theme.surfaceAlt.b, 0.95)
		                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { root.stepInt("idleScreenOffSeconds", root.settings.idleScreenOffSeconds, 15, 0, 7200); root.settings.applyIdle() } }
	                                Text { anchors.centerIn: parent; text: "+"; color: root.theme.text; font.pixelSize: 16; font.family: root.theme.fontFamily }
	                            }
	                        }

	                        RowLayout {
	                            Layout.fillWidth: true
	                            spacing: 10

	                            Text {
	                                text: "Sleep after"
	                                color: root.theme.text
	                                font.family: root.theme.fontFamily
	                                font.pixelSize: 12
	                                Layout.fillWidth: true
	                            }

	                            Text {
	                                text: Math.round(root.settings.idleSleepSeconds) + "s"
	                                color: root.theme.textMuted
	                                font.family: root.theme.fontFamily
	                                font.pixelSize: 12
	                                font.weight: Font.DemiBold
	                            }

	                            Rectangle {
	                                width: 44
	                                height: 30
	                                radius: 12
	                                color: Qt.rgba(root.theme.surfaceAlt.r, root.theme.surfaceAlt.g, root.theme.surfaceAlt.b, 0.95)
	                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { root.stepInt("idleSleepSeconds", root.settings.idleSleepSeconds, -60, 0, 14400); root.settings.applyIdle() } }
	                                Text { anchors.centerIn: parent; text: "–"; color: root.theme.text; font.pixelSize: 16; font.family: root.theme.fontFamily }
	                            }

	                            Rectangle {
	                                width: 44
	                                height: 30
	                                radius: 12
	                                color: Qt.rgba(root.theme.surfaceAlt.r, root.theme.surfaceAlt.g, root.theme.surfaceAlt.b, 0.95)
	                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { root.stepInt("idleSleepSeconds", root.settings.idleSleepSeconds, 60, 0, 14400); root.settings.applyIdle() } }
	                                Text { anchors.centerIn: parent; text: "+"; color: root.theme.text; font.pixelSize: 16; font.family: root.theme.fontFamily }
	                            }
	                        }

		                        // (No dim level for DPMS off)
	                    }

	                    // Nightlight (wlsunset)
	                    ColumnLayout {
	                        Layout.fillWidth: true
	                        spacing: 10

	                        Text {
	                            text: "Nightlight"
	                            color: root.theme.textMuted
	                            font.family: root.theme.fontFamily
	                            font.pixelSize: 11
	                            font.weight: Font.DemiBold
	                        }

	                        RowLayout {
	                            Layout.fillWidth: true
	                            spacing: 10

	                            Text {
	                                text: "Day temp"
	                                color: root.theme.text
	                                font.family: root.theme.fontFamily
	                                font.pixelSize: 12
	                                Layout.fillWidth: true
	                            }

	                            Text {
	                                text: Math.round(root.settings.nightlightTempDay) + "K"
	                                color: root.theme.textMuted
	                                font.family: root.theme.fontFamily
	                                font.pixelSize: 12
	                                font.weight: Font.DemiBold
	                            }

	                            Rectangle {
	                                width: 44
	                                height: 30
	                                radius: 12
	                                color: Qt.rgba(root.theme.surfaceAlt.r, root.theme.surfaceAlt.g, root.theme.surfaceAlt.b, 0.95)
	                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.stepInt("nightlightTempDay", root.settings.nightlightTempDay, -100, 2000, 6500) }
	                                Text { anchors.centerIn: parent; text: "–"; color: root.theme.text; font.pixelSize: 16; font.family: root.theme.fontFamily }
	                            }

	                            Rectangle {
	                                width: 44
	                                height: 30
	                                radius: 12
	                                color: Qt.rgba(root.theme.surfaceAlt.r, root.theme.surfaceAlt.g, root.theme.surfaceAlt.b, 0.95)
	                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.stepInt("nightlightTempDay", root.settings.nightlightTempDay, 100, 2000, 6500) }
	                                Text { anchors.centerIn: parent; text: "+"; color: root.theme.text; font.pixelSize: 16; font.family: root.theme.fontFamily }
	                            }
	                        }

	                        RowLayout {
	                            Layout.fillWidth: true
	                            spacing: 10

	                            Text {
	                                text: "Night temp"
	                                color: root.theme.text
	                                font.family: root.theme.fontFamily
	                                font.pixelSize: 12
	                                Layout.fillWidth: true
	                            }

	                            Text {
	                                text: Math.round(root.settings.nightlightTempNight) + "K"
	                                color: root.theme.textMuted
	                                font.family: root.theme.fontFamily
	                                font.pixelSize: 12
	                                font.weight: Font.DemiBold
	                            }

	                            Rectangle {
	                                width: 44
	                                height: 30
	                                radius: 12
	                                color: Qt.rgba(root.theme.surfaceAlt.r, root.theme.surfaceAlt.g, root.theme.surfaceAlt.b, 0.95)
	                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.stepInt("nightlightTempNight", root.settings.nightlightTempNight, -100, 2000, 6500) }
	                                Text { anchors.centerIn: parent; text: "–"; color: root.theme.text; font.pixelSize: 16; font.family: root.theme.fontFamily }
	                            }

	                            Rectangle {
	                                width: 44
	                                height: 30
	                                radius: 12
	                                color: Qt.rgba(root.theme.surfaceAlt.r, root.theme.surfaceAlt.g, root.theme.surfaceAlt.b, 0.95)
	                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.stepInt("nightlightTempNight", root.settings.nightlightTempNight, 100, 2000, 6500) }
	                                Text { anchors.centerIn: parent; text: "+"; color: root.theme.text; font.pixelSize: 16; font.family: root.theme.fontFamily }
	                            }
	                        }

	                        Text {
	                            visible: root.settings.nightlightTempDay <= root.settings.nightlightTempNight
	                            text: "Day temp must be higher than night temp"
	                            color: Qt.rgba(1, 0.35, 0.35, 0.9)
	                            font.family: root.theme.fontFamily
	                            font.pixelSize: 11
	                            font.weight: Font.DemiBold
	                        }
	                    }

	                    Item { Layout.fillHeight: true }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        Rectangle {
                            Layout.fillWidth: true
                            height: 40
                            radius: 14
                            color: Qt.rgba(root.theme.surfaceAlt.r, root.theme.surfaceAlt.g, root.theme.surfaceAlt.b, 0.95)
                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
	                                onClicked: root.settings.save({
	                                    pillTopMargin: 5,
	                                    pillHeight: 34,
	                                    pillHPadding: -1,
	                                    pillOpacity: 1.0,
	                                    popupGap: 10,
	                                    popupOverlap: 10,
	                                    idleScreenOffSeconds: 120,
	                                    idleSleepSeconds: 900,
	                                    nightlightTempDay: 3400,
	                                    nightlightTempNight: 3200,
	                                })
	                            }
                            Text {
                                anchors.centerIn: parent
                                text: "Reset defaults"
                                color: root.theme.text
                                font.family: root.theme.fontFamily
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                            }
                        }
                    }
                    }
                }
            }

            // Wallpapers
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                ColumnLayout {
                    id: wallpapersSection
                    anchors.fill: parent
                    spacing: 10

                    readonly property string wallpapersDir: (root.settings?.home ?? "") + "/Pictures/Wallpapers/"
                    property string selectedWallpaper: ""

	                    Text {
	                        text: "Wallpaper"
	                        color: root.theme.textMuted
	                        font.family: root.theme.fontFamily
	                        font.pixelSize: 11
	                        font.weight: Font.DemiBold
	                    }

	                    // Search
	                    Rectangle {
	                        Layout.fillWidth: true
	                        height: 36
	                        radius: 14
	                        color: Qt.rgba(root.theme.surfaceAlt.r, root.theme.surfaceAlt.g, root.theme.surfaceAlt.b, 0.75)
	                        border.width: 1
	                        border.color: Qt.rgba(root.theme.outline.r, root.theme.outline.g, root.theme.outline.b, 0.25)

	                        RowLayout {
	                            anchors.fill: parent
	                            anchors.margins: 8
	                            spacing: 8

	                            EinkSymbol {
	                                symbol: String.fromCodePoint(0xF034E) // nf-md-magnify
	                                fallbackSymbol: "search"
	                                fontFamily: root.theme.iconFontFamily
	                                fontFamilyFallback: root.theme.iconFontFamilyFallback
	                                color: root.theme.textMuted
	                                size: 16
	                                Layout.alignment: Qt.AlignVCenter
	                            }

	                            TextInput {
	                                id: wallpaperSearch
	                                Layout.fillWidth: true
	                                focus: true
	                                color: root.theme.text
	                                font.family: root.theme.fontFamily
	                                font.pixelSize: 12
	                                clip: true
	                                selectByMouse: true
	                                onTextChanged: wallpapersModel.nameFilters = [
	                                    "*" + text + "*.png",
	                                    "*" + text + "*.jpg",
	                                    "*" + text + "*.jpeg",
	                                    "*" + text + "*.webp",
	                                    "*" + text + "*.PNG",
	                                    "*" + text + "*.JPG",
	                                    "*" + text + "*.JPEG",
	                                    "*" + text + "*.WEBP",
	                                ]
	                            }

	                            Text {
	                                visible: wallpaperSearch.text.length === 0 && !wallpaperSearch.activeFocus
	                                text: "Search wallpapers…"
	                                color: Qt.rgba(root.theme.textMuted.r, root.theme.textMuted.g, root.theme.textMuted.b, 0.9)
	                                font.family: root.theme.fontFamily
	                                font.pixelSize: 12
	                                elide: Text.ElideRight
	                                Layout.fillWidth: true
	                                Layout.alignment: Qt.AlignVCenter
	                                MouseArea {
	                                    anchors.fill: parent
	                                    cursorShape: Qt.IBeamCursor
	                                    onClicked: wallpaperSearch.forceActiveFocus()
	                                }
	                            }
	                        }
	                    }

	                    FolderListModel {
	                        id: wallpapersModel
	                        // FolderListModel expects a file URL. Build a stable `file:///.../` URL.
	                        folder: "file:///" + String(wallpapersSection.wallpapersDir).split("/").filter(s => s.length > 0).join("/") + "/"
	                        nameFilters: ["*.png", "*.jpg", "*.jpeg", "*.webp", "*.PNG", "*.JPG", "*.JPEG", "*.WEBP"]
	                        showDirs: false
	                        showDotAndDotDot: false
	                        sortField: FolderListModel.Name
	                        sortReversed: false
	                    }

                    Text {
                        visible: wallpapersModel.count === 0
                        text: "No images found in " + wallpapersSection.wallpapersDir
                        color: root.theme.textMuted
                        font.family: root.theme.fontFamily
                        font.pixelSize: 12
                    }

		                    GridView {
	                        Layout.fillWidth: true
	                        Layout.fillHeight: true
	                        visible: wallpapersModel.count > 0
	                        clip: true
	                        // Fit an integer number of columns to remove leftover right-side space.
	                        readonly property int cols: Math.max(2, Math.floor(width / 160))
	                        cellWidth: Math.floor(width / cols)
	                        cellHeight: 96
	                        model: wallpapersModel

		                        delegate: Rectangle {
	                            width: GridView.view.cellWidth - 10
	                            height: 86
	                            x: Math.round((GridView.view.cellWidth - width) / 2)
	                            radius: 14
	                            color: Qt.rgba(root.theme.surfaceAlt.r, root.theme.surfaceAlt.g, root.theme.surfaceAlt.b, 0.85)
                            border.width: (wallpapersSection.selectedWallpaper === filePath) ? 2 : 1
                            border.color: (wallpapersSection.selectedWallpaper === filePath)
                                ? root.theme.accent
                                : Qt.rgba(root.theme.outline.r, root.theme.outline.g, root.theme.outline.b, 0.35)

	                            Image {
	                                anchors.fill: parent
	                                anchors.margins: 6
	                                source: "file://" + filePath
	                                fillMode: Image.PreserveAspectCrop
	                                asynchronous: true
	                                cache: true
	                                smooth: false
	                                mipmap: false
	                                sourceSize.width: 240
	                                sourceSize.height: 140
	                                clip: true
	                            }

	                            MouseArea {
	                                anchors.fill: parent
	                                hoverEnabled: true
	                                cursorShape: Qt.PointingHandCursor
	                                onClicked: {
	                                    wallpapersSection.selectedWallpaper = filePath
	                                    root.settings.applyWallpaper(filePath)
	                                    console.warn("wallpaper: applied", filePath)
	                                }
	                            }
                        }
                    }
                }
            }

            // System
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                component UsageChart: Rectangle {
                    id: chart
                    property string title: ""
                    property string valueText: ""
                    property var values: ([] )
                    radius: 16
                    color: Qt.rgba(root.theme.surfaceAlt.r, root.theme.surfaceAlt.g, root.theme.surfaceAlt.b, 0.75)
                    border.width: 1
                    border.color: Qt.rgba(root.theme.outline.r, root.theme.outline.g, root.theme.outline.b, 0.22)

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 10

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            Text {
                                text: chart.title
                                color: root.theme.text
                                font.family: root.theme.fontFamily
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                                Layout.fillWidth: true
                            }
                            Text {
                                text: chart.valueText
                                color: root.theme.textMuted
                                font.family: root.theme.fontFamily
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                                horizontalAlignment: Text.AlignRight
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            radius: 12
                            color: Qt.rgba(0, 0, 0, 0.10)
                            border.width: 1
                            border.color: Qt.rgba(root.theme.outline.r, root.theme.outline.g, root.theme.outline.b, 0.18)

                            Canvas {
                                id: canvas
                                anchors.fill: parent
                                anchors.margins: 8

                                Connections {
                                    target: chart
                                    function onValuesChanged() {
                                        canvas.requestPaint()
                                    }
                                }

                                onPaint: {
                                    const ctx = getContext("2d")
                                    ctx.clearRect(0, 0, width, height)

                                    const vals = chart.values ?? []
                                    if (!vals.length) return

                                    // grid
                                    ctx.strokeStyle = "rgba(255,255,255,0.06)"
                                    ctx.lineWidth = 1
                                    for (let i = 1; i <= 3; i++) {
                                        const y = Math.round((height * i) / 4)
                                        ctx.beginPath()
                                        ctx.moveTo(0, y)
                                        ctx.lineTo(width, y)
                                        ctx.stroke()
                                    }

                                    const accent = Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 1)
                                    ctx.strokeStyle = accent
                                    ctx.lineWidth = 2
                                    ctx.lineJoin = "round"
                                    ctx.lineCap = "round"

                                    const xStep = width / Math.max(1, (vals.length - 1))
                                    let started = false
                                    ctx.beginPath()
                                    for (let i = 0; i < vals.length; i++) {
                                        const v = vals[i]
                                        if (typeof v !== "number" || !isFinite(v) || v < 0) {
                                            started = false
                                            continue
                                        }
                                        const x = i * xStep
                                        const y = height - (Math.max(0, Math.min(100, v)) / 100) * height
                                        if (!started) {
                                            ctx.moveTo(x, y)
                                            started = true
                                        } else {
                                            ctx.lineTo(x, y)
                                        }
                                    }
                                    ctx.stroke()
                                }
                            }
                        }
                    }
                }

                Flickable {
                    anchors.fill: parent
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    contentWidth: width
                    contentHeight: sysContent.implicitHeight

                    ColumnLayout {
                        id: sysContent
                        width: parent.width
                        spacing: 14

                        Text {
                            text: "System monitor"
                            color: root.theme.textMuted
                            font.family: root.theme.fontFamily
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 10
                            GridLayout {
                                Layout.fillWidth: true
                                columns: 2
                                columnSpacing: 10
                                rowSpacing: 10

                                UsageChart {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 140
                                    title: "CPU"
                                    valueText: root.cpuPct + "%"
                                    values: root.cpuHist
                                }

                                UsageChart {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 140
                                    title: "GPU"
                                    valueText: (root.gpuPct < 0) ? "N/A" : (root.gpuPct + "%")
                                    values: root.gpuHist
                                }

                                UsageChart {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 140
                                    title: "RAM"
                                    valueText: root.ramPct + "%"
                                    values: root.ramHist
                                }

                                UsageChart {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 140
                                    title: "Disk " + root.diskLabel
                                    valueText: root.diskPct + "%"
                                    values: root.diskHist
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
