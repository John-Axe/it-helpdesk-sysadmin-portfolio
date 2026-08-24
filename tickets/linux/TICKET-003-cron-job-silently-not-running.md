# TICKET-003 — Nightly cron job silently not running

> Lab scenario. Environment: fictitious Ubuntu 22.04 LTS server `db01` in a
> small internal lab network. Not a real employer/customer ticket.

## Summary

| Field | Value |
|---|---|
| Priority | P2 — High (backups missing) |
| Category | Cron / Scheduled Tasks |
| Reported by | Weekly backup audit found 6 days of missing backups |
| Affected system | `db01`, cron job under user `backupsvc` |

## Symptom

A nightly `pg_dump` backup script that had run reliably for months stopped
producing output files. No error emails, no alerts — it just silently
stopped appearing in the backup directory. Discovered during a routine
weekly audit, not proactively.

## Triage steps

1. Confirmed the crontab entry still existed:

   ```
   crontab -u backupsvc -l
   ```

   ```
   0 2 * * * /opt/scripts/nightly_backup.sh >> /var/log/backup.log 2>&1
   ```

   Entry was present and looked correct at first glance.
2. Checked whether cron itself was running the job at all:

   ```
   grep CRON /var/log/syslog | grep backupsvc | tail -20
   ```

   Cron **was** invoking the script every night at 02:00 as scheduled —
   ruled out a disabled/masked cron service.
3. Checked `/var/log/backup.log` — the redirect target. It hadn't been
   updated in 6 days despite cron firing nightly. That meant the script was
   starting but failing before it could write to its own log, or the
   redirect itself was broken.
4. Manually ran the script as the `backupsvc` user to reproduce:

   ```
   sudo -u backupsvc /opt/scripts/nightly_backup.sh
   ```

   Failed immediately: `pg_dump: error: connection to server failed:
   FATAL: password authentication failed for user "backupsvc"`.
5. Checked when the DB password had last changed — a routine credential
   rotation had happened 6 days earlier (matching exactly when backups
   stopped). The script read its DB password from a `.pgpass` file in
   `backupsvc`'s home directory, which hadn't been updated as part of the
   rotation runbook.
6. Root-caused why no error alert fired: the script's error handling only
   checked `pg_dump`'s exit code and echoed a failure line to its **own**
   log — but that log's `>>` redirect in the crontab was correct, so the
   log *did* get the error. It just wasn't monitored; nothing was tailing
   or alerting on that log file's content, only on whether the job ran at
   all.

## Root cause

The database credential rotation runbook didn't include a step to update
the `.pgpass` file used by the automated backup job, so `pg_dump` started
failing authentication silently from cron's perspective (cron only reports
whether the command *ran*, not whether it succeeded).

## Resolution

1. Updated `/home/backupsvc/.pgpass` with the new rotated password,
   confirmed `chmod 600` was still set (required — `pg_dump` silently
   ignores a `.pgpass` file with looser permissions).
2. Re-ran the script manually, confirmed a fresh dump file was produced and
   `pg_restore --list` validated it as non-corrupt.
3. Backfilled the 6 missing nights by running the script manually against
   each day (data was still recoverable via point-in-time recovery from
   WAL archives for the gap period, so no data was actually lost, only the
   convenience of daily full dumps).

## Follow-up / prevention

- Added a step to the credential-rotation checklist: enumerate every
  service account whose password changed and grep for `.pgpass`,
  `.my.cnf`, or similar credential files referencing that account before
  closing a rotation ticket.
- Changed the backup script to `exit 1` with a message piped to `mail` (or
  a webhook, in more modern setups) on failure, rather than relying solely
  on someone reading the log file. Documented the improved pattern in
  `runbooks/linux/cron-troubleshooting-procedure.md`.
- Added a simple "freshness check" — a separate daily cron job that alerts
  if the expected backup file for *today's* date doesn't exist by 03:00,
  independent of whether the backup job itself reported success.
