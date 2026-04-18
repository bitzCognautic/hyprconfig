import QtQuick
import Quickshell
import Quickshell.Io 0.0

QtObject {
    id: theme

    property string mode: "dark"
    function envStr(name) {
        const v = Quickshell.env(name)
        return (typeof v === "string") ? v : ""
    }

    readonly property string home: envStr("HOME")
    readonly property string cacheHome: {
        const xdg = envStr("XDG_CACHE_HOME")
        if (xdg.length) return xdg
        return home.length ? (home + "/.cache") : ""
    }

    // Keep in sync with ~/.local/bin/eink-wallpaper (writes to ~/.cache/quickshell/eink/colors.json).
    property string colorsPath: cacheHome.length ? (cacheHome + "/quickshell/eink/colors.json") : Quickshell.cachePath("eink/colors.json")
    property string fontFamily: "Google Sans"
    // Primary icons: Nerd Font glyphs. Fallback: Material Symbols.
    // (Arch typically has JetBrains Nerd Font installed, not "Symbols Nerd Font".)
    readonly property var _families: Qt.fontFamilies()
    property string iconFontFamily: (_families.indexOf("JetBrainsMonoNL Nerd Font Propo") !== -1)
        ? "JetBrainsMonoNL Nerd Font Propo"
        : ((_families.indexOf("JetBrainsMono Nerd Font Propo") !== -1)
            ? "JetBrainsMono Nerd Font Propo"
            : ((_families.indexOf("JetBrainsMonoNL Nerd Font") !== -1)
                ? "JetBrainsMonoNL Nerd Font"
                : ((_families.indexOf("JetBrainsMono Nerd Font") !== -1)
                    ? "JetBrainsMono Nerd Font"
                    : "Material Symbols Rounded")))
    property string iconFontFamilyFallback: "Material Symbols Rounded"

    // FileView hot-reload can be flaky with some FS/update patterns.
    // Use a tiny polling reader to ensure theme updates without restarting quickshell.
    // Palette generation is handled exclusively by ~/.local/bin/eink-wallpaper
    // so matugen only runs when the wallpaper actually changes.
    property string _rawColorsText: ""
    property string _colorsMtime: ""

    property var readOut: StdioCollector { waitForEnd: true }
    property var readErr: StdioCollector { waitForEnd: true }

    property var readCmd: Process {
        stdout: theme.readOut
        stderr: theme.readErr
        onExited: function(exitCode, exitStatus) {
            theme.readCmd.running = false
            const txt = (theme.readOut.text ?? "")
            if (txt && txt !== theme._rawColorsText) theme._rawColorsText = txt
        }
    }

    property var statOut: StdioCollector { waitForEnd: true }
    property var statErr: StdioCollector { waitForEnd: true }

    property var statCmd: Process {
        stdout: theme.statOut
        stderr: theme.statErr
        onExited: function(exitCode, exitStatus) {
            theme.statCmd.running = false
            const out = (theme.statOut.text ?? "").trim()
            if (!out || out.length === 0) return

            const mColors = (out.match(/(?:^|\\s)colors=(\\d+)/) || [])[1] ?? ""
            const colorsMtime = mColors.length ? mColors : "0"

            if (colorsMtime !== theme._colorsMtime) {
                theme._colorsMtime = colorsMtime
                // Trigger a read on change.
                if (!theme.readCmd.running) {
                    theme.readOut.waitForEnd = true
                    theme.readErr.waitForEnd = true
                    theme.readCmd.command = ["sh", "-lc", "cat " + JSON.stringify(theme.colorsPath) + " 2>/dev/null || true"]
                    theme.readCmd.running = true
                }
            }
        }
    }

    property var pollTimer: Timer {
        // "Realtime" feeling without heavy IO: check mtime frequently,
        // only re-read the file when it changes.
        interval: 250
        running: true
        repeat: true
        onTriggered: {
            if (theme.statCmd.running) return
            if (!theme.colorsPath || theme.colorsPath.length === 0) return
            theme.statOut.waitForEnd = true
            theme.statErr.waitForEnd = true
            theme.statCmd.command = ["sh", "-lc",
                "echo -n colors=$(stat -c %Y " + JSON.stringify(theme.colorsPath) + " 2>/dev/null || echo 0); " +
                "echo"
            ]
            theme.statCmd.running = true
        }
    }

    property var json: {
        const raw = theme._rawColorsText
        try {
            if (!raw || raw.trim().length === 0) return ({})
            return JSON.parse(raw)
        } catch (e) {
            return ({})
        }
    }

    property var colors: (json.colors ?? ({}))

    function c(name, fallback) {
        const entry = colors[name]
        if (!entry) return fallback
        const picked = entry[mode] ?? entry.default ?? entry.dark ?? entry.light
        const val = picked?.color ?? picked
        return (val && typeof val === "string") ? val : fallback
    }

    // Bar palette (matches inspo: muted surface + strong primary accent)
    property color surface: c("surface_container_high", "#2b2a28")
    property color surfaceAlt: c("surface_container", "#22211f")
    property color outline: c("outline_variant", "#4a4739")
    property color text: c("on_surface", "#efe9db")
    property color textMuted: c("on_surface_variant", "#cdc6b4")

    function _hexToRgb(hex) {
        try {
            if (!hex || typeof hex !== "string") return null
            const h = hex.trim().replace("#", "")
            if (h.length !== 6) return null
            const r = parseInt(h.slice(0, 2), 16) / 255
            const g = parseInt(h.slice(2, 4), 16) / 255
            const b = parseInt(h.slice(4, 6), 16) / 255
            if (![r, g, b].every(x => isFinite(x))) return null
            return ({ r, g, b })
        } catch (e) {
            return null
        }
    }

    function _srgbToLinear(x) {
        return (x <= 0.04045) ? (x / 12.92) : Math.pow((x + 0.055) / 1.055, 2.4)
    }

    function _luminance(rgb) {
        const r = _srgbToLinear(rgb.r)
        const g = _srgbToLinear(rgb.g)
        const b = _srgbToLinear(rgb.b)
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }

    function _saturation(rgb) {
        const max = Math.max(rgb.r, rgb.g, rgb.b)
        const min = Math.min(rgb.r, rgb.g, rgb.b)
        if (max === 0) return 0
        return (max - min) / max
    }

    function _pickAccent() {
        // For very low-saturation (B/W) wallpapers matugen may pick a near-gray primary,
        // which looks like "no change". Prefer a more distinct palette color, then fall back
        // to a clean white accent.
        const primary = c("primary", "#ffffff")
        const secondary = c("secondary", primary)
        const tertiary = c("tertiary", secondary)

        const surfaceHex = c("surface_container_high", "#2b2a28")
        const p = _hexToRgb(primary)
        const s = _hexToRgb(surfaceHex)
        if (!p || !s) return primary

        const sat = _saturation(p)
        const lp = _luminance(p)
        const ls = _luminance(s)
        const closeToSurface = Math.abs(lp - ls) < 0.10

        if (sat < 0.10 || closeToSurface) {
            const cand = [tertiary, secondary, primary, "#ffffff"]
            for (const h of cand) {
                const rgb = _hexToRgb(h)
                if (!rgb) continue
                const l = _luminance(rgb)
                if (Math.abs(l - ls) >= 0.18) return h
            }
            return "#ffffff"
        }

        return primary
    }

    function _onColor(hex) {
        const rgb = _hexToRgb(hex)
        if (!rgb) return "#000000"
        return _luminance(rgb) >= 0.5 ? "#000000" : "#ffffff"
    }

    property color accent: _pickAccent()
    property color onAccent: _onColor(accent)
}
