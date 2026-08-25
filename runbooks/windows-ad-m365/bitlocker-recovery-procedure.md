# SOP — BitLocker recovery procedure

> Lab/practice SOP against a fictitious `contoso.local` domain with
> BitLocker key escrow to AD DS via Group Policy. Not a real employer's
> procedure. Generalized from
> `tickets/windows/TICKET-006-bitlocker-recovery-key-request.md`.

## Scope

Covers retrieving and providing a BitLocker recovery key to a locked-out
user, verifying escrow is configured correctly for new devices, and
distinguishing a normal one-time recovery prompt from a recurring
misconfiguration that needs deeper investigation.

## Prerequisites

- **Computer Configuration → Administrative Templates → Windows
  Components → BitLocker Drive Encryption → Operating System Drives →
  "Choose how BitLocker-protected operating system drives can be
  recovered"** GPO enabled, with **"Save BitLocker recovery information
  to AD DS"** and **"Store recovery passwords and key packages"** set.
- Help-desk role has delegated read access to the `msFVE-RecoveryPassword`
  attribute (via the **BitLocker Recovery** tab in AD Users and
  Computers, which requires **Advanced Features** enabled under the
  **View** menu) — full Domain Admin is not required and should not be
  used for this task.

## Part A — Providing a recovery key to a locked-out user

### 1. Verify caller identity first

A BitLocker recovery key is equivalent to full disk access. Confirm
identity per standard help-desk verification (employee ID + manager
name, or an equivalent org-approved method) before proceeding — do not
skip this step because the user sounds legitimate or is in a hurry.

### 2. Get the Recovery Key ID from the blue recovery screen

Ask the user to read the short **Recovery Key ID** (an 8-character
fragment, not the full key) shown on screen. A device can have multiple
historical recovery passwords on file if it was re-encrypted or had its
protectors reset previously — the ID is required to match the *correct*
key, since providing the wrong one will simply be rejected by the
recovery screen and waste time.

### 3. Look up the matching key in AD

**Active Directory Users and Computers** → enable **Advanced Features**
(View menu, if not already on) → locate the computer object → **BitLocker
Recovery** tab → find the entry whose **Password ID** matches what the
user read off screen.

Alternatively, from an admin PowerShell session with appropriate rights:

```powershell
Get-ADObject -Filter {objectClass -eq 'msFVE-RecoveryInformation'} `
    -SearchBase (Get-ADComputer "<ComputerName>").DistinguishedName `
    -Properties msFVE-RecoveryPassword, msFVE-KeyPackage
```

### 4. Read the key to the user

Read the 48-digit key in 6-digit groups, having the user confirm each
group back before continuing — a mistyped digit produces another failed
attempt and wastes another round trip.

### 5. Log the Password ID, not the key itself

Record which recovery **Password ID** was used to resolve the ticket, for
audit purposes. **Never** write the recovery key value itself into a
ticket, chat log, or email — treat it the same as a password.

### 6. Confirm the machine is still protected post-recovery

Once the user is back in Windows:

```powershell
manage-bde -status C:
```

Confirm **Protection Status: Protection On** — recovery unlocks the drive
for that boot only; it does not, by itself, suspend or disable ongoing
protection. If it *does* show suspended, re-enable:

```powershell
manage-bde -protectors -enable C:
```

## Part B — Verifying escrow on a new/reimaged device

Before a device ships or is handed to a user, confirm its recovery key
actually made it to AD rather than assuming the GPO alone guarantees it
(policy application timing, OU scope, or a device provisioned outside the
managed OU can all cause a silent miss):

```powershell
Get-ADObject -Filter {objectClass -eq 'msFVE-RecoveryInformation'} `
    -SearchBase (Get-ADComputer "<ComputerName>").DistinguishedName
```

If nothing returns, force a policy re-application and re-check:

```powershell
gpupdate /force
manage-bde -protectors -adbackup C: -id <ProtectorID>
```

The escrow-check script,
`scripts/powershell/bitlocker-recovery-key-escrow-check.ps1`, automates
this verification across a batch of computer objects (e.g. all devices
provisioned in the last N days) rather than checking one at a time by
hand.

## When a single recovery prompt is normal vs. when to escalate

| Situation | Action |
|---|---|
| One-time prompt right after a firmware/BIOS update | Expected — BitLocker validates boot integrity (TPM PCR measurements) and a firmware change can legitimately alter those values. Resolve via Part A, no further action needed. |
| Prompts every single boot, or after every Windows Update | Not normal — indicates a TPM/PCR binding, firmware setting (e.g. an unstable Secure Boot state), or driver issue. See `knowledge-base/bitlocker-recovery-key-prompt-every-boot.md` and escalate to endpoint engineering rather than repeatedly issuing recovery keys as a workaround. |
| No recovery password found in AD at all | Escrow failed or was never configured for this device. Resolve the immediate lockout using the device's locally-stored/printed recovery key if available (per organizational key-recovery policy for that case), then fix escrow going forward per Part B. |

## Follow-up hardening

- Periodically audit for devices with BitLocker enabled but **no**
  matching AD escrow record — a device that's encrypted but not
  recoverable through this procedure is a business-continuity risk if the
  local recovery key is ever lost.
- Schedule known-disruptive firmware/BIOS updates with advance user
  notice ("this update may prompt for a BitLocker recovery key — here's
  who to call") rather than delivering them silently.
