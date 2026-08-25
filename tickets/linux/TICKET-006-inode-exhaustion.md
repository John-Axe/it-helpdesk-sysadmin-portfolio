# TICKET-006 — Disk shows free space but writes fail with "No space left on device"

> Lab scenario. Environment: fictitious Ubuntu 22.04 LTS server `web02` in
> a small internal lab network. Not a real employer/customer ticket.

## Summary

| Field | Value |
|---|---|
| Priority | P1 — Critical (application fully down) |
| Category | Filesystem / Storage |
| Reported by | Monitoring alert + application team |
| Affected system | `web02`, application log/session directory `/var/app/sessions` |

## Symptom

The application on `web02` started throwing
`OSError: [Errno 28] No space left on device` on every request that
tried to write a session file, and new log entries stopped appearing.
Confusingly, `df -h` showed the filesystem at only 61% used — plenty of
free space by capacity, which didn't match the error at all.

## Triage steps

1. First reaction was to check disk usage the normal way:

   ```
   df -h /var
   ```

   ```
   Filesystem      Size  Used Avail Use% Mounted on
   /dev/sda1        50G   30G   18G  61% /
   ```

   Genuinely plenty of free space — ruled out the obvious "disk full"
   explanation (the scenario covered in TICKET-001) and pointed toward
   something else entirely.
2. Recalled that ext4 (and most Linux filesystems) allocate a fixed
   number of inodes at format time, separate from block/space capacity —
   a filesystem can be 100% out of inodes while having gigabytes of free
   space, if it's storing an enormous number of very small files. Checked:

   ```
   df -ih /var
   ```

   ```
   Filesystem      Inodes IUsed IFree IUse% Mounted on
   /dev/sda1         3.2M  3.2M     8  100% /
   ```

   `IUse%` at 100% with only 8 free inodes — confirmed inode exhaustion,
   not space exhaustion, as the actual root cause.
3. Needed to find which directory held the largest number of small files.
   A recursive `find | wc -l` across the whole filesystem would have
   taken a long time, so narrowed the search using `du --inodes` (a
   GNU-coreutils feature that reports inode count instead of size) on
   likely candidate directories first:

   ```
   sudo du --inodes -x -d 2 /var | sort -rn | head -20
   ```

   `/var/app/sessions` stood out with well over 3 million entries.
4. Sampled the directory to see what was actually in there:

   ```
   ls /var/app/sessions | head
   ls /var/app/sessions | wc -l
   ```

   Millions of tiny `sess_*` files, most with old timestamps — a
   session-cleanup cron job that was supposed to prune expired session
   files had silently stopped running weeks earlier (checked
   `/var/log/syslog` for the cron entry, confirmed no invocation since a
   deploy that changed the cron user's crontab without anyone noticing —
   the exact failure mode covered generally in
   `tickets/linux/TICKET-003-cron-job-silently-not-running.md`, here
   manifesting as inode exhaustion instead of a missed business task).

## Root cause

A session-cleanup cron job had stopped running (crontab entry was lost
during an unrelated deploy that reset the app service account's crontab).
Session files accumulated unchecked for weeks, eventually exhausting the
filesystem's fixed inode allocation even though block-level disk space
remained plentiful — ext4's inode count is fixed at `mkfs` time and
can't be increased without reformatting, so the only way out under
pressure was reducing the file count, not freeing space.

## Resolution

1. Confirmed it was safe to delete session files older than the app's
   session TTL (24 hours) by checking the app's session-expiry config
   with the application team first, then removed the backlog in batches
   (a single `rm *` across millions of files in one directory can itself
   fail with "argument list too long," so used `find` piped to a
   controlled delete instead):

   ```
   sudo find /var/app/sessions -maxdepth 1 -type f -mtime +1 -print0 | \
       xargs -0 -n 1000 rm --
   ```

   Ran incrementally, checking `df -ih` between batches to confirm inode
   count was actually recovering, before removing the entire backlog.
2. Restored the missing cron entry for the session-cleanup job (recreated
   from the runbook/deploy template, since the original had been lost):

   ```
   */15 * * * * find /var/app/sessions -maxdepth 1 -type f -mmin +1440 -delete
   ```

3. Verified `df -ih /var` returned to a healthy `IUse%` and the
   application resumed writing sessions successfully.

## Follow-up / prevention

- Added an inode-usage check (`df -ih` threshold, not just `df -h`) to
  the standard disk-monitoring alert set — the existing monitoring only
  watched block usage and completely missed this failure mode until the
  application itself started erroring.
- Recommended the application write sessions to a store better suited to
  large numbers of small, short-lived objects (Redis) rather than the
  filesystem, as a longer-term fix that removes this failure class
  entirely rather than just monitoring around it.
- Documented in the deploy runbook that service-account crontabs must be
  managed via the config-management tool's cron resource, not edited
  ad hoc, so a deploy can't silently wipe an existing entry again.
