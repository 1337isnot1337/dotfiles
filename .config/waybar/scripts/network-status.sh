#!/usr/bin/env bash

set -u

readonly IFACE="wlan0"
readonly SYS_NET="/sys/class/net/$IFACE"
readonly NEWLINE=$'\n'

carrier="$(cat "$SYS_NET/carrier" 2>/dev/null || true)"
operstate="$(cat "$SYS_NET/operstate" 2>/dev/null || true)"
ipaddr="$(ip -4 -o addr show dev "$IFACE" scope global 2>/dev/null | awk 'NR == 1 { print $4; exit }')"
gateway="$(ip -4 route show default dev "$IFACE" 2>/dev/null | awk 'NR == 1 { print $3; exit }')"
connection="$(nmcli -g GENERAL.CONNECTION device show "$IFACE" 2>/dev/null | head -n 1)"
signal="$(nmcli -t -f IN-USE,SSID,SIGNAL device wifi list 2>/dev/null | awk -F: '$1 == "*" { print $3; exit }')"

[ "$connection" = "--" ] && connection=""
[ "$signal" = "--" ] && signal=""
[ -n "$connection" ] || connection="Not connected"
[ -n "$signal" ] || signal="unknown"

if [ "$carrier" = "1" ] && [ -n "$ipaddr" ]; then
    text=""
    class="connected"
    tooltip="Wi-Fi${NEWLINE}${NEWLINE}${connection}${NEWLINE}Signal · ${signal}%${NEWLINE}${IFACE} · ${ipaddr}${NEWLINE}Gateway · ${gateway}${NEWLINE}${NEWLINE}Left click: Wi-Fi controls"
elif [ "$carrier" = "1" ] || [ "$operstate" = "up" ]; then
    text="󰤭 ${IFACE} (No IP)"
    class="linked"
    tooltip="Network${NEWLINE}${NEWLINE}Link detected · no IP address${NEWLINE}Interface · ${IFACE}${NEWLINE}${NEWLINE}Left click: Wi-Fi controls"
else
    text=" Disconnected"
    class="disconnected"
    tooltip="Network${NEWLINE}${NEWLINE}Disconnected${NEWLINE}No active network connection${NEWLINE}${NEWLINE}Left click: Wi-Fi controls"
fi

jq -cn \
    --arg text "$text" \
    --arg tooltip "$tooltip" \
    --arg class "$class" \
    '{text: $text, tooltip: $tooltip, class: $class}'
