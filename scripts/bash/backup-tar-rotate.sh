#!/usr/bin/env bash
#
# backup-tar-rotate.sh — Creates a compressed tar backup of a source
# directory, timestamps it, and rotates out backups older than a
# retention count. Intended for cron use on a small internal server.
#
# SAFE BY DEFAULT: --dry-run is the default; use --apply to actually write
# the archive and delete old rotations.
#
# Usage:
#   ./backup-tar-rotate.sh --source DIR --dest DIR [--retain N] [--dry-run|--apply]
#
# Examples:
#   ./backup-tar-rotate.sh --source /etc/myapp --dest /backups/myapp
#   ./backup-tar-rotate.sh --source /etc/myapp --dest /backups/myapp --retain 7 --apply
#
# Suggested crontab entry (runs nightly at 01:30, keeps 14 days):
#   30 1 * * * /opt/scripts/backup-tar-rotate.sh --source /etc/myapp \
#       --dest /backups/myapp --retain 14 --apply >> /var/log/backup-myapp.log 2>&1

set -euo pipefail

SOURCE_DIR=""
DEST_DIR=""
RETAIN=7
DRY_RUN=1
PREFIX="backup"

usage() {
    cat <<EOF
Usage: $0 --source DIR --dest DIR [--retain N] [--prefix NAME] [--dry-run|--apply]

Options:
  --source DIR    Directory to back up (required)
  --dest DIR      Directory to write the archive to (required)
  --retain N      Number of archives to keep (default: 7)
  --prefix NAME   Archive filename prefix (default: backup)
  --dry-run       Report only, no changes (default)
  --apply         Actually create the archive and prune old ones
EOF
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --source)
            SOURCE_DIR="$2"
            shift 2
            ;;
        --dest)
            DEST_DIR="$2"
            shift 2
            ;;
        --retain)
            RETAIN="$2"
            shift 2
            ;;
        --prefix)
            PREFIX="$2"
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

if [[ -z "$SOURCE_DIR" || -z "$DEST_DIR" ]]; then
    echo "ERROR: --source and --dest are both required." >&2
    usage
fi

if [[ ! -d "$SOURCE_DIR" ]]; then
    echo "ERROR: source directory '$SOURCE_DIR' does not exist." >&2
    exit 2
fi

if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "[DRY RUN] No archive will be written and no old backups will be deleted. Pass --apply to run for real."
fi

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
ARCHIVE_NAME="${PREFIX}-${TIMESTAMP}.tar.gz"
ARCHIVE_PATH="${DEST_DIR}/${ARCHIVE_NAME}"

echo "== Backup: $SOURCE_DIR -> $ARCHIVE_PATH =="

if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "  [would run] mkdir -p '$DEST_DIR'"
    echo "  [would run] tar -czf '$ARCHIVE_PATH' -C '$(dirname "$SOURCE_DIR")' '$(basename "$SOURCE_DIR")'"
else
    mkdir -p "$DEST_DIR"
    tar -czf "$ARCHIVE_PATH" -C "$(dirname "$SOURCE_DIR")" "$(basename "$SOURCE_DIR")"

    if [[ ! -s "$ARCHIVE_PATH" ]]; then
        echo "ERROR: archive was not created or is empty: $ARCHIVE_PATH" >&2
        exit 3
    fi

    # Verify the archive is readable/well-formed before trusting it as a
    # valid backup — an archive that tar wrote but can't be listed back
    # out is worse than no backup, because it gives false confidence.
    if ! tar -tzf "$ARCHIVE_PATH" &>/dev/null; then
        echo "ERROR: archive failed integrity check (tar -tzf): $ARCHIVE_PATH" >&2
        exit 3
    fi

    archive_size=$(du -h "$ARCHIVE_PATH" | cut -f1)
    echo "  Archive created and verified: $ARCHIVE_PATH ($archive_size)"
fi

echo ""
echo "-- Rotation (retain: $RETAIN) --"

mapfile -t existing_archives < <(ls -1t "${DEST_DIR}/${PREFIX}"-*.tar.gz 2>/dev/null || true)
existing_count="${#existing_archives[@]}"

if [[ "$existing_count" -le "$RETAIN" ]]; then
    echo "  $existing_count archive(s) present, at or under retention limit of $RETAIN. Nothing to prune."
else
    to_delete=("${existing_archives[@]:$RETAIN}")
    echo "  $existing_count archive(s) present, exceeds retention limit of $RETAIN."
    echo "  ${#to_delete[@]} archive(s) to remove:"
    for old_archive in "${to_delete[@]}"; do
        if [[ "$DRY_RUN" -eq 1 ]]; then
            echo "    [would delete] $old_archive"
        else
            rm -f -- "$old_archive"
            echo "    deleted: $old_archive"
        fi
    done
fi

echo ""
echo "Done."
