# SOP — Patch management procedure (staged rollout)

> Lab/practice SOP for a fictitious Ubuntu 22.04 LTS fleet managed via
> `apt` (a RHEL/`yum`/`dnf` equivalent note is included per step where
> the process differs meaningfully). Not a real employer's procedure.
> Complements
> `tickets/linux/TICKET-009-failed-unattended-upgrade-broken-apt.md`,
> which documents a failure mode this staged process is designed to
> catch before it reaches production.

## Scope

A repeatable, staged patch rollout process across a server fleet —
balancing timely security patching against the risk of a bad update
taking down production before it's been proven safe on a smaller
population first.

## Fleet staging groups

| Group | Purpose | Typical timing |
|---|---|---|
| `patch-canary` | 1-2 low-risk, non-critical hosts (e.g. a dev/test box) | Patch first, same day as release |
| `patch-wave1` | A representative slice of each service tier (one of each redundant pair, never both) | 2-3 days after canary, if clean |
| `patch-wave2` | Remainder of the fleet | 2-3 days after wave 1, if clean |

Never patch both members of a redundant/HA pair in the same wave — the
entire point of staging is to keep a fallback available if a patch
causes a problem.

## Procedure

### 1. Review what's pending before patching anything

```bash
apt list --upgradable 2>/dev/null
```

For a security-focused patch cycle specifically (vs. a full upgrade),
identify security-flagged updates:

```bash
apt list --upgradable 2>/dev/null | grep -i security
```

*(RHEL/`dnf` equivalent: `dnf updateinfo list security` for
security-classified advisories specifically.)*

Note any kernel updates — these require a reboot to take effect and
should be flagged distinctly in the rollout communication, since a
reboot has different blast-radius considerations than an in-place
package update.

### 2. Patch the canary group

```bash
sudo apt update
sudo apt upgrade -y
```

Reboot if a kernel update was included:

```bash
sudo needrestart -r a   # confirms which services need restarting after lib updates
sudo reboot   # only if kernel/core library updates require it
```

### 3. Validate the canary host

Don't just confirm the host came back up — confirm the actual services
on it are healthy:

```bash
sudo systemctl --failed
```

Check application-specific health (an HTTP health endpoint, a database
connection check, etc., depending on the host's role) and review
`/var/log/syslog` / `journalctl -p err -b` for anything new since the
patch that wasn't there before.

Let the canary run for at least 24 hours before proceeding — some issues
(memory leak from a changed library, a slow-building resource issue)
don't show up in the first few minutes.

### 4. Patch wave 1, staggered within the wave

Never patch all of wave 1 simultaneously if it includes both members of
any redundant pair. Patch one member, validate, then the other — a
simple loop through a host list works for a small fleet, or use an
orchestration tool (Ansible, etc.) with a `serial` batch size for a
larger one, ensuring hosts in the same redundancy group are never in the
same batch.

Example inventory-driven approach (conceptual, tool-agnostic):

```bash
for host in $(cat wave1-hosts.txt); do
    ssh "$host" "sudo apt update && sudo apt upgrade -y"
    # validate before moving to the next host in the same redundancy group
done
```

### 5. Validate wave 1, same checks as canary

Repeat the health checks from step 3 against each wave 1 host. Watch
monitoring/alerting dashboards for the wave 1 population specifically for
at least a few hours before proceeding to wave 2.

### 6. Patch wave 2 (remainder of fleet)

Same staggered-within-redundancy-group approach as wave 1, scaled to the
full remaining population.

### 7. Final fleet-wide verification

Run the fleet's patch-audit script
(`scripts/bash/patch-update-audit-report.sh`) across all hosts to confirm
everything landed and nothing is stuck in a partial/failed state:

```bash
./patch-update-audit-report.sh --hosts-file all-hosts.txt
```

Any host reporting a failed or held-back state should be investigated
individually — see TICKET-009 for a worked example of exactly this
failure mode.

## Rollback

Package-level rollback with `apt` is limited compared to some other
package managers — plan for it in advance rather than during an
incident:

- For a specific problem package, downgrade to a known-good version if
  it's still available in the local apt cache or a package archive:
  ```bash
  sudo apt install <package>=<known-good-version>
  ```
- For anything patched via a VM/container-based fleet, a full rollback
  to a pre-patch snapshot is often faster and more reliable than
  attempting a granular package downgrade — factor snapshot timing into
  the patch window if this is the fleet's rollback strategy.
- Kernel updates: GRUB retains prior kernel entries by default; a
  problematic new kernel can usually be avoided by booting the previous
  kernel version from the GRUB menu while the update is investigated.

## Communication

- Notify affected teams before each wave, not just once at the start of
  the whole rollout — wave 2 users shouldn't be surprised by a maintenance
  window they didn't know was still in progress.
- Document canary/wave 1 findings before proceeding to the next stage,
  even when the result is "nothing found" — the record of having checked
  matters for audit purposes as much as the result itself.

## Verification checklist

- [ ] Pending updates reviewed and security-flagged updates identified
- [ ] Canary patched and validated for 24+ hours before wave 1
- [ ] No two members of a redundant pair patched in the same batch
- [ ] Each wave validated (service health + logs) before the next begins
- [ ] Fleet-wide patch-audit run clean at the end
- [ ] Rollback plan confirmed available before starting (snapshot taken /
      known-good package versions confirmed available)
