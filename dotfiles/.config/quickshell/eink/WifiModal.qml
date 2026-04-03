import QtQuick
import QtQuick.Layouts
import Quickshell.Io 0.0

Item {
    id: root

    property var theme
    signal requestClose()

    property bool haveNmcli: true
    property bool wifiOn: false
    property string wifiDevice: ""
    property string activeSsid: ""
    property var networks: ([] ) // array<{ ssid: string, signal: int, security: string, active: bool }>

    property bool passwordOpen: false
    property string passwordSsid: ""
    property string passwordValue: ""
    property string passwordError: ""

    property bool busyOpen: false
    property string busyLabel: ""
    property string pendingConnectSsid: ""
    property int pendingPollsLeft: 0

    implicitWidth: 520
    implicitHeight: 320

    StdioCollector { id: out; waitForEnd: true }
    StdioCollector { id: err; waitForEnd: true }

    Process {
        id: cmd
        stdout: out
        stderr: err
        onExited: function(exitCode, exitStatus) {
            cmd.running = false
            const cb = root._pendingCb
            root._pendingCb = null
            if (cb) cb(exitCode, (out.text ?? "").trim(), (err.text ?? "").trim())
        }
    }

    property var _pendingCb: null

    function execSh(script, cb) {
        if (cmd.running) return
        root._pendingCb = cb
        out.waitForEnd = true
        err.waitForEnd = true
        cmd.command = ["sh", "-lc", script]
        cmd.running = true
    }

    function clearBusy() {
        root.busyOpen = false
        root.busyLabel = ""
        root.pendingConnectSsid = ""
        root.pendingPollsLeft = 0
        pendingTimer.stop()
    }

	    function refresh(doRescan, done) {
	        // Single command to avoid overlapping Process calls.
	        const rescan = (doRescan === true) ? "yes" : "no"
	        const script =
	            "if ! command -v nmcli >/dev/null 2>&1; then echo '__NO_NMCLI__'; exit 0; fi\n" +
	            "echo \"WIFI_ON=$(nmcli radio wifi 2>/dev/null | tr '[:upper:]' '[:lower:]')\"\n" +
	            "echo \"WIFI_DEV=$(nmcli -t -f DEVICE,TYPE device status 2>/dev/null | awk -F: '$2==\\\"wifi\\\"{print $1; exit}')\"\n" +
	            "echo \"ACTIVE_SSID=$(nmcli -t -f ACTIVE,SSID dev wifi 2>/dev/null | awk -F: '$1==\\\"yes\\\"{print $2; exit}')\"\n" +
	            "echo '__NETWORKS__'\n" +
	            ("nmcli -t -f IN-USE,SSID,SIGNAL,SECURITY device wifi list --rescan " + rescan + " 2>/dev/null || true\n")

	        root.execSh(script, function(code, stdout) {
	            const raw = (stdout ?? "").trim()
	            if (raw.indexOf("__NO_NMCLI__") !== -1) {
	                root.haveNmcli = false
                root.wifiOn = false
                root.wifiDevice = ""
                root.activeSsid = ""
                root.networks = []
                return
            }
            root.haveNmcli = true

            const lines = (raw ?? "").split("\n")
            const header = {}
            let i = 0
            for (; i < lines.length; i++) {
                const l = (lines[i] ?? "").trim()
                if (l === "__NETWORKS__") {
                    i++
                    break
                }
                const eq = l.indexOf("=")
                if (eq === -1) continue
                header[l.slice(0, eq)] = l.slice(eq + 1)
            }

            const wifiOnStr = (header.WIFI_ON ?? "")
            root.wifiOn = wifiOnStr.indexOf("enabled") !== -1
            root.wifiDevice = (header.WIFI_DEV ?? "").trim()
            root.activeSsid = (header.ACTIVE_SSID ?? "").trim()

            const list = []
            for (; i < lines.length; i++) {
                const l = (lines[i] ?? "").trim()
                if (!l) continue
                const parts = l.split(":")
                if (parts.length < 4) continue
                const inUse = parts[0] === "*"
                const ssid = parts[1] ?? ""
                if (!ssid) continue
                const sig = parseInt(parts[2] ?? "0", 10)
                const security = parts.slice(3).join(":")
                list.push({ ssid, signal: isFinite(sig) ? sig : 0, security, active: inUse })
            }
	            list.sort((a, b) => (b.active - a.active) || (b.signal - a.signal) || a.ssid.localeCompare(b.ssid))
	            root.networks = list
	            if (done) done()
	        })
	    }

	    function rescan() {
	        if (!root.haveNmcli) return
	        root.busyLabel = "Scanning…"
	        root.busyOpen = true
	        root.refresh(true, function() { root.clearBusy() })
	    }

	    function connect(ssid, password) {
	        if (!root.haveNmcli) return
	        root.busyLabel = "Connecting…"
	        root.busyOpen = true
            root.pendingConnectSsid = ssid
            root.pendingPollsLeft = 15
	        const ssidArg = JSON.stringify(ssid)
	        const pw = (password ?? "")
	        const cmd =
	            (pw.length > 0)
	                ? ("LANG=C nmcli -w 15 dev wifi connect " + ssidArg + " password " + JSON.stringify(pw))
	                : ("LANG=C nmcli -w 15 dev wifi connect " + ssidArg)
	        root.execSh(cmd, function(code, outText, errText) {
	            const outLower = ((outText ?? "").trim()).toLowerCase()
	            const errLower = ((errText ?? "").trim()).toLowerCase()
	            const combined = (outLower + "\n" + errLower).trim()
	            // If nmcli needs secrets, prompt for password instead of failing silently.
	            if (pw.length === 0 && (
	                combined.indexOf("secrets") !== -1 ||
	                combined.indexOf("password") !== -1 ||
	                combined.indexOf("802-11-wireless-security") !== -1 ||
	                combined.indexOf("need a password") !== -1 ||
	                combined.indexOf("requires a password") !== -1
	            )) {
	                root.passwordSsid = ssid
	                root.passwordValue = ""
	                root.passwordError = ""
	                root.passwordOpen = true
	                return
	            }

	            // If a password was provided but connect still failed, surface a short error.
	            if (pw.length > 0 && code !== 0) {
                    root.clearBusy()
	                root.passwordError = (errText ?? outText ?? "").trim()
	                root.passwordOpen = true
	                return
	            }

	            root.passwordOpen = false
	            root.passwordValue = ""
	            root.passwordError = ""
                pendingTimer.restart()
	        })
	    }

    Timer {
        id: pendingTimer
        interval: 900
        repeat: true
        running: false
        onTriggered: {
            if (root.pendingPollsLeft <= 0) {
                root.clearBusy()
                root.refresh(true)
                return
            }
            root.pendingPollsLeft -= 1
            root.refresh(true, function() {
                if (root.pendingConnectSsid.length > 0 && root.activeSsid === root.pendingConnectSsid) {
                    root.clearBusy()
                }
            })
        }
    }

	    Component.onCompleted: refresh(false)

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
        spacing: 12

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Text {
                text: "Wi‑Fi"
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

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Text {
                text: !root.haveNmcli
                    ? "nmcli not found"
                    : ("Wi‑Fi: " + (root.wifiOn ? "On" : "Off") + (root.activeSsid.length ? (" • " + root.activeSsid) : ""))
                color: root.theme.textMuted
                font.family: root.theme.fontFamily
                font.pixelSize: 12
                Layout.fillWidth: true
                elide: Text.ElideRight
            }

            Rectangle {
                width: 92
                height: 28
                radius: 12
                visible: root.haveNmcli
                color: Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.92)

                Text {
                    anchors.centerIn: parent
                    text: root.wifiOn ? "Turn Off" : "Turn On"
                    color: root.theme.onAccent
                    font.family: root.theme.fontFamily
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
	                    onClicked: {
	                        if (!root.haveNmcli) return
	                        root.execSh(root.wifiOn ? "nmcli radio wifi off" : "nmcli radio wifi on", function() { root.refresh(true) })
	                    }
	                }
	            }

            Rectangle {
                width: 92
                height: 28
                radius: 12
                visible: root.haveNmcli
                color: Qt.rgba(root.theme.surfaceAlt.r, root.theme.surfaceAlt.g, root.theme.surfaceAlt.b, 0.95)

                Text {
                    anchors.centerIn: parent
                    text: "Rescan"
                    color: root.theme.text
                    font.family: root.theme.fontFamily
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                }

	                MouseArea {
	                    anchors.fill: parent
	                    cursorShape: Qt.PointingHandCursor
	                    onClicked: root.rescan()
	                }
	            }
	        }

        Rectangle {
            Layout.fillWidth: true
            height: 1
            radius: 1
            color: Qt.rgba(root.theme.outline.r, root.theme.outline.g, root.theme.outline.b, 0.35)
        }

	        ListView {
	            Layout.fillWidth: true
	            Layout.fillHeight: true
	            clip: true
	            spacing: 8
	            model: root.networks
	            boundsBehavior: Flickable.StopAtBounds

	            delegate: Rectangle {
	                width: ListView.view.width
	                height: 48
	                radius: 16
	                readonly property bool active: !!modelData.active
	                readonly property bool hovered: hover.containsMouse
	                color: active
	                    ? Qt.rgba(root.theme.surfaceAlt.r, root.theme.surfaceAlt.g, root.theme.surfaceAlt.b, 0.92)
	                    : Qt.rgba(root.theme.surfaceAlt.r, root.theme.surfaceAlt.g, root.theme.surfaceAlt.b, hovered ? 0.78 : 0.68)
	                border.width: active ? 1 : 0
	                border.color: active
	                    ? Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.35)
	                    : "transparent"

		                MouseArea {
		                    id: hover
		                    anchors.fill: parent
		                    hoverEnabled: true
		                    acceptedButtons: Qt.NoButton
		                }

	                RowLayout {
	                    anchors.fill: parent
	                    anchors.margins: 10
	                    spacing: 10

	                    EinkSymbol {
	                        Layout.alignment: Qt.AlignVCenter
	                        readonly property int sig: (modelData.signal ?? 0)
	                        symbol:
	                            (sig >= 70) ? String.fromCodePoint(0xF0925) : // nf-md-wifi_strength_3
	                            (sig >= 40) ? String.fromCodePoint(0xF0922) : // nf-md-wifi_strength_2
	                            String.fromCodePoint(0xF091F) // nf-md-wifi_strength_1
	                        fallbackSymbol: "wifi"
	                        fontFamily: root.theme.iconFontFamily
	                        fontFamilyFallback: root.theme.iconFontFamilyFallback
	                        color: active ? root.theme.accent : root.theme.textMuted
	                        size: 18
	                    }

	                    Text {
	                        text: modelData.ssid
	                        color: root.theme.text
                        font.family: root.theme.fontFamily
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
	                        Layout.fillWidth: true
	                    }

	                    Text {
	                        text: (modelData.signal ?? 0) + "%"
	                        color: root.theme.textMuted
                        font.family: root.theme.fontFamily
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                        Layout.alignment: Qt.AlignVCenter
	                    }

	                    Rectangle {
	                        readonly property bool activeBtn: !!modelData.active
	                        width: 98
	                        height: 28
	                        radius: 12
	                        color: activeBtn
	                            ? Qt.rgba(root.theme.surface.r, root.theme.surface.g, root.theme.surface.b, 0.55)
	                            : Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.92)

		                        Text {
		                            anchors.centerIn: parent
		                            text: parent.activeBtn ? "Disconnect" : "Connect"
		                            color: parent.activeBtn ? root.theme.text : root.theme.onAccent
		                            font.family: root.theme.fontFamily
		                            font.pixelSize: 11
		                            font.weight: Font.DemiBold
		                        }

	                        MouseArea {
	                            anchors.fill: parent
	                            enabled: root.haveNmcli && root.wifiOn
	                            cursorShape: Qt.PointingHandCursor
	                            onClicked: {
                                if (!root.haveNmcli) return
                                if (parent.active) {
                                    if (root.wifiDevice.length) {
                                        root.execSh("nmcli dev disconnect " + root.wifiDevice + " 2>/dev/null || true", function() { root.refresh() })
                                    } else {
                                        root.execSh("nmcli networking off; nmcli networking on", function() { root.refresh() })
                                    }
	                                    return
	                                }
	                                const ssid = modelData.ssid
	                                root.connect(ssid, "")
	                            }
	                        }
	                    }
	                }
	            }
	        }

	        // Password prompt overlay
	        Item {
	            anchors.fill: parent
	            visible: root.passwordOpen
	            z: 100
	            onVisibleChanged: if (visible) pwInput.forceActiveFocus()

	            Rectangle {
	                anchors.fill: parent
	                color: Qt.rgba(0, 0, 0, 0.45)
	                MouseArea {
	                    anchors.fill: parent
	                    onClicked: {
	                        root.passwordOpen = false
	                        root.passwordValue = ""
	                        root.passwordError = ""
	                    }
	                }
	            }

	            Rectangle {
	                width: Math.min(parent.width - 40, 420)
	                implicitHeight: Math.round(col.implicitHeight + 22)
	                radius: 18
	                anchors.centerIn: parent
	                color: Qt.rgba(root.theme.surfaceAlt.r, root.theme.surfaceAlt.g, root.theme.surfaceAlt.b, 0.98)
	                border.width: 1
	                border.color: Qt.rgba(root.theme.outline.r, root.theme.outline.g, root.theme.outline.b, 0.35)

	                Keys.onEscapePressed: {
	                    root.passwordOpen = false
	                    root.passwordValue = ""
	                    root.passwordError = ""
	                }

	                ColumnLayout {
	                    id: col
	                    anchors.fill: parent
	                    anchors.margins: 14
	                    spacing: 10

	                    Text {
	                        text: "Connect to Wi‑Fi"
	                        color: root.theme.text
	                        font.family: root.theme.fontFamily
	                        font.pixelSize: 13
	                        font.weight: Font.DemiBold
	                        Layout.fillWidth: true
	                    }

	                    Text {
	                        text: root.passwordSsid.length ? root.passwordSsid : "Network"
	                        color: root.theme.textMuted
	                        font.family: root.theme.fontFamily
	                        font.pixelSize: 12
	                        elide: Text.ElideRight
	                        Layout.fillWidth: true
	                    }

	                    Rectangle {
	                        Layout.fillWidth: true
	                        height: 36
	                        radius: 14
	                        color: Qt.rgba(root.theme.surface.r, root.theme.surface.g, root.theme.surface.b, 0.55)
	                        border.width: 1
	                        border.color: Qt.rgba(root.theme.outline.r, root.theme.outline.g, root.theme.outline.b, 0.28)

	                        TextInput {
	                            id: pwInput
	                            anchors.fill: parent
	                            anchors.margins: 10
	                            color: root.theme.text
	                            selectionColor: Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.5)
	                            selectedTextColor: root.theme.onAccent
	                            font.family: root.theme.fontFamily
	                            font.pixelSize: 12
	                            echoMode: TextInput.Password
	                            inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText
	                            text: root.passwordValue
	                            onTextChanged: root.passwordValue = text
	                            focus: true
	                            Keys.onReturnPressed: connectBtn.clicked()
	                            Keys.onEnterPressed: connectBtn.clicked()
	                        }
	                    }

	                    Text {
	                        visible: root.passwordError.length > 0
	                        text: root.passwordError
	                        color: Qt.rgba(1, 0.4, 0.4, 1)
	                        font.family: root.theme.fontFamily
	                        font.pixelSize: 11
	                        wrapMode: Text.Wrap
	                        Layout.fillWidth: true
	                    }

	                    RowLayout {
	                        Layout.fillWidth: true
	                        spacing: 10

	                        Rectangle {
	                            Layout.fillWidth: true
	                            height: 32
	                            radius: 14
	                            color: Qt.rgba(root.theme.surface.r, root.theme.surface.g, root.theme.surface.b, 0.55)
	                            Text {
	                                anchors.centerIn: parent
	                                text: "Cancel"
	                                color: root.theme.text
	                                font.family: root.theme.fontFamily
	                                font.pixelSize: 11
	                                font.weight: Font.DemiBold
	                            }
	                            MouseArea {
	                                anchors.fill: parent
	                                cursorShape: Qt.PointingHandCursor
	                                onClicked: {
	                                    root.passwordOpen = false
	                                    root.passwordValue = ""
	                                    root.passwordError = ""
	                                }
	                            }
	                        }

	                        Rectangle {
	                            id: connectBtn
	                            Layout.fillWidth: true
	                            height: 32
	                            radius: 14
	                            color: Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.92)
	                            Text {
	                                anchors.centerIn: parent
	                                text: "Connect"
	                                color: root.theme.onAccent
	                                font.family: root.theme.fontFamily
	                                font.pixelSize: 11
	                                font.weight: Font.DemiBold
	                            }
	                            property bool clicked: false
	                            MouseArea {
	                                anchors.fill: parent
	                                cursorShape: Qt.PointingHandCursor
	                                onClicked: connectBtn.clicked()
	                            }
	                            function clicked() {
	                                if (!root.passwordSsid.length) return
	                                root.passwordError = ""
	                                root.connect(root.passwordSsid, root.passwordValue)
	                            }
	                        }
	                    }
	                }
	            }
	        }

	        // Busy overlay (scanning / connecting)
	        Item {
	            anchors.fill: parent
	            visible: root.busyOpen
	            z: 110

	            Rectangle {
	                anchors.fill: parent
	                color: Qt.rgba(0, 0, 0, 0.35)
	            }

	            Rectangle {
	                width: Math.min(parent.width - 40, 340)
	                height: 64
	                radius: 18
	                anchors.centerIn: parent
	                color: Qt.rgba(root.theme.surfaceAlt.r, root.theme.surfaceAlt.g, root.theme.surfaceAlt.b, 0.98)
	                border.width: 1
	                border.color: Qt.rgba(root.theme.outline.r, root.theme.outline.g, root.theme.outline.b, 0.35)

	                RowLayout {
	                    anchors.fill: parent
	                    anchors.margins: 14
	                    spacing: 12

                        Item {
                            Layout.alignment: Qt.AlignVCenter
                            width: 20
                            height: 20
                            property real phase: 0
                            RotationAnimator on phase {
                                running: root.busyOpen
                                from: 0
                                to: 1
                                duration: 850
                                loops: Animation.Infinite
                            }

                            Repeater {
                                model: 8
                                delegate: Rectangle {
                                    required property int index
                                    width: 4
                                    height: 4
                                    radius: 2
                                    color: root.theme.accent
                                    opacity: Math.max(0.18, ((index + 1) / 8) - parent.phase)
                                    x: (10 + Math.cos((index / 8) * Math.PI * 2) * 7) - width / 2
                                    y: (10 + Math.sin((index / 8) * Math.PI * 2) * 7) - height / 2
                                }
                            }
                        }

	                    Text {
	                        text: root.busyLabel.length ? root.busyLabel : "Working…"
	                        color: root.theme.text
	                        font.family: root.theme.fontFamily
	                        font.pixelSize: 12
	                        font.weight: Font.DemiBold
	                        Layout.fillWidth: true
	                        Layout.alignment: Qt.AlignVCenter
	                    }
	                }
	            }
	        }
	    }
	}
