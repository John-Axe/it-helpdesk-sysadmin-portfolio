# TICKET-008 — Application unreachable after routine firewalld reload

> Lab scenario. Environment: fictitious Ubuntu 22.04 LTS server `app03`
> running `firewalld` (used instead of raw `iptables`/`ufw` on this host
> for zone-based rule management). Not a real employer/customer ticket.

## Summary

| Field | Value |
|---|---|
| Priority | P1 — Critical (internal app fully unreachable) |
| Category | Networking / Firewall |
| Reported by | Application team, monitoring alert |
| Affected system | `app03`, internal API on TCP/8443 |

## Symptom

An internal API on `app03` became completely unreachable from other
hosts on the network immediately after a scheduled maintenance window
that included a `firewalld` configuration change (adding a rule for an
unrelated new service). The application process itself was confirmed
still running and healthy on the host.

## Triage steps

1. Confirmed the app was actually up and listening locally before
   suspecting the network layer at all:

   ```
   sudo ss -ltnp | grep 8443
   ```

   ```
   LISTEN  0  128  0.0.0.0:8443  0.0.0.0:*  users:(("app-api",pid=2214,fd=9))
   ```

   Process was listening on the correct port — ruled out an app-level
   crash or misconfiguration.
2. Tested reachability locally vs. remotely to isolate where the block
   was happening:

   ```
   curl -sk https://localhost:8443/health        # from app03 itself — worked
   curl -sk https://app03.contoso.local:8443/health   # from another host — timed out
   ```

   Worked locally, timed out remotely — classic host-firewall symptom
   rather than an app or DNS issue.
3. Checked the currently active firewalld rules for the zone the primary
   interface is in:

   ```
   sudo firewall-cmd --get-active-zones
   sudo firewall-cmd --zone=internal --list-all
   ```

   The `internal` zone's port list did **not** include `8443/tcp` —
   confirmed the port wasn't open in the currently active configuration.
4. This was surprising since the port had been open for months.
   Checked whether the maintenance window's change had been applied as
   `--permanent` correctly:

   ```
   sudo firewall-cmd --permanent --zone=internal --list-ports
   ```

   The **permanent** configuration *did* show `8443/tcp` — meaning the
   rule existed in the saved config but wasn't active in the running
   configuration, which pointed at the standard `firewalld` "runtime vs.
   permanent" trap.
5. Confirmed the theory: the maintenance change had added the *new*
   service's port with `--permanent` correctly, but the person doing the
   change had run `firewall-cmd --reload` — which is supposed to load the
   permanent config into the runtime config — yet the pre-existing
   `8443/tcp` rule still didn't show as active. Dug further and found the
   actual issue: the maintenance script had applied the new rule with
   `firewall-cmd --zone=internal --add-port=...` **without** `--permanent`
   first (to test it live), then run `--runtime-to-permanent` to persist
   it — which is correct — but a **subsequent** unrelated
   `firewall-cmd --complete-reload` later in the same script (intended to
   clear a stale connection tracking entry) fully re-reads zone files
   from disk. That step should have preserved `8443/tcp` too, since it
   was already in the permanent config... except a diff against the
   config's backup revealed `8443/tcp` had been **removed** from
   `/etc/firewalld/zones/internal.xml` months earlier during an
   unrelated cleanup pass, and had only kept working since because the
   in-memory **runtime** config still had it from before that cleanup —
   surviving purely because the service hadn't been reloaded or rebooted
   since. This maintenance window's `--complete-reload` was the first
   full reload since that earlier drift was introduced, which is what
   finally exposed it.

## Root cause

The permanent firewalld configuration for `internal.xml` had drifted from
the running configuration months earlier (an untracked manual edit during
unrelated cleanup removed the `8443/tcp` port from the permanent zone
file without also removing it from the live runtime config, so nothing
broke at the time). The discrepancy stayed invisible until this
maintenance window's `--complete-reload` re-read the zone files from
disk and applied the stale, incomplete permanent configuration — which
no longer included the port the application actually needed.

## Resolution

1. Re-added the port to the permanent configuration and reloaded:

   ```
   sudo firewall-cmd --permanent --zone=internal --add-port=8443/tcp
   sudo firewall-cmd --reload
   ```

2. Verified both runtime and permanent configs now agreed:

   ```
   sudo firewall-cmd --zone=internal --list-ports
   sudo firewall-cmd --permanent --zone=internal --list-ports
   ```

   Both showed `8443/tcp`.
3. Re-tested from a remote host — API reachable again.

## Follow-up / prevention

- Added a periodic drift check comparing `firewall-cmd --list-ports`
  (runtime) against `firewall-cmd --permanent --list-ports` for every
  managed zone across the fleet, alerting on any mismatch — this exact
  class of silent drift is otherwise undetectable until a full reload
  finally surfaces it, which could just as easily happen during an
  unplanned reboot instead of a controlled maintenance window.
- Standardized the team's process so firewalld changes always go through
  version-controlled zone XML files applied via config management,
  rather than ad hoc `firewall-cmd` commands run by hand against
  individual hosts — the drift here traced back to exactly that kind of
  untracked manual edit.
- Documented the runtime-vs-permanent distinction explicitly in
  `runbooks/linux/firewall-rule-change-procedure.md`, including the
  "always verify both after every change" step this incident would have
  been caught by.
