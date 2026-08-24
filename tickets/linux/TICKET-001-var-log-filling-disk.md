# TICKET-001 — `/var/log` filling disk, service outages

> Lab scenario. Environment: fictitious Ubuntu 22.04 LTS server `app01`
> in a small internal lab network. Not a real employer/customer ticket.

## Summary

| Field | Value |
|---|---|
| Priority | P1 — Critical (application down) |
| Category | Disk / Logging |
| Reported by | Monitoring alert (disk usage > 95%) |
| Affected system | `app01`, root filesystem `/` |

## Symptom

Monitoring paged for `app01` at 95% disk usage on `/`. Shortly after, the
application on that host started throwing `OSError: [Errno 28] No space
left on device` when writing temp files, and stopped accepting new
requests.

## Triage steps

1. Confirmed disk usage:

   ```
   df -h /
   ```

   `/` was at 98% used, ~2GB free on a 40GB root volume.
2. Found the biggest consumer:

   ```
   du -xh /var/log 2>/dev/null | sort -rh | head -20
   ```

   `/var/log/app/app.log` was 26GB. A single file, not rotated.
3. Checked why it wasn't rotating:

   ```
   cat /etc/logrotate.d/app
   ```

   The logrotate config existed but referenced the wrong path
   (`/var/log/app/*.log.1` glob with a typo — extra `.1` — meaning it never
   matched the actual active log file). It had silently done nothing since
   the app was deployed.
4. Checked whether logrotate itself was even running:

   ```
   systemctl status logrotate.timer
   grep app /var/lib/logrotate/status
   ```

   `logrotate.timer` was active and running daily via cron/systemd timer as
   expected — the problem was purely the broken glob in the app's config
   file, not the logrotate service itself.
5. Confirmed the app was configured to log at `DEBUG` level in production
   by mistake, which was why the file grew so fast (a few weeks) rather
   than over months.

## Root cause

Two compounding issues: (1) a typo in the `logrotate.d` config
(`app.log.1` instead of `app.log`) meant the file was never rotated or
truncated, and (2) the application was misconfigured to log at `DEBUG`
level in production, generating far more log volume than expected.

## Resolution

1. Freed immediate space by truncating the log in place (does not break the
   file handle the app already has open, unlike deleting it):

   ```
   truncate -s 0 /var/log/app/app.log
   ```

   Confirmed with `df -h /` that usage dropped back to 34%.
2. Fixed the logrotate config glob:

   ```
   /var/log/app/*.log {
       daily
       rotate 14
       compress
       delaycompress
       missingok
       notifempty
       copytruncate
   }
   ```

   Used `copytruncate` specifically because the app doesn't support
   re-opening its log file on `SIGHUP`, so a normal rotate-and-signal
   approach would leave it writing to a now-renamed, orphaned file handle.
3. Tested the fix without waiting for the next scheduled run:

   ```
   logrotate -f /etc/logrotate.d/app
   ```
4. Changed the app's log level from `DEBUG` to `INFO` in its config and
   restarted the service.

## Follow-up / prevention

- Added a disk-usage alert threshold at 80% (was previously only alerting
  at 95%, leaving very little lead time to react).
- Wrote `scripts/bash/log-cleanup-rotation-helper.sh` as a standalone
  safety-net script that can be run manually or via cron to catch
  oversized/unrotated logs even if a given service's logrotate config has
  a bug, rather than relying on a single point of failure.
- Added `logrotate -d` (dry-run/debug mode) to the pre-deployment checklist
  for any new logrotate config, to catch glob typos like this before they
  ship.
