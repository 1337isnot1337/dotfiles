#!/usr/bin/env bash

set -u

readonly SHIELD_ICON="󰒘"
readonly SNAPSHOT_FILE="/etc/top_attackers"
readonly SOURCE_FILE="/var/log/psad/top_attackers"
readonly MAX_ROWS=10

format_timestamp() {
    local epoch="$1"

    if [[ "$epoch" =~ ^[0-9]+$ ]] && (( epoch > 0 )); then
        date -d "@$epoch" '+%Y-%m-%d %H:%M:%S %Z' 2>/dev/null || printf 'unknown'
    else
        printf 'unknown'
    fi
}

format_age() {
    local seconds="$1"

    (( seconds < 0 )) && seconds=0

    if (( seconds < 60 )); then
        printf '%ss ago' "$seconds"
    elif (( seconds < 3600 )); then
        printf '%sm ago' "$((seconds / 60))"
    elif (( seconds < 86400 )); then
        printf '%sh ago' "$((seconds / 3600))"
    else
        printf '%sd ago' "$((seconds / 86400))"
    fi
}

service_state="$(timeout 2s systemctl is-active psad 2>/dev/null || true)"
enabled_state="$(timeout 2s systemctl is-enabled psad 2>/dev/null || true)"
now_epoch="$(date +%s)"
snapshot_epoch="$(stat -c %Y "$SNAPSHOT_FILE" 2>/dev/null || printf '0')"
source_epoch="$(stat -c %Y "$SOURCE_FILE" 2>/dev/null || printf '0')"

record_count="$(awk '$1 !~ /^#/ && NF >= 6 { count++ } END { print count + 0 }' \
    "$SNAPSHOT_FILE" 2>/dev/null || printf '0')"
[[ "$record_count" =~ ^[0-9]+$ ]] || record_count=0

record_details="$(awk -v max="$MAX_ROWS" '
function comma(value, text, grouped) {
    text = sprintf("%.0f", value)
    grouped = ""
    while (length(text) > 3) {
        grouped = "," substr(text, length(text) - 2) grouped
        text = substr(text, 1, length(text) - 3)
    }
    return text grouped
}

$1 !~ /^#/ && NF >= 6 {
    count++
    if (count <= max) {
        printf "  %d. %s\n     Danger level: %s | Packets: %s | Unique signatures: %s | Signature matches: %s | Local: %s\n", \
            count, $1, $2, comma($3), comma($4), comma($5), ($6 == 1 ? "yes" : "no")
    }
}

END {
    if (count == 0) {
        print "  None recorded."
    } else if (count > max) {
        printf "  ... plus %d more source(s).\n", count - max
    }
}' "$SNAPSHOT_FILE" 2>/dev/null || printf '  Unable to read the saved table.\n')"

status_label="UNKNOWN"
status_detail="The PSAD service status could not be determined."
status_class="psad-unknown"

case "$service_state" in
    active)
        status_label="RUNNING"
        status_detail="PSAD is running and watching firewall logs; no current attacker records are present."
        status_class="psad-no-alerts"
        ;;
    activating|reloading)
        status_label="STARTING"
        status_detail="PSAD is starting up."
        status_class="psad-unknown"
        ;;
    inactive|deactivating)
        status_label="STOPPED"
        status_detail="PSAD is not monitoring right now."
        status_class="psad-inactive"
        ;;
    failed)
        status_label="FAILED"
        status_detail="PSAD failed; there is no live scan detection."
        status_class="psad-error"
        ;;
esac

if [[ "$enabled_state" == "enabled" ]]; then
    startup_label="enabled"
elif [[ "$enabled_state" == "disabled" ]]; then
    startup_label="disabled"
else
    startup_label="${enabled_state:-unknown}"
fi

data_age_line="Data age: unknown"
data_is_fresh=0
if [[ "$source_epoch" =~ ^[0-9]+$ ]] && (( source_epoch > 0 )); then
    data_age_seconds=$((now_epoch - source_epoch))
    data_age_line="Last data write: $(format_timestamp "$source_epoch") ($(format_age "$data_age_seconds"))"
    (( data_age_seconds <= 300 )) && data_is_fresh=1
elif [[ "$snapshot_epoch" =~ ^[0-9]+$ ]] && (( snapshot_epoch > 0 )); then
    snapshot_age_seconds=$((now_epoch - snapshot_epoch))
    data_age_line="Saved snapshot time: $(format_timestamp "$snapshot_epoch") ($(format_age "$snapshot_age_seconds"))"
fi

if [[ "$service_state" == "active" ]]; then
    if (( record_count > 0 && data_is_fresh == 1 )); then
        status_class="psad-alert"
        status_label="ALERTS"
        status_detail="PSAD is running and has recently recorded source activity."
    elif (( record_count > 0 )); then
        status_class="psad-stale"
        status_label="STALE DATA"
        status_detail="PSAD is running, but the saved attacker table is old."
    else
        status_class="psad-no-alerts"
        status_label="NO ALERTS"
    fi
elif (( record_count > 0 )); then
    status_class="psad-stale"
fi

if (( record_count == 0 )); then
    records_line="Saved source records: none"
else
    records_line="Saved source records: $record_count"
fi

if [[ "$service_state" == "active" ]]; then
    freshness_note="The table is eligible to represent live activity."
else
    freshness_note="The service is stopped; listed sources are historical, not live alerts."
fi

tooltip="$({
    printf 'PSAD — port-scan detector\n'
    printf 'Status: %s\n' "$status_label"
    printf '%s\n' "$status_detail"
    printf 'Start at boot: %s\n' "$startup_label"
    printf '%s\n' "$freshness_note"
    printf '%s\n' "$data_age_line"
    printf '\n%s\n' "$records_line"
    printf 'Tracked sources (saved PSAD table):\n%s\n' "$record_details"
    printf '\nFields: danger level · packets · unique signatures · signature matches · local source\n'
})"

jq -cn \
    --arg text "$SHIELD_ICON" \
    --arg tooltip "$tooltip" \
    --arg class "$status_class" \
    --arg alt "$status_label" \
    '{text: $text, tooltip: $tooltip, class: $class, alt: $alt}'
