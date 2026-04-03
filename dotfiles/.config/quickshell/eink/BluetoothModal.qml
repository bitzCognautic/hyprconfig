import QtQuick
import QtQuick.Layouts
import Quickshell.Io 0.0

Item {
    id: root

    property var theme
    signal requestClose()
    signal stateChanged()

    property bool haveBluetoothctl: true
    property bool btPowered: false
    property var devices: ([] ) // array<{ mac: string, name: string, connected: bool }>

    property bool busyOpen: false
    property string busyLabel: ""
    property string pendingMac: ""
    property bool pendingConnectedState: false
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
        root.pendingMac = ""
        root.pendingConnectedState = false
        root.pendingPollsLeft = 0
        pendingTimer.stop()
    }

	    function refresh(doScan, done) {
	        // Single command to avoid overlapping Process calls.
	        const scan = (doScan === true)
	        const script =
	            "if ! command -v bluetoothctl >/dev/null 2>&1; then echo '__NO_BTCTL__'; exit 0; fi\n" +
	            "pwr=$(bluetoothctl show 2>/dev/null | awk -F': ' '/^\\s*Powered:/{print $2; exit}')\n" +
	            "echo \"POWERED=${pwr}\"\n" +
	            // Optional scan burst for discovery
	            (scan ? ("bluetoothctl scan on >/dev/null 2>&1 || true\n" +
	            "sleep 6\n" +
	            "bluetoothctl scan off >/dev/null 2>&1 || true\n") : "") +
	            "echo '__DEVICES__'\n" +
	            "bluetoothctl devices 2>/dev/null | awk '{mac=$2; $1=$2=\"\"; sub(/^  /, \"\"); print mac \"|\" $0}'\n"

	        root.execSh(script, function(code, stdout) {
	            const raw = (stdout ?? "").trim()
	            if (raw.indexOf("__NO_BTCTL__") !== -1) {
	                root.haveBluetoothctl = false
	                root.btPowered = false
	                root.devices = []
	                if (done) done()
	                return
	            }
	            root.haveBluetoothctl = true

            const lines = raw.split("\n")
            let powered = ""
            let i = 0
            for (; i < lines.length; i++) {
                const l = (lines[i] ?? "").trim()
                if (l === "__DEVICES__") {
                    i++
                    break
                }
                if (l.indexOf("POWERED=") === 0) powered = l.slice("POWERED=".length)
            }
            const p = (powered ?? "").toLowerCase()
            root.btPowered = (p.indexOf("yes") !== -1 || p.indexOf("on") !== -1)

            const devs = []
            for (; i < lines.length; i++) {
                const l = (lines[i] ?? "").trim()
                if (!l) continue
                const parts = l.split("|")
                if (parts.length < 2) continue
                const mac = (parts[0] ?? "").trim()
                const name = parts.slice(1).join("|").trim()
                if (!mac) continue
                devs.push({ mac, name, connected: false })
            }

            // Fill connected state (fast; but one-by-one would be slow). Limit to first 12.
            const limit = Math.min(devs.length, 12)
	            if (limit === 0) {
	                root.devices = []
                    root.stateChanged()
	                if (done) done()
	                return
	            }

            const infoScript =
                "for mac in " + devs.slice(0, limit).map(d => d.mac).join(" ") + "; do " +
                "  c=$(bluetoothctl info \"$mac\" 2>/dev/null | awk -F': ' '/^\\s*Connected:/{print $2; exit}'); " +
                "  [ -z \"$c\" ] && c=no; " +
                "  echo \"$mac|$c\"; " +
                "done"
	            root.execSh(infoScript, function(code2, out2) {
	                const map = {}
	                const l2 = (out2 ?? "").split("\n").map(s => s.trim()).filter(Boolean)
                for (const x of l2) {
                    const p2 = x.split("|")
                    if (p2.length < 2) continue
                    map[p2[0]] = (p2[1] ?? "").toLowerCase().indexOf("yes") !== -1
                }
	                for (const d of devs) d.connected = !!map[d.mac]
	                devs.sort((a, b) => (b.connected - a.connected) || a.name.localeCompare(b.name))
	                root.devices = devs
                    root.stateChanged()
	                if (done) done()
	            })
	        })
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
                text: "Bluetooth"
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

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Text {
                text: root.haveBluetoothctl ? ("Powered: " + (root.btPowered ? "On" : "Off")) : "bluetoothctl not found"
                color: root.theme.textMuted
                font.family: root.theme.fontFamily
                font.pixelSize: 12
                Layout.fillWidth: true
            }

            Rectangle {
                width: 92
                height: 28
                radius: 12
                color: Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.92)
                visible: root.haveBluetoothctl
                Text {
                    anchors.centerIn: parent
                    text: root.btPowered ? "Power Off" : "Power On"
                    color: root.theme.onAccent
                    font.family: root.theme.fontFamily
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                }
	                MouseArea {
	                    anchors.fill: parent
	                    cursorShape: Qt.PointingHandCursor
	                    onClicked: {
	                        if (!root.haveBluetoothctl) return
	                        root.busyLabel = root.btPowered ? "Turning off…" : "Turning on…"
	                        root.busyOpen = true
	                        root.execSh(root.btPowered ? "bluetoothctl power off" : "bluetoothctl power on", function() {
	                            root.refresh(false, function() { root.busyOpen = false; root.busyLabel = "" })
	                        })
	                    }
	                }
	            }

            Rectangle {
                width: 92
                height: 28
                radius: 12
                visible: root.haveBluetoothctl
                color: Qt.rgba(root.theme.surfaceAlt.r, root.theme.surfaceAlt.g, root.theme.surfaceAlt.b, 0.95)

                Text {
                    anchors.centerIn: parent
                    text: "Scan"
                    color: root.theme.text
                    font.family: root.theme.fontFamily
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                }

	                MouseArea {
	                    anchors.fill: parent
	                    cursorShape: Qt.PointingHandCursor
	                    onClicked: {
	                        if (!root.haveBluetoothctl) return
	                        root.busyLabel = "Scanning…"
	                        root.busyOpen = true
	                        root.refresh(true, function() { root.busyOpen = false; root.busyLabel = "" })
	                    }
	                }
	            }
	        }

	        ListView {
	            Layout.fillWidth: true
	            Layout.fillHeight: true
	            clip: true
	            spacing: 8
	            model: root.devices
	            boundsBehavior: Flickable.StopAtBounds

	            delegate: Rectangle {
	                width: ListView.view.width
	                height: 48
	                radius: 16
	                readonly property bool hovered: hover.containsMouse
	                color: Qt.rgba(root.theme.surfaceAlt.r, root.theme.surfaceAlt.g, root.theme.surfaceAlt.b, hovered ? 0.78 : 0.68)
	                border.width: modelData.connected ? 1 : 0
	                border.color: modelData.connected
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
	                        symbol: String.fromCodePoint(0xF00AF) // nf-md-bluetooth
	                        fallbackSymbol: "bluetooth"
	                        fontFamily: root.theme.iconFontFamily
	                        fontFamilyFallback: root.theme.iconFontFamilyFallback
	                        color: modelData.connected ? root.theme.accent : root.theme.textMuted
	                        size: 18
	                    }

	                    Text {
	                        text: modelData.name
	                        color: root.theme.text
                        font.family: root.theme.fontFamily
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
	                        Layout.fillWidth: true
	                    }

	                    Text {
	                        visible: !!modelData.connected
	                        text: "Connected"
	                        color: root.theme.textMuted
	                        font.family: root.theme.fontFamily
	                        font.pixelSize: 11
	                        font.weight: Font.DemiBold
	                        Layout.alignment: Qt.AlignVCenter
	                    }

	                    Rectangle {
	                        width: 98
	                        height: 28
                        radius: 12
                        color: modelData.connected
                            ? Qt.rgba(root.theme.surface.r, root.theme.surface.g, root.theme.surface.b, 0.55)
                            : Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.92)

                        Text {
                            anchors.centerIn: parent
                            text: modelData.connected ? "Disconnect" : "Connect"
                            color: modelData.connected ? root.theme.text : root.theme.onAccent
                            font.family: root.theme.fontFamily
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                        }

	                        MouseArea {
	                            anchors.fill: parent
	                            enabled: root.haveBluetoothctl && root.btPowered
	                            cursorShape: Qt.PointingHandCursor
	                            onClicked: {
	                                if (!root.haveBluetoothctl) return
	                                root.busyLabel = modelData.connected ? "Disconnecting…" : "Connecting…"
	                                root.busyOpen = true
                                    root.pendingMac = modelData.mac
                                    root.pendingConnectedState = !modelData.connected
                                    root.pendingPollsLeft = 15
	                                const cmd = modelData.connected
	                                    ? ("bluetoothctl disconnect " + modelData.mac + " >/dev/null 2>&1 || true")
	                                    : ("bluetoothctl connect " + modelData.mac + " >/dev/null 2>&1 || true")
	                                root.execSh(cmd, function() {
	                                    pendingTimer.restart()
	                                })
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
	            z: 100

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

    Timer {
        id: pendingTimer
        interval: 900
        repeat: true
        running: false
        onTriggered: {
            if (root.pendingPollsLeft <= 0) {
                root.clearBusy()
                root.refresh(false)
                return
            }
            root.pendingPollsLeft -= 1
            root.refresh(false, function() {
                const match = root.devices.find(d => d.mac === root.pendingMac)
                if (match && !!match.connected === root.pendingConnectedState) {
                    root.clearBusy()
                }
            })
        }
    }
	}
