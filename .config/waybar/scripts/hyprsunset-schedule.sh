#!/usr/bin/env bash

# Shared night-mode controller for Hyprland, hyprsunset, Waybar, SwayNC,
# wallpaper, and LibreWolf's next normal startup.

set -u
umask 077

readonly CONFIG_ROOT="${XDG_CONFIG_HOME:-$HOME/.config}"
readonly STATE_ROOT="${XDG_STATE_HOME:-$HOME/.local/state}"
readonly RUNTIME_ROOT="${XDG_RUNTIME_DIR:-$STATE_ROOT/night-mode}"
readonly WALLPAPER_ROOT="$CONFIG_ROOT/wallpapers"
readonly DAY_WALLPAPER="$WALLPAPER_ROOT/fractal_background.png"
readonly NIGHT_WALLPAPER="$WALLPAPER_ROOT/fractal_background.png"
readonly WAYBAR_ROOT="$CONFIG_ROOT/waybar"
readonly WAYBAR_STYLE="$WAYBAR_ROOT/style.css"
readonly WAYBAR_DAY_STYLE="$WAYBAR_ROOT/style-day.css"
readonly WAYBAR_NIGHT_STYLE="$WAYBAR_ROOT/style-night.css"
readonly SWAYNC_ROOT="$CONFIG_ROOT/swaync"
readonly SWAYNC_STYLE="$SWAYNC_ROOT/style.css"
readonly SWAYNC_DAY_STYLE="$SWAYNC_ROOT/style-day.css"
readonly SWAYNC_NIGHT_STYLE="$SWAYNC_ROOT/style-night.css"
readonly LIBREWOLF_ROOT="$HOME/.librewolf"
readonly LIBREWOLF_THEME_ROOT="$CONFIG_ROOT/librewolf-night-mode"
readonly NIGHT_LIGHT_UNIT="hyprsunset-night-light.service"
readonly STATE_FILE="$RUNTIME_ROOT/hyprsunset_state"
readonly TEMP_FILE="$RUNTIME_ROOT/hyprsunset_temp"
readonly SCHEDULED_TEMP_FILE="$RUNTIME_ROOT/hyprsunset_scheduled_temp"
readonly MODE_OVERRIDE_FILE="$RUNTIME_ROOT/night-mode-override"
readonly LEGACY_PID_FILE="$RUNTIME_ROOT/hyprsunset_pid"
readonly MODE_FILE="$RUNTIME_ROOT/night-mode"
readonly WALLPAPER_OVERRIDE_FILE="$RUNTIME_ROOT/wallpaper-override"
readonly LOCK_FILE="$RUNTIME_ROOT/night-mode.lock"

readonly DAY_TEMP=6500
readonly NIGHT_TEMP=1000
readonly DEFAULT_TEMP=4500
readonly MIN_TEMP=1000
readonly MAX_TEMP=6500
readonly DAY_START=$((6 * 60 * 60))
readonly NIGHT_START=$((22 * 60 * 60))
readonly RAMP_END=$((23 * 60 * 60))

librewolf_deferred_mode=""

mkdir -p "$RUNTIME_ROOT" 2>/dev/null || {
    printf 'night-mode: cannot create runtime directory %s\n' "$RUNTIME_ROOT" >&2
    exit 1
}
chmod 700 "$RUNTIME_ROOT" 2>/dev/null || true
exec 9>"$LOCK_FILE"
chmod 600 "$LOCK_FILE" 2>/dev/null || true

log() {
    printf 'night-mode: %s\n' "$*" >&2
}

write_value() {
    local path="$1" value="$2"
    printf '%s\n' "$value" > "$path"
    chmod 600 "$path" 2>/dev/null || true
}

is_integer() {
    [[ "$1" =~ ^[0-9]+$ ]]
}

