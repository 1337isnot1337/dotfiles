#!/usr/bin/env bash

set -u

set_busy() {
    eww update "bluetooth_busy=$1" >/dev/null 2>&1 || true
}

clear_busy() {
    set_busy ""
}

notify() {
    command -v notify-send >/dev/null 2>&1 || return 0
    notify-send -a "Bluetooth" "$1" "${2:-}" >/dev/null 2>&1 || true
}

case "${1:-}" in
    toggle)
        set_busy "toggle"
        trap clear_busy EXIT
        if bluetoothctl show 2>/dev/null | grep -q '^\s*Powered: yes$'; then
            bluetoothctl power off >/dev/null 2>&1 || notify "Could not turn Bluetooth off"
        else
            bluetoothctl power on >/dev/null 2>&1 || notify "Could not turn Bluetooth on"
        fi
        ;;
    scan)
        set_busy "scan"
        trap clear_busy EXIT
        if bluetoothctl show 2>/dev/null | grep -q '^\s*Powered: yes$'; then
            notify "Scanning for Bluetooth devices" "The scan will run for 10 seconds."
            bluetoothctl --timeout 10 scan on >/dev/null 2>&1 || true
        else
            notify "Bluetooth is off" "Turn it on before scanning."
        fi
        ;;
    connect)
        address="${2:-}"
        [[ "$address" =~ ^([[:xdigit:]]{2}:){5}[[:xdigit:]]{2}$ ]] || exit 2

        set_busy "connect:$address"
        trap clear_busy EXIT

        info=$(bluetoothctl info "$address" 2>/dev/null || true)
        if grep -q '^\s*Connected: yes$' <<<"$info"; then
            bluetoothctl disconnect "$address" >/dev/null 2>&1 \
                || notify "Could not disconnect the device"
            exit 0
        fi

        if ! grep -q '^\s*Paired: yes$' <<<"$info"; then
            bluetoothctl --timeout 20 pair "$address" >/dev/null 2>&1 || {
                notify "Pairing needs attention" "Use Advanced settings for a PIN or confirmation prompt."
                exit 1
            }
            bluetoothctl trust "$address" >/dev/null 2>&1 || true
        fi

        bluetoothctl connect "$address" >/dev/null 2>&1 \
            && notify "Bluetooth device connected" \
            || notify "Could not connect the device" "Try Advanced settings."
        ;;
    advanced)
        setsid -f /usr/bin/blueman-manager >/dev/null 2>&1
        ;;
    *)
        printf 'usage: %s {toggle|scan|connect MAC|advanced}\n' "$0" >&2
        exit 2
        ;;
esac
