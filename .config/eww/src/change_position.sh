#!/usr/bin/env bash

set -u

PLAYER_HELPER="$HOME/.config/waybar/scripts/media_player.sh"

percent="${1:-}"
[[ "$percent" =~ ^[0-9]+([.][0-9]+)?$ ]] || exit 0

"$PLAYER_HELPER" seek-percent "$percent"
