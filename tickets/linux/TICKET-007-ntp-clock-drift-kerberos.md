# TICKET-007 — Linux host can't authenticate against AD, clock drift + Kerberos

> Lab scenario. Environment: fictitious Ubuntu 22.04 LTS server `db01`,
> joined to `contoso.local` via SSSD for centralized AD authentication.
> Not a real employer/customer ticket.

## Summary

| Field | Value |
|---|---|
| Priority | P2 — High (admins locked out of AD-based SSH login) |
| Category | Authentication / Time Sync |
| Reported by | Sysadmin, unable to SSH in with AD credentials |
| Affected system | `db01`, SSSD + Kerberos AD integration |

## Symptom

An admin trying to SSH into `db01` using their AD domain credentials
(normal workflow — the box is joined to AD via SSSD for centralized
auth) got `Permission denied`, despite the same credentials working fine
on every other AD-joined Linux host. Logging in with a local (non-AD)
account on the same box worked without issue, isolating the problem to
the Kerberos/AD auth path specifically.

## Triage steps

1. Checked `/var/log/auth.log` for the failed attempt, which pointed
   straight at Kerberos rather than a generic SSSD/credential problem:

   ```
   sshd[...]: pam_sss(sshd:auth): received for user admin.jsmith:
   14 (User not known to the underlying authentication module)
   ```

   combined with, further up the log:

   ```
   sssd_be[...]: Failed to initialize credentials using keytab
   [MEMORY:...]: KRB5KDC_ERR_PREAUTH_FAILED
   ```

2. `KRB5KDC_ERR_PREAUTH_FAILED` alongside an otherwise-correct
   configuration is a very common symptom of **clock skew** — Kerberos
   tickets are time-bound and by default the KDC (a domain controller
   here) rejects auth requests if client/server clocks differ by more
   than 5 minutes, to limit replay-attack windows. Checked local time
   against the DC:

   ```
   timedatectl
   ```

   ```
   Local time: Mon 2026-08-24 09:47:12 UTC
                    NTP service: inactive
                 RTC in local TZ: no
   ```

   `NTP service: inactive` immediately stood out — this host wasn't
   syncing time at all.
3. Compared against the DC's time directly:

   ```
   ntpdate -q dc01.contoso.local
   ```

   ```
   server 10.10.10.10, stratum 2, offset +612.408453, delay 0.02734
   ```

   A ~612 second (over 10 minute) offset — comfortably past Kerberos's
   5-minute default tolerance, confirming clock skew as the root cause.
4. Checked why NTP was inactive when it should have been running by
   default per the base server image: `systemctl status systemd-timesyncd`
   showed the service had failed to start after the last reboot with a
   dependency-ordering error, tied back to an unrelated `systemd` unit
   change from a recent OS patch that hadn't been caught in testing.

## Root cause

`systemd-timesyncd` failed to start after a routine OS patch changed unit
dependency ordering, leaving the host's clock free-running with no NTP
correction. Over roughly three weeks, hardware clock drift accumulated to
over 10 minutes of offset from the domain controller. Kerberos, which
enforces a tight clock-skew tolerance by design (5 minutes by default) to
limit ticket replay attacks, rejected pre-authentication for any AD-based
login attempt once the drift exceeded that window — a purely time-sync
issue that presented as an authentication failure.

## Resolution

1. Manually corrected the clock immediately to unblock login:

   ```
   sudo timedatectl set-ntp true
   sudo systemctl restart systemd-timesyncd
   timedatectl timesync-status
   ```

2. Investigated and fixed the underlying unit ordering issue preventing
   `systemd-timesyncd` from starting at boot (a stale override in
   `/etc/systemd/system/systemd-timesyncd.service.d/` left over from
   earlier, unrelated troubleshooting, conflicting with the patched
   unit's new `After=` ordering) — removed the stale override:

   ```
   sudo rm /etc/systemd/system/systemd-timesyncd.service.d/override.conf
   sudo systemctl daemon-reload
   sudo systemctl enable --now systemd-timesyncd
   ```

3. Confirmed the service now started cleanly on a test reboot and time
   stayed in sync with the DC.
4. Re-tested AD SSH login — succeeded immediately once the clock was
   corrected.

## Follow-up / prevention

- Added a fleet-wide check (see
  `scripts/bash/` monitoring scripts pattern) to alert if any host's
  `systemd-timesyncd` (or `chronyd`, depending on host) is inactive, or
  if offset from the domain's NTP source exceeds 60 seconds — catching
  this well before it reaches Kerberos's 5-minute failure threshold.
- Audited other hosts for the same stale override left behind from past
  troubleshooting sessions; found and removed one more.
- Documented in the runbook that any "AD auth suddenly fails but local
  auth works" ticket should check `timedatectl` and clock offset against
  a DC as one of the first two or three checks, before assuming it's a
  credentials or SSSD configuration problem.
