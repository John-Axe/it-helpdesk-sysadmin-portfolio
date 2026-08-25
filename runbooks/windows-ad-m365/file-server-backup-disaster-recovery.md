# SOP — File server backup & disaster-recovery runbook

> Lab/practice SOP for a fictitious Windows file server `FILES01` in the
> `contoso.local` domain. Not a real employer's procedure.

## Scope

Backup configuration, verification, and full-restore procedure for a
Windows file server hosting departmental shares — covering both
day-to-day recoverability (a user deleted/overwrote a file) and a full
disaster-recovery scenario (server hardware failure, requiring restore to
new hardware or a VM).

## Backup architecture

- **Windows Server Backup** (built-in) for full server/system-state
  backups, scheduled nightly, written to a dedicated backup volume
  (separate physical disk from the data volume — a backup on the same
  disk as its source doesn't survive the failure mode it's meant to
  protect against).
- **Volume Shadow Copy Service (VSS) / Previous Versions** enabled on the
  data volume for fast, self-service recovery of individual
  accidentally-deleted or overwritten files without involving IT for the
  common case.
- Backup volume additionally replicated to an off-site/cloud target
  nightly, so a site-level event (fire, theft, site power loss
  destroying local backup media) doesn't take out both the primary data
  and its only backup copy.

## Part A — Initial backup configuration

### 1. Install Windows Server Backup feature

```powershell
Install-WindowsFeature Windows-Server-Backup
```

### 2. Configure a scheduled full backup

**Server Manager** → **Tools** → **Windows Server Backup** → **Backup
Schedule** → select **Full server** (or **Custom** to scope to specific
volumes) → set schedule (e.g. daily at 01:00, after business hours) →
destination: the dedicated backup volume.

Equivalent via `wbadmin` for scripting/documentation purposes:

```powershell
wbadmin enable backup -addtarget:{BackupVolumeGUID} -schedule:01:00 -include:D: -quiet
```

### 3. Enable Shadow Copies on the data volume

**File Explorer** → right-click the data volume → **Configure Shadow
Copies** → select the volume → **Enable** → **Settings** → set schedule
(default twice daily is reasonable for a typical file share's edit
patterns; adjust for higher-change-rate shares) and storage allocation
limit (undersizing this causes old shadow copies to be purged faster
than desired — size for the actual retention window needed).

### 4. Configure off-site replication of the backup volume

Set up replication of the backup destination to an off-site/cloud target
using whatever tool the environment standardizes on (Azure Backup, a
cloud sync agent, or a secondary physical location) — the specific tool
isn't load-bearing to this runbook, but the requirement that the backup
data leave the primary site is.

## Part B — Routine verification (do this on a schedule, not just when asked)

### 1. Confirm scheduled backups are actually completing

```powershell
Get-WBSummary
```

Check `LastBackupTime` and `LastBackupResultHR` (should be `0` for
success) — don't assume a scheduled job is running just because it's
configured; verify it's *actually completing* on the expected cadence.

### 2. Confirm off-site replication is current

Check the replication tool's own status/log for the backup volume,
confirm the most recent sync timestamp is within the expected window
(e.g. no more than 24-36 hours old for a nightly replication schedule).

### 3. Quarterly restore test (see also
`runbooks/linux/backup-verification-and-restore-test.md` for the
equivalent Linux-side procedure and shared rationale)

A backup that's never been test-restored is unverified by definition.
Quarterly, restore a sample file (and, at least annually, do a full
bare-metal-equivalent restore to a test VM) to confirm the backup is
actually usable, not just present. Document the result — the test itself
is the deliverable, not just a good outcome.

## Part C — Self-service file recovery (individual file/folder)

Point users to: right-click the parent folder in the share →
**Properties** → **Previous Versions** tab → select a date → **Restore**
(or **Open** to inspect first). This is Shadow Copies, not the nightly
full backup, and covers the overwhelming majority of "I need yesterday's
version of this file" requests without IT involvement.

## Part D — Full server disaster recovery

Use when the file server itself is lost (hardware failure, corruption
beyond what Shadow Copies covers) and needs to be rebuilt.

### 1. Provision replacement hardware/VM

Match or exceed original spec; OS install matching the original server's
edition/version where possible to simplify restore compatibility.

### 2. Boot to Windows Recovery Environment / installation media

For a bare-metal-equivalent restore, boot from Windows Server
installation media → **Repair your computer** → **Troubleshoot** →
**System Image Recovery**, and follow the wizard, pointing it at the
backup volume (or a restored copy of it, if the original backup volume
was also physically lost and had to be recovered from off-site
replication first).

### 3. Alternative: file-level restore to a fresh server build

If a full system-image restore isn't appropriate (e.g. deliberately
rebuilding on new/different hardware or a newer OS version rather than
restoring the exact prior state), instead build a fresh server and
restore just the data volume's files:

```powershell
wbadmin start recovery -version:{VersionID} -itemtype:Volume -items:D: -recoveryTarget:D:
```

### 4. Rebuild share definitions and permissions

A volume-level restore brings back files and their NTFS permissions, but
SMB share definitions themselves (share name, share-level permissions)
are a server configuration, not part of the volume — recreate shares
from documented configuration (kept current specifically for this
scenario) rather than trying to reconstruct them from memory during an
outage.

### 5. Validate before declaring recovery complete

- Confirm a sample of files across each major share open correctly and
  have expected content/modification dates.
- Confirm departmental groups have correct access (spot-check with a
  member of each affected group, not just an admin account which may
  have broader access that masks a permissions gap).
- Re-enable Shadow Copies on the restored volume (not automatically
  carried over by every restore method) and re-establish the backup
  schedule on the new server.

## Recovery time/point objectives (lab example targets)

| Scenario | RTO target | RPO target |
|---|---|---|
| Single file/folder restore (Shadow Copies) | Minutes, self-service | Since last shadow copy (typically <12hrs) |
| Full server restore, same-site hardware available | 4 hours | Since last nightly backup (<24hrs) |
| Full server restore requiring off-site backup recovery first | 24 hours | Since last off-site replication (<36hrs) |

## Follow-up

- Re-validate RTO/RPO targets periodically against actual restore-test
  timings, not just the theoretical schedule — a "4 hour" target that
  consistently takes 7 hours in practice needs either a process fix or
  an honestly adjusted target.
- Keep the share-definition/permissions documentation used in Part D
  step 4 current as shares are added or changed, or the disaster
  recovery path silently degrades even if backups themselves are fine.
