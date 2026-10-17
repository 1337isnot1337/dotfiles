#!/usr/bin/env bash

set -u

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
PLAYER_HELPER="$HOME/.config/waybar/scripts/media_player.sh"

player=$("$PLAYER_HELPER" player 2>/dev/null || true)

format_time() {
    local milliseconds="$1"
    local total_seconds=$((milliseconds / 1000))
    local hours=$((total_seconds / 3600))
    local minutes=$(((total_seconds % 3600) / 60))
    local seconds=$((total_seconds % 60))

    if (( hours > 0 )); then
        printf '%d:%02d:%02d\n' "$hours" "$minutes" "$seconds"
    else
        printf '%02d:%02d\n' "$minutes" "$seconds"
    fi
}

position_us=0
length_us=0
if [[ -n "$player" ]]; then
    position_us=$(playerctl --player="$player" metadata --format '{{ position }}' 2>/dev/null || printf '0')
    length_us=$(playerctl --player="$player" metadata --format '{{ mpris:length }}' 2>/dev/null || printf '0')
fi

[[ "$position_us" =~ ^[0-9]+$ ]] || position_us=0
[[ "$length_us" =~ ^[0-9]+$ ]] || length_us=0

position_ms=$((position_us / 1000))
length_ms=$((length_us / 1000))

case "${1:-progress}" in
    progress)
        if (( length_us > 0 )); then
            awk -v position="$position_us" -v duration="$length_us" 'BEGIN {
                value = position / duration * 100
                if (value < 0) value = 0
                if (value > 100) value = 100
                printf "%.2f\n", value
            }'
        else
            printf '0\n'
        fi
        ;;
    position)
        if [[ "${2:-}" == "ms" ]]; then
            printf '%s\n' "$position_ms"
        else
            format_time "$position_ms"
        fi
        ;;
    length)
        if [[ "${2:-}" == "ms" ]]; then
            printf '%s\n' "$length_ms"
        else
            format_time "$length_ms"
        fi
        ;;
    *)
        printf 'Unknown song_progress command: %s\n' "$1" >&2
        exit 2
        ;;
esac
