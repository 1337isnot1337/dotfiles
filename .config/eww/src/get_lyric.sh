#!/usr/bin/env bash

set -u

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
PLAYER_HELPER="$HOME/.config/waybar/scripts/media_player.sh"

emit_fallback() {
    local current="${1:-...}"
    jq -cn --arg previous "..." --arg current "$current" --arg next "..." \
        '{previous:$previous,current:$current,next:$next}'
}

player=$("$PLAYER_HELPER" player 2>/dev/null || true)
if [[ -z "$player" || "$player" != *spotify* ]]; then
    emit_fallback "Lyrics unavailable for this player"
    exit 0
fi

track_url=$(playerctl --player="$player" metadata --format '{{ xesam:url }}' 2>/dev/null || true)
if [[ "$track_url" == spotify:track:* ]]; then
    spotify_id="${track_url#spotify:track:}"
else
    spotify_id="${track_url##*/}"
fi
spotify_id="${spotify_id%%\?*}"

if [[ ! "$spotify_id" =~ ^[[:alnum:]]{22}$ ]]; then
    emit_fallback "Lyrics unavailable"
    exit 0
fi

current_time_ms=$("$SCRIPT_DIR/song_progress.sh" position ms 2>/dev/null || printf '0')
[[ "$current_time_ms" =~ ^[0-9]+$ ]] || current_time_ms=0

lyrics_file=$(mktemp)
trap 'rm -f "$lyrics_file"' EXIT

http_status=$(curl -fsS --max-time 2 -o "$lyrics_file" -w '%{http_code}' \
    "http://localhost:3000/v1/lyrics/$spotify_id" 2>/dev/null || printf '000')
if [[ "$http_status" != "200" ]]; then
    emit_fallback "No lyrics found"
    exit 0
fi

lyrics=$(jq -er --argjson time "$current_time_ms" '
    .lyrics.lines
    | sort_by(.startTimeMs)
    | reduce .[] as $line
        ({previous:"...", current:"...", next:"..."};
         if (($line.startTimeMs // 0) - 1000 > $time and .next == "...") then
             .next = ($line.words // "...")
         elif (($line.startTimeMs // 0) - 1000 <= $time) then
             {previous:.current, current:($line.words // "..."), next:"..."}
         else .
         end)
' "$lyrics_file" 2>/dev/null || true)

if [[ -z "$lyrics" ]]; then
    emit_fallback "No lyrics found"
    exit 0
fi

previous=$(jq -r '.previous // "..."' <<<"$lyrics")
current=$(jq -r '.current // "..."' <<<"$lyrics")
next=$(jq -r '.next // "..."' <<<"$lyrics")
jq -cn --arg previous "$previous" --arg current "$current" --arg next "$next" \
    '{previous:$previous,current:$current,next:$next}'
