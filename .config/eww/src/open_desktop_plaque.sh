#!/usr/bin/env bash

set -u

# Keep every call on the same explicit config. This matters when the launcher
# is run by systemd, whose working directory is not the EWW config directory.
readonly EWW_CONFIG="${HOME}/.config/eww"

eww_cmd() {
    eww --config "$EWW_CONFIG" "$@"
}

wait_for_wayland() {
    # The service may be started by graphical-session.target just before
    # Hyprland has imported its environment into the user manager. In that
    # case, wait briefly for the compositor socket and IPC to become usable.
    for _ in $(seq 1 80); do
        if [[ -n "${XDG_RUNTIME_DIR:-}" \
            && -n "${WAYLAND_DISPLAY:-}" \
            && -S "${XDG_RUNTIME_DIR}/${WAYLAND_DISPLAY}" \
            && -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]] \
            && hyprctl monitors -j >/dev/null 2>&1; then
            return 0
        fi
        sleep 0.25
    done
    return 1
}

wait_for_wayland || exit 1

# EWW is normally started lazily by the applet scripts. The desktop plaque is
# the one exception: start the daemon once during the Hyprland session, take
# one Fastfetch snapshot, then leave the data untouched until next session.
if ! eww_cmd ping >/dev/null 2>&1; then
    eww_cmd daemon >/dev/null 2>&1 &
fi

daemon_ready=0
for _ in $(seq 1 80); do
    if eww_cmd ping >/dev/null 2>&1; then
        daemon_ready=1
        break
    fi
    sleep 0.25
done
((daemon_ready == 1)) || exit 1

# `plaque_data` is a defvar, deliberately—not a polling variable. Updating it
# here makes the values static for the life of this Hyprland session.
snapshot="$(${HOME}/.config/eww/src/fastfetch_plaque.py 2>/dev/null)" || snapshot=""
[[ -n "$snapshot" ]] || exit 1

# The daemon can answer ping before its config has finished registering
# defvars, especially when it survived a Hyprland restart. Do not leave the
# window showing the placeholder SESSION START values in that case.
data_updated=0
for _ in $(seq 1 40); do
    if eww_cmd update "plaque_data=$snapshot" >/dev/null 2>&1 \
        && [[ "$(eww_cmd get plaque_data 2>/dev/null)" == "$snapshot" ]]; then
        data_updated=1
        break
    fi
    sleep 0.25
done
((data_updated == 1)) || exit 1

# `eww open` is not idempotent: invoking it while the named window is already
# open creates another layer-shell surface with the same geometry. This
# launcher is called from Hyprland startup and may also be run manually, so
# reuse the existing plaque instead of opening a duplicate.
if ! eww_cmd active-windows 2>/dev/null \
    | awk -F: '$1 == "desktop_plaque" { found = 1 } END { exit found ? 0 : 1 }'; then
    eww_cmd open desktop_plaque >/dev/null 2>&1 || exit 1
fi

# Do not report success until the layer-shell surface is actually registered.
for _ in $(seq 1 40); do
    if eww_cmd active-windows 2>/dev/null \
        | awk -F: '$1 == "desktop_plaque" { found = 1 } END { exit found ? 0 : 1 }'; then
        exit 0
    fi
    sleep 0.25
done
exit 1
