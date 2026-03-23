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

    function refresh() {
        // Single command to avoid overlapping Process calls.
        const script =
            "if ! command -v nmcli >/dev/null 2>&1; then echo '__NO_NMCLI__'; exit 0; fi\n" +
            "echo \"WIFI_ON=$(nmcli radio wifi 2>/dev/null | tr '[:upper:]' '[:lower:]')\"\n" +
            "echo \"WIFI_DEV=$(nmcli -t -f DEVICE,TYPE device status 2>/dev/null | awk -F: '$2==\\\"wifi\\\"{print $1; exit}')\"\n" +
            "echo \"ACTIVE_SSID=$(nmcli -t -f ACTIVE,SSID dev wifi 2>/dev/null | awk -F: '$1==\\\"yes\\\"{print $2; exit}')\"\n" +
            "echo '__NETWORKS__'\n" +
            "nmcli -t -f IN-USE,SSID,SIGNAL,SECURITY device wifi list --rescan yes 2>/dev/null || true\n"

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
                        root.execSh(root.wifiOn ? "nmcli radio wifi off" : "nmcli radio wifi on", function() { root.refresh() })
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
                    onClicked: root.refresh()
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
                                // Connect to SSID (may prompt in terminal if password needed; works for open/known nets).
                                const ssid = modelData.ssid
                                root.execSh("nmcli dev wifi connect " + JSON.stringify(ssid) + " 2>/dev/null || true", function() { root.refresh() })
                            }
                        }
                    }
                }
            }
        }
    }
}
