# SOP — Backup verification & restore-test procedure

> Lab/practice SOP for a fictitious small Linux server fleet using
> `scripts/bash/backup-tar-rotate.sh`-style tar-based backups to a
> dedicated backup target. Not a real employer's procedure. Windows-side
> equivalent:
> `runbooks/windows-ad-m365/file-server-backup-disaster-recovery.md`.

## Scope

A recurring procedure to confirm backups are not just running, but
actually restorable — the distinction that matters, since a backup job
reporting "success" only confirms the write completed, not that the
resulting archive is usable to recover from an actual incident.

## Why this is a separate procedure from "backup ran successfully"

A backup can report success while still being useless for recovery:
silent corruption in the archive, a permissions issue that excluded
files the job didn't error on, an incomplete database dump taken
mid-transaction without proper locking, or a script bug that's been
quietly backing up an empty or stale directory for months. None of these
show up as a job failure. The only way to actually know a backup works
is to restore it and check.

## Part A — Routine automated verification (daily/weekly, low-touch)

### 1. Confirm the backup job actually ran and produced expected output

```bash
ls -lh /backup/nightly/ | tail -5
```

Confirm a new archive exists for the expected date and its size is
roughly in line with recent history — a sudden drop to a fraction of the
usual size (even with a "success" exit code) is a strong signal something
was silently excluded.

### 2. Verify archive integrity without a full restore

```bash
tar -tzf /backup/nightly/db01-2026-08-24.tar.gz > /dev/null && echo "archive OK"
```

`tar -t` (list contents) reads through the entire archive and will fail
on corruption, without needing to actually extract anything — a fast,
cheap check suitable for running after every backup job.

### 3. Spot-check the file manifest

```bash
tar -tzf /backup/nightly/db01-2026-08-24.tar.gz | head -30
tar -tzf /backup/nightly/db01-2026-08-24.tar.gz | wc -l
```

Compare the file count against a recent baseline — a sharp drop suggests
files are being missed (a changed source path, a permissions issue
during the backup run) even though `tar -t` itself reports the archive
as structurally valid.

## Part B — Quarterly restore test (higher-effort, catches what Part A can't)

Part A confirms the archive is structurally intact and roughly
complete. It does **not** confirm the data inside is actually correct or
usable — that requires an actual restore.

### 1. Provision a scratch/test target

Use a disposable VM or container, isolated from production — never test
a restore by overwriting a live production path.

### 2. Perform a full restore of the most recent backup

```bash
mkdir -p /tmp/restore-test
tar -xzf /backup/nightly/db01-2026-08-24.tar.gz -C /tmp/restore-test
```

For a database backup specifically, this includes actually loading the
dump into a scratch database instance, not just extracting the dump
file — extraction succeeding doesn't confirm the dump itself is
loadable:

```bash
createdb restore_test_db
psql restore_test_db < /tmp/restore-test/db01-dump.sql
```

### 3. Validate the restored data, not just its presence

- Confirm row counts on a few key tables against expected ranges (a
  database restore that "succeeds" but is missing recent data due to a
  timing issue with the dump job is a real and common failure mode).
- Spot-check a handful of files for a file-based restore — open a sample
  and confirm content matches what's expected, not just that the file
  exists with a plausible size.
- For an application-data backup, ideally point a scratch instance of the
  application itself at the restored data and confirm it starts and
  functions — the strongest form of verification available, and worth
  the effort quarterly even if daily automated checks stay lightweight.

### 4. Time the restore and record it

Record how long the full restore actually took, end to end. This feeds
directly into the RTO figures used in the disaster-recovery runbook — an
RTO target that was never actually measured against a real restore is
just a guess.

### 5. Document the result

Record: date tested, backup tested (which date's archive), restore
target, validation steps performed, time taken, and outcome (pass, or
what failed and the remediation). A restore test with no findings is
still worth documenting — it's evidence the process was actually
performed, not skipped.

## When a restore test fails

Treat a failed restore test as a P2-equivalent finding even though
nothing is actually down — a backup that can't be restored is a
disaster waiting to compound an unrelated future incident. Investigate
and fix the backup process itself (not just the one bad archive), then
re-test before considering it resolved.

## Verification checklist

- [ ] Daily: backup archive present, expected size range, `tar -t`
      integrity check passed
- [ ] Weekly: file count/manifest spot-checked against baseline
- [ ] Quarterly: full restore performed to a scratch target
- [ ] Quarterly: restored data validated for correctness, not just
      presence (row counts, sample content, or a working app instance)
- [ ] Restore time recorded and compared against the documented RTO
      target
- [ ] Result documented regardless of outcome
