# TICKET-009 — apt broken after unattended-upgrades left a package half-configured

> Lab scenario. Environment: fictitious Ubuntu 22.04 LTS server `web02`
> with `unattended-upgrades` enabled for automatic security patching.
> Not a real employer/customer ticket.

## Summary

| Field | Value |
|---|---|
| Priority | P2 — High (host can't receive any package updates) |
| Category | Package Management / Patch Automation |
| Reported by | Monitoring alert (patch-audit script flagged the host) |
| Affected system | `web02`, `apt`/`dpkg` package state |

## Symptom

The scheduled patch-audit report (see
`scripts/bash/patch-update-audit-report.sh`) flagged `web02` as failing
its check entirely rather than reporting a pending-update count. Manually
running `sudo apt update && sudo apt upgrade` on the host failed with:

```
E: Sub-process /usr/bin/dpkg returned an error code (1)
dpkg: error processing package libssl3:amd64 (--configure):
 package is in a very bad inconsistent state; you should
 reinstall it before attempting configuration
```

## Triage steps

1. Checked `dpkg`'s own package state list to see how many packages were
   actually affected, not just the one named in the error:

   ```
   dpkg -l | grep -E "^.[^i]" | head -20
   ```

   Found `libssl3:amd64` in state `iF` (installed, but failed
   configuration) — a single package stuck mid-upgrade, which was
   blocking `apt`/`dpkg` from proceeding with anything else since other
   packages depend on it.
2. Checked `/var/log/unattended-upgrades/unattended-upgrades.log` to
   understand when and how this happened, since no one had manually
   touched `apt` recently:

   ```
   2026-08-09 03:14:02,441 INFO Packages that will be upgraded: ... libssl3 ...
   2026-08-09 03:17:41,009 ERROR Package installation failed:
     dpkg: dependency problems prevent configuration of libssl3:amd64
   ```

   The scheduled 3 AM unattended-upgrade run had hit a dependency
   conflict mid-transaction (a held-back package elsewhere on the system
   from an earlier manual `apt-mark hold`, unrelated to this incident,
   had pinned a library version incompatible with the new `libssl3`
   build) and the transaction failed midway, leaving `libssl3` partially
   configured instead of cleanly rolled back.
3. Checked for the specific held package causing the conflict:

   ```
   apt-mark showhold
   ```

   Returned `libcurl4:amd64` — held months earlier for an application
   compatibility reason that was no longer documented anywhere and, on
   checking with the app team, no longer necessary.
4. Confirmed the scope was contained to this one host by checking two
   other hosts in the same patch group — both had applied the same
   update cleanly, since neither had the same stale package hold in
   place.

## Root cause

An unrelated, undocumented `apt-mark hold` on `libcurl4` (set months
earlier for a compatibility reason no longer applicable) pinned a library
version that conflicted with the `libssl3` security update
`unattended-upgrades` tried to apply automatically. The automated upgrade
transaction failed partway through, leaving `libssl3` in a partially
configured (`iF`) state that blocked all subsequent `apt`/`dpkg`
operations on the host until manually repaired.

## Resolution

1. Removed the stale hold that caused the original conflict, after
   confirming with the application team it was no longer needed:

   ```
   sudo apt-mark unhold libcurl4
   ```

2. Forced `dpkg` to finish configuring the half-installed package:

   ```
   sudo dpkg --configure -a
   ```

3. Re-ran a full upgrade to let apt resolve the rest of the dependency
   graph cleanly:

   ```
   sudo apt update
   sudo apt upgrade -y
   ```

4. Verified clean package state and confirmed no more `iF`/half-installed
   entries:

   ```
   dpkg -l | grep -E "^.[^i]"
   ```

   Returned nothing — clean.
5. Re-ran the patch-audit script manually to confirm the host now
   reported normally instead of failing the check.

## Follow-up / prevention

- Audited the rest of the fleet for other undocumented `apt-mark hold`
  entries using the fleet-wide inventory approach in
  `scripts/bash/cron-job-inventory-fleet.sh`'s pattern (adapted to check
  package holds instead of cron jobs) — found one more stale hold on a
  different host and removed it during a planned maintenance window
  instead of waiting for it to cause the same failure.
- Recommended any `apt-mark hold` be logged in the change-management
  system with a reason and a review date, so holds don't silently outlive
  the reason they were created for.
- Confirmed `unattended-upgrades` is configured to email a report on
  failure (`Unattended-Upgrade::Mail` in
  `/etc/apt/apt.conf.d/50unattended-upgrades`) — it was already set, but
  the mail alias it sent to had gone stale after a team reorg; corrected
  the alias so future automated-upgrade failures reach someone who will
  actually see them, instead of only being caught by the weekly
  patch-audit report as happened here.
