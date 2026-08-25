#!/usr/bin/env bash
#
# disk-quota-per-user-report.sh — Reports per-user disk usage under a
# given directory (e.g. /home) and flags users over a size threshold.
# Falls back to `du`-based estimation if the filesystem doesn't have the
# `quota` tool/kernel support configured, since not every lab/small-fleet
# host has filesystem quotas actually enabled.
#
# Lab/practice script for a small internal server fleet. Read-only —
# reports only, takes no remediation action (there is nothing destructive
# to gate behind an --apply flag here, since this script never deletes or
# modifies user files).
#
# Usage:
#   ./disk-quota-per-user-report.sh <directory> [--threshold-gb <N>]
#
# Examples:
#   ./disk-quota-per-user-report.sh /home
#   ./disk-quota-per-user-report.sh /home --threshold-gb 20
#
# Exit codes:
#   0 no user over threshold, 1 usage error, 2 directory not found,
#   3 one or more users over threshold

set -euo pipefail

TARGET_DIR=""
THRESHOLD_GB=10

usage() {
    echo "Usage: $0 <directory> [--threshold-gb <N>]" >&2
    exit 1
}

if [[ $# -lt 1 ]]; then
    usage
fi

TARGET_DIR="$1"
shift

while [[ $# -gt 0 ]]; do
    case "$1" in
        --threshold-gb)
            THRESHOLD_GB="$2"
            shift 2
            ;;
        *)
            echo "Unknown argument: $1" >&2
            usage
            ;;
    esac
done

if [[ ! -d "$TARGET_DIR" ]]; then
    echo "ERROR: directory not found: $TARGET_DIR" >&2
    exit 2
fi

THRESHOLD_KB=$((THRESHOLD_GB * 1024 * 1024))
OVER_THRESHOLD=0

echo "Disk usage report for $TARGET_DIR (threshold: ${THRESHOLD_GB}GB)"
echo ""

if command -v quota &>/dev/null && command -v repquota &>/dev/null; then
    FS_DEVICE=$(df --output=source "$TARGET_DIR" | tail -1)
    if repquota "$FS_DEVICE" &>/dev/null; then
        echo "== Using kernel filesystem quotas (repquota) =="
        printf '%-15s %-12s %-12s %-10s\n' "USER" "USED" "SOFT LIMIT" "OVER"
        repquota -u "$FS_DEVICE" | tail -n +6 | while read -r line; do
            [[ -z "$line" ]] && continue
            username=$(echo "$line" | awk '{print $1}')
            used_blocks=$(echo "$line" | awk '{print $3}')
            soft_limit=$(echo "$line" | awk '{print $4}')
            printf '%-15s %-12s %-12s\n' "$username" "${used_blocks}K" "${soft_limit}K"
        done
        echo ""
        echo "(Quota-based report shown above. Falling through to du-based estimate below for a directory-scoped cross-check.)"
        echo ""
    fi
fi

echo "== du-based per-user usage under $TARGET_DIR =="
printf '%-20s %-12s %s\n' "USER/DIR" "SIZE" "NOTE"
printf '%-20s %-12s %s\n' "--------" "----" "----"

for user_dir in "$TARGET_DIR"/*/; do
    [[ -d "$user_dir" ]] || continue
    dir_name=$(basename "$user_dir")

    size_kb=$(du -sk "$user_dir" 2>/dev/null | awk '{print $1}' || echo "0")
    size_human=$(du -sh "$user_dir" 2>/dev/null | awk '{print $1}' || echo "?")

    note=""
    if [[ "$size_kb" -gt "$THRESHOLD_KB" ]]; then
        note="OVER ${THRESHOLD_GB}GB THRESHOLD"
        OVER_THRESHOLD=$((OVER_THRESHOLD + 1))
    fi

    printf '%-20s %-12s %s\n' "$dir_name" "$size_human" "$note"
done

echo ""
if [[ "$OVER_THRESHOLD" -eq 0 ]]; then
    echo "No user directories over the ${THRESHOLD_GB}GB threshold."
    exit 0
else
    echo "$OVER_THRESHOLD user directory(ies) over the ${THRESHOLD_GB}GB threshold — review above."
    exit 3
fi
