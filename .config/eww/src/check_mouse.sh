#!/bin/bash

dashboard_window="dashboard"

echo "Starting check_mouse.sh script..."

eww_active() {
    eww list-windows | grep -q "$dashboard_window"
}

get_window_geometry() {
    echo "Fetching window geometry..."
    window_id=$(xdotool search --name "$dashboard_window" | head -n 1)
    if [ -z "$window_id" ]; then
        echo "Window ID not found!"
        return 1
    fi
    echo "Found window ID: $window_id"
    eval $(xwininfo -id "$window_id" | awk 'BEGIN{X=Y=WIDTH=HEIGHT=0}
        /Absolute upper-left X:/ {X=$4}
        /Absolute upper-left Y:/ {Y=$4}
        /Width:/ {WIDTH=$2}
        /Height:/ {HEIGHT=$2}
        END {print "WINDOW_X=" X "\nWINDOW_Y=" Y "\nWIDTH=" WIDTH "\nHEIGHT=" HEIGHT}')
    echo "Window Geometry: X=$WINDOW_X, Y=$WINDOW_Y, WIDTH=$WIDTH, HEIGHT=$HEIGHT"
    return 0
}

while true; do
    echo "Checking if Eww window is active..."
    if ! eww_active; then
        echo "Dashboard window is not active. Sleeping..."
        sleep 1
        continue
    fi

    if ! get_window_geometry; then
        echo "Failed to get window geometry. Sleeping..."
        sleep 1
        continue
    fi

    echo "Fetching mouse location..."
    eval $(xdotool getmouselocation --shell)
    echo "Mouse Position: X=$X, Y=$Y"

    if [[ "$X" -lt "$WINDOW_X" || "$X" -gt $((WINDOW_X + WIDTH)) || "$Y" -lt "$WINDOW_Y" || "$Y" -gt $((WINDOW_Y + HEIGHT)) ]]; then
        echo "Mouse is outside the window bounds. Closing dashboard..."
        if eww_active; then
            eww close "$dashboard_window"
        fi
    else
        echo "Mouse is inside the window bounds."
    fi

    sleep 1  # Polling interval
done
