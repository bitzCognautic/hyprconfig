import QtQuick
import QtQuick.Layouts

import Quickshell
import Quickshell.Hyprland._Ipc 0.0
import Quickshell.Io 0.0
import Quickshell.Networking 0.0
import Quickshell.Services.Pipewire 0.0
import Quickshell.Services.UPower 0.0
import Quickshell.Wayland._WlrLayerShell 0.0


Item {
    id: root

    EinkSettings { id: settings }
    Theme { id: theme }

    // Derived state (kept simple + robust; polling avoids model change edge cases)
    property string ssid: ""
    property int wifiSignalPct: 0
    property int volumePct: 0
    property int brightnessPct: 0
    property bool recordingOn: false
    property bool muted: false
    property bool muteTogglePending: false
    property int muteToggleAttempts: 0
    property bool preferWpctl: true
    readonly property string wpctlPath: "/usr/sbin/wpctl"
    property bool wpctlEverWorked: false
    property bool haveBrightnessctl: true
    property bool quickSettingsOpen: false
    property bool settingsOpen: false
    property bool wifiDetailsOpen: false
    property bool bluetoothDetailsOpen: false
    property bool powerOpen: false
    property bool recordOpen: false
    property real quickSettingsAnim: 0
    property real settingsAnim: 0
    property real wifiAnim: 0
    property real bluetoothAnim: 0
    property real powerAnim: 0
    property real recordAnim: 0
    readonly property int popupGap: settings.popupGap
    readonly property int popupOverlap: settings.popupOverlap
    readonly property int pillHPaddingPx: (settings.pillHPadding < 0) ? 0 : settings.pillHPadding

    Behavior on quickSettingsAnim {
        NumberAnimation {
            duration: 180
            easing.type: Easing.OutCubic
        }
    }

    onQuickSettingsOpenChanged: quickSettingsAnim = quickSettingsOpen ? 1 : 0

    Behavior on settingsAnim {
        NumberAnimation {
            duration: 180
            easing.type: Easing.OutCubic
        }
    }

    Behavior on wifiAnim {
        NumberAnimation {
            duration: 180
            easing.type: Easing.OutCubic
        }
    }

    Behavior on bluetoothAnim {
        NumberAnimation {
            duration: 180
            easing.type: Easing.OutCubic
        }
    }

    Behavior on powerAnim {
        NumberAnimation {
            duration: 180
            easing.type: Easing.OutCubic
        }
    }

    Behavior on recordAnim {
        NumberAnimation {
            duration: 180
            easing.type: Easing.OutCubic
        }
    }

    onSettingsOpenChanged: settingsAnim = settingsOpen ? 1 : 0
    onWifiDetailsOpenChanged: wifiAnim = wifiDetailsOpen ? 1 : 0
    onBluetoothDetailsOpenChanged: bluetoothAnim = bluetoothDetailsOpen ? 1 : 0
    onPowerOpenChanged: powerAnim = powerOpen ? 1 : 0
    onRecordOpenChanged: recordAnim = recordOpen ? 1 : 0

    StdioCollector {
        id: wpctlGetOut
        waitForEnd: true
    }

    StdioCollector {
        id: wpctlGetErr
        waitForEnd: true
    }

    Process {
        id: wpctlGet
        stdout: wpctlGetOut
        stderr: wpctlGetErr
        onExited: function(exitCode, exitStatus) {
            wpctlGet.running = false
            const raw = ((wpctlGetOut.text ?? "").trim() || (wpctlGetErr.text ?? "").trim())
            wpctlGetOut.waitForEnd = true
            wpctlGetErr.waitForEnd = true

            if (exitCode !== 0 || raw.length === 0) {
                if (!root.wpctlEverWorked) console.warn("wpctl get-volume failed", exitCode, raw)
                root.refreshAudioViaPipewire()
                return
            }

            const parsed = root.parseWpctlGetVolume(raw)
            if (!parsed) {
                if (!root.wpctlEverWorked) console.warn("wpctl get-volume parse failed:", raw)
                return
            }
            root.wpctlEverWorked = true
            root.muted = parsed.muted
            root.volumePct = parsed.volumePct
        }
    }

    StdioCollector {
        id: wpctlMuteOut
        waitForEnd: true
    }

    StdioCollector {
        id: wpctlMuteErr
        waitForEnd: true
    }

    Process {
        id: wpctlMute
        stdout: wpctlMuteOut
        stderr: wpctlMuteErr
        onExited: function(exitCode, exitStatus) {
            wpctlMute.running = false
            if (exitCode !== 0) {
                console.warn("wpctl set-mute failed", exitCode, ((wpctlMuteOut.text ?? "").trim() || (wpctlMuteErr.text ?? "").trim()))
                return
            }
            root.refreshAudio()
        }
    }

    StdioCollector {
        id: wpctlSetVolErr
        waitForEnd: true
    }

    StdioCollector {
        id: wpctlSetVolOut
        waitForEnd: true
    }

    Process {
        id: wpctlSetVol
        stdout: wpctlSetVolOut
        stderr: wpctlSetVolErr
        onExited: function(exitCode, exitStatus) {
            wpctlSetVol.running = false
            if (exitCode !== 0) {
                console.warn("wpctl set-volume failed", exitCode, ((wpctlSetVolOut.text ?? "").trim() || (wpctlSetVolErr.text ?? "").trim()))
                return
            }
            root.refreshAudio()
        }
    }

    StdioCollector {
        id: brightnessGetOut
        waitForEnd: true
    }

    StdioCollector {
        id: brightnessGetErr
        waitForEnd: true
    }

    Process {
        id: brightnessGet
        stdout: brightnessGetOut
        stderr: brightnessGetErr
        onExited: function(exitCode, exitStatus) {
            brightnessGet.running = false
            const raw = ((brightnessGetOut.text ?? "").trim() || (brightnessGetErr.text ?? "").trim())
            brightnessGetOut.waitForEnd = true
            brightnessGetErr.waitForEnd = true

            if (exitCode !== 0 || raw.length === 0) {
                root.haveBrightnessctl = false
                return
            }

            // Expected: "CUR=123 MAX=456"
            const mCur = raw.match(/CUR\\s*=\\s*(\\d+)/i)
            const mMax = raw.match(/MAX\\s*=\\s*(\\d+)/i)
            if (!mCur || !mMax) return
            const cur = parseInt(mCur[1], 10)
            const max = parseInt(mMax[1], 10)
            if (!isFinite(cur) || !isFinite(max) || max <= 0) return
            root.haveBrightnessctl = true
            root.brightnessPct = Math.max(0, Math.min(100, Math.round((cur / max) * 100)))
        }
    }

    StdioCollector { id: brightnessSetOut; waitForEnd: true }
    StdioCollector { id: brightnessSetErr; waitForEnd: true }

    Process {
        id: brightnessSet
        stdout: brightnessSetOut
        stderr: brightnessSetErr
        onExited: function(exitCode, exitStatus) {
            brightnessSet.running = false
            if (exitCode !== 0) {
                root.haveBrightnessctl = false
                console.warn("brightnessctl set failed", exitCode, ((brightnessSetOut.text ?? "").trim() || (brightnessSetErr.text ?? "").trim()))
                return
            }
            root.refreshBrightness()
        }
    }

    function wsOccupied(wsId) {
        try {
            const list = Hyprland.workspaces?.values ?? []
            for (const w of list) {
                if (w && w.id === wsId) return true
            }
            return false
        } catch (e) {
            return false
        }
    }

    function refreshNetworking() {
        try {
            let best = ""
            let strength = 0
            const devs = Networking.devices?.values ?? []
            if (devs.length === 0) {
                root.ssid = ""
                root.wifiSignalPct = 0
                return
            }

            for (const d of devs) {
                if (!d || d.type !== DeviceType.Wifi) continue
                const nets = d.networks?.values ?? []
                for (const n of nets) {
                    if (n && n.connected && n.name) {
                        best = n.name
                        let s = n.signalStrength ?? 0
                        if (typeof s === "number" && isFinite(s)) {
                            if (s <= 1.0) s = s * 100
                            strength = Math.max(0, Math.min(100, Math.round(s)))
                        } else {
                            strength = 0
                        }
                        break
                    }
                }
                if (best) break
            }
            root.ssid = best
            root.wifiSignalPct = strength
        } catch (e) {
            root.ssid = ""
            root.wifiSignalPct = 0
        }
    }

    function wifiLevelFromPct(pct) {
        if (pct >= 67) return 3
        if (pct >= 34) return 2
        return 1
    }

    function wifiGlyph(level) {
        // Nerd Font Material Design Icons:
        // nf-md-wifi_strength_1 (f091f)
        // nf-md-wifi_strength_2 (f0922)
        // nf-md-wifi_strength_3 (f0925)
        const cp = (level === 3) ? 0xF0925 : (level === 2 ? 0xF0922 : 0xF091F)
        try {
            return String.fromCodePoint(cp)
        } catch (e) {
            return ""
        }
    }

    function refreshAudio() {
        try {
            if (root.preferWpctl) {
                root.refreshAudioViaWpctl()
            } else {
                root.refreshAudioViaPipewire()
            }
        } catch (e) {
            // Keep last known values if Pipewire is briefly unavailable.
        }
    }

    function refreshAudioViaWpctl() {
        if (wpctlGet.running) return
        wpctlGetOut.waitForEnd = true
        wpctlGet.command = [root.wpctlPath, "get-volume", "@DEFAULT_AUDIO_SINK@"]
        wpctlGet.running = true
    }

    function parseWpctlGetVolume(raw) {
        try {
            // Example outputs:
            //   "Volume: 0.55"
            //   "Volume: 0.55 [MUTED]"
            const lines = raw.split("\n").map(s => s.trim()).filter(Boolean)
            const last = lines.reverse().find(s => s.toLowerCase().indexOf("volume:") !== -1) ?? raw
            const muted = last.indexOf("[MUTED]") !== -1
            const m = last.match(/Volume:\s*([0-9]*\.?[0-9]+)/i)
            if (!m) return null
            const v = parseFloat(m[1])
            if (!isFinite(v)) return null
            return ({
                muted,
                volumePct: Math.max(0, Math.min(100, Math.round(v * 100))),
            })
        } catch (e) {
            return null
        }
    }

    function refreshAudioViaPipewire() {
        if (!Pipewire.ready) return

        const sink = root.pickAudioSink()
        const audio = sink?.audio
        if (!sink || !sink.ready || !audio) return

        root.muted = !!audio.muted

        let v = audio.volume
        if ((typeof v !== "number" || v <= 0) && audio.volumes && audio.volumes.length) {
            let sum = 0
            let count = 0
            for (const x of audio.volumes) {
                if (typeof x !== "number") continue
                sum += x
                count += 1
            }
            if (count > 0) v = sum / count
        }
        if (typeof v !== "number" || !isFinite(v)) return

        root.volumePct = Math.max(0, Math.min(150, Math.round(v * 100)))
    }

    function refreshBrightness() {
        if (!root.haveBrightnessctl) return
        if (brightnessGet.running) return
        brightnessGetOut.waitForEnd = true
        brightnessGetErr.waitForEnd = true
        brightnessGet.command = ["sh", "-lc", "cur=$(brightnessctl g 2>/dev/null) && max=$(brightnessctl m 2>/dev/null) && echo \"CUR=${cur} MAX=${max}\""]
        brightnessGet.running = true
    }

    function stepBrightness(deltaPct) {
        if (!root.haveBrightnessctl) return
        try {
            const step = Math.max(1, Math.min(20, Math.round(Math.abs(deltaPct))))
            const dir = deltaPct >= 0 ? "+" : "-"
            if (brightnessSet.running) return
            brightnessSet.command = ["sh", "-lc", "brightnessctl set " + step + "%" + dir + " >/dev/null 2>&1"]
            brightnessSet.running = true
        } catch (e) {
            // no-op
        }
    }

    function pickAudioSink() {
        try {
            const def = Pipewire.defaultAudioSink
            if (def && def.ready) return def

            const nodes = Pipewire.nodes?.values ?? []
            for (const n of nodes) {
                if (!n || !n.ready) continue
                if (!n.isSink) continue
                if (!n.audio) continue
                return n
            }

            return def ?? null
        } catch (e) {
            return null
        }
    }

    function tryToggleMute() {
        try {
            if (root.preferWpctl) {
                if (wpctlMute.running) return false
                wpctlMuteOut.waitForEnd = true
                wpctlMute.command = [root.wpctlPath, "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"]
                wpctlMute.running = true
                return true
            }

            if (!Pipewire.ready) return false
            const sink = root.pickAudioSink()
            const audio = sink?.audio
            if (!sink || !sink.ready || !audio) return false
            audio.muted = !audio.muted
            root.refreshAudioViaPipewire()
            return true
        } catch (e) {
            return false
        }
    }

    Connections {
        target: Pipewire
        function onReadyChanged() { root.refreshAudio() }
        function onDefaultAudioSinkChanged() { root.refreshAudio() }
    }

    function stepVolume(deltaPct) {
        try {
            const step = Math.max(1, Math.min(20, Math.round(Math.abs(deltaPct))))
            const dir = deltaPct >= 0 ? "+" : "-"
            if (wpctlSetVol.running) return
            wpctlSetVol.command = [root.wpctlPath, "set-volume", "@DEFAULT_AUDIO_SINK@", "" + step + "%" + dir]
            wpctlSetVol.running = true
        } catch (e) {
            // no-op
        }
    }

    Timer {
        id: muteToggleTimer
        interval: 120
        running: false
        repeat: true
        onTriggered: {
            if (!root.muteTogglePending) {
                stop()
                return
            }

            root.muteToggleAttempts += 1
            if (root.tryToggleMute() || root.muteToggleAttempts >= 15) {
                root.muteTogglePending = false
                stop()
            }
        }
    }

    Timer {
        interval: 2000
        running: true
        repeat: true
        onTriggered: {
            root.refreshNetworking()
            root.refreshAudio()
            root.refreshBrightness()
            root.refreshRecording()
        }
    }

    Component.onCompleted: {
        root.refreshNetworking()
        root.refreshAudio()
        root.refreshBrightness()
        root.refreshRecording()
    }

    StdioCollector { id: recOut; waitForEnd: true }
    StdioCollector { id: recErr; waitForEnd: true }

    Process {
        id: recGet
        stdout: recOut
        stderr: recErr
        onExited: function(exitCode, exitStatus) {
            recGet.running = false
            const raw = ((recOut.text ?? "").trim() || (recErr.text ?? "").trim())
            root.recordingOn = (exitCode === 0 && raw === "1")
        }
    }

    StdioCollector { id: recStopOut; waitForEnd: true }
    StdioCollector { id: recStopErr; waitForEnd: true }

    Process {
        id: recStop
        stdout: recStopOut
        stderr: recStopErr
        onExited: function(exitCode, exitStatus) {
            recStop.running = false
            // Refresh shortly after to let wf-recorder exit.
            recStopRefresh.restart()
        }
    }

    Timer {
        id: recStopRefresh
        interval: 200
        repeat: false
        onTriggered: root.refreshRecording()
    }

    function refreshRecording() {
        if (recGet.running) return
        recOut.waitForEnd = true
        recErr.waitForEnd = true
        recGet.command = ["sh", "-lc", "pgrep -x wf-recorder >/dev/null 2>&1 && echo 1 || echo 0"]
        recGet.running = true
    }

    function stopRecording() {
        if (recStop.running) return
        recStopOut.waitForEnd = true
        recStopErr.waitForEnd = true
        recStop.command = ["sh", "-lc", "pkill -INT wf-recorder >/dev/null 2>&1 || true; ~/.local/bin/eink-notify \"Recording stopped\" \"\" || true"]
        recStop.running = true
    }

    SystemClock {
        id: clock
        enabled: true
        precision: SystemClock.Minutes
    }

    WlrLayershell {
        id: barLayer

        layer: WlrLayer.Top
        keyboardFocus: WlrKeyboardFocus.None
        aboveWindows: true
        focusable: false
        // Reserve exactly up to the pill bottom (minimal gap, no overlap).
        exclusiveZone: Math.round(pill.y + pill.height)
        namespace: "eink-topbar"
        color: "transparent"

        anchors {
            top: true
            left: true
            right: true
        }

	        // Keep the layer only as tall as the pill (plus margins),
	        // so the bar feels compact and doesn't reserve extra space.
	        implicitHeight: Math.round(settings.pillTopMargin + settings.pillHeight + 4)

        Item {
            id: barLayerRoot
            anchors.fill: parent

                    Rectangle {
                        id: pill
                anchors.top: parent.top
                anchors.topMargin: settings.pillTopMargin
                anchors.horizontalCenter: parent.horizontalCenter

	                // Slightly lighter than pure black to match the theme.
	                color: Qt.rgba(0.08, 0.08, 0.08, settings.pillOpacity)
                border.width: 0
                radius: 999

                height: settings.pillHeight
                width: row.implicitWidth

		                RowLayout {
		                    id: row
		                    anchors.horizontalCenter: parent.horizontalCenter
		                    anchors.verticalCenter: parent.verticalCenter
		                    spacing: 12

                    Item {
                        Layout.preferredWidth: root.pillHPaddingPx
                        Layout.preferredHeight: 1
                    }

                    // Time
                    Text {
                        text: Qt.formatTime(clock.date, "hh:mm")
                        color: theme.text
                        font.family: theme.fontFamily
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                        Layout.alignment: Qt.AlignVCenter
                    }

                    // Recording indicator
                    Rectangle {
                        Layout.alignment: Qt.AlignVCenter
                        visible: root.recordingOn
                        height: 22
                        radius: 999
                        color: Qt.rgba(0.85, 0.15, 0.15, 0.90)
                        border.width: 0
                        implicitWidth: recRow.implicitWidth + 16

                        RowLayout {
                            id: recRow
                            anchors.centerIn: parent
                            anchors.margins: 8
                            spacing: 6

                            EinkSymbol {
                                // nf-md-stop (f04db)
                                symbol: String.fromCodePoint(0xF04DB)
                                fallbackSymbol: "stop"
                                fontFamily: theme.iconFontFamily
                                fontFamilyFallback: theme.iconFontFamilyFallback
                                color: "#ffffff"
                                size: 14
                                iconOpacity: 0.95
                                Layout.alignment: Qt.AlignVCenter
                            }

                            Text {
                                text: "REC"
                                color: "#ffffff"
                                font.family: theme.fontFamily
                                font.pixelSize: 10
                                font.weight: Font.DemiBold
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.stopRecording()
                        }
                    }

                    // Workspaces 1..5 (Hyprland) — capsule container + small capsule buttons
                    Rectangle {
	                        id: wsIsland
	                        Layout.alignment: Qt.AlignVCenter
	                        property int wsCount: 5
	                        readonly property int islandHeight: Math.max(18, Math.round(settings.pillHeight * 0.55))
	                        readonly property int buttonHeight: Math.max(14, islandHeight - 4)
	                        readonly property int buttonWidth: Math.max(20, buttonHeight + 8)

	                        radius: 999
	                        height: islandHeight
	                        color: Qt.rgba(theme.surface.r, theme.surface.g, theme.surface.b, 0.38)
	                        border.width: 0

	                        implicitWidth: wsRow.implicitWidth + 2
                        width: implicitWidth

                        RowLayout {
                            id: wsRow
                            anchors.centerIn: parent
                            spacing: 6

                            Repeater {
                                model: wsIsland.wsCount
	                                delegate: Rectangle {
                                    property int ws: index + 1
                                    property bool active: (Hyprland.focusedWorkspace && Hyprland.focusedWorkspace.id === ws)
                                    property bool occupied: root.wsOccupied(ws)

	                                    width: wsIsland.buttonWidth
	                                    height: wsIsland.buttonHeight
	                                    radius: 999
                                    color: active
                                        ? theme.accent
                                        : (occupied
                                            ? Qt.rgba(theme.surface.r, theme.surface.g, theme.surface.b, 0.70)
                                            : Qt.rgba(theme.surface.r, theme.surface.g, theme.surface.b, 0.48))
                                    border.width: 0

                                    Text {
                                        anchors.centerIn: parent
                                        text: "" + ws
                                        color: active ? theme.onAccent : (occupied ? theme.text : theme.textMuted)
                                        font.family: theme.fontFamily
                                        font.pixelSize: 10
                                        font.weight: Font.DemiBold
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: Hyprland.dispatch("workspace " + ws)
                                    }
                                }
                            }
                        }
                    }

                    // Volume % + icon (matches inspo: "55%" then speaker icon)
                    Item {
                        id: volumeArea
                        Layout.alignment: Qt.AlignVCenter
                        implicitWidth: volumeRow.implicitWidth
                        implicitHeight: volumeRow.implicitHeight
                        Layout.preferredWidth: implicitWidth
                        Layout.preferredHeight: implicitHeight

	                        RowLayout {
	                            id: volumeRow
	                            spacing: 8

		                            EinkSymbol {
		                                // Nerd Font Material Design:
		                                //   nf-md-volume_off (f0581)
		                                //   nf-md-volume_high (f057e)
		                                symbol: root.muted ? String.fromCodePoint(0xF0581) : String.fromCodePoint(0xF057E)
		                                fallbackSymbol: root.muted ? "volume_off" : "volume_up"
		                                fallbackIconName: root.muted ? "audio-volume-muted-symbolic" : "audio-volume-high-symbolic"
		                                fontFamily: theme.iconFontFamily
		                                fontFamilyFallback: theme.iconFontFamilyFallback
		                                color: theme.text
	                                size: 14
	                                iconOpacity: 0.95
	                                Layout.alignment: Qt.AlignVCenter
	                            }

                            Text {
                                text: root.volumePct + "%"
                                color: theme.text
                                font.family: theme.fontFamily
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                                Layout.alignment: Qt.AlignVCenter
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: function(mouse) {
                                if (mouse.button === Qt.RightButton) {
                                    root.muteTogglePending = true
                                    root.muteToggleAttempts = 0
                                    if (!root.tryToggleMute()) muteToggleTimer.start()
                                    return
                                }
                                root.quickSettingsOpen = !root.quickSettingsOpen
                            }
                        }

                        WheelHandler {
                            target: volumeArea
                            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                            onWheel: function(wheel) {
                                const dy = (wheel.angleDelta && wheel.angleDelta.y) ? wheel.angleDelta.y
                                    : ((wheel.pixelDelta && wheel.pixelDelta.y) ? wheel.pixelDelta.y : 0)
                                if (dy === 0) return
                                root.stepVolume(dy > 0 ? 5 : -5)
                                wheel.accepted = true
                            }
                        }
                    }

                    // Wi-Fi icon + SSID (only when connected)
	                    Item {
	                        id: wifiArea
	                        visible: root.ssid.length > 0
	                        Layout.alignment: Qt.AlignVCenter
                        implicitWidth: wifiRow.implicitWidth
                        implicitHeight: wifiRow.implicitHeight
                        Layout.preferredWidth: implicitWidth
                        Layout.preferredHeight: implicitHeight

	                        RowLayout {
	                            id: wifiRow
	                            spacing: 8

			                            EinkSymbol {
			                                // Nerd Font Material Design: nf-md-wifi_strength_1 (f091f)
			                                symbol: String.fromCodePoint(0xF091F)
		                                fallbackSymbol: "wifi"
		                                fallbackIconName: "network-wireless-signal-excellent-symbolic"
		                                fontFamily: theme.iconFontFamily
			                                fontFamilyFallback: theme.iconFontFamilyFallback
			                                color: theme.text
                                size: 14
                                iconOpacity: 0.95
                                Layout.alignment: Qt.AlignVCenter
                            }

                            Text {
                                text: root.ssid
                                color: theme.text
                                font.family: theme.fontFamily
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                                maximumLineCount: 1
                                Layout.maximumWidth: 140
                                Layout.minimumWidth: 0
                            }
                        }

			                        MouseArea {
			                            anchors.fill: parent
			                            hoverEnabled: true
			                            cursorShape: Qt.PointingHandCursor
			                            onClicked: {
			                                root.powerOpen = false
			                                root.quickSettingsOpen = !root.quickSettingsOpen
			                            }
			                        }
		                    }

                    // Battery pill (UPower)
                    Rectangle {
                        id: batteryPill
                        Layout.alignment: Qt.AlignVCenter
                        height: 18
                        radius: 999
                        color: theme.accent
                        border.width: 0

                        function computePct() {
                            try {
                                const dev = UPower.displayDevice
                                if (!dev) return 0
                                let p = dev.percentage ?? 0
                                if (typeof p !== "number") return 0
                                if (p <= 1.0) p = p * 100
                                return Math.max(0, Math.min(100, Math.round(p)))
                            } catch (e) {
                                return 0
                            }
                        }

                        property int pct: computePct()
                        readonly property bool charging: {
                            try {
                                const dev = UPower.displayDevice
                                if (!dev) return false
                                return dev.state === UPowerDeviceState.Charging
                                    || dev.state === UPowerDeviceState.PendingCharge
                            } catch (e) {
                                return false
                            }
                        }

                        // Fixed width capsule (prevents visual jitter / circle look).
                        width: 48

                        RowLayout {
                            anchors.centerIn: parent
                            spacing: 6

                            EinkSymbol {
                                visible: batteryPill.charging
                                symbol: String.fromCodePoint(0xF0241) // nf-md-flash
                                fallbackSymbol: "bolt"
                                fontFamily: theme.iconFontFamily
                                fontFamilyFallback: theme.iconFontFamilyFallback
                                color: theme.onAccent
                                size: 12
                                iconOpacity: 0.95
                                Layout.alignment: Qt.AlignVCenter
                            }

                            Text {
                                id: batteryText
                                text: "" + batteryPill.pct
                                color: theme.onAccent
                                font.family: theme.fontFamily
                                font.pixelSize: 11
                                font.weight: Font.DemiBold
                                Layout.alignment: Qt.AlignVCenter
                            }
                        }

		                        MouseArea {
		                            anchors.fill: parent
		                            hoverEnabled: true
		                            cursorShape: Qt.PointingHandCursor
		                            onClicked: root.powerOpen = !root.powerOpen
		                        }
		                    }

                    Item {
                        Layout.preferredWidth: root.pillHPaddingPx
                        Layout.preferredHeight: 1
                    }
	                }

	            }

	            // Screen corner scroll zones: top-left = brightness, top-right = volume
	            // Attach to the layer root so it receives wheel events regardless of which child is under the cursor.
	            WheelHandler {
	                target: barLayerRoot
	                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
	                onWheel: function(wheel) {
	                    const dy = (wheel.angleDelta && wheel.angleDelta.y) ? wheel.angleDelta.y
	                        : ((wheel.pixelDelta && wheel.pixelDelta.y) ? wheel.pixelDelta.y : 0)
	                    if (dy === 0) return

	                    const px = (typeof wheel.x === "number") ? wheel.x : (wheel.point?.position?.x ?? null)
	                    const py = (typeof wheel.y === "number") ? wheel.y : (wheel.point?.position?.y ?? null)
	                    if (px === null || py === null) return

	                    // Define corner hitboxes in screen/layer coordinates.
	                    const cornerSize = 56
	                    const topBand = 80

	                    if (py <= topBand && px <= cornerSize) {
	                        root.stepBrightness(dy > 0 ? 5 : -5)
	                        wheel.accepted = true
	                        return
	                    }
	                    if (py <= topBand && px >= (barLayerRoot.width - cornerSize)) {
	                        root.stepVolume(dy > 0 ? 5 : -5)
	                        wheel.accepted = true
	                    }
	                }
	            }
	        }
	    }

    WlrLayershell {
        id: popupLayer

        layer: WlrLayer.Top
        keyboardFocus: WlrKeyboardFocus.None
        aboveWindows: true
        focusable: false
        exclusiveZone: 0
        namespace: "eink-quicksettings"
        color: "transparent"
        visible: root.quickSettingsOpen || root.quickSettingsAnim > 0.001

        anchors {
            top: true
            left: true
            right: true
            bottom: true
        }

        readonly property real openY: Math.round(pill.y + pill.height + root.popupGap - root.popupOverlap)
        readonly property real closedY: Math.round(-quickSettings.implicitHeight - 12)
        Item {
            anchors.fill: parent

            QuickSettings {
                id: quickSettings
                theme: theme
                settings: settings
                width: Math.min(implicitWidth, popupLayer.width - 24)
                x: Math.round((popupLayer.width - width) / 2)
                y: Math.round(popupLayer.closedY + root.quickSettingsAnim * (popupLayer.openY - popupLayer.closedY))
                onRequestClose: root.quickSettingsOpen = false
                onRequestOpenSettings: {
                    root.quickSettingsOpen = false
                    root.settingsOpen = true
                }
                onRequestOpenWifiDetails: {
                    root.quickSettingsOpen = false
                    root.wifiDetailsOpen = true
                }
                onRequestOpenBluetoothDetails: {
                    root.quickSettingsOpen = false
                    root.bluetoothDetailsOpen = true
                }
                onRequestOpenRecorder: {
                    root.quickSettingsOpen = false
                    root.recordOpen = true
                }
                z: 2
            }

            MouseArea {
                anchors.fill: parent
                z: 1
                enabled: root.quickSettingsAnim > 0.001
                onClicked: function(mouse) {
                    const inside =
                        mouse.x >= quickSettings.x &&
                        mouse.x <= (quickSettings.x + quickSettings.width) &&
                        mouse.y >= quickSettings.y &&
                        mouse.y <= (quickSettings.y + quickSettings.height)
                    if (!inside) root.quickSettingsOpen = false
                }
            }
        }
    }

	    WlrLayershell {
	        id: settingsLayer

	        layer: WlrLayer.Top
	        keyboardFocus: WlrKeyboardFocus.OnDemand
	        aboveWindows: true
	        focusable: true
        exclusiveZone: 0
        namespace: "eink-settings"
        color: "transparent"
        visible: root.settingsOpen || root.settingsAnim > 0.001

        anchors {
            top: true
            left: true
            right: true
            bottom: true
        }

        Item {
            anchors.fill: parent

            MouseArea {
                anchors.fill: parent
                enabled: root.settingsAnim > 0.001
                onClicked: root.settingsOpen = false
            }

            SettingsModal {
                theme: theme
                settings: settings
                anchors.centerIn: parent
                width: Math.min(implicitWidth, settingsLayer.width - 24)
                height: implicitHeight
                y: Math.round((-height - 24) + root.settingsAnim * (((settingsLayer.height - height) / 2) - (-height - 24)))
                onRequestClose: root.settingsOpen = false
            }
        }
    }

    WlrLayershell {
        id: wifiLayer

        layer: WlrLayer.Top
        keyboardFocus: WlrKeyboardFocus.None
        aboveWindows: true
        focusable: false
        exclusiveZone: 0
        namespace: "eink-wifi"
        color: "transparent"
        visible: root.wifiDetailsOpen || root.wifiAnim > 0.001

        anchors {
            top: true
            left: true
            right: true
            bottom: true
        }

        Item {
            anchors.fill: parent

            MouseArea {
                anchors.fill: parent
                enabled: root.wifiAnim > 0.001
                onClicked: root.wifiDetailsOpen = false
            }

            WifiModal {
                theme: theme
                anchors.centerIn: parent
                width: Math.min(implicitWidth, wifiLayer.width - 24)
                height: implicitHeight
                y: Math.round((-height - 24) + root.wifiAnim * (((wifiLayer.height - height) / 2) - (-height - 24)))
                onRequestClose: root.wifiDetailsOpen = false
            }
        }
    }

    WlrLayershell {
        id: btLayer

        layer: WlrLayer.Top
        keyboardFocus: WlrKeyboardFocus.None
        aboveWindows: true
        focusable: false
        exclusiveZone: 0
        namespace: "eink-bluetooth"
        color: "transparent"
        visible: root.bluetoothDetailsOpen || root.bluetoothAnim > 0.001

        anchors {
            top: true
            left: true
            right: true
            bottom: true
        }

        Item {
            anchors.fill: parent

            MouseArea {
                anchors.fill: parent
                enabled: root.bluetoothAnim > 0.001
                onClicked: root.bluetoothDetailsOpen = false
            }

            BluetoothModal {
                theme: theme
                anchors.centerIn: parent
                width: Math.min(implicitWidth, btLayer.width - 24)
                height: implicitHeight
                y: Math.round((-height - 24) + root.bluetoothAnim * (((btLayer.height - height) / 2) - (-height - 24)))
                onRequestClose: root.bluetoothDetailsOpen = false
            }
        }
    }

	    WlrLayershell {
	        id: powerLayer

        layer: WlrLayer.Top
        keyboardFocus: WlrKeyboardFocus.None
        aboveWindows: true
        focusable: false
        exclusiveZone: 0
        namespace: "eink-power"
        color: "transparent"
        visible: root.powerOpen || root.powerAnim > 0.001

        anchors {
            top: true
            left: true
            right: true
            bottom: true
        }

	        readonly property real openY: Math.round(pill.y + pill.height + root.popupGap - root.popupOverlap)
	        readonly property real closedY: Math.round(-powerModal.implicitHeight - 12)

	        Item {
	            anchors.fill: parent

	            PowerModal {
	                id: powerModal
	                theme: theme
	                width: Math.min(implicitWidth, powerLayer.width - 24)
	                x: Math.round((powerLayer.width - width) / 2)
	                y: Math.round(powerLayer.closedY + root.powerAnim * (powerLayer.openY - powerLayer.closedY))
	                onRequestClose: root.powerOpen = false
	                z: 2
	            }

	            MouseArea {
	                anchors.fill: parent
	                z: 1
	                enabled: root.powerAnim > 0.001
	                onClicked: function(mouse) {
	                    const inside =
	                        mouse.x >= powerModal.x &&
	                        mouse.x <= (powerModal.x + powerModal.width) &&
	                        mouse.y >= powerModal.y &&
	                        mouse.y <= (powerModal.y + powerModal.height)
	                    if (!inside) root.powerOpen = false
	                }
	            }
	        }
	    }

    WlrLayershell {
        id: recordLayer

        layer: WlrLayer.Top
        keyboardFocus: WlrKeyboardFocus.None
        aboveWindows: true
        focusable: false
        exclusiveZone: 0
        namespace: "eink-record"
        color: "transparent"
        visible: root.recordOpen || root.recordAnim > 0.001

        anchors {
            top: true
            left: true
            right: true
            bottom: true
        }

        readonly property real openY: Math.round(pill.y + pill.height + root.popupGap - root.popupOverlap)
        readonly property real closedY: Math.round(-recordModal.implicitHeight - 12)

        Item {
            anchors.fill: parent

            RecordModal {
                id: recordModal
                theme: theme
                width: Math.min(implicitWidth, recordLayer.width - 24)
                x: Math.round((recordLayer.width - width) / 2)
                y: Math.round(recordLayer.closedY + root.recordAnim * (recordLayer.openY - recordLayer.closedY))
                onRequestClose: root.recordOpen = false
                z: 2
            }

            MouseArea {
                anchors.fill: parent
                z: 1
                enabled: root.recordAnim > 0.001
                onClicked: function(mouse) {
                    const inside =
                        mouse.x >= recordModal.x &&
                        mouse.x <= (recordModal.x + recordModal.width) &&
                        mouse.y >= recordModal.y &&
                        mouse.y <= (recordModal.y + recordModal.height)
                    if (!inside) root.recordOpen = false
                }
            }
        }
    }
}