clamp_temperature() {
    local value="$1"
    is_integer "$value" || value="$DEFAULT_TEMP"
    [ "$value" -lt "$MIN_TEMP" ] && value="$MIN_TEMP"
    [ "$value" -gt "$MAX_TEMP" ] && value="$MAX_TEMP"
    printf '%s\n' "$value"
}

hyprctl_safe() {
    command -v hyprctl >/dev/null 2>&1 || return 1
    timeout --kill-after=1s 3s hyprctl "$@" >/dev/null 2>&1
}

hyprctl_timed() {
    command -v hyprctl >/dev/null 2>&1 || return 1
    timeout --kill-after=1s 5s hyprctl "$@"
}

recover_hyprpaper() {
    log "hyprpaper IPC is unavailable; restarting hyprpaper.service"
    systemctl --user restart hyprpaper.service >/dev/null 2>&1 || {
        log "could not restart hyprpaper.service"
        return 1
    }
    sleep 1
}

pid_is_hyprsunset() {
    local pid="$1"
    [ -n "$pid" ] || return 1
    is_integer "$pid" || return 1
    [ "$(ps -o comm= -p "$pid" 2>/dev/null | tr -d '[:space:]')" = "hyprsunset" ]
}

stop_legacy_hyprsunset() {
    local pid=""

    if [ -r "$LEGACY_PID_FILE" ]; then
        pid=$(<"$LEGACY_PID_FILE")
        if pid_is_hyprsunset "$pid"; then
            log "stopping legacy Waybar-owned hyprsunset process $pid"
            kill "$pid" 2>/dev/null || true
            for _ in 1 2 3 4 5; do
                kill -0 "$pid" 2>/dev/null || break
                sleep 0.2
            done
            if pid_is_hyprsunset "$pid"; then
                kill -KILL "$pid" 2>/dev/null || true
            fi
        fi
        mv -f "$LEGACY_PID_FILE" "$LEGACY_PID_FILE.stale" 2>/dev/null || true
    fi
}

night_light_active() {
    systemctl --user is-active --quiet "$NIGHT_LIGHT_UNIT"
}

start_night_light() {
    local temperature
    temperature=$(clamp_temperature "$1")

    if ! night_light_active; then
        # The old Waybar helper could leave a daemon outside this service's
        # cgroup. Clean up only the PID that it explicitly recorded; do not
        # kill arbitrary user-launched hyprsunset processes.
        stop_legacy_hyprsunset
        if ! systemctl --user start "$NIGHT_LIGHT_UNIT"; then
            log "could not start $NIGHT_LIGHT_UNIT"
            return 1
        fi
    fi

    if ! night_light_active; then
        log "$NIGHT_LIGHT_UNIT did not become active"
        return 1
    fi

    write_value "$STATE_FILE" on
    write_value "$TEMP_FILE" "$temperature"
    if ! hyprctl_safe hyprsunset temperature "$temperature"; then
        log "hyprctl could not set night-light temperature to ${temperature}K"
        return 1
    fi
    return 0
}

stop_night_light() {
    local ok=0

    if night_light_active; then
        systemctl --user stop "$NIGHT_LIGHT_UNIT" || ok=1
    fi
    stop_legacy_hyprsunset
    write_value "$STATE_FILE" off
    [ "$ok" -eq 0 ] || log "could not stop $NIGHT_LIGHT_UNIT"
    return "$ok"
}

seconds_since_midnight() {
    local stamp hour minute second
    stamp=$(date +%H:%M:%S)
    IFS=: read -r hour minute second <<< "$stamp"
    printf '%s\n' "$((10#$hour * 60 * 60 + 10#$minute * 60 + 10#$second))"
}

current_mode() {
    local now
    now=$(seconds_since_midnight)

    if [ "$now" -lt "$DAY_START" ] || [ "$now" -ge "$NIGHT_START" ]; then
        printf 'night\n'
    else
        printf 'day\n'
    fi
}

