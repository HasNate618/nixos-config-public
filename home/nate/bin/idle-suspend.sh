#!/usr/bin/env bash
# Scheduled suspend for hypridle:
#   "schedule" — check power source and time, then suspend or schedule.
#   "cancel"   — cancel any pending scheduled sleep.

UNIT="hypridle-scheduled-suspend.service"

is_on_ac() {
    for path in /sys/class/power_supply/AC/online /sys/class/power_supply/AC0/online /sys/class/power_supply/ADP1/online; do
        if [[ -f "$path" ]]; then
            [[ "$(cat "$path")" == "1" ]]
            return
        fi
    done
    # Default: assume AC if no battery info
    return 0
}

in_evening_window() {
    local hour
    hour=$(date +%H)
    (( hour >= 22 && hour < 23 ))
}

cancel() {
    systemctl --user stop "$UNIT" 2>/dev/null && echo "Cancelled scheduled sleep"
}

schedule() {
    cancel

    if ! is_on_ac; then
        echo "On battery — suspending now"
        systemctl suspend -i
        return
    fi

    if in_evening_window; then
        local target_epoch now_epoch delay
        target_epoch=$(date -d "today 23:00" +%s)
        now_epoch=$(date +%s)
        delay=$(( target_epoch - now_epoch ))
        echo "On AC, evening window — scheduling sleep in ${delay}s (at 23:00)"
        systemd-run --user --unit="$UNIT" --on-active="${delay}s" systemctl suspend -i
    else
        echo "On AC, outside evening window — suspending now"
        systemctl suspend -i
    fi
}

case "${1:-schedule}" in
    schedule) schedule ;;
    cancel)   cancel ;;
    *)        echo "Usage: $0 [schedule|cancel]"; exit 1 ;;
esac
