#!/usr/bin/env bash
#
# log-cleanup-rotation-helper.sh — Safety-net script that finds oversized
# or stale log files and rotates/compresses them, independent of whatever
# per-application logrotate config may or may not be working correctly.
#
# Written after a real-world-style incident (see
# tickets/linux/TICKET-001-var-log-filling-disk.md) where a broken
# logrotate glob let a single log grow to 26GB before anyone noticed.
# This script is meant as a defense-in-depth backstop, not a replacement
# for fixing the underlying logrotate config.
#
# SAFE BY DEFAULT: runs in --dry-run mode unless --apply is passed.
#
# Usage:
#   ./log-cleanup-rotation-helper.sh [--dir DIR] [--max-size-mb N] [--dry-run|--apply]
#
# Examples:
#   ./log-cleanup-rotation-helper.sh --dir /var/log/myapp --max-size-mb 100
#   ./log-cleanup-rotation-helper.sh --dir /var/log/myapp --max-size-mb 100 --apply

set -euo pipefail

LOG_DIR="/var/log"
MAX_SIZE_MB=200
DRY_RUN=1
RETAIN_COMPRESSED=14

usage() {
    cat <<EOF
Usage: $0 [options]

Options:
  --dir DIR             Directory to scan for oversized logs (default: $LOG_DIR)
  --max-size-mb N        Size threshold in MB to trigger rotation (default: $MAX_SIZE_MB)
  --retain N             Number of compressed rotations to keep per file (default: $RETAIN_COMPRESSED)
  --dry-run               Report only, no changes (default)
  --apply                 Actually rotate/compress/delete
EOF
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dir)
            LOG_DIR="$2"
            shift 2
            ;;
        --max-size-mb)
            MAX_SIZE_MB="$2"
            shift 2
            ;;
        --retain)
            RETAIN_COMPRESSED="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        --apply)
            DRY_RUN=0
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Unknown argument: $1" >&2
            usage
            ;;
    esac
done

if [[ ! -d "$LOG_DIR" ]]; then
    echo "ERROR: directory '$LOG_DIR' does not exist." >&2
    exit 2
fi

if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "[DRY RUN] No files will be modified. Pass --apply to actually rotate/compress."
fi

MAX_SIZE_BYTES=$((MAX_SIZE_MB * 1024 * 1024))
PROCESSED=0
SKIPPED=0

echo "Scanning '$LOG_DIR' for *.log files >= ${MAX_SIZE_MB}MB..."

# find + a null-delimited loop to safely handle filenames with spaces
while IFS= read -r -d '' logfile; do
    size_bytes=$(stat -c '%s' "$logfile")
    size_mb=$((size_bytes / 1024 / 1024))

    if [[ "$size_bytes" -lt "$MAX_SIZE_BYTES" ]]; then
        continue
    fi

    echo ""
    echo "Found oversized log: $logfile (${size_mb}MB)"

    timestamp=$(date +%Y%m%d-%H%M%S)
    rotated_name="${logfile}.${timestamp}"

    if [[ "$DRY_RUN" -eq 1 ]]; then
        echo "  [would run] cp '$logfile' '$rotated_name'"
        echo "  [would run] truncate -s 0 '$logfile'   # copytruncate-style, safe for apps holding an open fd"
        echo "  [would run] gzip '$rotated_name'"
        PROCESSED=$((PROCESSED + 1))
    else
        echo "  Rotating..."
        cp "$logfile" "$rotated_name"
        # copytruncate approach: truncate in place rather than deleting/
        # renaming the original, so a process with the file already open
        # keeps writing to a valid file handle instead of an orphaned one.
        truncate -s 0 "$logfile"
        gzip "$rotated_name"
        echo "  Rotated to ${rotated_name}.gz, original truncated in place."
        PROCESSED=$((PROCESSED + 1))
    fi

    # Cleanup: remove old compressed rotations beyond the retention count
    mapfile -t old_rotations < <(ls -1t "${logfile}".*.gz 2>/dev/null | tail -n +$((RETAIN_COMPRESSED + 1)))
    if [[ "${#old_rotations[@]}" -gt 0 ]]; then
        echo "  ${#old_rotations[@]} rotation(s) beyond retain count of $RETAIN_COMPRESSED:"
        for old_file in "${old_rotations[@]}"; do
            if [[ "$DRY_RUN" -eq 1 ]]; then
                echo "    [would delete] $old_file"
            else
                rm -f -- "$old_file"
                echo "    deleted: $old_file"
            fi
        done
    fi

done < <(find "$LOG_DIR" -type f -name '*.log' -print0)

echo ""
if [[ "$PROCESSED" -eq 0 ]]; then
    echo "No log files at or above ${MAX_SIZE_MB}MB found under $LOG_DIR."
else
    echo "Processed $PROCESSED oversized log file(s)."
fi

if [[ "$DRY_RUN" -eq 1 && "$PROCESSED" -gt 0 ]]; then
    echo "This was a dry run. Re-run with --apply to actually rotate these files."
fi
