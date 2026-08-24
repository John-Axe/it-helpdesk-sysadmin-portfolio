# SOP — Cron troubleshooting procedure

> Lab/practice SOP for Ubuntu 22.04 LTS. Not a real employer's procedure.
> Generalized from `tickets/linux/TICKET-003-cron-job-silently-not-running.md`,
> where a job kept "running" from cron's perspective while silently failing
> every night.

## Scope

A structured way to diagnose "a cron job isn't doing what it's supposed to"
— covering both "it never fires" and the more insidious "it fires but
fails silently," which is the more common real-world case.

## Step 1 — Confirm the crontab entry actually exists where you think it does

Cron jobs can live in several places; check all of them for the relevant
user/system:

```bash
crontab -u <user> -l              # user's personal crontab
sudo cat /etc/crontab             # system-wide crontab
ls /etc/cron.d/                   # drop-in system cron files
ls /etc/cron.{daily,hourly,weekly,monthly}/   # run-parts directories
systemctl list-timers --all       # systemd timers (increasingly used instead of cron)
```

Confirm the schedule syntax is what you think it is — a misplaced field is
a classic error. Use `crontab -l | crontab -` round-trip or a syntax
checker if unsure, or just reason through each field carefully:
`minute hour day-of-month month day-of-week`.

## Step 2 — Confirm cron is actually invoking it

```bash
grep CRON /var/log/syslog | grep <username-or-job-identifier> | tail -20
```

If entries appear here at the expected times, **cron itself is working
correctly** — the problem is inside the job, not with cron/scheduling.
This distinction matters: don't spend time debugging cron's scheduler if
it's already firing the job reliably.

If no entries appear at all, check:

```bash
systemctl status cron
```

And confirm the user running the job isn't blocked via
`/etc/cron.allow` / `/etc/cron.deny` if those files exist on the system.

## Step 3 — Check whether the job's own logging shows success or failure

If the crontab entry redirects output somewhere
(`>> /var/log/myjob.log 2>&1` — always do this for any cron job, a bare
crontab entry with no redirect silently discards output except for
cron's own default behavior of emailing the job owner, which often isn't
configured to go anywhere useful):

```bash
tail -50 /var/log/myjob.log
```

Look for the actual exit status or error message from the last several
runs, not just whether the file was touched.

## Step 4 — Reproduce manually as the exact same user, with the exact same environment

This step catches the most common class of "works when I run it, fails
under cron" bugs: **cron runs jobs with a minimal environment**, not your
interactive shell's environment (no `PATH` additions from `.bashrc`, no
inherited env vars, different working directory).

```bash
sudo -u <user> -i /path/to/script.sh
```

If that succeeds but the cron-triggered version fails, compare
environments explicitly:

```bash
# What cron actually sees — add this as a temporary crontab entry, or
# check /etc/environment and any env vars the crontab explicitly sets
env > /tmp/cron-env.txt  # from *inside* a cron-triggered run
env > /tmp/shell-env.txt # from an interactive shell as the same user
diff /tmp/cron-env.txt /tmp/shell-env.txt
```

Common differences that break scripts: `PATH` missing directories a script
relies on being implicitly available, missing `HOME`, and relative paths
in the script that assume a working directory cron doesn't set.

## Step 5 — Check for credential/permission drift since it last worked

If the job has run successfully for a long time and suddenly stopped, ask:
**what changed recently?** In practice this is very often:

- A credential rotation that didn't update a config file the job reads
  from (`.pgpass`, `.my.cnf`, an API token file) — see TICKET-003.
- A permissions change on a file/directory the job needs (intentional or
  accidental, e.g. from a broader config-management run).
- A dependency upgrade that changed CLI flags/output format the script
  parses.

```bash
# For credential files specifically, confirm both existence and permissions
ls -la ~/.pgpass ~/.my.cnf 2>/dev/null
```

## Step 6 — Fix, then verify with a manual trigger, not just waiting for the next scheduled run

```bash
sudo -u <user> /path/to/script.sh
echo $?   # confirm exit code 0
```

Don't close the ticket on "I fixed the config, should be fine now" without
actually re-running it once — several of the real incidents this
procedure is based on had a fix that *looked* right but had a second,
compounding issue that only manual re-execution surfaced.

## Step 7 — Add a failure-visible safety net going forward

Cron's default behavior (emailing the job owner on any output, if a local
MTA is even configured — often it isn't) is not a reliable alerting
mechanism. For anything business-critical:

- Have the script explicitly check its own critical outputs (e.g. "did the
  expected output file actually get created today?") and exit non-zero /
  alert if not — don't rely solely on the job's own internal exit code,
  since a job can exit 0 while still not producing the expected result.
- Consider a separate, independent freshness-check job (see
  TICKET-003's follow-up) that verifies expected output *exists* by a
  deadline, decoupled from whether the producing job reported success.

## Quick reference: where a cron job's expected behavior can silently diverge from actual

| Symptom | Likely cause |
|---|---|
| Job never appears in syslog | Cron service down, or entry doesn't exist where expected |
| Appears in syslog, but does nothing visible | Output not redirected anywhere useful; check job's own log if any |
| Fails only under cron, works manually | Environment/PATH difference between interactive shell and cron |
| Was working, now silently fails | Credential rotation or permission change since last success |
| Runs but produces stale/wrong output | Working directory assumption broken, or a dependency changed behavior |
