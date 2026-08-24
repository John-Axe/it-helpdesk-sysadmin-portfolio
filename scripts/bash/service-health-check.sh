#!/usr/bin/env bash
#
# service-health-check.sh — Checks the status of one or more systemd
# services and, optionally, attempts a restart if a service is found down.
#
# Lab/practice script for a small internal server fleet. Read-only by
# default; restart action requires --apply (in addition to --restart-failed)
# as a deliberate two-flag guard against accidental service restarts.
#
# Usage:
#   ./service-health-check.sh <service1> [service2 ...] [--restart-failed] [--apply]
#
# Examples:
#   ./service-health-check.sh nginx postgresql
#   ./service-health-check.sh nginx postgresql --restart-failed --apply
#
# Exit codes:
#   0 all healthy, 1 usage error, 2 one or more services unhealthy (after
#   any restart attempts, if requested)

set -euo pipefail

RESTART_FAILED=0
APPLY=0
SERVICES=()

usage() {
    echo "Usage: $0 <service1> [service2 ...] [--restart-failed] [--apply]" >&2
    exit 1
}

if [[ $# -lt 1 ]]; then
    usage
fi

for arg in "$@"; do
    case "$arg" in
        --restart-failed)
            RESTART_FAILED=1
            ;;
        --apply)
            APPLY=1
            ;;
        --*)
            echo "Unknown option: $arg" >&2
            usage
            ;;
        *)
            SERVICES+=("$arg")
            ;;
    esac
done

if [[ "${#SERVICES[@]}" -eq 0 ]]; then
    echo "No service names provided." >&2
    usage
fi

if [[ "$RESTART_FAILED" -eq 1 && "$APPLY" -eq 0 ]]; then
    echo "[NOTE] --restart-failed was passed without --apply — will report only, no restarts will be attempted."
fi

UNHEALTHY_COUNT=0

printf '%-25s %-12s %-10s %s\n' "SERVICE" "ACTIVE" "ENABLED" "NOTES"
printf '%-25s %-12s %-10s %s\n' "-------" "------" "-------" "-----"

for service in "${SERVICES[@]}"; do
    unit="${service}.service"

    if ! systemctl list-unit-files "$unit" &>/dev/null; then
        printf '%-25s %-12s %-10s %s\n' "$service" "UNKNOWN" "UNKNOWN" "unit not found"
        UNHEALTHY_COUNT=$((UNHEALTHY_COUNT + 1))
        continue
    fi

    active_state=$(systemctl is-active "$unit" 2>/dev/null || true)
    enabled_state=$(systemctl is-enabled "$unit" 2>/dev/null || true)

    notes=""
    if [[ "$active_state" != "active" ]]; then
        notes="DOWN"
        UNHEALTHY_COUNT=$((UNHEALTHY_COUNT + 1))

        if [[ "$RESTART_FAILED" -eq 1 ]]; then
            if [[ "$APPLY" -eq 1 ]]; then
                echo ""
                echo "  Attempting restart of $unit..."
                if systemctl restart "$unit"; then
                    sleep 2
                    recheck=$(systemctl is-active "$unit" 2>/dev/null || true)
                    if [[ "$recheck" == "active" ]]; then
                        notes="RESTARTED-OK"
                        UNHEALTHY_COUNT=$((UNHEALTHY_COUNT - 1))
                    else
                        notes="RESTART-FAILED (still $recheck)"
                    fi
                else
                    notes="RESTART-COMMAND-FAILED"
                fi
            else
                notes="DOWN (would restart with --apply)"
            fi
        fi
    fi

    printf '%-25s %-12s %-10s %s\n' "$service" "$active_state" "$enabled_state" "$notes"
done

echo ""
if [[ "$UNHEALTHY_COUNT" -eq 0 ]]; then
    echo "All ${#SERVICES[@]} service(s) healthy."
    exit 0
else
    echo "$UNHEALTHY_COUNT of ${#SERVICES[@]} service(s) unhealthy."
    exit 2
fi
