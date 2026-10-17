#!/usr/bin/env bash

set -u

player_helper="$HOME/.config/waybar/scripts/media_player.sh"

case "${1:-}" in
    play-pause|previous|next|shuffle-toggle|loop-toggle)
        "$player_helper" "$1"
        ;;
    seek)
        "$player_helper" seek-percent "${2:-0}"
        ;;
    volume-set)
        value="${2:-0}"
        [[ "$value" =~ ^[0-9]+([.][0-9]+)?$ ]] || exit 0
        wpctl set-volume @DEFAULT_AUDIO_SINK@ "${value}%" --limit 1.5 >/dev/null 2>&1 || true
        ;;
    volume-step)
        case "${2:-}" in
            up) wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+ --limit 1.5 >/dev/null 2>&1 || true ;;
            down) wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%- >/dev/null 2>&1 || true ;;
        esac
        ;;
    mute)
        wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle >/dev/null 2>&1 || true
        ;;
    *)
        printf 'usage: %s {play-pause|previous|next|shuffle-toggle|loop-toggle|seek N|volume-set N|volume-step up|down|mute}\n' "$0" >&2
        exit 2
        ;;
esac
