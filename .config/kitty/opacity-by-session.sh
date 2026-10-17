#!/bin/sh

desktop="${XDG_CURRENT_DESKTOP:-} ${XDG_SESSION_DESKTOP:-} ${DESKTOP_SESSION:-} ${KDE_FULL_SESSION:-} ${KDE_SESSION_VERSION:+kde}"
desktop=$(printf '%s' "$desktop" | tr '[:upper:]' '[:lower:]')

case "$desktop" in
    *kde*|*plasma*) opacity=1.0 ;;
    *hyprland*) opacity=0.35 ;;
    *)
        if [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
            opacity=0.35
        else
            opacity=1.0
        fi
        ;;
esac

printf 'background_opacity %s\n' "$opacity"
