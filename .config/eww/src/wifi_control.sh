#!/usr/bin/env bash

set -u

set_busy() {
    eww update "wifi_busy=$1" >/dev/null 2>&1 || true
}

clear_busy() {
    set_busy ""
}

notify() {
    command -v notify-send >/dev/null 2>&1 || return 0
    notify-send -a "Wi-Fi" "$1" "${2:-}" >/dev/null 2>&1 || true
}

wifi_device() {
    nmcli -t -f DEVICE,TYPE,STATE device status 2>/dev/null \
        | awk -F: '$2 == "wifi" && $1 !~ /^p2p-/ {
              if ($3 == "connected") { print $1; printed=1; exit }
              if (fallback == "") fallback=$1
          }
          END { if (!printed && fallback != "") print fallback }'
}

case "${1:-}" in
    toggle)
        set_busy "toggle"
        trap clear_busy EXIT
        if [[ "$(nmcli -t -f WIFI general 2>/dev/null)" == "enabled" ]]; then
            nmcli radio wifi off >/dev/null 2>&1 || notify "Could not disable Wi-Fi"
        else
            nmcli radio wifi on >/dev/null 2>&1 || notify "Could not enable Wi-Fi"
        fi
        ;;
    rescan)
        set_busy "scan"
        trap clear_busy EXIT
        nmcli device wifi rescan >/dev/null 2>&1 \
            && notify "Wi-Fi scan complete" \
            || notify "Wi-Fi scan failed" "Try Advanced settings."
        ;;
    disconnect)
        set_busy "disconnect"
        trap clear_busy EXIT
        device=$(wifi_device)
        if [[ -n "$device" ]]; then
            nmcli --wait 8 device disconnect "$device" >/dev/null 2>&1 \
                || notify "Could not disconnect Wi-Fi"
        fi
        ;;
    connect)
        encoded_ssid="${2:-}"
        [[ -n "$encoded_ssid" ]] || exit 2
        ssid=$(printf '%s' "$encoded_ssid" | base64 --decode 2>/dev/null || true)
        [[ -n "$ssid" ]] || exit 2

        set_busy "connect:$encoded_ssid"
        trap clear_busy EXIT

        result=""
        if nmcli -g NAME connection show 2>/dev/null | grep -Fxq -- "$ssid"; then
            result=$(nmcli --wait 12 connection up id "$ssid" 2>&1) \
                && notify "Connected" "$ssid" \
                || notify "Could not connect to $ssid" "${result:0:160}"
        else
            result=$(nmcli --wait 12 device wifi connect "$ssid" 2>&1) \
                && notify "Connected" "$ssid" \
                || notify "Could not connect to $ssid" "Use Advanced settings to enter credentials."
        fi
        ;;
    connect-password)
        encoded_ssid="${2:-}"
        [[ -n "$encoded_ssid" ]] || exit 2
        ssid=$(printf '%s' "$encoded_ssid" | base64 --decode 2>/dev/null || true)
        [[ -n "$ssid" ]] || exit 2
        password=$(eww get wifi_password 2>/dev/null || true)
        [[ -n "$password" ]] || {
            notify "Password required" "Enter the network password first."
            exit 1
        }

        set_busy "connect:$encoded_ssid"
        trap clear_busy EXIT
        result=$(nmcli --wait 15 device wifi connect "$ssid" password "$password" 2>&1) \
            && {
                notify "Connected" "$ssid"
                eww update "wifi_selected=" "wifi_password=" >/dev/null 2>&1 || true
            } \
            || notify "Could not connect to $ssid" "${result:0:160}"
        ;;
    enterprise)
        notify "Advanced sign-in required" "Open Network settings for enterprise credentials."
        ;;
    advanced)
        setsid -f /usr/bin/nm-connection-editor >/dev/null 2>&1
        ;;
    *)
        printf 'usage: %s {toggle|rescan|disconnect|connect BASE64_SSID|connect-password BASE64_SSID|enterprise|advanced}\n' "$0" >&2
        exit 2
        ;;
esac
