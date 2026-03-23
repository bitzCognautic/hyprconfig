import QtQuick
import Quickshell
import Quickshell.Io 0.0

Item {
    id: root
    visible: false
    width: 0
    height: 0

    function envStr(name) {
        const v = Quickshell.env(name)
        return (typeof v === "string") ? v : ""
    }

    readonly property string home: envStr("HOME")
    readonly property string configHome: {
        const xdg = envStr("XDG_CONFIG_HOME")
        if (xdg.length) return xdg
        return home.length ? (home + "/.config") : ""
    }
    readonly property string configDir: configHome.length ? (configHome + "/eink") : ""
    readonly property string settingsPath: configDir.length ? (configDir + "/settings.json") : ""
    readonly property string wallpaperPathFile: configDir.length ? (configDir + "/wallpaper") : ""

    property FileView settingsFile: FileView {
        path: root.settingsPath
        preload: true
        watchChanges: true
        atomicWrites: true
        printErrors: false
    }

    property FileView wallpaperFile: FileView {
        path: root.wallpaperPathFile
        preload: true
        watchChanges: true
        printErrors: false
    }

    property var json: {
        try {
            const raw = settingsFile.__text
            if (!raw || raw.trim().length === 0) return ({})
            return JSON.parse(raw)
        } catch (e) {
            return ({})
        }
    }

    property string wallpaperPath: {
        try {
            const raw = (wallpaperFile.__text ?? "").trim()
            const lines = raw.split("\n").map(s => s.trim()).filter(Boolean)
            // First non-comment line
            for (const ln of lines) {
                if (ln.startsWith("#")) continue
                return ln
            }
            return ""
        } catch (e) {
            return ""
        }
    }

    function n(name, fallback) {
        const v = json[name]
        return (typeof v === "number" && isFinite(v)) ? v : fallback
    }

    function b(name, fallback) {
        const v = json[name]
        return (typeof v === "boolean") ? v : fallback
    }

    // Top bar defaults match current look.
    property int pillTopMargin: Math.max(0, Math.round(n("pillTopMargin", 5)))
    property int pillHeight: Math.max(24, Math.round(n("pillHeight", 34)))
    // Horizontal padding (per side) inside the pill.
    // `-1` means "auto" (treated as 0px by default).
    property int pillHPadding: Math.max(-1, Math.round(n("pillHPadding", -1)))
    property real pillOpacity: Math.max(0.15, Math.min(1.0, n("pillOpacity", 1.0)))

    // Popup spacing
    property int popupGap: Math.max(0, Math.round(n("popupGap", 10)))
    property int popupOverlap: Math.max(0, Math.round(n("popupOverlap", 10)))

    // Idle behavior (hypridle)
    property int idleScreenOffSeconds: Math.max(0, Math.round(n("idleScreenOffSeconds", 120)))
    property int idleSleepSeconds: Math.max(0, Math.round(n("idleSleepSeconds", 900)))

    // Nightlight (wlsunset)
    property int nightlightTempDay: Math.max(2000, Math.min(6500, Math.round(n("nightlightTempDay", 3400))))
    property int nightlightTempNight: Math.max(2000, Math.min(6500, Math.round(n("nightlightTempNight", 3200))))

    Component.onCompleted: {
        if (!root.configDir.length) return
        Quickshell.execDetached(["sh", "-lc", "mkdir -p " + JSON.stringify(root.configDir)])
    }

    function save(patchObj) {
        try {
            if (!root.settingsPath.length || !root.configDir.length) return

            const cur = root.json
            const next = ({})
            if (cur && typeof cur === "object") {
                for (const k in cur) next[k] = cur[k]
            }
            if (patchObj && typeof patchObj === "object") {
                for (const k2 in patchObj) next[k2] = patchObj[k2]
            }

            const text = JSON.stringify(next, null, 2) + "\n"
            settingsFile.setText(text)
        } catch (e) {
            console.warn("settings save exception", e)
        }
    }

    function applyWallpaper(path) {
        try {
            if (!path || !path.trim().length) return
            Quickshell.execDetached(["sh", "-lc", "$HOME/.local/bin/eink-wallpaper " + JSON.stringify(path.trim())])
        } catch (e) {
            console.warn("applyWallpaper failed", e)
        }
    }

    function applyIdle() {
        try {
            Quickshell.execDetached(["sh", "-lc", "$HOME/.local/bin/eink-hypridle-apply --start"])
        } catch (e) {
            console.warn("applyIdle failed", e)
        }
    }

    // Dynamic accent colors removed.
}
