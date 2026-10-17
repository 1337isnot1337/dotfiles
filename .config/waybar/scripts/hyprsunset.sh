#!/usr/bin/env bash

# Waybar status/control client. The scheduled controller and its dedicated
# systemd unit are the only components that own the hyprsunset daemon.

set -u

CONFIG_ROOT="${XDG_CONFIG_HOME:-$HOME/.config}"
STATE_ROOT="${XDG_STATE_HOME:-$HOME/.local/state}"
RUNTIME_ROOT="${XDG_RUNTIME_DIR:-$STATE_ROOT/night-mode}"
STATE_FILE="$RUNTIME_ROOT/hyprsunset_state"
TEMP_FILE="$RUNTIME_ROOT/hyprsunset_temp"
SCHEDULE_SCRIPT="$CONFIG_ROOT/waybar/scripts/hyprsunset-schedule.sh"

sync_systemd_session_environment() {
  # The Waybar child is launched with the live compositor's environment. A
  # stale user-systemd environment can otherwise start hyprsunset against a
  # dead Wayland socket after a compositor restart.
  systemctl --user import-environment \
    WAYLAND_DISPLAY HYPRLAND_INSTANCE_SIGNATURE \
    XDG_CURRENT_DESKTOP XDG_SESSION_TYPE XDG_RUNTIME_DIR \
    >/dev/null 2>&1 || true
  dbus-update-activation-environment --systemd \
    WAYLAND_DISPLAY HYPRLAND_INSTANCE_SIGNATURE \
    XDG_CURRENT_DESKTOP XDG_SESSION_TYPE XDG_RUNTIME_DIR \
    >/dev/null 2>&1 || true
}

run_controller() {
  sync_systemd_session_environment
  timeout 5s "$SCHEDULE_SCRIPT" "$@" >/dev/null 2>&1 || true
}

run_mode_controller() {
  sync_systemd_session_environment
  timeout 20s "$SCHEDULE_SCRIPT" "$@" >/dev/null 2>&1 || true
}

run_scroll_adjust() {
  local delta="$1" state="off" temperature new_temperature

  # Keep wheel events independent from the scheduler's long-running wallpaper
  # and display-maintenance lock.  The wheel path only needs to update the
  # current value and send one hyprsunset IPC request.
  exec 8>"$RUNTIME_ROOT/hyprsunset-scroll.lock"
  flock -x 8

  [ -r "$TEMP_FILE" ] && temperature=$(<"$TEMP_FILE") || temperature=4500
  [[ "$temperature" =~ ^[0-9]+$ ]] || temperature=4500
  new_temperature=$((temperature + delta))
  [ "$new_temperature" -lt 1000 ] && new_temperature=1000
  [ "$new_temperature" -gt 6500 ] && new_temperature=6500

  [ -r "$STATE_FILE" ] && state=$(<"$STATE_FILE")
  if [ "$state" = on ] && command -v hyprctl >/dev/null 2>&1; then
    if timeout --kill-after=1s 2s hyprctl hyprsunset temperature "$new_temperature" >/dev/null 2>&1; then
      printf '%s\n' "$new_temperature" > "$TEMP_FILE"
    fi
  fi

  flock -u 8
  exec 8>&-
}

case "${1:-}" in
  click)
    run_mode_controller --toggle-manual
    ;;
  scroll_up)
    run_scroll_adjust 500
    ;;
  scroll_down)
    run_scroll_adjust -500
    ;;
  force_night)
    run_mode_controller --force-night
    ;;
  resume_schedule)
    run_mode_controller --resume-schedule
    ;;
esac

state="off"
temp="Off"
[ -r "$STATE_FILE" ] && state=$(<"$STATE_FILE")
if [ "$state" = on ]; then
  [ -r "$TEMP_FILE" ] && temp="$(<"$TEMP_FILE")K" || temp="4500K"
fi

icon=$([ "$state" = on ] && echo "󱩍" || echo "󰹐")
printf '{"text": "%s", "tooltip": "Temp: %s\\nLeft click: toggle night mode\\nRight click: resume schedule\\nScroll: adjust temperature by 500K", "class": "%s"}\n' "$icon" "$temp" "$state"
