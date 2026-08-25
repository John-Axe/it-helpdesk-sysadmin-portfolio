#!/usr/bin/env bash
#
# firewall-rule-audit.sh — Audits host firewall configuration
# (ufw or firewalld, auto-detected) for two things:
#   1. Any rule permitting an overly broad source (0.0.0.0/0 / "anywhere")
#      on a port other than a documented allowlist.
#   2. For firewalld hosts specifically: drift between the runtime and
#      permanent configuration (see tickets/linux/TICKET-008 for why this
#      matters — a mismatch here can silently revert on next reload/reboot).
#
# Lab/practice script for a small internal server fleet. Read-only by
# default; the --fix-drift option (firewalld only, requires --apply) only
# ever reloads the permanent config into runtime — it never removes or
# adds a rule on its own.
#
# Usage:
#   ./firewall-rule-audit.sh [--allow-port <port>[,<port>...]] [--fix-drift] [--apply]
#
# Examples:
#   ./firewall-rule-audit.sh
#   ./firewall-rule-audit.sh --allow-port 22,443,8443
#   ./firewall-rule-audit.sh --fix-drift --apply
#
# Exit codes:
#   0 no findings, 1 usage error, 2 tool not found, 3 findings reported

set -euo pipefail

ALLOWED_PORTS=""
FIX_DRIFT=0
APPLY=0

usage() {
    echo "Usage: $0 [--allow-port <port>[,<port>...]] [--fix-drift] [--apply]" >&2
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --allow-port)
            ALLOWED_PORTS="$2"
            shift 2
            ;;
        --fix-drift)
            FIX_DRIFT=1
            shift
            ;;
        --apply)
            APPLY=1
            shift
            ;;
        *)
            echo "Unknown argument: $1" >&2
            usage
            ;;
    esac
done

FINDINGS=0

is_allowed_port() {
    local port="$1"
    [[ -z "$ALLOWED_PORTS" ]] && return 1
    IFS=',' read -ra allowed <<< "$ALLOWED_PORTS"
    for p in "${allowed[@]}"; do
        [[ "$p" == "$port" ]] && return 0
    done
    return 1
}

if command -v firewall-cmd &>/dev/null && systemctl is-active --quiet firewalld 2>/dev/null; then
    echo "== Detected firewalld =="

    for zone in $(firewall-cmd --get-active-zones | grep -v '^\s' | tr -d ':'); do
        echo ""
        echo "-- Zone: $zone --"

        runtime_ports=$(firewall-cmd --zone="$zone" --list-ports 2>/dev/null || true)
        permanent_ports=$(firewall-cmd --permanent --zone="$zone" --list-ports 2>/dev/null || true)

        if [[ "$runtime_ports" != "$permanent_ports" ]]; then
            echo "  [DRIFT] runtime ports differ from permanent config:"
            echo "    runtime:   ${runtime_ports:-<none>}"
            echo "    permanent: ${permanent_ports:-<none>}"
            FINDINGS=$((FINDINGS + 1))

            if [[ "$FIX_DRIFT" -eq 1 ]]; then
                if [[ "$APPLY" -eq 1 ]]; then
                    echo "  [FIX] reloading permanent config into runtime for zone $zone..."
                    firewall-cmd --reload
                else
                    echo "  [NOTE] --fix-drift passed without --apply — would run 'firewall-cmd --reload'"
                fi
            fi
        else
            echo "  runtime and permanent config match (${runtime_ports:-no open ports})."
        fi

        for port_proto in $runtime_ports; do
            port="${port_proto%%/*}"
            if ! is_allowed_port "$port" && [[ -n "$ALLOWED_PORTS" ]]; then
                echo "  [REVIEW] port $port_proto open in zone $zone, not on the allowlist"
                FINDINGS=$((FINDINGS + 1))
            fi
        done
    done

elif command -v ufw &>/dev/null && ufw status | grep -q "Status: active"; then
    echo "== Detected ufw =="
    echo ""

    while IFS= read -r line; do
        [[ "$line" =~ ^To|^--|^$ ]] && continue

        if echo "$line" | grep -qE "ALLOW.*Anywhere"; then
            port=$(echo "$line" | awk '{print $1}' | cut -d'/' -f1)
            echo "$line"
            if ! is_allowed_port "$port" && [[ -n "$ALLOWED_PORTS" ]]; then
                echo "  [REVIEW] port $port open to Anywhere, not on the allowlist"
                FINDINGS=$((FINDINGS + 1))
            fi
        fi
    done < <(ufw status | tail -n +4)

else
    echo "No active firewalld or ufw installation detected on this host." >&2
    exit 2
fi

echo ""
if [[ "$FINDINGS" -eq 0 ]]; then
    echo "No findings."
    exit 0
else
    echo "$FINDINGS finding(s) reported above — review before considering this host's firewall state clean."
    exit 3
fi
