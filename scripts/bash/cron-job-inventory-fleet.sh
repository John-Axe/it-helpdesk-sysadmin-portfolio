#!/usr/bin/env bash
#
# cron-job-inventory-fleet.sh — Inventories crontabs (system + all users)
# across a list of hosts via SSH, and optionally verifies that a specific
# expected job is present on every host.
#
# Lab/practice script for a small internal server fleet (no central config
# management inventory in this lab). Read-only over SSH by default; never
# modifies remote crontabs — the --verify-job option only compares
# against expected state and reports mismatches.
#
# Usage:
#   ./cron-job-inventory-fleet.sh --hosts-file <file> [--verify-job "<pattern>"] [--user <username>]
#
# Examples:
#   ./cron-job-inventory-fleet.sh --hosts-file fleet-hosts.txt
#   ./cron-job-inventory-fleet.sh --hosts-file fleet-hosts.txt --verify-job "session-cleanup" --user app
#
# fleet-hosts.txt format: one hostname per line, SSH key-based auth assumed
# (see runbooks/linux/ssh-hardening-checklist.md — password auth is
# disabled fleet-wide in this lab, so this script relies on key auth only).
#
# Exit codes:
#   0 all hosts checked (and, if --verify-job used, all have it),
#   1 usage error, 2 hosts file not found, 3 one or more hosts unreachable
#   or missing the verified job

set -euo pipefail

HOSTS_FILE=""
VERIFY_JOB=""
TARGET_USER=""

usage() {
    echo "Usage: $0 --hosts-file <file> [--verify-job \"<pattern>\"] [--user <username>]" >&2
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --hosts-file)
            HOSTS_FILE="$2"
            shift 2
            ;;
        --verify-job)
            VERIFY_JOB="$2"
            shift 2
            ;;
        --user)
            TARGET_USER="$2"
            shift 2
            ;;
        *)
            echo "Unknown argument: $1" >&2
            usage
            ;;
    esac
done

if [[ -z "$HOSTS_FILE" ]]; then
    usage
fi

if [[ ! -f "$HOSTS_FILE" ]]; then
    echo "ERROR: hosts file not found: $HOSTS_FILE" >&2
    exit 2
fi

UNREACHABLE=0
MISSING_JOB=0
TOTAL=0

while IFS= read -r host; do
    [[ -z "$host" || "$host" =~ ^# ]] && continue
    TOTAL=$((TOTAL + 1))

    echo "== $host =="

    if ! ssh -o ConnectTimeout=5 -o BatchMode=yes "$host" "true" 2>/dev/null; then
        echo "  UNREACHABLE (SSH connection failed)"
        UNREACHABLE=$((UNREACHABLE + 1))
        echo ""
        continue
    fi

    if [[ -n "$TARGET_USER" ]]; then
        crontab_output=$(ssh "$host" "sudo crontab -u '$TARGET_USER' -l 2>/dev/null" || echo "")
        echo "  crontab for user '$TARGET_USER':"
    else
        crontab_output=$(ssh "$host" "sudo crontab -l 2>/dev/null" || echo "")
        echo "  crontab for current SSH user:"
    fi

    if [[ -z "$crontab_output" ]]; then
        echo "    (empty or no crontab)"
    else
        echo "$crontab_output" | sed 's/^/    /'
    fi

    system_cron_count=$(ssh "$host" "ls /etc/cron.d/ 2>/dev/null | wc -l" || echo "0")
    echo "  /etc/cron.d/ entries: $system_cron_count"

    if [[ -n "$VERIFY_JOB" ]]; then
        if echo "$crontab_output" | grep -q "$VERIFY_JOB"; then
            echo "  [OK] expected job pattern '$VERIFY_JOB' found"
        else
            echo "  [MISSING] expected job pattern '$VERIFY_JOB' NOT found"
            MISSING_JOB=$((MISSING_JOB + 1))
        fi
    fi

    echo ""
done < "$HOSTS_FILE"

echo "== Summary =="
echo "Hosts checked: $TOTAL"
echo "Unreachable:   $UNREACHABLE"
if [[ -n "$VERIFY_JOB" ]]; then
    echo "Missing '$VERIFY_JOB': $MISSING_JOB"
fi

if [[ "$UNREACHABLE" -gt 0 || "$MISSING_JOB" -gt 0 ]]; then
    exit 3
fi

exit 0