effective_mode() {
    local override=""

    if [ -r "$MODE_OVERRIDE_FILE" ]; then
        override=$(<"$MODE_OVERRIDE_FILE")
        case "$override" in
            day|night)
                printf '%s\n' "$override"
                return
                ;;
        esac
    fi

    current_mode
}

scheduled_temperature() {
    local now elapsed temperature
    now=$(seconds_since_midnight)

    if [ "$now" -ge "$NIGHT_START" ] && [ "$now" -lt "$RAMP_END" ]; then
        elapsed=$((now - NIGHT_START))
        temperature=$((DAY_TEMP - (elapsed * (DAY_TEMP - NIGHT_TEMP) / (RAMP_END - NIGHT_START))))
        [ "$temperature" -lt "$NIGHT_TEMP" ] && temperature="$NIGHT_TEMP"
        printf '%s\n' "$temperature"
        return
    fi

    if [ "$now" -ge "$RAMP_END" ] || [ "$now" -lt "$DAY_START" ]; then
        printf '%s\n' "$NIGHT_TEMP"
    else
        printf '%s\n' "$DAY_TEMP"
    fi
}

apply_display_mode() {
    local mode="$1" scheduled_temperature_value last_scheduled_temperature
    local current_temperature delta temperature

    if [ "$mode" = night ]; then
        scheduled_temperature_value=$(scheduled_temperature)

        # Keep the automatic ramp relative to the current temperature. This
        # preserves manual adjustments instead of replacing them with the
        # schedule's absolute value on the next controller pass.
        if [ -r "$SCHEDULED_TEMP_FILE" ]; then
            last_scheduled_temperature=$(<"$SCHEDULED_TEMP_FILE")
        else
            last_scheduled_temperature=""
        fi

        if is_integer "$last_scheduled_temperature" && [ -r "$TEMP_FILE" ]; then
            current_temperature=$(<"$TEMP_FILE")
            if is_integer "$current_temperature"; then
                delta=$((scheduled_temperature_value - last_scheduled_temperature))
                temperature=$(clamp_temperature "$((current_temperature + delta))")
            else
                temperature="$scheduled_temperature_value"
            fi
        else
            temperature="$scheduled_temperature_value"
        fi

        start_night_light "$temperature"
        write_value "$SCHEDULED_TEMP_FILE" "$scheduled_temperature_value"
    else
        # A new night ramp starts from its scheduled entry point.
        rm -f "$SCHEDULED_TEMP_FILE"
        stop_night_light
    fi
}

