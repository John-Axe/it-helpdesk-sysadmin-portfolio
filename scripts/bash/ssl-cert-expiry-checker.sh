#!/usr/bin/env bash
#
# ssl-cert-expiry-checker.sh — Checks TLS certificate expiry for a list of
# host:port endpoints and flags any expiring within a warning window.
#
# Lab/practice script for a small internal service fleet, checking
# certificates for internal endpoints (e.g. web02.contoso.local:443,
# a reverse-proxied internal API, etc.) — not tied to any real domain.
#
# Read-only — this script only queries certificate expiry, it never
# renews or replaces a certificate. There is no --apply flag because
# there's nothing destructive or state-changing to gate here.
#
# Usage:
#   ./ssl-cert-expiry-checker.sh --endpoints-file <file> [--warn-days <N>]
#
# endpoints-file format: one "host:port" per line, e.g.:
#   web02.contoso.local:443
#   files01.contoso.local:8443
#
# Examples:
#   ./ssl-cert-expiry-checker.sh --endpoints-file endpoints.txt
#   ./ssl-cert-expiry-checker.sh --endpoints-file endpoints.txt --warn-days 21
#
# Exit codes:
#   0 all certs healthy, 1 usage error, 2 endpoints file not found,
#   3 one or more certs expiring soon or already expired/unreachable

set -euo pipefail

ENDPOINTS_FILE=""
WARN_DAYS=30

usage() {
    echo "Usage: $0 --endpoints-file <file> [--warn-days <N>]" >&2
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --endpoints-file)
            ENDPOINTS_FILE="$2"
            shift 2
            ;;
        --warn-days)
            WARN_DAYS="$2"
            shift 2
            ;;
        *)
            echo "Unknown argument: $1" >&2
            usage
            ;;
    esac
done

if [[ -z "$ENDPOINTS_FILE" ]]; then
    usage
fi

if [[ ! -f "$ENDPOINTS_FILE" ]]; then
    echo "ERROR: endpoints file not found: $ENDPOINTS_FILE" >&2
    exit 2
fi

if ! command -v openssl &>/dev/null; then
    echo "ERROR: openssl is required but not found on PATH." >&2
    exit 2
fi

WARNING_COUNT=0
NOW_EPOCH=$(date +%s)

printf '%-40s %-12s %-8s %s\n' "ENDPOINT" "EXPIRES" "DAYS" "STATUS"
printf '%-40s %-12s %-8s %s\n' "--------" "-------" "----" "------"

while IFS= read -r endpoint; do
    [[ -z "$endpoint" || "$endpoint" =~ ^# ]] && continue

    host="${endpoint%%:*}"
    port="${endpoint##*:}"

    cert_end_date=$(echo | timeout 10 openssl s_client -connect "${host}:${port}" -servername "$host" 2>/dev/null | \
        openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2 || true)

    if [[ -z "$cert_end_date" ]]; then
        printf '%-40s %-12s %-8s %s\n' "$endpoint" "N/A" "N/A" "UNREACHABLE / NO CERT RETRIEVED"
        WARNING_COUNT=$((WARNING_COUNT + 1))
        continue
    fi

    expiry_epoch=$(date -d "$cert_end_date" +%s 2>/dev/null || echo "0")
    if [[ "$expiry_epoch" -eq 0 ]]; then
        printf '%-40s %-12s %-8s %s\n' "$endpoint" "$cert_end_date" "N/A" "COULD NOT PARSE EXPIRY DATE"
        WARNING_COUNT=$((WARNING_COUNT + 1))
        continue
    fi

    days_remaining=$(( (expiry_epoch - NOW_EPOCH) / 86400 ))
    expiry_display=$(date -d "$cert_end_date" +%Y-%m-%d 2>/dev/null || echo "$cert_end_date")

    status="OK"
    if [[ "$days_remaining" -lt 0 ]]; then
        status="EXPIRED"
        WARNING_COUNT=$((WARNING_COUNT + 1))
    elif [[ "$days_remaining" -le "$WARN_DAYS" ]]; then
        status="EXPIRING SOON"
        WARNING_COUNT=$((WARNING_COUNT + 1))
    fi

    printf '%-40s %-12s %-8s %s\n' "$endpoint" "$expiry_display" "$days_remaining" "$status"

done < "$ENDPOINTS_FILE"

echo ""
if [[ "$WARNING_COUNT" -eq 0 ]]; then
    echo "All certificates healthy (more than ${WARN_DAYS} days remaining)."
    exit 0
else
    echo "$WARNING_COUNT endpoint(s) expired, expiring within ${WARN_DAYS} days, or unreachable — review above."
    exit 3
fi
