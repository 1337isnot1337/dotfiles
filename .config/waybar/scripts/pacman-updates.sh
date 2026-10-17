#!/usr/bin/env bash

set -u

status_json="$($HOME/.config/eww/src/pacman_status.py --once 2>/dev/null || true)"

if [[ -z "$status_json" ]] || ! jq -e . >/dev/null 2>&1 <<< "$status_json"; then
    jq -cn '{text:"󰅖",class:"error",tooltip:"Could not read the pacman update state\nClick: inspect package updater"}'
    exit 0
fi

status="$(jq -r '.status // "error"' <<< "$status_json")"
count="$(jq -r '.count // 0' <<< "$status_json")"
error="$(jq -r '.error // ""' <<< "$status_json")"
kernel_count="$(jq -r '.kernel_count // 0' <<< "$status_json")"
dkms_count="$(jq -r '.dkms_count // 0' <<< "$status_json")"

notice=""
if (( kernel_count > 0 )); then
    notice+="\nKernel update detected — reboot after installing"
fi
if (( dkms_count > 0 )); then
    notice+="\nDKMS/kernel module changes detected — rebuild after reboot"
fi

case "$status" in
    available)
        class="available"
        (( kernel_count > 0 )) && class+=" kernel"
        (( dkms_count > 0 )) && class+=" dkms"
        jq -cn --arg text "󱍷 $count" --arg tooltip "$count package updates available\nClick: review packages$notice" --arg class "$class" \
            '{text:$text,class:$class,tooltip:$tooltip}'
        ;;
    running)
        class="running"
        (( kernel_count > 0 )) && class+=" kernel"
        (( dkms_count > 0 )) && class+=" dkms"
        jq -cn --arg text "󰔟 $count" --arg tooltip "Updating $count packages in the background\nClick: inspect update status$notice" --arg class "$class" \
            '{text:$text,class:$class,tooltip:$tooltip}'
        ;;
    failed)
        jq -cn --arg error "$error" \
            '{text:"󰅖",class:"failed",tooltip:("Last full pacman update failed\n" + $error + "\nClick: inspect the failure")}'
        ;;
    idle)
        jq -cn '{text:"",class:"idle",tooltip:"System is up to date"}'
        ;;
    *)
        jq -cn --arg error "$error" \
            '{text:"󰅖",class:"error",tooltip:("Could not check for updates\n" + $error + "\nClick: inspect package updater")}'
        ;;
esac
