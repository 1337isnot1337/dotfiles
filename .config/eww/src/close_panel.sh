#!/usr/bin/env bash

set -u

eww_daemon_broken=0
recover_eww_daemon() {
    "$HOME/.config/eww/src/recover_eww_daemon.sh" >/dev/null 2>&1 || true
}

# Keep the emergency close path bounded. If EWW IPC stops answering, kill the
# daemon so a stale layer-shell surface cannot remain as an input trap.
run_eww() {
    (( eww_daemon_broken )) && return 1

    timeout --kill-after=0.5s 1s eww "$@" >/dev/null 2>&1
    local result=$?
    # GNU timeout returns 124 when the IPC client exceeded its deadline (or
    # 137 if the follow-up kill was needed). A normal EWW error, such as
    # closing a window that is already closed, must not kill a healthy daemon.
    if (( result == 124 || result == 137 )); then
        recover_eww_daemon
        eww_daemon_broken=1
    elif (( result != 0 )); then
        # A close of an already-closed window can legitimately return an
        # error.  Only classify it as a dead daemon if a short ping also fails.
        timeout --kill-after=0.25s 0.5s eww ping >/dev/null 2>&1
        local ping_result=$?
        if (( ping_result != 0 )); then
            if (( ping_result == 124 || ping_result == 137 )); then
                recover_eww_daemon
            fi
            eww_daemon_broken=1
        fi
    fi
    return "$result"
}

case "${1:-all}" in
    dashboard|wifi_panel|bluetooth_panel|pacman_panel)
        # EWW accepts multiple window names, so close the applet and the
        # transparent Waybar guard in one IPC request.
        run_eww close "$1" waybar_dismiss || true
        ;;
    all)
        # Keep unrelated EWW windows (for example the media player) intact;
        # only close the applet family and its Waybar guard.
        run_eww close dashboard wifi_panel bluetooth_panel pacman_panel waybar_dismiss || true
        ;;
    *) exit 2 ;;
esac

# Do not leave a half-entered password or a stale spinner behind when the
# panel is reopened from Waybar.
case "${1:-all}" in
    wifi_panel|all)
        if [[ "${1:-all}" == all ]]; then
            run_eww update wifi_selected='' wifi_password='' wifi_busy='' bluetooth_busy='' || true
        else
            run_eww update wifi_selected='' wifi_password='' wifi_busy='' || true
        fi
        ;;
esac
case "${1:-all}" in
    bluetooth_panel)
        run_eww update bluetooth_busy='' || true
        ;;
esac

hyprctl eval 'hl.unbind("Escape")' >/dev/null 2>&1 || true
