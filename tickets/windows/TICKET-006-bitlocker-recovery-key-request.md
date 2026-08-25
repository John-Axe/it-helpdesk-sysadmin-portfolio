# TICKET-006 — User locked out by BitLocker recovery prompt, no key on file

> Lab scenario. Environment: fictitious `contoso.local` domain, Windows 11,
> BitLocker with AD-based key escrow via Group Policy. Not a real
> employer/customer ticket.

## Summary

| Field | Value |
|---|---|
| Priority | P2 — High (user fully locked out of device) |
| Category | Endpoint / Disk Encryption |
| Reported by | End user, via phone (using personal mobile) |
| Affected system | Laptop `HQ-LT-042`, Windows 11 23H2, BitLocker-encrypted |

## Symptom

User's laptop rebooted after a firmware update prompt overnight and, on
next boot, presented the blue BitLocker recovery screen asking for a
48-digit recovery key instead of booting normally. User has no idea what
a "recovery key" is and cannot get past this screen — the laptop is
completely unusable until resolved.

## Triage steps

1. Confirmed identity of the caller through the standard help-desk
   verification process (employee ID + manager name) before proceeding,
   since a BitLocker recovery key is effectively full disk access.
2. Asked the user to read the **BitLocker Recovery Key ID** shown on the
   blue screen (a short GUID fragment, not the key itself) — this is
   needed to look up the *matching* key, since a device can have
   multiple historical recovery keys if it was re-encrypted before.
3. Checked whether the device's BitLocker key was actually escrowed to
   AD, since escrow is what makes this recoverable at all:

   ```
   Get-ADComputer -Identity "HQ-LT-042" -Properties msFVE-RecoveryPassword
   ```

   *(Directly reading `msFVE-RecoveryPassword` this way only returns a
   value if the querying account has read rights on that attribute —
   most help desk tiers use the **BitLocker Recovery** tab in AD Users
   and Computers instead, which has the correct delegated permissions
   built in.)*
4. Opened **Active Directory Users and Computers** → enabled **Advanced
   Features** (View menu) → located the computer object → **BitLocker
   Recovery** tab → found a recovery password entry whose **Password ID**
   matched the first 8 characters the user read off the blue screen
   (multiple entries existed from a prior drive re-encryption six months
   earlier, so matching the ID mattered — using the wrong one would have
   been rejected by the recovery screen).
5. Confirmed via the GPO settings (`gpresult` history on a similar
   machine, since this one couldn't boot) that
   **Computer Configuration → Administrative Templates → Windows
   Components → BitLocker Drive Encryption → Operating System Drives →
   "Choose how BitLocker-protected operating system drives can be
   recovered"** had **"Save BitLocker recovery information to AD DS"**
   enabled — this confirmed escrow was policy-driven and not something
   that failed silently, ruling out "the key was never saved" as a
   possibility once the correct Password ID was matched.

## Root cause

A firmware/BIOS update changed the device's measured boot values (PCR
values used by TPM-based BitLocker validation), which BitLocker
interprets as a potential tamper/boot-integrity change and responds to by
requiring the recovery key before continuing — expected, intentional
BitLocker behavior after a firmware update, not a fault or misconfiguration.

## Resolution

1. Read the 48-digit recovery key from the **BitLocker Recovery** tab to
   the user over the phone, in 6-digit groups, having them confirm each
   group back before moving to the next to avoid a transcription error
   locking them out again on a mistyped digit.
2. User entered the key, device booted successfully into Windows.
3. Confirmed BitLocker was still in a protected/encrypting state
   post-boot (`manage-bde -status C:` run by the user under guidance)
   rather than having been suspended by the recovery process.
4. Logged the recovery key **Password ID** used in the ticket (not the
   key itself) for audit trail purposes, per team policy — the full key
   value is never written into ticket notes.

## Follow-up / prevention

- Confirmed with the sysadmin team that firmware/BIOS updates that are
  known to trigger a BitLocker recovery prompt should be scheduled with
  advance user notice ("your laptop may ask for a recovery key after this
  update — here's who to call") rather than delivered silently overnight,
  so users aren't blindsided by a screen they don't understand.
- Verified TPM PCR binding settings weren't unnecessarily strict for this
  device model — some PCR profiles are more update-sensitive than others;
  recommended the standard image use a profile less prone to tripping on
  routine firmware updates (PCR 7 SecureBoot state changes specifically)
  where the model supports it.
- Added a KB article
  (`knowledge-base/bitlocker-recovery-key-prompt-every-boot.md`) covering
  both this one-time case and the more concerning "asks every single
  boot" variant, which has a different root cause.