wallpaper_is_applied() {
    local mode="$1" wallpaper active monitor
    local -a monitors=()

    wallpaper=$(wallpaper_for_mode "$mode") || return 1

    [ -f "$wallpaper" ] || return 1
    command -v jq >/dev/null 2>&1 || return 1
    active=$(hyprctl_timed hyprpaper listactive 2>/dev/null) || return 1
    local monitors_json
    monitors_json=$(hyprctl_timed monitors -j 2>/dev/null) || return 1
    mapfile -t monitors < <(jq -r '.[].name' <<< "$monitors_json")
    (( ${#monitors[@]} > 0 )) || return 1

    for monitor in "${monitors[@]}"; do
        grep -Fqx "$monitor: $wallpaper" <<< "$active" || return 1
    done
    return 0
}

wallpaper_for_mode() {
    local mode="$1" wallpaper

    if [ -r "$WALLPAPER_OVERRIDE_FILE" ]; then
        wallpaper=$(<"$WALLPAPER_OVERRIDE_FILE")
        if [ -f "$wallpaper" ]; then
            printf '%s\n' "$wallpaper"
            return 0
        fi
    fi

    if [ "$mode" = night ]; then
        printf '%s\n' "$NIGHT_WALLPAPER"
    else
        printf '%s\n' "$DAY_WALLPAPER"
    fi
}

apply_wallpaper() {
    local mode="$1" wallpaper monitor applied=0 attempt
    local -a monitors=()

    wallpaper=$(wallpaper_for_mode "$mode") || return 1

    [ -f "$wallpaper" ] || {
        log "wallpaper is missing: $wallpaper"
        return 1
    }
    command -v jq >/dev/null 2>&1 || {
        log "jq is required to apply wallpapers"
        return 1
    }

    local monitors_json
    monitors_json=$(hyprctl_timed monitors -j 2>/dev/null) || return 1
    mapfile -t monitors < <(jq -r '.[].name' <<< "$monitors_json")
    (( ${#monitors[@]} > 0 )) || return 1

    for attempt in 1 2; do
        applied=0
        for monitor in "${monitors[@]}"; do
            if hyprctl_timed hyprpaper wallpaper "$monitor, $wallpaper, cover" >/dev/null 2>&1; then
                applied=1
            fi
        done
        [ "$applied" -eq 1 ] && break
        [ "$attempt" -eq 1 ] || break
        recover_hyprpaper || break
    done

    [ "$applied" -eq 1 ]
}

prepare_waybar_style_link() {
    local target="$1" current backup

    [ -f "$target" ] || {
        log "Waybar stylesheet is missing: $target"
        return 1
    }

    if [ -L "$WAYBAR_STYLE" ]; then
        current=$(readlink -f "$WAYBAR_STYLE" 2>/dev/null || true)
    elif [ -f "$WAYBAR_STYLE" ]; then
        backup="$WAYBAR_STYLE.before-night-mode-$(date +%Y%m%d-%H%M%S)"
        mv "$WAYBAR_STYLE" "$backup" || {
            log "could not preserve the existing Waybar stylesheet"
            return 1
        }
        current=""
    elif [ -e "$WAYBAR_STYLE" ]; then
        log "Waybar stylesheet path is not a regular file or symlink"
        return 1
    else
        current=""
    fi

    if [ "$current" != "$target" ]; then
        # Swap the link atomically.  ln -sfn briefly leaves a dangling link,
        # which can make Waybar reload the wrong fallback during a mode change.
        local temporary_link="$WAYBAR_STYLE.tmp.$$"
        rm -f -- "$temporary_link"
        ln -s "$target" "$temporary_link" || {
            log "could not point Waybar at $target"
            return 1
        }
        mv -Tf -- "$temporary_link" "$WAYBAR_STYLE" || {
            rm -f -- "$temporary_link"
            log "could not install the Waybar style link"
            return 1
        }
        return 0
    fi
    return 2
}

apply_waybar_mode() {
    local mode="$1" target

    if [ "$mode" = night ]; then
        target="$WAYBAR_NIGHT_STYLE"
    else
        target="$WAYBAR_DAY_STYLE"
    fi

    prepare_waybar_style_link "$target"
    case "$?" in
        0)
            # The transition caller performs the clean child restart.
            ;;
        2)
            ;;
        *)
            return 1
            ;;
    esac
    return 0
}

prepare_swaync_style_link() {
    local target="$1" current backup temporary_link

    [ -f "$target" ] || {
        log "SwayNC stylesheet is missing: $target"
        return 1
    }

    if [ -L "$SWAYNC_STYLE" ]; then
        current=$(readlink -f "$SWAYNC_STYLE" 2>/dev/null || true)
    elif [ -f "$SWAYNC_STYLE" ]; then
        backup="$SWAYNC_STYLE.before-night-mode-$(date +%Y%m%d-%H%M%S)"
        mv "$SWAYNC_STYLE" "$backup" || {
            log "could not preserve the existing SwayNC stylesheet"
            return 1
        }
        current=""
    elif [ -e "$SWAYNC_STYLE" ]; then
        log "SwayNC stylesheet path is not a regular file or symlink"
        return 1
    else
        current=""
    fi

    if [ "$current" != "$target" ]; then
        temporary_link="$SWAYNC_STYLE.tmp.$$"
        rm -f -- "$temporary_link"
        ln -s "$target" "$temporary_link" || {
            log "could not point SwayNC at $target"
            return 1
        }
        mv -Tf -- "$temporary_link" "$SWAYNC_STYLE" || {
            rm -f -- "$temporary_link"
            log "could not install the SwayNC style link"
            return 1
        }
        return 0
    fi
    return 2
}

apply_swaync_mode() {
    local mode="$1" target

    if [ "$mode" = night ]; then
        target="$SWAYNC_NIGHT_STYLE"
    else
        target="$SWAYNC_DAY_STYLE"
    fi

    prepare_swaync_style_link "$target"
    case "$?" in
        0)
            if pgrep -x swaync >/dev/null 2>&1; then
                swaync-client -rs >/dev/null 2>&1 || return 1
            fi
            ;;
        2)
            ;;
        *)
            return 1
            ;;
    esac
    return 0
}

