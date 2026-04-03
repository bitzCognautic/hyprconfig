import QtQuick
import QtQuick.Layouts
import Quickshell.Io 0.0

Item {
    id: root

    property var theme
    property var settings

    signal requestClose()
    signal requestOpenSettings()
    signal requestOpenWifiDetails()
    signal requestOpenBluetoothDetails()
    signal requestOpenRecorder()

    property int margin: 12
    property int tileWidth: 118
    property int tileHeight: 54
    property int gridCols: 3
    property int gridGap: 10
    readonly property int innerWidth: (gridCols * tileWidth) + ((gridCols - 1) * gridGap)
    readonly property int gridRows: 3
    readonly property int gridHeight: (gridRows * tileHeight) + ((gridRows - 1) * gridGap)

    property bool wifiOn: false
    property bool btOn: false
    property bool micOn: false
    property bool cameraOn: false
    property string cameraNodeId: ""
    property bool nightlightOn: false
    property bool keepAwakeOn: false
    property bool gameModeOn: false
    property bool cpuPerformanceOn: false
    property string cpuGovernor: ""
    property string powerProfile: ""

    property bool haveNmcli: true
    property bool haveBluetoothctl: true
    property bool haveWpctl: true
    property bool haveCameraToggle: false
    property bool haveNightlight: true
    property bool haveWlsunset: false
    property bool haveGammastep: false
    property bool haveHyprsunset: false
    property string nightlightTool: ""
    property bool haveCpuModeHelper: true
    property bool canSetCpuGovernor: false
    property bool haveSystemdInhibit: true
    property bool haveSystemdRun: true
    property bool haveHyprctl: true
    property bool havePowerprofilesctl: true
    property bool haveWfRecorder: true
    property bool recordingOn: false

    implicitWidth: innerWidth + margin * 2
    implicitHeight: mainColumn.implicitHeight + (margin * 2)

    StdioCollector { id: cmdOut; waitForEnd: true }
    StdioCollector { id: cmdErr; waitForEnd: true }

    Process {
        id: cmd
        stdout: cmdOut
        stderr: cmdErr
        onExited: function(exitCode, exitStatus) {
            cmd.running = false
            const out = (cmdOut.text ?? "").trim()
            const err = (cmdErr.text ?? "").trim()
            const cb = root._pendingCb
            root._pendingCb = null
            if (cb) cb(exitCode, out, err)
            root.pumpQueue()
        }
    }

    Process { id: detached }

    property var _pendingCb: null
    property var _queue: []
    property bool _refreshing: false

    function execSh(script, cb) {
        if (cmd.running) {
            root._queue.push([script, cb])
            return
        }
        root._pendingCb = cb
        cmdOut.waitForEnd = true
        cmdErr.waitForEnd = true
        cmd.command = ["sh", "-lc", script]
        cmd.running = true
    }

    function pumpQueue() {
        if (cmd.running) return
        if (root._queue.length === 0) return
        const next = root._queue.shift()
        root.execSh(next[0], next[1])
    }

    function setKnownMissing(toolFlag) {
        root[toolFlag] = false
    }

    function refreshAll() {
        if (root._refreshing) return
        root._refreshing = true

        const tasks = []

        tasks.push(function(done) {
            root.execSh("command -v nmcli >/dev/null 2>&1", function(code) {
                root.haveNmcli = (code === 0)
                done()
            })
        })
        tasks.push(function(done) {
            if (!root.haveNmcli) return done()
            root.execSh("nmcli radio wifi 2>/dev/null", function(code, out) {
                if (code !== 0) return done()
                root.wifiOn = out.toLowerCase().indexOf("enabled") !== -1
                done()
            })
        })

        tasks.push(function(done) {
            root.execSh("command -v bluetoothctl >/dev/null 2>&1", function(code) {
                root.haveBluetoothctl = (code === 0)
                done()
            })
        })
        tasks.push(function(done) {
            if (!root.haveBluetoothctl) return done()
            root.execSh("bluetoothctl show 2>/dev/null | grep -i '^\\s*Powered:' || true", function(code, out) {
                const s = out.toLowerCase()
                root.btOn = (s.indexOf("yes") !== -1 || s.indexOf("on") !== -1)
                done()
            })
        })

        tasks.push(function(done) {
            root.execSh("command -v wpctl >/dev/null 2>&1", function(code) {
                root.haveWpctl = (code === 0)
                done()
            })
        })
        tasks.push(function(done) {
            if (!root.haveWpctl) {
                root.micOn = false
                return done()
            }
            root.execSh("wpctl get-volume @DEFAULT_AUDIO_SOURCE@ 2>/dev/null || true", function(code, out) {
                const s = (out ?? "").trim()
                if (s.length === 0 || s.toLowerCase().indexOf("volume:") === -1) {
                    root.micOn = false
                    root.haveWpctl = false
                    return done()
                }
                root.micOn = s.indexOf("[MUTED]") === -1
                done()
            })
        })
        tasks.push(function(done) {
            if (!root.haveWpctl) {
                root.haveCameraToggle = false
                root.cameraOn = false
                root.cameraNodeId = ""
                return done()
            }
            root.execSh(
                'cam_id="$(pw-dump 2>/dev/null | jq -r ".[] | select(.type == \\"PipeWire:Interface:Node\\") | select(.info.props[\\"media.class\\"] == \\"Video/Source\\") | .id" 2>/dev/null | head -n1)"; ' +
                '[ -n "$cam_id" ] && wpctl get-volume "$cam_id" 2>/dev/null | sed "1s/^/ID=$cam_id /" || true',
                function(code, out) {
                const s = (out ?? "").trim()
                const m = s.match(/^ID=(\S+)\s+(.*)$/)
                if (!m) {
                    root.haveCameraToggle = false
                    root.cameraOn = false
                    root.cameraNodeId = ""
                    return done()
                }
                root.cameraNodeId = m[1]
                const vol = m[2]
                root.haveCameraToggle = (vol.length > 0 && vol.toLowerCase().indexOf("volume:") !== -1)
                root.cameraOn = root.haveCameraToggle && vol.indexOf("[MUTED]") === -1
                done()
            })
        })

	        tasks.push(function(done) {
	            // Prefer hyprsunset only if IPC is reachable.
	            root.execSh(
	                "have_wlsunset=0; have_gammastep=0; have_hyprsunset=0;\n" +
	                "command -v wlsunset >/dev/null 2>&1 && have_wlsunset=1;\n" +
	                "command -v gammastep >/dev/null 2>&1 && have_gammastep=1;\n" +
	                "if command -v hyprctl >/dev/null 2>&1; then\n" +
	                "  hyprctl -j hyprsunset >/dev/null 2>&1 && have_hyprsunset=1;\n" +
	                "fi;\n" +
	                "echo \"WLSUNSET=${have_wlsunset}\"\n" +
	                "echo \"GAMMASTEP=${have_gammastep}\"\n" +
	                "echo \"HYPRSUNSET=${have_hyprsunset}\"\n" +
	                "if [ \"$have_hyprsunset\" = 1 ]; then echo hyprsunset;\n" +
	                "elif [ \"$have_wlsunset\" = 1 ]; then echo wlsunset;\n" +
	                "elif [ \"$have_gammastep\" = 1 ]; then echo gammastep;\n" +
	                "else echo; fi",
	                function(code, out) {
	                    const lines = (out ?? "").trim().split("\n").map(s => s.trim()).filter(Boolean)
	                    root.haveWlsunset = lines.some(l => l === "WLSUNSET=1")
	                    root.haveGammastep = lines.some(l => l === "GAMMASTEP=1")
	                    root.haveHyprsunset = lines.some(l => l === "HYPRSUNSET=1")
	                    // The last line is our chosen tool name (may be empty).
	                    root.nightlightTool = (lines[lines.length - 1] ?? "").trim()
	                    root.haveNightlight = root.haveHyprsunset || root.haveWlsunset || root.haveGammastep
	                    done()
	                }
	            )
	        })
	        tasks.push(function(done) {
	            if (!root.haveNightlight) return done()
	            // If hyprsunset IPC is reachable, use it as source of truth for state.
	            if (root.haveHyprsunset && root.nightlightTool === "hyprsunset") {
	                root.execSh("hyprctl -j hyprsunset 2>/dev/null || echo '{}'", function(code, out) {
	                    try {
	                        const j = JSON.parse((out ?? "").trim() || "{}")
	                        const t = Number(j.temperature ?? 6500)
	                        root.nightlightOn = isFinite(t) && t !== 6500
	                    } catch (e) {
	                        root.nightlightOn = false
	                    }
	                    done()
	                })
	                return
	            }
	            root.execSh("pgrep -x " + root.nightlightTool + " >/dev/null 2>&1", function(code) {
	                root.nightlightOn = (code === 0)
	                done()
	            })
	        })

        tasks.push(function(done) {
            root.execSh("command -v systemd-inhibit >/dev/null 2>&1", function(code) {
                root.haveSystemdInhibit = (code === 0)
                done()
            })
        })
        tasks.push(function(done) {
            root.execSh("command -v ~/.local/bin/eink-cpu-mode >/dev/null 2>&1 || [ -x \"$HOME/.local/bin/eink-cpu-mode\" ]", function(code) {
                root.haveCpuModeHelper = (code === 0)
                done()
            })
        })
        tasks.push(function(done) {
            if (!root.haveCpuModeHelper) {
                root.cpuGovernor = ""
                root.cpuPerformanceOn = false
                return done()
            }
            root.execSh("~/.local/bin/eink-cpu-mode status 2>/dev/null || true", function(code, out) {
                const gov = (out ?? "").trim().toLowerCase()
                root.cpuGovernor = gov
                root.cpuPerformanceOn = (gov === "performance")
                done()
            })
        })
        tasks.push(function(done) {
            if (!root.haveCpuModeHelper) {
                root.canSetCpuGovernor = false
                return done()
            }
            root.execSh("~/.local/bin/eink-cpu-mode can-set 2>/dev/null || true", function(code, out) {
                root.canSetCpuGovernor = ((out ?? "").trim() === "1")
                done()
            })
        })
        tasks.push(function(done) {
            root.execSh("command -v systemd-run >/dev/null 2>&1 && command -v systemctl >/dev/null 2>&1", function(code) {
                root.haveSystemdRun = (code === 0)
                done()
            })
        })
        tasks.push(function(done) {
            if (root.haveSystemdRun) {
                root.execSh("systemctl --user is-active --quiet eink-keep-awake.service", function(code) {
                    root.keepAwakeOn = (code === 0)
                    done()
                })
                return
            }
            if (!root.haveSystemdInhibit) return done()
            root.execSh("pgrep -f 'systemd-inhibit.*eink-keep-awake' >/dev/null 2>&1", function(code) {
                root.keepAwakeOn = (code === 0)
                done()
            })
        })

        tasks.push(function(done) {
            root.execSh("command -v hyprctl >/dev/null 2>&1", function(code) {
                root.haveHyprctl = (code === 0)
                done()
            })
        })
        tasks.push(function(done) {
            root.execSh("command -v wf-recorder >/dev/null 2>&1", function(code) {
                root.haveWfRecorder = (code === 0)
                done()
            })
        })
        tasks.push(function(done) {
            if (!root.haveWfRecorder) {
                root.recordingOn = false
                return done()
            }
            root.execSh("pgrep -x wf-recorder >/dev/null 2>&1 && echo 1 || echo 0", function(code, out) {
                root.recordingOn = ((out ?? "").trim() === "1")
                done()
            })
        })
        tasks.push(function(done) {
            if (!root.haveHyprctl) return done()
            root.execSh("hyprctl getoption animations:enabled 2>/dev/null | grep -oE 'int:\\s*[01]' || true", function(code, out) {
                const v = out.indexOf("int: 0") !== -1
                root.gameModeOn = v
                done()
            })
        })

        tasks.push(function(done) {
            root.execSh("command -v powerprofilesctl >/dev/null 2>&1", function(code) {
                root.havePowerprofilesctl = (code === 0)
                done()
            })
        })
        tasks.push(function(done) {
            if (!root.havePowerprofilesctl) return done()
            root.execSh("powerprofilesctl get 2>/dev/null || true", function(code, out) {
                root.powerProfile = (out ?? "").trim()
                done()
            })
        })

        let i = 0
        const runNext = function() {
            if (i >= tasks.length) {
                root._refreshing = false
                root.pumpQueue()
                return
            }
            const t = tasks[i++]
            t(runNext)
        }
        runNext()
    }

    Timer {
        interval: 4000
        running: root.visible
        repeat: true
        onTriggered: root.refreshAll()
    }

    Component.onCompleted: root.refreshAll()

    Rectangle {
        anchors.fill: parent
        radius: 22
        color: Qt.rgba(0.08, 0.08, 0.08, 0.96)
        border.width: 1
        border.color: Qt.rgba(root.theme.outline.r, root.theme.outline.g, root.theme.outline.b, 0.35)
    }

    ColumnLayout {
        id: mainColumn
        anchors.fill: parent
        anchors.margins: root.margin
        spacing: 12

        GridLayout {
            columns: 3
            columnSpacing: root.gridGap
            rowSpacing: root.gridGap
            Layout.preferredWidth: root.innerWidth
            Layout.maximumWidth: root.innerWidth

            QuickToggle {
                theme: root.theme
                label: "Wi‑Fi"
                // Nerd Font Material Design: nf-md-wifi_strength_1 (f091f)
                symbol: String.fromCodePoint(0xF091F)
                fallbackSymbol: "wifi"
                checked: root.wifiOn
                enabled: root.haveNmcli
                onClicked: {
                    if (!root.haveNmcli) return
                    root.execSh(root.wifiOn ? "nmcli radio wifi off" : "nmcli radio wifi on", function() { root.refreshAll() })
                }
                onRightClicked: root.requestOpenWifiDetails()
            }

            QuickToggle {
                theme: root.theme
                label: "Bluetooth"
                // Nerd Font Material Design: nf-md-bluetooth (f00af)
                symbol: String.fromCodePoint(0xF00AF)
                fallbackSymbol: "bluetooth"
                checked: root.btOn
                enabled: root.haveBluetoothctl
                onClicked: {
                    if (!root.haveBluetoothctl) return
                    root.execSh(root.btOn ? "bluetoothctl power off" : "bluetoothctl power on", function() { root.refreshAll() })
                }
                onRightClicked: root.requestOpenBluetoothDetails()
            }

            QuickToggle {
                theme: root.theme
                label: "Mic"
                iconFontFamily: "Material Symbols Rounded"
                iconFontFamilyFallback: "Material Symbols Rounded"
                symbol: root.micOn ? "mic" : "mic_off"
                fallbackSymbol: root.micOn ? "mic" : "mic_off"
                checked: root.micOn
                enabled: root.haveWpctl
                onClicked: {
                    if (!root.haveWpctl) return
                    root.execSh("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle 2>/dev/null || true", function() { root.refreshAll() })
                }
            }

            QuickToggle {
                theme: root.theme
                label: "Camera"
                iconFontFamily: "Material Symbols Rounded"
                iconFontFamilyFallback: "Material Symbols Rounded"
                symbol: root.cameraOn ? "videocam" : "videocam_off"
                fallbackSymbol: root.cameraOn ? "videocam" : "videocam_off"
                checked: root.cameraOn
                enabled: root.haveCameraToggle
                onClicked: {
                    if (!root.haveCameraToggle) return
                    root.execSh("wpctl set-mute " + root.cameraNodeId + " toggle 2>/dev/null || true", function() { root.refreshAll() })
                }
            }

            QuickToggle {
                theme: root.theme
                label: "Nightlight"
                // Nerd Font Material Design: nf-md-weather_night (f0594)
                symbol: String.fromCodePoint(0xF0594)
                fallbackSymbol: "nightlight"
                checked: root.nightlightOn
                enabled: root.haveNightlight
	                onClicked: {
		                    if (!root.haveNightlight) return
		                    if (root.nightlightOn) {
		                        if (root.haveHyprsunset && root.nightlightTool === "hyprsunset") {
		                            root.execSh("hyprctl hyprsunset identity >/dev/null 2>&1 || true", function() { root.refreshAll() })
		                        } else {
		                            root.execSh(
		                                "pkill -x " + root.nightlightTool + " >/dev/null 2>&1 || true; " +
	                                "sleep 0.05; " +
	                                "pgrep -x " + root.nightlightTool + " >/dev/null 2>&1 && echo 1 || echo 0",
	                                function(code, out) {
		                                    root.nightlightOn = ((out ?? "").trim() === "1")
	                                    root.refreshAll()
	                                }
	                            )
		                        }
		                    } else {
		                        if (root.haveHyprsunset && root.nightlightTool === "hyprsunset") {
		                            // Ensure daemon is running, then set a warm temp.
		                            root.execSh(
		                                "pgrep -x hyprsunset >/dev/null 2>&1 || (hyprsunset >/dev/null 2>&1 &); " +
	                                "sleep 0.05; " +
	                                "hyprctl hyprsunset temperature 3200 >/dev/null 2>&1 && " +
	                                "hyprctl hyprsunset gamma 80 >/dev/null 2>&1",
	                                function(code) {
	                                    if (code === 0) return root.refreshAll()
	                                    // Fallback to wlsunset/gammastep if IPC still fails.
	                                    if (root.haveWlsunset) root.nightlightTool = "wlsunset"
	                                    else if (root.haveGammastep) root.nightlightTool = "gammastep"
	                                    root.refreshAll()
	                                }
	                            )
	                        } else if (root.nightlightTool === "wlsunset") {
	                            // Force a warm tone regardless of time-of-day (and verify it stays running).
	                            let dayT = Math.round(root.settings?.nightlightTempDay ?? 3400)
	                            let nightT = Math.round(root.settings?.nightlightTempNight ?? 3200)
	                            // wlsunset requires day temp > night temp.
	                            if (dayT <= nightT) dayT = nightT + 100
	                            root.execSh(
	                                "pkill -x wlsunset >/dev/null 2>&1 || true; " +
	                                // Keep it warm even during "day" by using a low max temp.
	                                "(nohup wlsunset -T " + dayT + " -t " + nightT + " >/tmp/eink-wlsunset.log 2>&1 &) ; " +
	                                "sleep 0.10; " +
	                                "pgrep -x wlsunset >/dev/null 2>&1 && echo 1 || echo 0",
	                                function(code, out) {
	                                    root.nightlightOn = ((out ?? "").trim() === "1")
	                                    root.refreshAll()
	                                }
	                            )
	                        } else if (root.nightlightTool === "gammastep") {
	                            root.execSh(
	                                "pkill -x gammastep >/dev/null 2>&1 || true; " +
	                                "(nohup gammastep -O 3200 >/tmp/eink-gammastep.log 2>&1 &) ; " +
	                                "sleep 0.10; " +
	                                "pgrep -x gammastep >/dev/null 2>&1 && echo 1 || echo 0",
	                                function(code, out) {
		                                    root.nightlightOn = ((out ?? "").trim() === "1")
	                                    root.refreshAll()
	                                }
	                            )
	                        } else {
	                            root.refreshAll()
	                        }
	                    }
	                }
            }

            QuickToggle {
                theme: root.theme
                label: "Keep Awake"
                // Nerd Font Material Design: nf-md-sleep_off (f04b3)
                symbol: String.fromCodePoint(0xF04B3)
                fallbackSymbol: "coffee"
                checked: root.keepAwakeOn
                enabled: root.haveSystemdInhibit
                onClicked: {
                    if (!root.haveSystemdInhibit) return
                    if (root.keepAwakeOn) {
                        if (root.haveSystemdRun) {
                            root.execSh("systemctl --user stop eink-keep-awake.service 2>/dev/null || true", function() { root.refreshAll() })
                        } else {
                            root.execSh("pkill -f 'eink-keep-awake' || true", function() { root.refreshAll() })
                        }
                    } else {
                        if (root.haveSystemdRun) {
                            root.execSh("systemd-run --user --unit=eink-keep-awake --collect systemd-inhibit --what=idle:sleep --why=eink-keep-awake sleep infinity >/dev/null 2>&1 || true", function() { root.refreshAll() })
                        } else {
                            detached.command = ["systemd-inhibit", "--what=idle:sleep", "--why=eink-keep-awake", "sleep", "infinity"]
                            detached.startDetached()
                            root.refreshAll()
                        }
                    }
                }
            }

            QuickToggle {
                theme: root.theme
                label: "Game Mode"
                // Nerd Font Material Design: nf-md-gamepad_variant (f0297)
                symbol: String.fromCodePoint(0xF0297)
                fallbackSymbol: "sports_esports"
                checked: root.gameModeOn
                enabled: root.haveHyprctl
                onClicked: {
                    if (!root.haveHyprctl) return
                    const on = !root.gameModeOn
                    root.execSh(on
                        ? "hyprctl --batch 'keyword animations:enabled 0; keyword decoration:blur:enabled 0' >/dev/null 2>&1 || true"
                        : "hyprctl --batch 'keyword animations:enabled 1; keyword decoration:blur:enabled 1' >/dev/null 2>&1 || true",
                        function() { root.refreshAll() })
                }
            }

            QuickToggle {
                theme: root.theme
                label: "Settings"
                // Nerd Font Material Design: nf-md-cog (f0493)
                symbol: String.fromCodePoint(0xF0493)
                fallbackSymbol: "settings"
                checked: false
                enabled: true
                onClicked: root.requestOpenSettings()
            }

            QuickToggle {
                theme: root.theme
                label: root.recordingOn ? "Stop" : "Record"
                // Nerd Font Material Design:
                //   nf-md-video (f03e8)
                //   nf-md-stop (f04db)
                symbol: root.recordingOn ? String.fromCodePoint(0xF04DB) : String.fromCodePoint(0xF03E8)
                fallbackSymbol: root.recordingOn ? "stop" : "videocam"
                checked: root.recordingOn
                enabled: root.haveWfRecorder
                onClicked: {
                    if (!root.haveWfRecorder) return
                    if (root.recordingOn) {
                        root.execSh("pkill -INT wf-recorder >/dev/null 2>&1 || true; ~/.local/bin/eink-notify \"Recording stopped\" \"\" || true", function() { root.refreshAll() })
                        return
                    }
                    root.requestOpenRecorder()
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            height: 1
            radius: 1
            color: Qt.rgba(root.theme.outline.r, root.theme.outline.g, root.theme.outline.b, 0.35)
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 8

            Text {
                id: powerTitle
                text: "Power profile"
                color: root.theme.textMuted
                font.family: root.theme.fontFamily
                font.pixelSize: 11
                font.weight: Font.DemiBold
            }

            RowLayout {
                id: profilesRow
                Layout.fillWidth: true
                spacing: 8
                Layout.preferredWidth: root.innerWidth
                Layout.maximumWidth: root.innerWidth

                Repeater {
                    model: [
                        // Nerd Font Material Design icons:
                        //   nf-md-leaf (f032a)
                        //   nf-md-tune (f062e)
                        //   nf-md-speedometer (f04c5)
                        ({ profile: "power-saver", label: "Saver", symbol: String.fromCodePoint(0xF032A), fallbackSymbol: "energy_savings_leaf" }),
                        ({ profile: "balanced", label: "Balanced", symbol: String.fromCodePoint(0xF062E), fallbackSymbol: "tune" }),
                        ({ profile: "performance", label: "Performance", symbol: String.fromCodePoint(0xF04C5), fallbackSymbol: "speed" }),
                    ]
                    delegate: Rectangle {
                        readonly property bool active: root.powerProfile === modelData.profile
                        Layout.fillWidth: false
                        Layout.preferredWidth: Math.floor((root.innerWidth - (profilesRow.spacing * 2)) / 3)
                        Layout.maximumWidth: Layout.preferredWidth
                        height: 42
                        radius: 14
                        color: !root.havePowerprofilesctl
                            ? Qt.rgba(root.theme.surfaceAlt.r, root.theme.surfaceAlt.g, root.theme.surfaceAlt.b, 0.45)
                            : (active
                                ? Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.92)
                                : Qt.rgba(root.theme.surfaceAlt.r, root.theme.surfaceAlt.g, root.theme.surfaceAlt.b, 0.95))

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 10
                            spacing: 8

                            EinkSymbol {
                                symbol: modelData.symbol
                                fallbackSymbol: modelData.fallbackSymbol
                                fontFamily: root.theme.iconFontFamily
                                fontFamilyFallback: root.theme.iconFontFamilyFallback
                                color: (!root.havePowerprofilesctl
                                    ? Qt.rgba(root.theme.textMuted.r, root.theme.textMuted.g, root.theme.textMuted.b, 0.7)
                                    : (active ? root.theme.onAccent : root.theme.text))
                                size: 18
                                Layout.alignment: Qt.AlignVCenter
                            }

                            Text {
                                text: modelData.label
                                color: (!root.havePowerprofilesctl
                                    ? Qt.rgba(root.theme.textMuted.r, root.theme.textMuted.g, root.theme.textMuted.b, 0.7)
                                    : (active ? root.theme.onAccent : root.theme.text))
                                font.family: root.theme.fontFamily
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                                Layout.alignment: Qt.AlignVCenter
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            enabled: root.havePowerprofilesctl
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.execSh("powerprofilesctl set " + modelData.profile + " 2>/dev/null || true", function() { root.refreshAll() })
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                height: 42
                radius: 14
                color: !root.haveCpuModeHelper || !root.canSetCpuGovernor
                    ? Qt.rgba(root.theme.surfaceAlt.r, root.theme.surfaceAlt.g, root.theme.surfaceAlt.b, 0.45)
                    : (root.cpuPerformanceOn
                        ? Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.92)
                        : Qt.rgba(root.theme.surfaceAlt.r, root.theme.surfaceAlt.g, root.theme.surfaceAlt.b, 0.95))

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 8

                    EinkSymbol {
                        symbol: root.cpuPerformanceOn ? "speed" : "eco"
                        fallbackSymbol: root.cpuPerformanceOn ? "speed" : "eco"
                        fontFamily: "Material Symbols Rounded"
                        fontFamilyFallback: "Material Symbols Rounded"
                        color: (!root.haveCpuModeHelper || !root.canSetCpuGovernor
                            ? Qt.rgba(root.theme.textMuted.r, root.theme.textMuted.g, root.theme.textMuted.b, 0.7)
                            : (root.cpuPerformanceOn ? root.theme.onAccent : root.theme.text))
                        size: 18
                        Layout.alignment: Qt.AlignVCenter
                    }

                    Text {
                        text: root.cpuPerformanceOn
                            ? "CPU governor: Performance"
                            : ("CPU governor: " + (root.cpuGovernor.length > 0 ? root.cpuGovernor : "Powersave"))
                        color: (!root.haveCpuModeHelper || !root.canSetCpuGovernor
                            ? Qt.rgba(root.theme.textMuted.r, root.theme.textMuted.g, root.theme.textMuted.b, 0.7)
                            : (root.cpuPerformanceOn ? root.theme.onAccent : root.theme.text))
                        font.family: root.theme.fontFamily
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    enabled: root.haveCpuModeHelper && root.canSetCpuGovernor
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (!root.haveCpuModeHelper || !root.canSetCpuGovernor) return
                        const nextGov = root.cpuPerformanceOn ? "powersave" : "performance"
                        root.execSh("~/.local/bin/eink-cpu-mode set " + nextGov + " >/dev/null 2>&1 || true", function() { root.refreshAll() })
                    }
                }
            }
        }

    }
}
