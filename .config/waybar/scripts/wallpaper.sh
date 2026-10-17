#!/usr/bin/env bash

set -u

directory="${XDG_CONFIG_HOME:-$HOME/.config}/wallpapers"
state_root="${XDG_RUNTIME_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/night-mode}"
log_file="${XDG_STATE_HOME:-$HOME/.local/state}/wallpaper-button.log"

log() {
    mkdir -p -- "$(dirname -- "$log_file")" 2>/dev/null || return 0
    printf '%s wallpaper: %s\n' "$(date --iso-8601=seconds)" "$*" >> "$log_file"
}

hyprctl_timed() {
    command -v hyprctl >/dev/null 2>&1 || return 1
    timeout --kill-after=1s "$@"
}

restart_hyprpaper() {
    log "hyprpaper IPC unavailable; restarting hyprpaper.service"
    systemctl --user restart hyprpaper.service >/dev/null 2>&1 || return 1
    sleep 1
}

mkdir -p -- "$state_root" 2>/dev/null || exit 0

# Serialize manual changes with the night-mode scheduler. This lets the
# scheduler see the override before its next wallpaper health check.
exec 9>"$state_root/night-mode.lock" || exit 0
flock -w 4 -x 9 || exit 0

if [[ ! -d "$directory" ]]; then
    exit 0
fi

mapfile -t backgrounds < <(
    find "$directory" -maxdepth 1 -type f \
        \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) \
        -print 2>/dev/null | sort
)

if ((${#backgrounds[@]} == 0)); then
    exit 0
fi

active_wallpapers="$(hyprctl_timed 3s hyprctl hyprpaper listactive 2>/dev/null)" || {
    restart_hyprpaper || exit 0
    active_wallpapers="$(hyprctl_timed 3s hyprctl hyprpaper listactive 2>/dev/null)" || exit 0
}
mapfile -t active_backgrounds < <(
    sed -n 's/^[^:]*:[[:space:]]*//p' <<< "$active_wallpapers"
)

available_backgrounds=()
for background in "${backgrounds[@]}"; do
    background_path="$(realpath -e -- "$background" 2>/dev/null || printf '%s' "$background")"
    is_active=0

    for active_background in "${active_backgrounds[@]}"; do
        active_background_path="$(realpath -e -- "$active_background" 2>/dev/null || printf '%s' "$active_background")"
        if [[ "$background_path" == "$active_background_path" ]]; then
            is_active=1
            break
        fi
    done

    if ((is_active == 0)); then
        available_backgrounds+=("$background")
    fi
done

if ((${#available_backgrounds[@]} == 0)); then
    exit 0
fi

mapfile -t monitors < <(hyprctl_timed 3s hyprctl monitors -j 2>/dev/null | jq -r '.[].name')

if ((${#monitors[@]} == 0)); then
    exit 0
fi

random_background="${available_backgrounds[RANDOM % ${#available_backgrounds[@]}]}"

applied=0
for attempt in 1 2; do
    applied=0
    for monitor in "${monitors[@]}"; do
        if hyprctl_timed 5s hyprctl hyprpaper wallpaper "$monitor, $random_background, cover"; then
            applied=1
        fi
    done
    [ "$applied" -eq 1 ] && break
    [ "$attempt" -eq 1 ] || break
    restart_hyprpaper || break
done

if ((applied == 0)); then
    log "could not apply selected wallpaper: $random_background"
    exit 0
fi

# A deliberate button click is a manual exception, which the scheduler
# preserves until the next mode transition restores its automatic wallpaper.
if ((applied == 1)); then
    override_file="$state_root/wallpaper-override"
    temporary_override="$override_file.tmp.$$"
    if printf '%s\n' "$random_background" > "$temporary_override"; then
        mv -f -- "$temporary_override" "$override_file" || rm -f -- "$temporary_override"
    else
        rm -f -- "$temporary_override"
    fi
    log "applied $random_background"
fi
