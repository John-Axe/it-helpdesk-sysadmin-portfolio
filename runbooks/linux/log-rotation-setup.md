# SOP — Log rotation setup with logrotate

> Lab/practice SOP for Ubuntu 22.04 LTS. Not a real employer's procedure.
> Written after `tickets/linux/TICKET-001-var-log-filling-disk.md`, where a
> misconfigured logrotate glob let a single log file grow to 26GB.

## Scope

Set up a new logrotate configuration for an application log, verify it
works with a dry run, and avoid the specific pitfalls that caused a real
disk-full incident.

## Prerequisites

`logrotate` is installed by default on Ubuntu, driven by
`logrotate.timer` (systemd) rather than the older cron-based trigger on
recent releases:

```bash
systemctl status logrotate.timer
```

Should show `active (waiting)`. It fires `logrotate.service` daily.

## Steps

### 1. Identify the log file(s) to manage

```bash
ls -lh /var/log/myapp/
```

Confirm the exact, literal path and filename pattern — this is where
TICKET-001's bug originated (a typo'd glob that never matched the actual
file). Don't guess; check.

### 2. Decide the rotation strategy: `copytruncate` vs. `create` + signal

This is the most consequential decision in the config:

- **`create`** (default): logrotate renames the old log
  (`app.log` → `app.log.1`), creates a fresh empty `app.log`, and expects
  the application to either re-open the file on the next write or receive
  a signal (`postrotate` script, commonly `SIGHUP` or `SIGUSR1`) telling
  it to reopen its file handle. This is the cleaner option **if the app
  supports it** — no risk of losing a few log lines in a race.
- **`copytruncate`**: logrotate copies the current log content out, then
  truncates the original file in place, so the application's existing
  open file handle keeps working with no restart/signal needed. Safer for
  apps that don't support a reload signal, but there's a small window
  where log lines written between the copy and the truncate can be lost.

Check whether the app supports a reload signal (read its docs/logging
library config) before choosing. If unsure or if the app has no
documented reload behavior, default to `copytruncate` — it's the safer
choice for an unknown/legacy app, which was the right call for the
service in TICKET-001.

### 3. Write the config

`/etc/logrotate.d/myapp`:

```
/var/log/myapp/*.log {
    daily
    rotate 14
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
    size 100M
}
```

Notes on each directive:
- `daily` — check/rotate once a day (logrotate itself still only actually
  runs when its timer fires, this just sets the rotation interval logic)
- `rotate 14` — keep 14 rotated copies before deleting the oldest
- `compress` + `delaycompress` — gzip old logs, but skip compressing the
  most recent rotation (`.1`) so a script or human can still grep it
  immediately without decompressing
- `missingok` — don't error if the log doesn't exist yet (e.g. app hasn't
  started)
- `notifempty` — don't rotate an empty file, avoids empty log churn
- `size 100M` — also rotate early if the file hits 100MB before the daily
  check, regardless of schedule — a safety net against runaway logging
  between scheduled rotations

### 4. Verify the glob actually matches before trusting it

```bash
ls -l /var/log/myapp/*.log
```

Confirm the pattern in the config matches real files on disk, character
for character. This single check would have caught TICKET-001 before it
became an incident.

### 5. Dry-run test

```bash
sudo logrotate -d /etc/logrotate.d/myapp
```

`-d` (debug) shows exactly what logrotate *would* do without actually
touching any files — confirms the glob matches, shows whether it thinks
rotation is due, and prints any config syntax errors.

### 6. Force a real rotation to confirm end-to-end

```bash
sudo logrotate -f /etc/logrotate.d/myapp
ls -lh /var/log/myapp/
```

Confirm a `.1.gz` (or `.1` if `delaycompress`) file appeared and the
active log file is fresh/small, and — critically — confirm the
application is **still writing to the log** after rotation (tail it,
generate a log line via the app if possible). This catches a
`copytruncate` app that actually did need a reload signal after all.

### 7. Confirm the systemd timer will pick it up going forward

```bash
systemctl list-timers logrotate.timer
```

Shows the next scheduled run. No further action needed — `logrotate.timer`
already scans all of `/etc/logrotate.d/` on every run.

## Verification checklist

- [ ] Glob pattern confirmed against real filenames with `ls`
- [ ] `logrotate -d` dry run shows no errors and matches expected files
- [ ] Rotation strategy (`copytruncate` vs `create`+signal) matches what
      the application actually supports
- [ ] Forced real rotation confirms the app keeps writing post-rotation
- [ ] `size` safety-net threshold set so a runaway log can't fill the disk
      before the next scheduled rotation
