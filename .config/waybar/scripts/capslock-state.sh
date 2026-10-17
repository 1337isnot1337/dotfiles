#!/usr/bin/env bash

set -u

readonly POLL_SECONDS=0.25

caps_led=""
last_state=""

find_physical_caps_led() {
    local led resolved

    for led in /sys/class/leds/*::capslock; do
        [[ -r "$led/brightness" ]] || continue
        resolved="$(readlink -f -- "$led" 2>/dev/null || true)"
        case "$resolved" in
            */devices/platform/i8042/serio0/input/*::capslock)
                printf '%s\n' "$led"
                return 0
                ;;
        esac
    done

    # Fallback for this machine if the stable physical-device path is not
    # available during a brief input-device re-enumeration.
    if [[ -r /sys/class/leds/input3::capslock/brightness ]]; then
        printf '%s\n' /sys/class/leds/input3::capslock
        return 0
    fi

    return 1
}

emit_state() {
    case "$1" in
        1)
            printf '%s\n' '{"text":"","class":"locked","tooltip":"Caps Lock\n\nOn\n\nPress Caps Lock to turn off"}'
            ;;
        0)
            printf '%s\n' '{"text":"","class":"unlocked","tooltip":"Caps Lock\n\nOff\n\nPress Caps Lock to turn on"}'
            ;;
        *)
            printf '%s\n' '{"text":"?","class":"unknown","tooltip":"Caps Lock\n\nState unavailable"}'
            ;;
    esac
}

while :; do
    if [[ -z "$caps_led" || ! -r "$caps_led/brightness" ]]; then
        caps_led="$(find_physical_caps_led || true)"
        last_state=""
    fi

    state=""
    if [[ -n "$caps_led" && -r "$caps_led/brightness" ]]; then
        IFS= read -r state < "$caps_led/brightness" || state=""
    fi

    case "$state" in
        0|1)
            if [[ "$state" != "$last_state" ]]; then
                emit_state "$state"
                last_state="$state"
            fi
            ;;
        *)
            if [[ "$last_state" != "unknown" ]]; then
                emit_state unknown
                last_state="unknown"
            fi
            ;;
    esac

    sleep "$POLL_SECONDS"
done
