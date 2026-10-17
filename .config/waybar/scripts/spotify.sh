#!/usr/bin/env bash

set -u

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
PLAYER_HELPER="$SCRIPT_DIR/media_player.sh"

metadata_json=$("$PLAYER_HELPER" metadata-json 2>/dev/null || printf '{}')
player=$(jq -r '.player // ""' <<<"$metadata_json")
status=$(jq -r '.status // "Stopped"' <<<"$metadata_json")
artist=$(jq -r '.artist // ""' <<<"$metadata_json")
title=$(jq -r '.title // ""' <<<"$metadata_json")
url=$(jq -r '.url // ""' <<<"$metadata_json")

if [[ -z "$player" || ( -z "$artist" && -z "$title" ) ]]; then
    jq -cn '{text:"",tooltip:""}'
    exit 0
fi

url_lower=${url,,}
player_lower=${player,,}

# Browser MPRIS players identify themselves as Firefox/LibreWolf regardless
# of the site producing the audio. Prefer the media-page origin so Spotify in
# a browser does not inherit the YouTube icon.
case "$url_lower" in
    *spotify.com*|spotify:*) icon=" " ;;
    *youtube.com*|*youtu.be*|*youtube-nocookie.com*) icon=" " ;;
    *soundcloud.com*) icon=" " ;;
    *bandcamp.com*) icon=" " ;;
    *music.apple.com*) icon=" " ;;
    *music.amazon.com*) icon=" " ;;
    *twitch.tv*) icon=" " ;;
    *vimeo.com*) icon=" " ;;
    *)
        case "$player_lower" in
            *spotify*) icon=" " ;;
            *firefox*|*librewolf*) icon=" " ;;
            *) icon=" " ;;
        esac
        ;;
esac

[[ -z "$artist" ]] && artist="$title"
[[ -z "$title" ]] && title="$artist"

state_prefix=""
[[ "$status" == "Paused" ]] && state_prefix=" "

text="${icon}${state_prefix}${artist}"
tooltip="${icon}${state_prefix}${artist} - ${title}"$'\n'"Click: open media player"
jq -cn --arg text "$text" --arg tooltip "$tooltip" '{text:$text,tooltip:$tooltip}'
