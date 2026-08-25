# SOP — Windows Autopilot device provisioning

> Lab/practice SOP against a fictitious `contoso.onmicrosoft.com` tenant
> with Intune + Windows Autopilot. Not a real employer's procedure.
> Complements the enrollment-focused
> `runbooks/windows-ad-m365/intune-device-enrollment-walkthrough.md` —
> this runbook covers the procurement-to-shipping provisioning workflow,
> that one covers enrollment/troubleshooting once a device reaches OOBE.

## Scope

The full device-lifecycle procedure for getting a **new** corporate
laptop from "just arrived from the OEM/reseller" to "shipped to the
end user, fully provisioned on first boot with no IT hands-on setup" —
covering hardware-hash registration, profile/group-tag assignment, and
the pre-ship verification steps that catch a bad Autopilot registration
before it reaches the user instead of after.

## Prerequisites

- Intune license assigned to the target user population.
- A defined set of Autopilot deployment profiles for each device
  use-case (e.g. `Standard-CorpOwned-UserDriven`,
  `Kiosk-SharedDevice`) already built in **Intune admin center** →
  **Devices** → **Enrollment** → **Windows Autopilot deployment
  profiles**.
- Group Tag naming convention agreed with whoever manages dynamic Entra
  ID group membership rules, since group tags are commonly used as the
  dynamic-group matching key for app/policy assignment.

## Procedure

### 1. Determine registration path

Two options, pick based on reseller relationship:

- **Reseller/OEM registers on your behalf** (preferred where available):
  provide the reseller your tenant ID; they register each device's
  hardware hash directly to your tenant at time of purchase — device
  shows up in Intune before you ever touch it.
- **Manual registration**: capture and upload the hardware hash yourself
  (below) — needed for devices bought through a channel that doesn't
  support direct registration, or for repurposing an existing device.

### 2. Manual hardware hash capture (if needed)

On the device, booted to Windows (OOBE or an existing install) with
admin rights:

```powershell
Install-Script -Name Get-WindowsAutopilotInfo -Force
Get-WindowsAutopilotInfo.ps1 -OutputFile AutopilotHWID.csv -GroupTag "Sales"
```

The `-GroupTag` parameter sets the tag at capture time, saving a manual
step later. For a batch of devices, run against each and merge the CSVs,
or use `-OutputFile` per device and concatenate before import.

### 3. Import into Intune

**Intune admin center** → **Devices** → **Enrollment** → **Windows
enrollment** → **Devices** → **Import** → upload the CSV. Sync can take
a few minutes for a handful of devices, up to roughly an hour for a large
batch — don't assume a device is missing and re-import if it hasn't
appeared within a few minutes.

### 4. Assign deployment profile and confirm group tag

1. **Devices** → **Enrollment** → **Windows Autopilot deployment
   profiles** → select the correct profile → **Assigned devices** (or
   assign via the dynamic group the group tag feeds, if profiles are
   assigned that way in this tenant).
2. If the group tag wasn't set at capture time, set it now on the
   imported device record, or via bulk edit for a batch.
3. Confirm **Profile status: Assigned** on each device before proceeding
   — a device without an assigned profile will boot to a generic OOBE
   experience rather than the branded, silent Autopilot flow.

### 5. Pre-ship verification (do this before the device leaves IT)

Don't ship on faith that import + profile assignment worked. For at
least a sample of each batch (ideally every device for a small batch):

1. Power on the device (or, if it must ship immediately, do this
   verification against a spare unit of the same batch/config if
   available).
2. Confirm it reaches the branded Autopilot OOBE sign-in screen rather
   than a generic "Let's set up your device" flow — the branding is a
   fast visual confirmation the profile applied.
3. If the device is being provisioned in-house before shipping (some
   orgs image and pre-provision rather than ship straight to the user),
   let it complete the full Autopilot ESP flow and confirm compliance
   before boxing it, per the compliance check in step 6 below.

### 6. Confirm compliance once the user has completed setup

A few hours after the device should have completed first-boot
provisioning at the user's location:

**Intune admin center** → **Devices** → **All devices** → find the
device → confirm:
- **Management state**: `Managed`
- **Compliance**: `Compliant` (or `In grace period`, acceptable
  temporarily if a required setting like BitLocker is still finishing)
- **Last check-in**: recent

Optionally automate this check across a recent cohort of provisioned
devices using `Get-MgDeviceManagementManagedDevice` filtered by
enrollment date, rather than checking one at a time in the console.

## Common provisioning-stage failures

| Symptom | Likely cause | Check |
|---|---|---|
| Device shows in **Devices** but never gets a profile assigned | Group tag doesn't match any dynamic group's membership rule, or profile wasn't assigned to the right group/device | Compare the device's actual Group Tag value against the dynamic group rule syntax exactly (case and exact string matter) |
| Device boots to generic OOBE, not branded Autopilot | Profile assignment hadn't synced before first boot (imported and shipped too close together) | Re-check "sync now" and allow more buffer time between import/assignment and shipping for future batches |
| "This device is already assigned to a different profile" on re-registration | Device was previously imported to this or another tenant and not cleanly removed | Delete the stale device record before re-importing |
| Hardware hash upload rejected/malformed | CSV export corrupted (commonly from opening/re-saving in Excel, which can mangle the hash) | Re-run `Get-WindowsAutopilotInfo.ps1` fresh rather than editing an existing CSV in a spreadsheet tool |

## Follow-up

- Maintain the deployment-profile-to-use-case mapping and group tag
  naming convention as living documentation — most Autopilot support
  issues trace back to a mismatch between what a device was tagged and
  what a human expected it to be tagged, not a platform bug.
- Periodically clean up stale device records for hardware that's been
  decommissioned, so "already assigned" errors don't accumulate for
  units that get reused or resold.
