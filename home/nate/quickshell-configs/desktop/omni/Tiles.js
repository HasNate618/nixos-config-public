.pragma library

// Static base list for the Quick-mode tile grid. Order matches the
// Samsung-style quick panel - most glanced (battery/audio/wifi/bt)
// first. The Repeater's 12 delegates are built once from this array and
// never torn down; per-tile live data lives in the parallel `dyn` map
// the QuickContainer builds from navbar telemetry on every tick.
var base = [
    { key: "battery",     keywords: "battery power charge plugged ac percent watt",
      action: "ghostty -e 'bash -c \"upower -i /org/freedesktop/UPower/devices/battery_BAT0; read\"'" },
    { key: "audio",       keywords: "audio sound speaker volume mute pulse pipewire",
      action: "pavucontrol", longAction: "pamixer -t" },
    { key: "network",     keywords: "wifi wireless network internet ssid signal ethernet eth",
      action: "nmtui" },
    { key: "bluetooth",   keywords: "bluetooth bt pair device headset speaker keyboard",
      action: "blueman-manager" },
    { key: "weather",     keywords: "weather forecast temperature wttr rain sun wind",
      action: "qs -c desktop ipc call weather toggle",
      longAction: "qs -c desktop ipc call weather refresh" },

    { key: "cpu",         keywords: "cpu processor memory monitor btop top htop performance load",
      action: "ghostty -e btop" },
    { key: "calendar",    keywords: "calendar date month day today schedule planner",
      action: "qs -c desktop ipc call calendar toggle" },


    { key: "power",       keywords: "power menu suspend hibernate logout restart shutdown lock",
      action: "bash -c 'systemctl poweroff'" }
];

// Build the per-tile dynamic map (glyph/label/sub/tone) from live
// navbar state. Caller passes the navbar instance; this function does
// not retain it. Returns {} when navbar is missing so delegate
// bindings can still chain `.glyph`/`.sub` reads via `({}).foo`.
function buildDyn(n) {
    if (!n) return ({});
    const chargingTag = n.batState === "Charging"    ? " · CHARGING"
                      : n.batState === "Full"        ? " · FULL"
                      : n.batState === "Not charging" ? " · PLUGGED"
                      : "";
    return {
        battery: {
            glyph: n.batteryIcon(),
            label: "BATTERY",
            sub: n.batVal + "%" + chargingTag
                 + (n.batPower >= 0.05
                    ? "  " + n.batPower.toFixed(1) + "W"
                    : ""),
            tone: n.batVal <= 10 ? n.seal
                                 : n.batVal <= 20 ? n.indigo
                                                  : n.ink
        },
        audio: {
            glyph: n.audioIcon,
            label: "AUDIO",
            sub: n.audioMuted ? "MUTED" : (n.audioVol + "%"),
            tone: n.audioMuted ? n.seal : n.ink
        },
        network: {
            glyph: n.netIcon,
            label: n.netKind === "wifi" ? "WI-FI"
                   : n.netKind === "eth"  ? "ETHERNET"
                                          : "OFFLINE",
            sub: n.netKind === "wifi"
                 ? ((n.wifiSsid || "(hidden)") + " · " + n.wifiSignal + "%")
                 : n.netKind === "eth" ? "CONNECTED" : "—",
            tone: n.netKind === "none" ? n.inkDeep : n.ink
        },
        bluetooth: {
            glyph: n.btIcon,
            label: "BLUETOOTH",
            sub: !n.btPowered ? "OFF"
                              : (n.btCount > 0 ? n.btCount + " CONN" : "ON"),
            tone: !n.btPowered ? n.inkDeep : n.ink
        },
        weather: {
            glyph: n.weatherUnavailable ? "?"
                 : (n.weatherLoaded ? n.weatherIcon : "·"),
            label: "WEATHER",
            sub: n.weatherUnavailable ? "OFFLINE"
                 : (n.weatherLoaded ? Math.round(n.weatherTempC) + "°C" : "…"),
            tone: n.weatherUnavailable ? n.inkDeep : n.ink
        },

        aether:      { glyph: n.icoAether, label: "AETHER", sub: "THEMES", tone: n.ink },
        cpu: {
            glyph: "󰍛",
            label: "CPU",
            sub: Math.round(n.cpuVal) + "%",
            tone: n.cpuVal > 80 ? n.seal : n.ink
        },
        calendar:    { glyph: "󰃭",          label: "CALENDAR",    sub: n.dd + " " + n.mon, tone: n.ink },
        power:       { glyph: n.icoPower,   label: "POWER",       sub: "MENU",             tone: n.ink }
    };
}