find_librewolf_profile() {
    local relative profile_spec profile_path is_relative

    if [ -r "$LIBREWOLF_ROOT/installs.ini" ]; then
        relative=$(awk -F= '$1 == "Default" { gsub(/[[:space:]]/, "", $2); print $2; exit }' \
            "$LIBREWOLF_ROOT/installs.ini")
        if [ -n "$relative" ] && [ -f "$LIBREWOLF_ROOT/$relative/prefs.js" ]; then
            printf '%s\n' "$LIBREWOLF_ROOT/$relative"
            return 0
        fi
    fi

    [ -r "$LIBREWOLF_ROOT/profiles.ini" ] || return 1
    profile_spec=$(awk -F= '
        /^\[Profile0\]$/ { in_profile=1; next }
        in_profile && /^\[/ { exit }
        in_profile && $1 == "Path" { path=$2 }
        in_profile && $1 == "IsRelative" { relative=$2 }
        END { if (path != "") print path "|" relative }
    ' "$LIBREWOLF_ROOT/profiles.ini")
    profile_path=${profile_spec%%|*}
    is_relative=${profile_spec##*|}
    [ -n "$profile_path" ] || return 1
    if [ "$is_relative" = 1 ]; then
        profile_path="$LIBREWOLF_ROOT/$profile_path"
    fi
    [ -f "$profile_path/prefs.js" ] || return 1
    printf '%s\n' "$profile_path"
}

librewolf_running() {
    local pid command_line

    while read -r pid; do
        [ -n "$pid" ] || continue
        command_line=$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null || true)
        case "$command_line" in
            *-contentproc*) ;;
            *) return 0 ;;
        esac
    done < <(pgrep -u "$(id -u)" -x librewolf 2>/dev/null || true)
    return 1
}

managed_user_js_target() {
    local user_js="$1" target="$2" current

    if [ -L "$user_js" ]; then
        current=$(readlink -f "$user_js" 2>/dev/null || true)
        case "$current" in
            "$LIBREWOLF_THEME_ROOT/day.user.js"|"$LIBREWOLF_THEME_ROOT/night.user.js")
                ;;
            *)
                log "leaving user-managed LibreWolf user.js symlink untouched"
                return 2
                ;;
        esac
    elif [ -e "$user_js" ]; then
        if ! grep -Fq 'Managed by the Hyprland night-mode schedule' "$user_js" 2>/dev/null; then
            log "leaving user-managed LibreWolf user.js untouched"
            return 2
        fi
        mv "$user_js" "$user_js.before-night-mode-$(date +%Y%m%d-%H%M%S)" || return 1
    fi

    current=$(readlink -f "$user_js" 2>/dev/null || true)
    [ "$current" = "$target" ] && return 0
    ln -sfn "$target" "$user_js"
}

