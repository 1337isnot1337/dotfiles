#!/usr/bin/env bash

set -u

panel="${1:-}"
case "$panel" in
    dashboard|wifi_panel|bluetooth_panel|pacman_panel) ;;
    *)
        printf 'usage: %s {dashboard|wifi_panel|bluetooth_panel|pacman_panel}\n' "$0" >&2
        exit 2
        ;;
esac

# Waybar can launch a second click while a panel is opening.  Queue that
# transition so a quick follow-up click still closes the panel.
panel_runtime_dir="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
panel_lock_file="$panel_runtime_dir/eww-panel-toggle.lock"
exec 9>"$panel_lock_file"
flock -w 15 9 || exit 0

# The launcher has to inspect active windows before it knows whether a click
# means open or close.  Make that work even when no Eww daemon is running yet,
# and recover an instance whose IPC socket is genuinely unresponsive.
eww_request() {
    timeout --kill-after=0.5s 2s eww "$@"
}

ensure_eww_daemon() {
    local attempt

    if pgrep -x eww >/dev/null 2>&1; then
        eww_request ping >/dev/null 2>&1 && return 0

        # Recover from a stale process/socket before starting a replacement.
        "$HOME/.config/eww/src/recover_eww_daemon.sh" || true
    fi

    # Do not let the daemon inherit this launcher's serialization lock. If it
    # keeps fd 9 open, every later click sees the lock as permanently busy and
    # silently exits.
    eww daemon 9>&- >/dev/null 2>&1 || true
    for attempt in $(seq 1 30); do
        eww_request ping >/dev/null 2>&1 && return 0
        sleep 0.1
    done

    return 1
}

ensure_eww_daemon || exit 1

panel_is_active() {
    local target="$1"
    local active_output
    local result

    # Keep every state probe short.  This script is launched from Waybar, so
    # an unhealthy EWW daemon must not leave the click command waiting behind
    # a dead IPC socket.
    active_output=$(eww_request active-windows 2>/dev/null)
    result=$?
    if (( result == 124 || result == 137 )); then
        # Do not treat a timed-out state probe as "not active" and open a
        # second copy of the panel.
        return 2
    elif (( result != 0 )); then
        # The daemon may have disappeared between the ping and this probe.
        return 2
    fi

    awk -F': ' -v target="$target" '$2 == target { found = 1 } END { exit !found }' <<<"$active_output"
}

# Read the current applet set once for the opening decision.  This lets the
# common case (nothing open) skip the full close/reset helper entirely.
active_output=$(eww_request active-windows 2>/dev/null)
active_result=$?
if (( active_result != 0 )); then
    exit 1
fi

wait_for_panel_state() {
    local target="$1"
    local desired="$2"
    local attempt
    local state

    for attempt in $(seq 1 20); do
        if [[ "$desired" == "open" ]]; then
            panel_is_active "$target"
            state=$?
            (( state == 0 )) && return 0
            (( state == 2 )) && return 1
        else
            panel_is_active "$target"
            state=$?
            (( state == 2 )) && return 1
            (( state != 0 )) && return 0
        fi
        sleep 0.1
    done

    return 1
}

open_panel_without_orphaning_cli() {
    local target="$1"
    shift

    # With the daemon explicitly running, `eww open` is a short-lived IPC
    # client. Do not background and kill it: if Eww daemonizes during that
    # race, the captured PID can be the daemon itself.
    eww_request open "$target" "$@" >/dev/null 2>&1 || return 1
    wait_for_panel_state "$target" open
}

awk -F': ' -v target="$panel" '$2 == target { found = 1 } END { exit !found }' <<<"$active_output"
panel_state=$?
if (( panel_state == 2 )); then
    exit 1
elif (( panel_state == 0 )); then
    "$HOME/.config/eww/src/close_panel.sh" "$panel"
    wait_for_panel_state "$panel" closed || true
    exit 0
fi

# Close the applet family only when the initial snapshot shows that another
# applet or the Waybar guard is actually open.  The usual clean open now skips
# this work altogether.
if awk -F': ' '$2 ~ /^(dashboard|wifi_panel|bluetooth_panel|pacman_panel|waybar_dismiss)$/ { found = 1 } END { exit !found }' <<<"$active_output"; then
    "$HOME/.config/eww/src/close_panel.sh" all
fi

wait_for_panel_state "$panel" closed || true

if open_panel_without_orphaning_cli "$panel"; then
    # EWW's normal window is placed below Waybar's exclusive zone.  Offset the
    # narrow dismissal strip upward so a second Waybar click closes the panel.
    # Open it only after the panel is registered.
    if ! open_panel_without_orphaning_cli waybar_dismiss --pos 0x-48; then
        # Never leave an applet open without its Waybar dismissal strip.
        "$HOME/.config/eww/src/close_panel.sh" "$panel"
        exit 1
    fi

    # Hyprland's Lua configuration does not accept legacy dynamic keywords.
    # Register a temporary native Lua bind while an applet is visible.
    hyprctl eval 'hl.unbind("Escape")' >/dev/null 2>&1 || true
    hyprctl eval 'hl.bind("Escape", hl.dsp.exec_cmd("$HOME/.config/eww/src/close_panel.sh"))' >/dev/null 2>&1 || true
    exit 0
fi

exit 1
