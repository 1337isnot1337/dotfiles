#!/usr/bin/env bash

set -u

# Eww owns the Wayland layer surface.  Ask it to exit cleanly first, then
# escalate so an unresponsive daemon cannot leave a stale click-catching
# surface behind.
pgrep -x eww >/dev/null 2>&1 || exit 0
pkill -TERM -x eww >/dev/null 2>&1 || true

for attempt in {1..10}; do
    pgrep -x eww >/dev/null 2>&1 || exit 0
    sleep 0.1
done

pkill -KILL -x eww >/dev/null 2>&1 || true
for attempt in {1..10}; do
    pgrep -x eww >/dev/null 2>&1 || exit 0
    sleep 0.1
done

exit 1
