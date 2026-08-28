import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Quickshell.Services.Mpris

// Omarchy top bar. Owns the per-bar state, probes, and IPC; per-feature
// surfaces (Bar, *Popup) and widgets (Module, Workspace,
// Bloom, …) read from `root` via `root: root` injection. Palette comes
// from the shared Theme; colours are re-exposed on root so sibling files
// keep their `root.paper` bindings.
Item {
    id: root

    required property var theme

    readonly property color paper:   theme.paper
    readonly property color ink:     theme.ink
    readonly property color inkDeep: theme.inkDeep
    readonly property color sumi:    theme.inkDeep
    readonly property color indigo:  theme.indigo
    readonly property color seal:    theme.seal
    readonly property color bg:      theme.bg
    readonly property color fg:      theme.fg
    readonly property color muted:   theme.muted
    readonly property color accent:  theme.accent
    readonly property color warn:    theme.warn
    readonly property color sep:     theme.sep

    // Blend a base color ~55% toward white — keeps the hue visible and never
    // clamps to pure white (unlike Qt.lighter, which washes out light accents).
    function nearWhite(base) {
        return Qt.rgba(
            base.r + (1.0 - base.r) * 0.55,
            base.g + (1.0 - base.g) * 0.55,
            base.b + (1.0 - base.b) * 0.55,
            1.0
        );
    }
    readonly property color tintCpu:    root.nearWhite(theme.seal)
    readonly property color tintRam:    root.nearWhite(theme.seal)
    readonly property color tintVol:    root.nearWhite(theme.seal)
    readonly property color tintBat:    root.nearWhite(theme.seal)
    readonly property color tintCorne:  root.nearWhite(theme.seal)

    // Traces the corne keyboard outline onto a Canvas 2D context.
    function cornePath(ctx) {
        ctx.moveTo(1.2, 5.91);
        ctx.quadraticCurveTo(1.2, 5.61, 1.5, 5.61);
        ctx.lineTo(6.98, 5.61);
        ctx.quadraticCurveTo(7.13, 5.61, 7.13, 5.46);
        ctx.lineTo(7.13, 5.02);
        ctx.quadraticCurveTo(7.13, 4.87, 7.28, 4.87);
        ctx.lineTo(9.97, 4.87);
        ctx.quadraticCurveTo(10.12, 4.87, 10.12, 4.72);
        ctx.lineTo(10.12, 4.63);
        ctx.quadraticCurveTo(10.12, 4.48, 10.27, 4.48);
        ctx.lineTo(13.25, 4.48);
        ctx.quadraticCurveTo(13.4, 4.48, 13.4, 4.63);
        ctx.lineTo(13.4, 4.72);
        ctx.quadraticCurveTo(13.4, 4.87, 13.55, 4.87);
        ctx.lineTo(16.24, 4.87);
        ctx.quadraticCurveTo(16.39, 4.87, 16.39, 5.02);
        ctx.lineTo(16.39, 5.06);
        ctx.quadraticCurveTo(16.39, 5.21, 16.54, 5.21);
        ctx.lineTo(19.43, 5.21);
        ctx.quadraticCurveTo(19.58, 5.21, 19.58, 5.36);
        ctx.lineTo(19.58, 5.46);
        ctx.quadraticCurveTo(19.58, 5.61, 19.73, 5.61);
        ctx.lineTo(22.51, 5.61);
        ctx.quadraticCurveTo(22.81, 5.61, 22.81, 5.91);
        ctx.lineTo(22.81, 15.25);
        ctx.quadraticCurveTo(22.81, 15.55, 22.66, 15.81);
        ctx.lineTo(20.61, 19.26);
        ctx.quadraticCurveTo(20.46, 19.52, 20.2, 19.37);
        ctx.lineTo(17.99, 18.15);
        ctx.quadraticCurveTo(17.81, 18.05, 17.61, 18.02);
        ctx.lineTo(11.98, 17.25);
        ctx.quadraticCurveTo(11.78, 17.22, 11.66, 17.06);
        ctx.lineTo(10.24, 15.13);
        ctx.quadraticCurveTo(10.12, 14.97, 9.92, 14.97);
        ctx.lineTo(1.5, 14.97);
        ctx.quadraticCurveTo(1.2, 14.97, 1.2, 14.67);
        ctx.closePath();
    }

    // Hex string of tintCorne — lets the corne SVG Image re-load when theme changes.
    readonly property string corneTintHex: "#" + ((Math.round(tintCorne.r*255)<<16) | (Math.round(tintCorne.g*255)<<8) | Math.round(tintCorne.b*255)).toString(16).padStart(6,"0")

    readonly property string serif: theme.serif
    readonly property string mono:  theme.mono

    readonly property int  cornerRadius: theme.cornerRadius
    readonly property bool round:        theme.round

    // Wired in desktop/shell.qml to the sibling OmniMenu's toggle().
    signal paletteToggleRequested()

    // Kanji numerals 〇 一 二 ... 十.
    readonly property var kanjiNum: ["〇","一","二","三","四","五","六","七","八","九","十"]
    function indexKanji(n) { return n >= 0 && n <= 10 ? kanjiNum[n] : String(n); }

    // BMP Private Use Area icons; written via fromCodePoint so the source
    // stays ASCII-safe.
    readonly property string icoNixos:   String.fromCodePoint(0xf313)  // ❄ snowflake = NixOS
    readonly property string icoBtOn:    String.fromCodePoint(0xf294)
    readonly property string icoVol1:    String.fromCodePoint(0xf026)
    readonly property string icoVol2:    String.fromCodePoint(0xf027)
    readonly property string icoVol3:    String.fromCodePoint(0xf028)
    readonly property string icoMute:    String.fromCodePoint(0xeee8)
    readonly property string icoRefresh: String.fromCodePoint(0xf0450)
    readonly property string icoPower:   String.fromCodePoint(0xf0425)
    readonly property string icoAether:  String.fromCodePoint(0xf03d8)
    readonly property string icoSearch:  String.fromCodePoint(0xf0349)
    readonly property string icoUpdate:  String.fromCodePoint(0xf021)
    readonly property string icoPlug:    String.fromCodePoint(0xf06a5)
    readonly property string icoMusic:   String.fromCodePoint(0xf001)
    readonly property string icoPause:   String.fromCodePoint(0xf04c)
    readonly property string icoCpu:     String.fromCodePoint(0xf2db)  //  microchip
    readonly property string icoMem:     String.fromCodePoint(0xf473)  //  memory
    readonly property string icoBat:     String.fromCodePoint(0xf241)  //  battery-3
    readonly property string icoCorne:   String.fromCodePoint(0xf11c)
    readonly property string icoRam:     String.fromCodePoint(0xefc5)  // ram  //  keyboard
    readonly property string icoPerf:    String.fromCodePoint(0xf0e7)  //  bolt = performance
    readonly property string icoBal:     String.fromCodePoint(0xf2db)  //  chip = balanced (distinct from leaf)
    readonly property string icoQuiet:   String.fromCodePoint(0xf06c)  //  leaf = quiet

    // Current power-profile icon.
    readonly property string profileIcon: {
        const p = root.powerProfile;
        if (p === "performance") return root.icoPerf;
        if (p === "quiet")       return root.icoQuiet;
        return root.icoBal; // balanced (default)
    }

    // Volume icon ramps with level: mute → icoMute, 0 → off, <50 → low, ≥50 → high.
    readonly property string volIcon: {
        if (root.audioMuted) return root.icoMute;
        const v = root.audioVol;
        if (isNaN(v) || v <= 0) return root.icoVol1;
        if (v < 50) return root.icoVol2;
        return root.icoVol3;
    }

    // Battery icon ramps with charge: charging/full → plug, else 10% steps.
    readonly property string batIcon: {
        if (root.batState === "Charging" || root.batState === "Full" || root.batState === "Not charging")
            return root.icoPlug;
        const c = root.batVal;
        const r = [0xf244, 0xf243, 0xf242, 0xf241, 0xf240]; // 
        return String.fromCodePoint(r[Math.min(4, Math.floor(c / 20))]);
    }

    readonly property int barHeight: 34

    // ---------- Edge ----------
    // Drives bar anchors, internal Row/Column flow, and where the toggle
    // arrow points.
    property string barEdge: "top"
    readonly property bool isHorizontal: barEdge === "top" || barEdge === "bottom"


    // ---------- Tooltips ----------
    // A single overlay panel reads these and renders the label near the
    // hovered icon. Positions are bar-window-local; the overlay translates
    // them into its own (full-screen) coordinate space based on barEdge.
    property string tooltipText: ""
    property real   tooltipBarX: 0
    property real   tooltipBarY: 0
    property bool   tooltipShown: false

    function showTooltip(text, x, y) {
        if (!text) return;
        root.tooltipText  = text;
        root.tooltipBarX  = x;
        root.tooltipBarY  = y;
        root.tooltipShown = true;
    }

    function hideTooltip(text) {
        // Guard against a late-fired hide from a module the cursor has
        // already left for another tooltip-bearing module.
        if (!text || root.tooltipText === text) root.tooltipShown = false;
    }

    // ---------- Popup anchor ----------
    // Bar-window-local coordinates, the same coordinate space the tooltip
    // overlay consumes — both surfaces are full-edge PanelWindows so the
    // bar-local point translates 1:1.
    property real popupAnchorX: 0
    property real popupAnchorY: 0
    // Screen the last popup trigger came from; null = default screen.
    // Set by the bar before calling openCalendar/openWeather/openBattery
    // so the popup CardWindow appears on the correct monitor.
    property var popupScreen: null

    // Sorted power profiles for battery popup display.
    readonly property var sortedProfiles: {
        if (root.powerProfiles.length > 0) {
            var out = root.powerProfiles.slice();
            out.sort(function(a,b) {
                var prio = {"performance":0, "balanced":1, "quiet":2};
                return (prio[a]||99) - (prio[b]||99);
            });
            return out;
        }
        return ["performance", "balanced", "quiet"];
    }

    // Bar registers its trigger Items here so openCalendar/Weather/Display
    // can re-anchor on every open — including IPC opens from OmniMenu that
    // don't go through a click handler.
    property Item calendarAnchorItem: null
    property Item weatherAnchorItem:  null
    property Item displayAnchorItem:  null
    property Item batteryAnchorItem:  null

    function anchorPopupTo(item) {
        const p = item.mapToItem(null, item.width / 2, item.height / 2);
        root.popupAnchorX = p.x;
        root.popupAnchorY = p.y;
    }

    // ---------- State ----------
    property int activeWs: 1
    property var existingWs: []
    // +1 = user navigated to a higher-numbered workspace (rightward along
    // the bar), -1 = lower-numbered (leftward), 0 = no recent travel. The
    // active Workspace cell reads this to bias its kanji's entry offset.
    property int lastDirection: 0

    property int cpuVal: 0
    property int memVal: 0
    property real memUsedGB: 0
    property real memTotalGB: 0
    property int cpuTemp: 0
    property int batVal: 0
    property string batState: "Unknown"
    // Instantaneous power draw in watts; magnitude only — direction is in batState.
    property real batPower: 0
    property string batTime: ""

    // Corne keyboard battery levels (-1 = unknown/disconnected).
    property int corneLeft: -1
    property int corneRight: -1

    function refreshCorneBattery() { corneBatteryProbe.running = false; corneBatteryProbe.running = true; }

    property string netIcon: "󰤯"
    property string netKind: "none"   // "eth" | "wifi" | "none"
    property string wifiSsid: ""
    property int    wifiSignal: 0

    // Wi-Fi scan state for the Quick panel. `wifiNetworks` is a list of
    // {ssid, signal, security, inUse} sorted desc by signal. Driven by
    // nmcli; populated on demand by refreshWifi().
    property var    wifiNetworks: []
    property bool   wifiRadioOn: true
    property bool   wifiScanning: false
    property string _wifiNetworksSer: ""

    // iwd-based: omarchy uses iwctl, not nmcli. The probe detects the
    // first station-mode device dynamically so multi-radio laptops work.
    function refreshWifi() {
        if (wifiScanProbe.running) return;
        root.wifiScanning = true;
        wifiScanProbe.running = false;
        wifiScanProbe.running = true;
    }
    function connectWifi(ssid) {
        if (!ssid) return;
        // Saved networks reconnect silently. New networks need a passphrase
        // which we can't prompt for inside Quickshell — for those, the user
        // has to run `iwctl` once manually. After a successful connect the
        // post-action timer re-probes so the inUse flag flips.
        root.run("DEV=$(iwctl --dont-ask device list 2>/dev/null"
                 + " | sed 's/\\x1b\\[[0-9;]*m//g'"
                 + " | awk '/station/{print $1; exit}');"
                 + " [ -n \"$DEV\" ] && iwctl --dont-ask station \"$DEV\" connect "
                 + JSON.stringify(ssid));
        wifiPostConnectTimer.restart();
    }
    function disconnectWifi() {
        root.run("DEV=$(iwctl --dont-ask device list 2>/dev/null"
                 + " | sed 's/\\x1b\\[[0-9;]*m//g'"
                 + " | awk '/station/{print $1; exit}');"
                 + " [ -n \"$DEV\" ] && iwctl --dont-ask station \"$DEV\" disconnect");
        wifiPostConnectTimer.restart();
    }
    function toggleWifiRadio() {
        const target = root.wifiRadioOn ? "off" : "on";
        root.wifiRadioOn = !root.wifiRadioOn;
        root.run("DEV=$(iwctl --dont-ask device list 2>/dev/null"
                 + " | sed 's/\\x1b\\[[0-9;]*m//g'"
                 + " | awk '/^[[:space:]]+[a-z][a-z0-9]+/{print $1; exit}');"
                 + " [ -n \"$DEV\" ] && iwctl --dont-ask device \"$DEV\" set-property Powered " + target);
        wifiPostConnectTimer.restart();
    }
    Timer {
        id: wifiPostConnectTimer
        interval: 800
        repeat: false
        onTriggered: root.refreshWifi()
    }
    property string btIcon:  "󰂲"
    property bool   btPowered: false
    property int    btCount: 0
    // Bluetooth device list for the Quick panel. Each entry:
    // { mac, name, connected, paired, trusted }.
    property var    btDevices: []
    property bool   btScanning: false
    property string _btDevicesSer: ""

    function refreshBluetooth() {
        if (btDevicesProbe.running) return;
        btDevicesProbe.running = false;
        btDevicesProbe.running = true;
    }
    // bluez-tools path (omarchy ships bt-adapter / bt-device, not the
    // bluetoothctl utility). Same semantics as before, different CLI.
    function btConnect(mac) {
        if (!mac) return;
        root.run("bt-device --connect " + mac);
        btPostActionTimer.restart();
    }
    function btDisconnect(mac) {
        if (!mac) return;
        root.run("bt-device --disconnect " + mac);
        btPostActionTimer.restart();
    }
    function btTogglePower() {
        root.btPowered = !root.btPowered;
        // If turning on, unblock rfkill first (blocked on boot for battery savings)
        if (root.btPowered)
            root.run("rfkill unblock bluetooth");
        root.run("bt-adapter -s Powered " + (root.btPowered ? 1 : 0));
        btPostActionTimer.restart();
    }
    function btToggleScan() {
        root.btScanning = !root.btScanning;
        // `bt-adapter -d --timeout N` blocks for N seconds while
        // discovering, so fork it off and let the refresh probe pick up
        // any new devices it surfaces.
        if (root.btScanning) {
            root.run("setsid -f bt-adapter -d --timeout 15 >/dev/null 2>&1");
            btScanStopTimer.restart();
        }
        btPostActionTimer.restart();
    }
    Timer {
        id: btPostActionTimer
        interval: 600
        repeat: false
        onTriggered: root.refreshBluetooth()
    }
    Timer {
        // Clear the "scanning" flag once the bluetoothctl --timeout expires.
        id: btScanStopTimer
        interval: 15000
        repeat: false
        onTriggered: root.btScanning = false
    }
    property string audioIcon: ""
    property int    audioVol: 0
    property bool   audioMuted: false
    // List of PipeWire/Pulse output sinks with the current default flagged.
    // Each entry: { id, name, description, isDefault }. Populated by the
    // audioSinks probe on demand (refreshed when the Audio quick panel opens).
    property var    audioSinks: []
    property string audioDefaultSink: ""
    property string _audioSinksSer: ""

    function setDefaultSink(id) {
        if (!id) return;
        root.audioDefaultSink = id;
        root.run("wpctl set-default " + id);
        // Re-probe so the badge re-evaluates after wpctl applies.
        audioSinksProbe.running = false;
        audioSinksProbe.running = true;
    }
    function refreshAudioSinks() {
        audioSinksProbe.running = false;
        audioSinksProbe.running = true;
    }

    // Current ASUS platform profile (quiet/balanced/performance). Empty when
    // probe hasn't run yet — keeps the Quick detail panel hidden in that case.
    property string powerProfile: ""
    property var    powerProfiles: []  // list of available profiles

    function setPowerProfile(name) {
        if (!name) return;
        root.powerProfile = name;
        root.run("sudo -n platform-profile " + name);
        powerProfileRefreshTimer.restart();
    }

    Timer {
        id: powerProfileRefreshTimer
        interval: 400
        repeat: false
        onTriggered: root.refreshPowerProfile()
    }

    // === Battery charge limit ===
    property int batChargeLimit: 100
    property int _clProbeSeq: 0

    function setBatteryLimit(pct) {
        root.batChargeLimit = pct;
        root._clProbeSeq++;
        root.run("asusctl battery limit " + pct);
        chargeLimitRefreshTimer.restart();
    }
    Timer {
        id: chargeLimitRefreshTimer
        interval: 1200
        repeat: false
        onTriggered: root.refreshChargeLimit()
    }
    function refreshChargeLimit() {
        root._clProbeSeq++;
        chargeLimitProbe.running = false;
        chargeLimitProbe.running = true;
    }
    Process {
        id: chargeLimitProbe
        running: false
        command: ["bash", "-c",
            "cat /sys/class/power_supply/BAT0/charge_control_end_threshold 2>/dev/null || echo 100"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (root._clProbeSeq > 0) root._clProbeSeq--;
                if (root._clProbeSeq > 0) return;
                const v = parseInt(this.text.trim());
                if (!isNaN(v) && root.batChargeLimit !== v) root.batChargeLimit = v;
            }
        }
    }

    // omarchy-update-available exits 0 when the local omarchy clone is
    // behind the latest tag. The bar surfaces a small refresh glyph next
    // to the battery for as long as that's the case; click → launch the
    // floating update terminal.
    property bool   omarchyUpdateAvailable: false
    property string omarchyLatestTag: ""

    function openOmarchyUpdate() {
        root.run("omarchy-launch-floating-terminal-with-presentation omarchy-update");
    }
    function refreshOmarchyUpdateCheck() {
        omarchyUpdateProbe.running = false;
        omarchyUpdateProbe.running = true;
    }

    property string hh: "--"
    property string mm: "--"
    property string dd: "--"
    property string mon: "---"
    property string ap: "AM"
    property string dow: "---"

    // ---------- Calendar popup state ----------
    property bool calendarVisible: false
    property bool batteryVisible: false
    property int calendarMonthOffset: 0
    // Bumped on each open so the cells/title bindings below re-evaluate
    // (new Date() is opaque to QML's dependency tracker — touching this
    // int forces a recompute even when calendarMonthOffset is unchanged).
    property int calendarTick: 0

    // Easter Sunday for any Gregorian year via Butcher's anonymous algorithm.
    // Pure arithmetic, no loops; returns a Date in local time.
    function easterDate(year) {
        const a = year % 19;
        const b = Math.floor(year / 100);
        const c = year % 100;
        const d = Math.floor(b / 4);
        const e = b % 4;
        const f = Math.floor((b + 8) / 25);
        const g = Math.floor((b - f + 1) / 3);
        const h = (19 * a + b - d - g + 15) % 30;
        const i = Math.floor(c / 4);
        const k = c % 4;
        const l = (32 + 2 * e + 2 * i - h - k) % 7;
        const mm = Math.floor((a + 11 * h + 22 * l) / 451);
        const month = Math.floor((h + l - 7 * mm + 114) / 31);   // 3=Mar, 4=Apr
        const day = ((h + l - 7 * mm + 114) % 31) + 1;
        return new Date(year, month - 1, day);
    }

    // Norwegian red days. Caller passes precomputed `easter` (Date) so the
    // outer loop in calendarCells doesn't recompute it per day.
    function norwegianHoliday(year, month, day, easter) {
        if (month === 0  && day === 1)  return "Nyttårsdag";
        if (month === 4  && day === 1)  return "Arbeidernes dag";
        if (month === 4  && day === 17) return "Grunnlovsdagen";
        if (month === 11 && day === 25) return "Første juledag";
        if (month === 11 && day === 26) return "Andre juledag";

        const target = new Date(year, month, day);
        const offset = Math.round((target.getTime() - easter.getTime()) / 86400000);

        if (offset === -3) return "Skjærtorsdag";
        if (offset === -2) return "Langfredag";
        if (offset === 0)  return "Første påskedag";
        if (offset === 1)  return "Andre påskedag";
        if (offset === 39) return "Kristi himmelfartsdag";
        if (offset === 49) return "Første pinsedag";
        if (offset === 50) return "Andre pinsedag";

        return "";
    }

    readonly property var calendarCells: {
        root.calendarTick;  // forces recompute on same-month re-open
        const now = new Date();
        const first = new Date(now.getFullYear(), now.getMonth() + root.calendarMonthOffset, 1);
        const year = first.getFullYear();
        const month = first.getMonth();
        const lastDay = new Date(year, month + 1, 0).getDate();
        // Monday-first week: shift Sunday (0) to slot 6.
        const startDay = (first.getDay() + 6) % 7;
        const today = new Date();
        const isCurrentMonth = year === today.getFullYear() && month === today.getMonth();
        const easter = root.easterDate(year);
        const cells = [];
        for (let i = 0; i < startDay; i++) cells.push({day: 0, today: false, holiday: ""});
        for (let d = 1; d <= lastDay; d++) {
            cells.push({
                day: d,
                today: isCurrentMonth && d === today.getDate(),
                holiday: root.norwegianHoliday(year, month, d, easter)
            });
        }
        while (cells.length < 42) cells.push({day: 0, today: false, holiday: ""});
        return cells;
    }

    readonly property string calendarMonthName: {
        const months = ["JANUARY","FEBRUARY","MARCH","APRIL","MAY","JUNE",
                        "JULY","AUGUST","SEPTEMBER","OCTOBER","NOVEMBER","DECEMBER"];
        const now = new Date();
        return months[(now.getMonth() + root.calendarMonthOffset + 12000) % 12];
    }

    readonly property string calendarYear: {
        const now = new Date();
        const d = new Date(now.getFullYear(), now.getMonth() + root.calendarMonthOffset, 1);
        return String(d.getFullYear());
    }

    // Selected day-of-month within the displayed month; 0 = none. Reset
    // on month nav since the selection only makes sense within the
    // visible month.
    property int selectedDay: 0

    readonly property string selectedDayDetail: {
        if (root.selectedDay <= 0) return "";
        const days   = ["SUNDAY","MONDAY","TUESDAY","WEDNESDAY","THURSDAY","FRIDAY","SATURDAY"];
        const months = ["JAN","FEB","MAR","APR","MAY","JUN","JUL","AUG","SEP","OCT","NOV","DEC"];
        const now = new Date();
        const d = new Date(now.getFullYear(), now.getMonth() + root.calendarMonthOffset, root.selectedDay);
        return days[d.getDay()] + " · " + root.selectedDay + " " + months[d.getMonth()] + " " + d.getFullYear();
    }

    readonly property string selectedDayHoliday: {
        if (root.selectedDay <= 0) return "";
        const cells = root.calendarCells;
        for (let i = 0; i < cells.length; i++) {
            if (cells[i].day === root.selectedDay) return cells[i].holiday;
        }
        return "";
    }

    function openCalendar() {
        // popupAnchorX/Y already set by Bar click handler
        root.calendarMonthOffset = 0;
        root.calendarTick++;
        root.selectedDay = (new Date()).getDate();
        if (root.popupScreen) _calendarPopup.screen = root.popupScreen;
        root.calendarVisible = true;
    }

    function openBattery() {
        // popupAnchorX/Y already set by Bar click handler
        _batteryPopup.screen = root.popupScreen;
        root.batteryVisible = true;
    }

    property int   brightnessPct: 100
    property int   kbdBrightness: 0
    property int   kbdBrightnessMax: 3
    function setBrightness(pct) {
        pct = Math.max(1, Math.min(100, Math.round(pct)));
        root.brightnessPct = pct;
        root.run("brightnessctl set " + pct + "%");
    }
    function setVolume(pct) {
        pct = Math.max(0, Math.min(150, Math.round(pct)));
        root.audioVol = pct;
        root.run("pamixer --allow-boost --set-volume " + pct);
    }
    function toggleMute() {
        root.audioMuted = !root.audioMuted;
        root.run("pamixer -t");
    }
    // ---------- Brightness status ----------
    // brightnessctl monitor does not stream on this kernel; poll at 300ms
    // (reactive OSD, ~3 spawns/sec vs 10 at the old 100ms).
    Process {
        id: brightnessProbe
        running: false
        command: ["bash", "-lc",
            "b=$(brightnessctl --device intel_backlight get 2>/dev/null); "
            + "mb=$(brightnessctl --device intel_backlight max 2>/dev/null); "
            + "pct=100; "
            + "if [ -n \"$b\" ] && [ -n \"$mb\" ] && [ \"$mb\" -gt 0 ]; then pct=$(( b * 100 / mb )); fi; "
            + "printf '%s' \"$pct\""]
        stdout: StdioCollector {
            onStreamFinished: {
                const v = parseInt(this.text.trim());
                if (!isNaN(v) && root.brightnessPct !== v) root.brightnessPct = v;
            }
        }
    }
    Timer { interval: 300; running: true; repeat: true; triggeredOnStart: true
        onTriggered: { brightnessProbe.running = false; brightnessProbe.running = true; } }

    // ---------- Keyboard brightness status ----------
    Process {
        id: kbdBrightnessProbe
        running: false
        command: ["bash", "-lc",
            "b=$(brightnessctl -d '*::kbd_backlight' get 2>/dev/null); "
            + "m=$(brightnessctl -d '*::kbd_backlight' max 2>/dev/null); "
            + "printf '%s|%s' \"${b:-0}\" \"${m:-3}\""]
        stdout: StdioCollector {
            onStreamFinished: {
                const p = this.text.trim().split("|");
                if (p.length === 2) {
                    const v = parseInt(p[0]);
                    const mx = parseInt(p[1]);
                    if (!isNaN(v)) root.kbdBrightness = v;
                    if (!isNaN(mx)) root.kbdBrightnessMax = mx;
                }
            }
        }
    }
    Timer { interval: 300; running: true; repeat: true; triggeredOnStart: true
        onTriggered: { kbdBrightnessProbe.running = false; kbdBrightnessProbe.running = true; } }

    // ---------- Weather state ----------
    // Single curl to wttr.in?format=j1 backs both the bar glyph and the
    // popup. Refreshed every 30 minutes; right-click the bar icon to
    // force-refresh. The location is read from
    //   ~/.config/omarchy/weather/location
    // (a single line, e.g. "Oslo" or "lat,lon"). Empty file / missing
    // file means wttr.in falls back to IP geolocation. Click the place
    // name in the popup to open that file in the editor.
    readonly property string weatherLocationPath: Quickshell.env("HOME") + "/.config/quickshell/weather/location"
    property string weatherLocation: ""
    property bool   weatherVisible: false
    property bool   weatherLoaded: false
    property bool   weatherUnavailable: false
    property string weatherPlace: ""
    property real   weatherTempC: 0
    property real   weatherFeelsC: 0
    property int    weatherWindKmh: 0
    property string weatherWindDir: ""
    property int    weatherHumidity: 0
    property int    weatherUv: 0
    property string weatherDesc: ""
    property int    weatherCode: 0
    property string weatherSunrise: ""
    property string weatherSunset: ""
    property real   weatherHighC: 0
    property real   weatherLowC: 0
    property var    weatherForecast: []
    property string weatherUpdatedAt: ""

    // Mirrors omarchy-weather-icon's case statement so the bar glyph stays
    // honest when a manual location overrides IP geolocation. `night`
    // swaps the variants for codes that have one.
    function weatherGlyph(code, night) {
        const n = parseInt(code) || 0;
        if (n === 113) return String.fromCodePoint(night ? 0xe32b : 0xe30d);
        if (n === 116) return String.fromCodePoint(night ? 0xe32e : 0xe302);
        if (n === 119 || n === 122) return String.fromCodePoint(0xe33d);
        if (n === 143 || n === 248 || n === 260) return String.fromCodePoint(0xe313);
        if (n === 176 || n === 263 || n === 353) return String.fromCodePoint(night ? 0xe333 : 0xe308);
        if ([179,227,230,323,326,368].indexOf(n) !== -1) return String.fromCodePoint(night ? 0xe327 : 0xe30a);
        if ([182,185,281,284,311,314,317,320,350,362,365,374,377].indexOf(n) !== -1) return String.fromCodePoint(0xe3ad);
        if ([200,386,389,392,395].indexOf(n) !== -1) return String.fromCodePoint(0xe31d);
        if ([266,293,296,299,302,305,308,356,359].indexOf(n) !== -1) return String.fromCodePoint(0xe318);
        if ([329,332,335,338,371].indexOf(n) !== -1) return String.fromCodePoint(0xe31a);
        return String.fromCodePoint(0xe33d);
    }

    function parseClock(s) {
        const m = String(s).match(/^(\d{1,2}):(\d{2})\s*(AM|PM)?\s*$/i);
        if (!m) return -1;
        let h = parseInt(m[1]);
        const min = parseInt(m[2]);
        if (m[3]) {
            const pm = m[3].toUpperCase() === "PM";
            if (h === 12) h = pm ? 12 : 0;
            else if (pm) h += 12;
        }
        return h * 60 + min;
    }

    // Touching root.mm — the minute string from the 1Hz telemetry tick —
    // forces this binding to recompute when the clock rolls a minute, so
    // dusk flips the glyph without a fresh wttr fetch.
    readonly property bool weatherIsNight: {
        root.mm;
        const sr = root.parseClock(root.weatherSunrise);
        const ss = root.parseClock(root.weatherSunset);
        if (sr < 0 || ss < 0) return false;
        const now = new Date();
        const cur = now.getHours() * 60 + now.getMinutes();
        return cur < sr || cur >= ss;
    }
    readonly property string weatherIcon: root.weatherLoaded
        ? root.weatherGlyph(root.weatherCode, root.weatherIsNight)
        : ""

    function fmtTemp(c) {
        const v = Math.round(c);
        return (v > 0 ? "+" : "") + v + "°";
    }

    // Wi-Fi signal-bars glyph from a 0-100% strength reading. Same ramp
    // the netProbe uses to drive the bar icon — shared so the Quick
    // panel rows render identical iconography.
    readonly property var _wifiBarsRamp: ["󰤯","󰤟","󰤢","󰤥","󰤨"]
    function wifiBarsGlyph(pct) {
        const idx = pct >= 80 ? 4 : pct >= 60 ? 3 : pct >= 40 ? 2 : pct >= 20 ? 1 : 0;
        return _wifiBarsRamp[idx];
    }

    function openWeather() {
        if (root.weatherAnchorItem) root.anchorPopupTo(root.weatherAnchorItem);
        if (root.popupScreen) _weatherPopup.screen = root.popupScreen;
        root.weatherVisible = true;
    }
    function refreshWeather() { weatherProbe.running = false; weatherProbe.running = true; }
    function editWeatherLocation() {
        root.run("mkdir -p \"$(dirname " + JSON.stringify(root.weatherLocationPath) + ")\""
                 + " && touch " + JSON.stringify(root.weatherLocationPath)
                 + " && omarchy-launch-editor " + JSON.stringify(root.weatherLocationPath));
        root.weatherVisible = false;
    }

    // ---------- Weather location file ----------
    FileView {
        id: weatherLocFile
        path: root.weatherLocationPath
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            root.weatherLocation = weatherLocFile.text().trim();
            // false→true edge so an in-flight probe doesn't swallow the
            // new URL on a runtime location edit.
            weatherProbe.running = false;
            weatherProbe.running = true;
        }
    }

    // ---------- Weather probe ----------
    // wttr.in rate-limits; we cap at one fetch per 30 minutes plus
    // refresh-on-demand. The location segment is empty for auto-geo and
    // a URL-encoded city otherwise. encodeURIComponent keeps spaces and
    // diacritics safe so "São Paulo" or "New York" work without escaping
    // by hand.
    readonly property string weatherUrl: {
        const loc = root.weatherLocation;
        return "https://wttr.in/" + (loc ? encodeURIComponent(loc) : "") + "?format=j1";
    }
    Process {
        id: weatherProbe
        running: false
        command: ["bash", "-lc",
            "URL=" + JSON.stringify(root.weatherUrl) + ";"
            + " j=$(curl -fsS --max-time 5 \"$URL\" 2>/dev/null);"
            + " if [ -z \"$j\" ]; then printf 'ERR'; exit 0; fi;"
            + " data=$(printf '%s' \"$j\" | jq -r '"
            + "  .current_condition[0] as $c"
            + "  | .weather as $w"
            + "  | .nearest_area[0] as $a"
            + "  | [$a.areaName[0].value, $c.temp_C, $c.FeelsLikeC,"
            + "     $c.windspeedKmph, $c.winddir16Point, $c.humidity, $c.uvIndex,"
            + "     $c.weatherDesc[0].value, $c.weatherCode,"
            + "     $w[0].astronomy[0].sunrise, $w[0].astronomy[0].sunset,"
            + "     $w[0].maxtempC, $w[0].mintempC,"
            + "     $w[1].date, $w[1].maxtempC, $w[1].mintempC, $w[1].hourly[4].weatherCode,"
            + "     $w[2].date, $w[2].maxtempC, $w[2].mintempC, $w[2].hourly[4].weatherCode]"
            + "  | map(tostring) | join(\"|\")');"
            + " printf 'OK|%s' \"$data\""]
        stdout: StdioCollector {
            onStreamFinished: {
                const txt = this.text.trim();
                if (!txt.startsWith("OK|")) {
                    root.weatherUnavailable = true;
                    return;
                }
                const p = txt.substring(3).split("|");
                if (p.length < 21) {
                    root.weatherUnavailable = true;
                    return;
                }
                root.weatherPlace    = p[0];
                root.weatherTempC    = parseFloat(p[1]);
                root.weatherFeelsC   = parseFloat(p[2]);
                root.weatherWindKmh  = parseInt(p[3]);
                root.weatherWindDir  = p[4];
                root.weatherHumidity = parseInt(p[5]);
                root.weatherUv       = parseInt(p[6]);
                root.weatherDesc     = p[7];
                root.weatherCode     = parseInt(p[8]);
                root.weatherSunrise  = p[9];
                root.weatherSunset   = p[10];
                root.weatherHighC    = parseFloat(p[11]);
                root.weatherLowC     = parseFloat(p[12]);
                const days = [];
                for (let i = 0; i < 2; i++) {
                    const off = 13 + i * 4;
                    days.push({
                        day:  Qt.formatDate(new Date(p[off]), "ddd").toUpperCase(),
                        high: parseFloat(p[off + 1]),
                        low:  parseFloat(p[off + 2]),
                        code: parseInt(p[off + 3])
                    });
                }
                root.weatherForecast = days;
                const now = new Date();
                root.weatherUpdatedAt = String(now.getHours()).padStart(2,"0")
                                        + ":" + String(now.getMinutes()).padStart(2,"0");
                root.weatherLoaded = true;
                root.weatherUnavailable = false;
            }
        }
    }

    // Initial fetch is driven by weatherLocFile.onLoaded — this timer only
    // handles the half-hourly refresh once the bar is settled.
    Timer {
        interval: 1800000
        running: true
        repeat: true
        onTriggered: { weatherProbe.running = false; weatherProbe.running = true; }
    }

    // ---------- Generic launcher ----------
    Process { id: runner; running: false }
    function run(cmd) {
        runner.command = ["bash", "-lc", cmd];
        runner.running = false;
        runner.running = true;
    }

    // ---------- Telemetry (1 Hz) ----------
    Process {
        id: tel
        running: false
        command: ["bash", "-lc",
            "read _ a b c d _ < <(grep '^cpu ' /proc/stat); "
            + "sleep 0.15; "
            + "read _ e f g h _ < <(grep '^cpu ' /proc/stat); "
            + "du=$(( (e+f+g) - (a+b+c) )); dt=$(( (e+f+g+h) - (a+b+c+d) )); "
            + "cpu=$(( dt>0 ? du*100/dt : 0 )); "
            + "mem=$(awk '/MemTotal/{t=$2}/MemAvailable/{m=$2}END{printf \"%d\",(t-m)*100/t}' /proc/meminfo); "
            + "bat=0; bst=Unknown; pwr=0; "
            + "if [ -d /sys/class/power_supply/BAT0 ]; then "
            + "  bat=$(cat /sys/class/power_supply/BAT0/capacity 2>/dev/null || echo 0); "
            + "  bst=$(cat /sys/class/power_supply/BAT0/status 2>/dev/null || echo Unknown); "
            + "  pwr=$(cat /sys/class/power_supply/BAT0/power_now 2>/dev/null || echo 0); eng=$(cat /sys/class/power_supply/BAT0/energy_now 2>/dev/null || echo 0); "
            + "elif [ -d /sys/class/power_supply/BAT1 ]; then "
            + "  bat=$(cat /sys/class/power_supply/BAT1/capacity 2>/dev/null || echo 0); "
            + "  bst=$(cat /sys/class/power_supply/BAT1/status 2>/dev/null || echo Unknown); "
            + "  pwr=$(cat /sys/class/power_supply/BAT1/power_now 2>/dev/null || echo 0); eng=$(cat /sys/class/power_supply/BAT1/energy_now 2>/dev/null || echo 0); "
            + "fi; "
            + "pwr=${pwr#-}; "  // some kernels prefix '-' on discharge; magnitude is enough, sign comes from $bst
            + "cput=$(z=$(grep -rl x86_pkg_temp /sys/class/thermal/thermal_zone*/type 2>/dev/null | head -1); [ -n \"$z\" ] && cat \"$(dirname \"$z\")/temp\" 2>/dev/null || echo 0); "
            + "memt=$(awk '/MemTotal/{t=$2}END{printf \"%d\",t}' /proc/meminfo); "
            + "memu=$(awk '/MemTotal/{t=$2}/MemAvailable/{m=$2}END{printf \"%d\",t-m}' /proc/meminfo); "
            + "printf '%d|%d|%d|%s|%s|%s|%s|%s|%s|%s|%s|%d|%d|%d|%d' "
            + "  \"$cpu\" \"$mem\" \"$bat\" \"$bst\" "
            + "  \"$(date +%I)\" \"$(date +%M)\" \"$(date +%p)\" \"$(date +%d)\" \"$(date +%b | tr a-z A-Z)\" \"$(date +%a | tr a-z A-Z)\" \"$pwr\" "
            + "  \"$cput\" \"$memt\" \"$memu\" \"$eng\" "
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                const p = this.text.split("|");
                if (p.length === 15) {
                    root.cpuVal = parseInt(p[0]) || 0;
                    root.memVal = parseInt(p[1]) || 0;
                    root.batVal = parseInt(p[2]) || 0;
                    root.batState = p[3] || "Unknown";
                    root.hh = p[4]; root.mm = p[5];
                    root.ap = p[6];
                    root.dd = p[7]; root.mon = p[8]; root.dow = p[9];
                    root.batPower = (parseInt(p[10]) || 0) / 1e6;
                    root.cpuTemp = Math.round((parseInt(p[11]) || 0) / 1000);
                    root.memTotalGB = Math.round((parseInt(p[12]) || 0) / 1024 / 1024);
                    root.memUsedGB = Math.round((parseInt(p[13]) || 0) / 1024 / 1024);
                    // Battery time remaining
                    const bst = p[3] || "Unknown";
                    const pwr = (parseFloat(p[10]) || 0) / 1e6;  // convert µW to W
                    const eng = parseFloat(p[14]) || 0;   // energy_now in microwatt-hours
                    if (bst === "Discharging" && pwr > 0 && eng > 0) {
                        const hours = (eng / 1e6) / pwr;  // convert µWh to Wh, divide by W
                        const h = Math.floor(hours);
                        const m = Math.round((hours - h) * 60);
                        root.batTime = h + ":" + String(m).padStart(2, "0");
                    } else {
                        root.batTime = "";
                    }
                }
            }
        }
    }
    Timer { interval: 1000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: { tel.running = false; tel.running = true; } }

    // ---------- Workspaces (5 Hz) ----------
    Process {
        id: wsProbe
        running: false
        command: ["bash", "-lc",
            "act=$(hyprctl activeworkspace -j 2>/dev/null | jq -r '.id // 1'); "
            + "ids=$(hyprctl workspaces -j 2>/dev/null | jq -r '.[] | select(.windows > 0) | .id' | sort -nu | paste -sd,); "
            + "printf '%s|%s' \"${act:-1}\" \"${ids:-1}\""]
        stdout: StdioCollector {
            onStreamFinished: {
                const p = this.text.split("|");
                if (p.length === 2) {
                    const next = parseInt(p[0]) || 1;
                    // Set direction first; the Workspace delegates read it
                    // inside their onActiveChanged handlers, which fire as
                    // soon as we write activeWs below.
                    if (next > root.activeWs) root.lastDirection = 1;
                    else if (next < root.activeWs) root.lastDirection = -1;
                    root.activeWs = next;
                    const have = p[1].split(",").map(s => parseInt(s)).filter(n => !isNaN(n));
                    root.existingWs = [...new Set(have)].sort((a,b) => a-b).slice(0, 9);
                }
            }
        }
    }
    Timer { interval: 200; running: true; repeat: true; triggeredOnStart: true
        onTriggered: { wsProbe.running = false; wsProbe.running = true; } }

    // ---------- Network status ----------
    Process {
        id: netProbe
        running: false
        command: ["bash", "-lc",
            "type=none; "
            + "if ip -o addr show | grep -qE '^[0-9]+: (en|eth)[^ ]*.*inet '; then type=eth; fi; "
            + "if [ \"$type\" = none ]; then "
            + "  DEV=$(iwctl --dont-ask device list 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' | awk '/station/{print $1; exit}'); "
            + "  if [ -n \"$DEV\" ]; then "
            + "    link=$(iwctl --dont-ask station \"$DEV\" show 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g'); "
            + "    dbm=$(printf '%s\\n' \"$link\" | awk '/^[[:space:]]*RSSI[[:space:]]/{print $2}'); "
            + "    if [ -n \"$dbm\" ]; then "
            + "      pct=$((2 * (dbm + 100))); [ $pct -lt 0 ] && pct=0; [ $pct -gt 100 ] && pct=100; "
            + "      ssid=$(printf '%s\\n' \"$link\" | sed -n 's/^[[:space:]]*Connected network[[:space:]]*//p'); "
            + "      type=\"wifi:$pct:$ssid\"; "
            + "    fi; "
            + "  fi; "
            + "fi; printf '%s' \"$type\""]
        stdout: StdioCollector {
            onStreamFinished: {
                const t = this.text.trim();
                if (t === "eth") {
                    root.netIcon = "󰀂"; root.netKind = "eth";
                    root.wifiSsid = ""; root.wifiSignal = 0;
                } else if (t.startsWith("wifi:")) {
                    // Split on the first two colons: signal pct, then SSID
                    // (which may itself contain colons, so a naive split
                    // would truncate networks like "Foo:Bar").
                    const rest = t.slice(5);
                    const c = rest.indexOf(":");
                    const sig = parseInt(c < 0 ? rest : rest.slice(0, c)) || 0;
                    const ssid = c < 0 ? "" : rest.slice(c + 1);
                    root.netIcon = root.wifiBarsGlyph(sig); root.netKind = "wifi";
                    root.wifiSignal = sig; root.wifiSsid = ssid;
                } else {
                    root.netIcon = "󰤮"; root.netKind = "none";
                    root.wifiSsid = ""; root.wifiSignal = 0;
                }
            }
        }
    }
    Timer { interval: 15000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: { netProbe.running = false; netProbe.running = true; } }

    // ---------- Network burst detection ----------
    // Samples cumulative rx+tx bytes from /proc/net/dev once per second.
    // When the per-second delta crosses the threshold and the burst is
    // armed, emits netBurst() and disarms for `burstCooldown.interval` ms
    // so a sustained download doesn't keep retriggering — this should read
    // as a rare event, not a continuous activity light.
    signal netBurst()
    property real netPrevBytes: -1
    property bool burstArmed: false
    // First sample after startup seeds netPrevBytes; arm only after a
    // settling beat, otherwise the initial delta (counter vs 0) would
    // always fire.
    Timer { interval: 2500; running: true; repeat: false
        onTriggered: root.burstArmed = true }

    Process {
        id: netBurstProbe
        running: false
        // $2 is rx_bytes, $10 is tx_bytes per /proc/net/dev's column layout.
        // Skip loopback so localhost chatter doesn't count as "network".
        // Direct argv (no shell) — saves the per-poll login-shell startup.
        command: ["awk", "NR>2 && $1!~/^lo:/ {s+=$2+$10} END {print s+0}",
                  "/proc/net/dev"]
        stdout: StdioCollector {
            onStreamFinished: {
                const cur = parseFloat(this.text.trim());
                if (isNaN(cur)) return;
                if (root.netPrevBytes < 0) { root.netPrevBytes = cur; return; }
                const delta = cur - root.netPrevBytes;
                root.netPrevBytes = cur;
                // ~1.5 MB in a 1s sample window. Low enough that an active
                // download or stream paints the arc regularly, high enough
                // that idle browser chatter doesn't.
                if (root.burstArmed && delta > 1.5 * 1024 * 1024) {
                    root.burstArmed = false;
                    root.netBurst();
                    burstCooldown.restart();
                }
            }
        }
    }
    Timer { interval: 1000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: { netBurstProbe.running = false; netBurstProbe.running = true; } }
    Timer { id: burstCooldown; interval: 2000; repeat: false
        onTriggered: root.burstArmed = true }

    // ---------- Idle dim ----------
    // Wayland ext-idle-notify-v1 via Quickshell. The compositor counts
    // pointer AND keyboard activity, so typing keeps the bar bright even
    // when the mouse hasn't moved. Once idle the rectangle eases to 0.7
    // opacity over 6s; the next input snaps it back over 60ms — slow
    // fade reads ambient, fast restore reads responsive.
    IdleMonitor {
        id: idleMonitor
        enabled: true
        timeout: 60
        respectInhibitors: true
    }
    readonly property bool isIdle: idleMonitor.isIdle

    // ---------- Bluetooth status ----------
    // bluez-tools path: bt-adapter --info for power state only — the
    // per-device connected count is updated by btDevicesProbe which
    // runs on-demand from the Quick panel. Keeping the 5s loop here
    // single-shell-out avoids N+1 forks on machines with several
    // paired devices.
    Process {
        id: btProbe
        running: false
        command: ["bash", "-lc",
            "p=$(bt-adapter --info 2>/dev/null | awk '/Powered:/{print $2; exit}');"
            + " if [ \"$p\" = 1 ]; then echo on; else echo off; fi"]
        stdout: StdioCollector {
            onStreamFinished: {
                const s = this.text.trim();
                const powered = (s === "on");
                if (root.btPowered !== powered) root.btPowered = powered;
                if (!powered) {
                    if (root.btIcon !== "󰂲") root.btIcon = "󰂲";
                    if (root.btCount !== 0)  root.btCount = 0;
                } else {
                    const icon = root.btCount > 0 ? "󰂱" : root.icoBtOn;
                    if (root.btIcon !== icon) root.btIcon = icon;
                }
            }
        }
    }
    Timer { interval: 15000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: { btProbe.running = false; btProbe.running = true; } }

    // ---------- Audio status ----------
    // Icon ramps with volume: muted → icoMute, 0 → off, <50 → low, ≥50 → high.
    // Event-driven: pactl subscribe streams "Event 'change' on sink..." on
    // every volume/mute change; we re-read pamixer once per event (cheap)
    // so the OSD stays instant with no idle polling.
    Process {
        id: audioProbe
        running: true
        command: ["bash", "-lc", "/nix/store/7ay5l5jpsvxzfvhzsxp5njz1h52l7kll-pulseaudio-17.0/bin/pactl subscribe"]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function (data) {
                // volume/mute changes surface as 'change' on sink or sink-input
                if (!/Event 'change' on (sink|source)/.test(data)) return;
                audioRefresh.running = false; audioRefresh.running = true;
            }
        }
    }
    Process {
        id: audioRefresh
        running: false
        command: ["bash", "-lc",
            "v=$(pamixer --get-volume 2>/dev/null || echo 0); "
            + "m=$(pamixer --get-mute 2>/dev/null || echo false); "
            + "printf '%s|%s' \"$v\" \"$m\""]
        stdout: StdioCollector {
            onStreamFinished: {
                const p = this.text.split("|");
                if (p.length !== 2) return;
                const v = parseInt(p[0]);
                const m = p[1].trim() === "true";
                root.audioVol = isNaN(v) ? 0 : v;
                root.audioMuted = m;
                if (m) root.audioIcon = root.icoMute;
                else if (isNaN(v) || v <= 0) root.audioIcon = root.icoVol1;
                else if (v < 50) root.audioIcon = root.icoVol2;
                else root.audioIcon = root.icoVol3;
            }
        }
    }

    // ---------- Bluetooth device probe ----------
    // Walks every paired/known device through `bt-device --info` to pull
    // its name + connected/paired/trusted flags. Cheap at the few-devices-
    // per-machine scale; the `bt-device -l` output is "Name (MAC)" lines
    // with a leading "Added devices:" header that tail strips.
    Process {
        id: btDevicesProbe
        running: false
        command: ["bash", "-lc",
            "macs=$(bt-device -l 2>/dev/null | tail -n +2"
            + "   | sed -n 's/.*(\\([0-9A-F:]\\{17\\}\\))$/\\1/p');"
            + " for m in $macs; do"
            + "   info=$(bt-device --info \"$m\" 2>/dev/null);"
            + "   [ -z \"$info\" ] && continue;"
            + "   name=$(printf '%s' \"$info\" | awk -F': ' '/^[[:space:]]*Name:/{print $2; exit}');"
            + "   conn=$(printf '%s' \"$info\" | awk '/^[[:space:]]*Connected: 1/{print 1; exit}');"
            + "   paired=$(printf '%s' \"$info\" | awk '/^[[:space:]]*Paired: 1/{print 1; exit}');"
            + "   trusted=$(printf '%s' \"$info\" | awk '/^[[:space:]]*Trusted: 1/{print 1; exit}');"
            + "   printf '%s\\t%s\\t%s\\t%s\\t%s\\\\n' \"$m\" \"${name:-$m}\" \"${conn:-0}\" \"${paired:-0}\" \"${trusted:-0}\";"
            + " done"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = this.text.trim().split("\n").filter(s => s.length > 0);
                const devs = lines.map(line => {
                    const f = line.split("\t");
                    return {
                        mac:       f[0] || "",
                        name:      (f[1] || "").trim() || (f[0] || ""),
                        connected: f[2] === "1",
                        paired:    f[3] === "1",
                        trusted:   f[4] === "1"
                    };
                });
                // Connected first, then paired, then everything else.
                devs.sort((a, b) =>
                    (b.connected - a.connected)
                    || (b.paired - a.paired)
                    || a.name.localeCompare(b.name));
                // Equality guard so the Quick panel's Repeater doesn't
                // re-evaluate every refresh when nothing has changed.
                const serialised = JSON.stringify(devs);
                if (serialised === root._btDevicesSer) return;
                root._btDevicesSer = serialised;
                root.btDevices = devs;
                const connCount = devs.filter(d => d.connected).length;
                if (root.btCount !== connCount) root.btCount = connCount;
            }
        }
    }

    // ---------- Wi-Fi scan probe ----------
    // iwctl path (omarchy ships iwd, not NetworkManager): detect the
    // station device, check Powered state, kick a non-blocking scan,
    // then parse human-formatted get-networks output. Signal is reported
    // in tenths of dBm (e.g. -6400 = -64 dBm); convert to a 0-100% bar
    // on the QML side. ANSI codes are stripped before parsing.
    Process {
        id: wifiScanProbe
        running: false
        command: ["bash", "-lc",
            "DEV=$(iwctl --dont-ask device list 2>/dev/null"
            + "   | sed 's/\\x1b\\[[0-9;]*m//g'"
            + "   | awk '/station/{print $1; exit}');"
            + " if [ -z \"$DEV\" ]; then echo 'RADIO|off'; exit 0; fi;"
            + " powered=$(iwctl --dont-ask device \"$DEV\" show 2>/dev/null"
            + "   | sed 's/\\x1b\\[[0-9;]*m//g'"
            + "   | awk '/Powered/{print $NF; exit}');"
            + " if [ \"$powered\" != on ]; then echo 'RADIO|off'; exit 0; fi;"
            + " echo 'RADIO|on';"
            + " iwctl --dont-ask station \"$DEV\" scan >/dev/null 2>&1;"
            + " iwctl --dont-ask station \"$DEV\" get-networks rssi-dbms 2>/dev/null"
            + "   | sed 's/\\x1b\\[[0-9;]*m//g'"
            + "   | awk '"
            + "       /^-+$/ { sep++; next }"
            + "       sep < 2 || $0 ~ /^[[:space:]]*$/ { next }"
            + "       {"
            + "         line=$0;"
            + "         conn=(index(substr(line,1,4),\">\")>0)?1:0;"
            + "         sub(/^[ >]+/, \"\", line);"
            + "         sub(/[ ]+$/, \"\", line);"
            + "         if (match(line, /^(.*[^ ])  +([^ ]+)  +(-?[0-9]+)$/, m))"
            + "           printf \"%d\\t%s\\t%s\\t%s\\\\n\", conn, m[1], m[2], m[3];"
            + "       }'"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = this.text.split("\n").filter(s => s.length > 0);
                let radioOn = false;
                const networks = [];
                for (const line of lines) {
                    if (line.startsWith("RADIO|")) {
                        radioOn = line.slice(6) === "on";
                        continue;
                    }
                    const f = line.split("\t");
                    if (f.length < 4) continue;
                    // dBm tenths -> dBm -> 0-100%. -50dBm or stronger pegs at 100%.
                    const dbm = parseInt(f[3]) / 100;
                    const pct = Math.max(0, Math.min(100, Math.round(2 * (dbm + 100))));
                    networks.push({
                        inUse: f[0] === "1",
                        ssid: f[1],
                        signal: pct,
                        security: f[2]
                    });
                }
                networks.sort((a, b) => (b.inUse - a.inUse) || (b.signal - a.signal));
                if (root.wifiRadioOn !== radioOn) root.wifiRadioOn = radioOn;
                const ser = JSON.stringify(networks);
                if (ser !== root._wifiNetworksSer) {
                    root._wifiNetworksSer = ser;
                    root.wifiNetworks = networks;
                }
                root.wifiScanning = false;
            }
        }
    }

    // ---------- Audio sinks probe ----------
    // wpctl status's structured form: lines like
    //   "*    52. WH-1000XM4              [vol: 0.45]"
    // The leading "*" flags the current default; we capture id, label, and
    // default state. Skipped automatically when wireplumber isn't around.
    Process {
        id: audioSinksProbe
        running: false
        // Tracks the Audio top-level section AND the Sinks subsection
        // separately so we don't pick up Sources, Filters, or Video's
        // Sinks. Section header lines start with `├─` or `└─`; the Audio
        // section ends at the next top-level label (Video / Settings).
        command: ["bash", "-lc",
            "wpctl status 2>/dev/null | awk '"
            + "  /^Audio$/                                    {sec=\"audio\"; sub=\"\"; next}"
            + "  /^[A-Z][a-zA-Z]+$/                           {sec=\"\";      sub=\"\"; next}"
            + "  /^[[:space:]]*[├└]─[[:space:]]*Sinks:/       {sub=\"sinks\"; next}"
            + "  /^[[:space:]]*[├└]─/                          {sub=\"\";      next}"
            + "  sec==\"audio\" && sub==\"sinks\" {"
            + "    star=(index($0,\"*\")>0 && index($0,\"*\")<index($0,\".\")) ? 1 : 0;"
            + "    line=$0;"
            + "    sub(/^[ │├─└*]+/, \"\", line);"
            + "    if (match(line, /^([0-9]+)\\. (.+)\\[/, m)) {"
            + "      gsub(/[ \\t]+$/, \"\", m[2]);"
            + "      printf \"%s\\t%s\\t%d\\\\n\", m[1], m[2], star;"
            + "    }"
            + "  }'"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = this.text.trim().split("\n").filter(s => s.length > 0);
                const sinks = lines.map(line => {
                    const f = line.split("\t");
                    return {
                        id: f[0] || "",
                        name: (f[1] || "").trim(),
                        isDefault: f[2] === "1"
                    };
                });
                const ser = JSON.stringify(sinks);
                if (ser !== root._audioSinksSer) {
                    root._audioSinksSer = ser;
                    root.audioSinks = sinks;
                }
                const def = sinks.find(s => s.isDefault);
                if (def && root.audioDefaultSink !== def.id) root.audioDefaultSink = def.id;
            }
        }
    }

    // ---------- Power-profile probe ----------
    // Polled every 5s so the battery popup stays in sync with TLP auto-switches.
    // Also triggered on-demand from setPowerProfile()/refreshPowerProfile().
    function refreshPowerProfile() {
        powerProfileProbe.running = false;
        powerProfileProbe.running = true;
    }
    Process {
        id: powerProfileProbe
        running: false
        command: ["bash", "-lc",
            "cur=$(cat /sys/firmware/acpi/platform_profile 2>/dev/null); "
            + "if [ -z \"$cur\" ]; then echo '|'; exit 0; fi; "
            + "list=$(tr ' ' ',' < /sys/firmware/acpi/platform_profile_choices 2>/dev/null); "
            + "printf '%s|%s' \"$cur\" \"$list\""]
        stdout: StdioCollector {
            onStreamFinished: {
                const p = this.text.trim().split("|");
                if (p.length !== 2) return;
                const cur = p[0] || "";
                const list = p[1] ? p[1].split(",").filter(Boolean) : [];
                if (JSON.stringify(root.powerProfiles) !== JSON.stringify(list))
                    root.powerProfiles = list;
                if (root.powerProfile !== cur) root.powerProfile = cur;
            }
        }
    }

    Timer { interval: 5000; running: true; repeat: true
        onTriggered: root.refreshPowerProfile()
    }

    Component.onCompleted: { refreshPowerProfile(); refreshChargeLimit(); }

    // ---------- Omarchy update probe ----------
    // Mirrors waybar's custom/update: omarchy-update-available exits 0 and
    // prints "Omarchy update available (<tag>)" when behind, exits non-zero
    // otherwise. Network-bound (ls-remote), so the cadence matches waybar
    // at 6h; refreshOmarchyUpdateCheck() retriggers on demand.
    Process {
        id: omarchyUpdateProbe
        running: false
        command: ["omarchy-update-available"]
        stdout: StdioCollector { id: omarchyUpdateOut }
        onExited: (code, status) => {
            if (code === 0) {
                const m = omarchyUpdateOut.text.match(/\(([^)]+)\)/);
                root.omarchyLatestTag = m ? m[1] : "";
                root.omarchyUpdateAvailable = true;
            } else {
                root.omarchyUpdateAvailable = false;
                root.omarchyLatestTag = "";
            }
        }
    }
    Timer { interval: 21600000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: root.refreshOmarchyUpdateCheck() }

    // ---------- Corne keyboard battery ----------
    // BLE GATT battery level proxy via corne-battery script.
    // Outputs {"left":N,"right":N}; polled every 60s (BLE is slow to change).
    Process {
        id: corneBatteryProbe
        running: false
        command: ["/home/nate/.local/bin/corne-battery"]
        stdout: StdioCollector {
            onStreamFinished: {
                const txt = this.text.trim();
                try {
                    const j = JSON.parse(txt);
                    if (j.error) { root.corneLeft = -1; root.corneRight = -1; return; }
                    root.corneLeft  = (j.left  !== undefined) ? j.left  : -1;
                    root.corneRight = (j.right !== undefined) ? j.right : -1;
                } catch(e) {
                    root.corneLeft = -1; root.corneRight = -1;
                }
            }
        }
    }
    Timer { interval: 60000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: root.refreshCorneBattery() }

    // ---------- Battery icon helper ----------
    // "Not charging" covers plugged-in-but-topped-up laptops; "Full" is the
    // briefly-stable Charging→Full edge. Treat all three as AC-powered and
    // swap the battery ramp for a single plug glyph — once AC is in, the
    // % digit in the tooltip is the only number worth glancing at.
    function batteryIcon() {
        if (root.batState === "Charging"
            || root.batState === "Full"
            || root.batState === "Not charging") return root.icoPlug;
        const c = root.batVal;
        const r = ["󰁺","󰁻","󰁼","󰁽","󰁾","󰁿","󰂀","󰂁","󰂂","󰁹"];
        return r[Math.min(9, Math.floor(c / 10))];
    }
    // Bars live in shell.qml (one PanelWindow per screen). Do not add Bar here.

    CalendarPopup    { id: _calendarPopup; root: root }
    WeatherPopup     { id: _weatherPopup; root: root }
    BatteryPopup     { id: _batteryPopup; root: root }

    // ---------- IPC ----------
    // bind = SUPER, W, exec, qs ipc call weather toggle
    IpcHandler {
        target: "weather"
        function toggle(): void {
            if (root.weatherVisible) root.weatherVisible = false;
            else root.openWeather();
        }
        function open(): void    { root.openWeather(); }
        function close(): void   { root.weatherVisible = false; }
        function refresh(): void { root.refreshWeather(); }
    }

    // bind = SUPER, A, exec, qs ipc call aether toggle
    IpcHandler {
        target: "aether"
        function toggle(): void {
            if (root.aetherVisible) root.aetherVisible = false;
            else root.openAether();
        }
        function open(): void  { root.openAether(); }
        function close(): void { root.aetherVisible = false; }
    }

    // bind = SUPER, C, exec, qs ipc call calendar toggle
    IpcHandler {
        target: "calendar"
        function toggle(): void {
            if (root.calendarVisible) root.calendarVisible = false;
            else root.openCalendar();
        }
        function open(): void  { root.openCalendar(); }
        function close(): void { root.calendarVisible = false; }
    }

    // bind = SUPER, B, exec, qs ipc call battery toggle
    IpcHandler {
        target: "battery"
        function toggle(): void {
            if (root.batteryVisible) root.batteryVisible = false;
            else root.openBattery();
        }
        function open(): void  { root.openBattery(); }
        function close(): void { root.batteryVisible = false; }
    }

    // ---------- MPRIS (now playing) ----------
    // Mpris.players is a live list of every player that has registered on
    // the bus. We don't bind to a single "active" one — instead the hidden
    // Repeater below subscribes to each player's signals, and on any track
    // or playback change we recompute which player to surface in the bar.
    // Preference: a playing player wins; otherwise the most-recently-seen
    // paused one with non-empty metadata; otherwise nothing.
    property MprisPlayer musicPlayer: null
    property string musicTitle: ""
    property string musicArtist: ""
    property bool   musicPlaying: false

    function refreshMusic() {
        const players = Mpris.players ? Mpris.players.values : [];
        let best = null;
        let bestRank = -1;
        for (let i = 0; i < players.length; i++) {
            const p = players[i];
            if (!p) continue;
            const hasTitle = !!(p.trackTitle && p.trackTitle.length > 0);
            // 2 = playing with title, 1 = paused with title, 0 = anything else.
            // Ties broken by list order, which roughly tracks bus registration.
            let rank = 0;
            if (hasTitle && p.isPlaying) rank = 2;
            else if (hasTitle) rank = 1;
            if (rank > bestRank) { best = p; bestRank = rank; }
        }
        root.musicPlayer  = best;
        root.musicTitle   = best ? (best.trackTitle  || "") : "";
        root.musicArtist  = best ? (best.trackArtist || "") : "";
        root.musicPlaying = best ? !!best.isPlaying : false;
    }

    function musicToggle() {
        if (root.musicPlayer && root.musicPlayer.canTogglePlaying) root.musicPlayer.togglePlaying();
    }
    function musicNext() {
        if (root.musicPlayer && root.musicPlayer.canGoNext) root.musicPlayer.next();
    }
    function musicPrev() {
        if (root.musicPlayer && root.musicPlayer.canGoPrevious) root.musicPlayer.previous();
    }

    Item {
        visible: false
        Repeater {
            model: Mpris.players
            delegate: Item {
                required property MprisPlayer modelData
                Connections {
                    target: modelData
                    function onPostTrackChanged()     { root.refreshMusic(); }
                    function onPlaybackStateChanged() { root.refreshMusic(); }
                }
                Component.onCompleted:   root.refreshMusic()
                Component.onDestruction: root.refreshMusic()
            }
        }
    }
}
