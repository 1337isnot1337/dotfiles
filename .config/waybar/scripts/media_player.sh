#!/usr/bin/env bash

# Shared MPRIS player selection and controls for Waybar and Eww.
# Prefer a currently playing player; otherwise use the first paused player.

set -u

select_player() {
    local player status paused=""

    while IFS= read -r player; do
        [[ -z "$player" ]] && continue
        status=$(playerctl --player="$player" status 2>/dev/null || true)
        case "$status" in
            Playing)
                printf '%s\n' "$player"
                return 0
                ;;
            Paused)
                [[ -z "$paused" ]] && paused="$player"
                ;;
        esac
    done < <(playerctl -l 2>/dev/null || true)

    if [[ -n "$paused" ]]; then
        printf '%s\n' "$paused"
        return 0
    fi

    return 1
}

player_or_empty() {
    select_player 2>/dev/null || true
}

playerctl_for_selected() {
    local player
    player=$(select_player 2>/dev/null) || return 0
    playerctl --player="$player" "$@"
}

metadata_value() {
    local player="$1"
    local field="$2"
    # MPRIS names containing ':' are template fields, not positional
    # arguments to `playerctl metadata`.  The template form works for both
    # standard and namespaced fields and keeps seeking reliable.
    playerctl --player="$player" metadata --format "{{ $field }}" 2>/dev/null | head -n 1
}

status() {
    local player
    player=$(select_player 2>/dev/null) || {
        printf 'Stopped\n'
        return 0
    }
    playerctl --player="$player" status 2>/dev/null || printf 'Stopped\n'
}

shuffle_status() {
    local player
    player=$(select_player 2>/dev/null) || {
        printf 'Off\n'
        return 0
    }
    playerctl --player="$player" shuffle 2>/dev/null || printf 'Off\n'
}

loop_status() {
    local player
    player=$(select_player 2>/dev/null) || {
        printf 'None\n'
        return 0
    }
    playerctl --player="$player" loop 2>/dev/null || printf 'None\n'
}

metadata_json() {
    local player status title artist album art_url url

    player=$(select_player 2>/dev/null) || {
        jq -cn '{player:"",status:"Stopped",title:"",artist:"",album:"",art_url:"",url:""}'
        return 0
    }

    status=$(playerctl --player="$player" status 2>/dev/null || printf 'Stopped')
    title=$(metadata_value "$player" xesam:title)
    artist=$(metadata_value "$player" xesam:artist)
    album=$(metadata_value "$player" xesam:album)
    art_url=$(metadata_value "$player" mpris:artUrl)
    url=$(metadata_value "$player" xesam:url)

    jq -cn \
        --arg player "$player" \
        --arg status "$status" \
        --arg title "$title" \
        --arg artist "$artist" \
        --arg album "$album" \
        --arg art_url "$art_url" \
        --arg url "$url" \
        '{player:$player,status:$status,title:$title,artist:$artist,album:$album,art_url:$art_url,url:$url}'
}

seek_percent() {
    local player length_us percent position_seconds
    percent="${1:-}"

    [[ "$percent" =~ ^[0-9]+([.][0-9]+)?$ ]] || return 0
    player=$(select_player 2>/dev/null) || return 0
    length_us=$(metadata_value "$player" mpris:length)
    [[ "$length_us" =~ ^[0-9]+$ ]] || return 0

    percent=$(awk -v value="$percent" 'BEGIN { if (value < 0) value = 0; if (value > 100) value = 100; printf "%.6f", value }')
    position_seconds=$(awk -v track_length="$length_us" -v value="$percent" 'BEGIN { printf "%.3f", track_length * value / 100000000 }')
    playerctl --player="$player" position "$position_seconds" >/dev/null 2>&1 || true
}

case "${1:-player}" in
    player)
        player_or_empty
        ;;
    status)
        status
        ;;
    shuffle-status)
        shuffle_status
        ;;
    loop-status)
        loop_status
        ;;
    metadata-json)
        metadata_json
        ;;
    play-pause)
        playerctl_for_selected play-pause >/dev/null 2>&1 || true
        ;;
    previous)
        playerctl_for_selected previous >/dev/null 2>&1 || true
        ;;
    next)
        playerctl_for_selected next >/dev/null 2>&1 || true
        ;;
    shuffle-toggle)
        playerctl_for_selected shuffle toggle >/dev/null 2>&1 || true
        ;;
    loop-toggle)
        player=$(select_player 2>/dev/null) || exit 0
        current_loop=$(playerctl --player="$player" loop 2>/dev/null || printf 'None')
        if [[ "$current_loop" == "None" ]]; then
            playerctl --player="$player" loop Track >/dev/null 2>&1 || true
        else
            playerctl --player="$player" loop None >/dev/null 2>&1 || true
        fi
        ;;
    volume-up)
        playerctl_for_selected volume 0.05+ >/dev/null 2>&1 || true
        ;;
    volume-down)
        playerctl_for_selected volume 0.02- >/dev/null 2>&1 || true
        ;;
    seek-percent)
        seek_percent "${2:-}"
        ;;
    *)
        printf 'Unknown media_player command: %s\n' "$1" >&2
        exit 2
        ;;
esac
