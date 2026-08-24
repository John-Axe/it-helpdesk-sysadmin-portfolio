#!/usr/bin/env bash
#
# user-offboarding.sh — Locks out and cleans up a departing user's access
# on a single Linux host, per runbooks/linux/user-provisioning-and-offboarding.md
#
# Lab/practice script for a fictitious small server fleet (no central IdM).
# Not tied to any real employer's systems.
#
# SAFE BY DEFAULT: runs in --dry-run mode unless --apply is passed
# explicitly. Dry run prints every action it WOULD take without touching
# the system.
#
# Usage:
#   ./user-offboarding.sh <username> [--dry-run|--apply] [--remove-home]
#
# Examples:
#   ./user-offboarding.sh jsmith                # dry run (default)
#   ./user-offboarding.sh jsmith --apply         # actually lock/offboard
#   ./user-offboarding.sh jsmith --apply --remove-home   # also delete home dir
#
# Exit codes:
#   0 success, 1 usage error, 2 user not found, 3 one or more steps failed

set -euo pipefail

DRY_RUN=1
REMOVE_HOME=0
TARGET_USER=""

usage() {
    echo "Usage: $0 <username> [--dry-run|--apply] [--remove-home]" >&2
    exit 1
}

if [[ $# -lt 1 ]]; then
    usage
fi

TARGET_USER="$1"
shift

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)
            DRY_RUN=1
            ;;
        --apply)
            DRY_RUN=0
            ;;
        --remove-home)
            REMOVE_HOME=1
            ;;
        *)
            echo "Unknown argument: $1" >&2
            usage
            ;;
    esac
    shift
done

if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "[DRY RUN] No changes will be made. Pass --apply to actually offboard the account."
fi

if ! id "$TARGET_USER" &>/dev/null; then
    echo "ERROR: user '$TARGET_USER' does not exist on this host." >&2
    exit 2
fi

run() {
    # Wrapper: prints the command always; only executes it if not a dry run.
    if [[ "$DRY_RUN" -eq 1 ]]; then
        echo "  [would run] $*"
    else
        echo "  [running]   $*"
        eval "$@" || { echo "  FAILED: $*" >&2; FAILURES=$((FAILURES + 1)); }
    fi
}

FAILURES=0

echo "== Offboarding user: $TARGET_USER =="

echo "-- Step 1: lock password and disable shell --"
run "sudo usermod -L '$TARGET_USER'"
run "sudo usermod -s /usr/sbin/nologin '$TARGET_USER'"

echo "-- Step 2: disable SSH key auth --"
SSH_DIR="/home/$TARGET_USER/.ssh"
AUTH_KEYS="$SSH_DIR/authorized_keys"
if [[ -f "$AUTH_KEYS" ]]; then
    TIMESTAMP=$(date +%F)
    run "sudo mv '$AUTH_KEYS' '${AUTH_KEYS}.disabled-${TIMESTAMP}'"
else
    echo "  (no authorized_keys file found at $AUTH_KEYS — skipping)"
fi

echo "-- Step 3: terminate active sessions --"
if who | grep -qw "$TARGET_USER"; then
    run "sudo pkill -KILL -u '$TARGET_USER'"
else
    echo "  (no active sessions found for $TARGET_USER)"
fi

echo "-- Step 4: report cron/at jobs for manual review (not auto-removed) --"
if sudo crontab -u "$TARGET_USER" -l &>/dev/null; then
    echo "  WARNING: $TARGET_USER has a crontab. Review before removing:"
    sudo crontab -u "$TARGET_USER" -l | sed 's/^/    /'
    echo "  Not removed automatically — migrate any needed jobs first, then run:"
    echo "    sudo crontab -u $TARGET_USER -r"
else
    echo "  (no crontab found for $TARGET_USER)"
fi

echo "-- Step 5: remove from sudo/admin group --"
if id -nG "$TARGET_USER" | grep -qw sudo; then
    run "sudo deluser '$TARGET_USER' sudo"
else
    echo "  ($TARGET_USER is not in the sudo group)"
fi

if [[ "$REMOVE_HOME" -eq 1 ]]; then
    echo "-- Step 6: remove account and home directory --"
    echo "  NOTE: this is destructive and irreversible. Confirm home directory"
    echo "  contents have been archived/handed off if needed before proceeding."
    run "sudo deluser --remove-home '$TARGET_USER'"
else
    echo "-- Step 6: skipped (pass --remove-home to delete the account and home dir) --"
fi

echo ""
if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "Dry run complete. Re-run with --apply to make these changes."
    exit 0
fi

if [[ "$FAILURES" -gt 0 ]]; then
    echo "Completed with $FAILURES failed step(s) — review output above." >&2
    exit 3
fi

echo "Offboarding steps completed for $TARGET_USER."
exit 0
