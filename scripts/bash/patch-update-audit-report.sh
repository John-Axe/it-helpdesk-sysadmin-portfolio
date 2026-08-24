#!/usr/bin/env bash
#
# patch-update-audit-report.sh — Reports available/pending OS package
# updates on a Debian/Ubuntu (apt) host, flags security updates
# specifically, and reports how long it's been since the last successful
# `apt update` metadata refresh and the last full upgrade.
#
# Read-only reporting script. Does NOT install any updates itself — by
# design, patch application should go through a change-managed process,
# not an unattended script run ad hoc. See --apply-security-only below
# for the one narrow exception, which still defaults to dry-run.
#
# Usage:
#   ./patch-update-audit-report.sh [--apply-security-only]
#
# Examples:
#   ./patch-update-audit-report.sh
#       Report-only: lists pending updates, flags security updates,
#       reports staleness of apt metadata.
#
#   ./patch-update-audit-report.sh --apply-security-only
#       Still dry-run by default. Combine with --apply to actually
#       install ONLY security-flagged updates (never a full dist-upgrade).
#
#   ./patch-update-audit-report.sh --apply-security-only --apply
#       Actually installs security updates only.

set -euo pipefail

APPLY_SECURITY_ONLY=0
APPLY=0

for arg in "$@"; do
    case "$arg" in
        --apply-security-only)
            APPLY_SECURITY_ONLY=1
            ;;
        --apply)
            APPLY=1
            ;;
        -h|--help)
            echo "Usage: $0 [--apply-security-only] [--apply]" >&2
            exit 1
            ;;
        *)
            echo "Unknown argument: $arg" >&2
            exit 1
            ;;
    esac
done

if ! command -v apt-get &>/dev/null; then
    echo "ERROR: this script targets Debian/Ubuntu (apt-get not found)." >&2
    exit 2
fi

echo "== Patch/Update Audit Report — $(hostname) — $(date -Is) =="
echo ""

echo "-- apt metadata freshness --"
APT_LISTS_DIR="/var/lib/apt/lists"
if [[ -d "$APT_LISTS_DIR" ]]; then
    newest_list=$(find "$APT_LISTS_DIR" -maxdepth 1 -type f -printf '%T@\n' 2>/dev/null | sort -rn | head -1 || true)
    if [[ -n "$newest_list" ]]; then
        now=$(date +%s)
        age_seconds=$(( now - ${newest_list%.*} ))
        age_hours=$(( age_seconds / 3600 ))
        echo "  Package metadata last refreshed approximately ${age_hours}h ago."
        if [[ "$age_hours" -gt 48 ]]; then
            echo "  WARNING: metadata is stale (>48h). Run 'sudo apt-get update' before trusting this report."
        fi
    else
        echo "  Could not determine metadata age (no list files found)."
    fi
fi
echo ""

echo "-- Pending upgrades --"
# --dry-run + a fixed-format simulation is the standard safe way to list
# what would be upgraded without actually changing anything.
mapfile -t pending < <(apt list --upgradable 2>/dev/null | tail -n +2)

if [[ "${#pending[@]}" -eq 0 ]]; then
    echo "  No pending package upgrades."
else
    echo "  ${#pending[@]} package(s) with available upgrades:"
    printf '    %s\n' "${pending[@]}"
fi
echo ""

echo "-- Security updates specifically --"
if command -v unattended-upgrade &>/dev/null || dpkg -l unattended-upgrades &>/dev/null 2>&1; then
    mapfile -t security_pending < <(apt-get --just-print upgrade 2>/dev/null | grep -i security || true)
    if [[ "${#security_pending[@]}" -eq 0 ]]; then
        echo "  No security-flagged updates pending (or unattended-upgrades reporting unavailable)."
    else
        echo "  Security-related pending updates detected:"
        printf '    %s\n' "${security_pending[@]}"
    fi
else
    echo "  'unattended-upgrades' package not installed — cannot reliably distinguish"
    echo "  security updates from general updates on this host. Consider installing it:"
    echo "    sudo apt-get install unattended-upgrades"
fi
echo ""

echo "-- Reboot required? --"
if [[ -f /var/run/reboot-required ]]; then
    echo "  YES — /var/run/reboot-required exists."
    if [[ -f /var/run/reboot-required.pkgs ]]; then
        echo "  Packages requiring reboot:"
        sed 's/^/    /' /var/run/reboot-required.pkgs
    fi
else
    echo "  No reboot currently flagged as required."
fi
echo ""

if [[ "$APPLY_SECURITY_ONLY" -eq 1 ]]; then
    echo "-- Security-only update application --"
    if [[ "$APPLY" -eq 1 ]]; then
        echo "  Applying security updates only (this may take a few minutes)..."
        sudo apt-get update -qq
        sudo apt-get -s dist-upgrade | grep -i security || true
        sudo unattended-upgrade -d
        echo "  Security update pass complete. Re-run this script to confirm remaining pending count."
    else
        echo "  [DRY RUN] Would run: sudo unattended-upgrade -d (security updates only)."
        echo "  Pass --apply-security-only --apply together to actually apply them."
    fi
fi

echo ""
echo "Report complete."