sync_librewolf_extension_state() {
    local profile="$1" target_id="$2" extensions_json temp backup

    extensions_json="$profile/extensions.json"
    [ -f "$extensions_json" ] || return 1
    command -v jq >/dev/null 2>&1 || return 1

    jq -e --arg target "$target_id" \
        'any(.addons[]?; .type == "theme" and .id == $target)' \
        "$extensions_json" >/dev/null 2>&1 || {
        log "requested LibreWolf theme is not installed: $target_id"
        return 1
    }

    if librewolf_running; then
        return 2
    fi

    temp=$(mktemp "$profile/extensions.json.night-mode.XXXXXX") || return 1
    if ! jq --arg target "$target_id" '
        .addons |= map(
            if .type == "theme" and .id == $target then
                .active = true | .userDisabled = false | .softDisabled = false
            elif .type == "theme" and .visible == true then
                .active = false | .userDisabled = true
            else . end
        )
    ' "$extensions_json" > "$temp"; then
        rm -f "$temp"
        return 1
    fi

    if cmp -s "$temp" "$extensions_json"; then
        rm -f "$temp"
        return 0
    fi

    backup="$extensions_json.before-night-mode-$(date +%Y%m%d-%H%M%S)"
    cp -p "$extensions_json" "$backup" || {
        rm -f "$temp"
        return 1
    }
    chmod 600 "$temp" 2>/dev/null || true
    mv "$temp" "$extensions_json"
}

apply_librewolf_startup_mode() {
    local mode="$1" profile target user_js target_id rc

    profile=$(find_librewolf_profile || true)
    [ -n "$profile" ] || return 0

    if [ "$mode" = night ]; then
        target="$LIBREWOLF_THEME_ROOT/night.user.js"
        target_id='firefox-compact-dark@mozilla.org'
    else
        target="$LIBREWOLF_THEME_ROOT/day.user.js"
        target_id='firefox-compact-light@mozilla.org'
    fi
    [ -f "$target" ] || return 1

    user_js="$profile/user.js"
    managed_user_js_target "$user_js" "$target"
    rc=$?
    [ "$rc" -eq 2 ] && return 2
    [ "$rc" -eq 0 ] || return 1

    sync_librewolf_extension_state "$profile" "$target_id"
    rc=$?
    if [ "$rc" -eq 2 ]; then
        if [ "$librewolf_deferred_mode" != "$mode" ]; then
            log "deferring persisted LibreWolf theme activation until the browser exits"
            librewolf_deferred_mode="$mode"
        fi
        return 2
    fi
    librewolf_deferred_mode=""
    [ "$rc" -eq 0 ] || return 1
    return 0
}

apply_mode() {
    local mode="$1" rc failed=0

    # A manual wallpaper only applies within the current mode window. Every
    # automatic transition starts with the scheduled wallpaper.
    rm -f -- "$WALLPAPER_OVERRIDE_FILE"
    apply_display_mode "$mode" || failed=1
    apply_waybar_mode "$mode" || failed=1
    # Do not reload Waybar here. Even an in-process CSS reload can briefly
    # recreate its exclusive layer surface, which makes Hyprland re-tile and
    # bounce every window. The selected stylesheet is ready for Waybar's next
    # normal restart; keep the current bar mounted during mode changes.
    apply_swaync_mode "$mode" || failed=1
    apply_wallpaper "$mode" || failed=1
    apply_librewolf_startup_mode "$mode"
    rc=$?
    # A running browser is an intentional deferral, not a controller failure.
    [ "$rc" -eq 0 ] || [ "$rc" -eq 2 ] || failed=1
    write_value "$MODE_FILE" "$mode"
    return "$failed"
}

force_night_mode() {
    write_value "$MODE_OVERRIDE_FILE" night
    apply_mode night
}

resume_scheduled_mode() {
    rm -f -- "$MODE_OVERRIDE_FILE"
    apply_mode "$(current_mode)"
}

toggle_manual_mode() {
    local state="off"

    # This is the Waybar left-click action, so it must behave like an
    # on/off control even when the clock is currently inside the scheduled
    # night window. Keep the schedule available through the explicit
    # right-click resume action.
    [ -r "$STATE_FILE" ] && state=$(<"$STATE_FILE")
    if [ "$state" = on ] || night_light_active; then
        write_value "$MODE_OVERRIDE_FILE" day
        apply_mode day
    else
        force_night_mode
    fi
}

toggle_night_light() {
    local state="off" temperature
    [ -r "$STATE_FILE" ] && state=$(<"$STATE_FILE")

    if [ "$state" = on ] || night_light_active; then
        stop_night_light
    else
        temperature="$DEFAULT_TEMP"
        [ -r "$TEMP_FILE" ] && temperature=$(<"$TEMP_FILE")
        start_night_light "$(clamp_temperature "$temperature")"
    fi
}

adjust_night_light() {
    local delta="$1" state="off" temperature
    if [[ "$delta" == -* ]]; then
        is_integer "${delta#-}" || return 2
    else
        is_integer "$delta" || return 2
    fi
    [ -r "$TEMP_FILE" ] && temperature=$(<"$TEMP_FILE") || temperature="$DEFAULT_TEMP"
    is_integer "$temperature" || temperature="$DEFAULT_TEMP"
    temperature=$((temperature + delta))
    temperature=$(clamp_temperature "$temperature")
    write_value "$TEMP_FILE" "$temperature"
    [ -r "$STATE_FILE" ] && state=$(<"$STATE_FILE")
    if [ "$state" = on ] || night_light_active; then
        start_night_light "$temperature"
    fi
}

run_locked_command() {
    if ! flock -w 4 -x 9; then
        log "another night-mode operation is still running"
        return 1
    fi
    "$@"
    local rc=$?
    flock -u 9
    return "$rc"
}

case "${1:-}" in
    --mode)
        case "${2:-}" in
            day|night)
                run_locked_command apply_mode "$2"
                rc=$?
                exit "$rc"
                ;;
            *)
                printf 'usage: %s [--mode day|night|--toggle|--adjust N]\n' "$0" >&2
                exit 2
                ;;
        esac
        ;;
    --toggle)
        run_locked_command toggle_night_light
        exit "$?"
        ;;
    --adjust)
        run_locked_command adjust_night_light "${2:-}"
        exit "$?"
        ;;
    --force-night)
        run_locked_command force_night_mode
        exit "$?"
        ;;
    --toggle-manual)
        run_locked_command toggle_manual_mode
        exit "$?"
        ;;
    --resume-schedule)
        run_locked_command resume_scheduled_mode
        exit "$?"
        ;;
    "")
        ;;
    *)
        printf 'usage: %s [--mode day|night|--toggle|--adjust N]\n' "$0" >&2
        exit 2
        ;;
esac

cleanup() {
    # systemd stops the dedicated daemon through the PartOf relationship; this
    # explicit cleanup also handles a script termination during a transition.
    stop_night_light >/dev/null 2>&1 || true
    exit 0
}
trap cleanup INT TERM

last_mode=""
last_wallpaper_error_mode=""

while :; do
    if flock -n 9; then
        mode=$(effective_mode)
        if [ "$mode" != "$last_mode" ]; then
            log "entering $mode mode"
            apply_mode "$mode" || log "one or more $mode-mode components need retrying"
            last_mode="$mode"
            last_wallpaper_error_mode=""
        else
            apply_display_mode "$mode" || true
            apply_waybar_mode "$mode" || true
            apply_swaync_mode "$mode" || true
            apply_librewolf_startup_mode "$mode" || true
        fi

        if ! wallpaper_is_applied "$mode"; then
            if apply_wallpaper "$mode"; then
                log "applied $mode wallpaper"
                last_wallpaper_error_mode=""
            elif [ "$last_wallpaper_error_mode" != "$mode" ]; then
                log "could not apply $mode wallpaper yet; will retry"
                last_wallpaper_error_mode="$mode"
            fi
        fi

        flock -u 9
    fi
    sleep 30
done
