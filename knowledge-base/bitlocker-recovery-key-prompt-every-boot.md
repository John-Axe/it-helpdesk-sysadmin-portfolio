# KB — BitLocker asks for the recovery key on every boot

> Lab/practice KB article, generic guidance not tied to a real
> environment. See also
> `tickets/windows/TICKET-006-bitlocker-recovery-key-request.md` (a
> normal one-time recovery prompt) and
> `runbooks/windows-ad-m365/bitlocker-recovery-procedure.md` (the
> recovery-key lookup/provisioning procedure this article assumes).

## Symptom

A device prompts for the BitLocker recovery key on **every** boot, not
just once after a specific event (a firmware update, for example). Each
time, entering the 48-digit key successfully unlocks the drive and
Windows boots fine — but the prompt returns again on the next boot,
sometimes even after supposedly being "fixed."

This is meaningfully different from a one-time recovery prompt (see
TICKET-006) and should not be treated as the same issue — repeatedly
issuing recovery keys as a workaround without addressing the underlying
cause is not sustainable and usually means the actual problem is getting
worse, not resolving itself.

## Likely causes, in order of frequency

1. **TPM not properly initialized/owned, or in a degraded state.** If the
   TPM itself isn't healthy, BitLocker falls back to requiring the
   recovery key every time since it can't rely on the TPM to
   automatically unlock the drive after validating boot integrity.
2. **Unstable PCR (Platform Configuration Register) measurements** — some
   device/firmware combinations have a Secure Boot or firmware setting
   that changes on every boot (not just after an update), which looks to
   BitLocker like the boot state changed every single time.
3. **BitLocker bound to a PCR profile that's simply too strict for this
   hardware** (e.g. including PCR values that legitimately vary boot to
   boot on this specific model, such as certain PCR 0/2 measurements on
   some OEM firmware implementations).
4. **A pending firmware/driver update stuck in a partially-applied
   state**, causing measured boot values to differ from what was recorded
   at encryption/last-successful-unlock time on every attempt.

## Diagnostic steps

1. Check TPM health first, since this is the most common root cause:
   ```
   tpm.msc
   ```
   Under **Status**, confirm it reads "The TPM is ready for use." If it
   shows any error state, that's the priority to resolve before anything
   BitLocker-specific.
2. Check TPM ownership/readiness via PowerShell for a more detailed view:
   ```powershell
   Get-Tpm
   ```
   Look at `TpmReady`, `TpmPresent`, and `TpmEnabled` — all should be
   `True` on a healthy system.
3. Check the current TPM/BitLocker protector configuration:
   ```powershell
   manage-bde -protectors -get C:
   ```
   Confirm which protector type is active (TPM-only, TPM+PIN, etc.) and
   whether it matches what's expected for this device's configuration
   policy.
4. Check Event Viewer for BitLocker-specific errors around each failed
   auto-unlock attempt:
   **Event Viewer** → **Applications and Services Logs** → **Microsoft**
   → **Windows** → **BitLocker-API** → **Management**, looking for
   repeated errors correlating with each boot.

## Fix

- **If the TPM itself is unhealthy**: clear and re-initialize it
  (`tpm.msc` → **Actions** → **Clear TPM**, requires a restart and
  BIOS/UEFI confirmation) — **this will require re-suspending and
  decrypting/re-encrypting protectors**, so coordinate with the endpoint
  team rather than doing this unilaterally on a user's device; back up
  the current recovery key first regardless.
- **If PCR measurements are the issue on this hardware model**: change
  the BitLocker PCR validation profile via Group Policy
  (**Computer Configuration → Administrative Templates → Windows
  Components → BitLocker Drive Encryption → Operating System Drives →
  "Configure TPM platform validation profile"**) to a profile less
  sensitive to the specific PCR that's varying on this model — this is a
  fleet-wide policy decision, not a per-device fix, and should go through
  the endpoint engineering team rather than being changed ad hoc per
  ticket.
- **If a firmware/driver update is stuck**: fully apply or fully roll
  back the pending update rather than leaving it half-applied — a
  partially-applied firmware update is a common source of every-boot PCR
  mismatches.
- As a **temporary** stabilizing step only (not a fix): suspend BitLocker
  protection for a defined number of reboots
  (`manage-bde -protectors -disable C: -RebootCount 1`) while performing
  the actual firmware/TPM remediation, then re-enable
  (`manage-bde -protectors -enable C:`) once done — suspending disables
  the recovery-key requirement for that many reboots only, it does not
  decrypt the drive.

## When to escalate

If the device continues prompting after a TPM clear/re-init and a PCR
profile adjustment, escalate to the endpoint hardware team — this can
indicate a genuine hardware fault in the TPM module itself (more common
on older devices) rather than something resolvable through software
configuration alone, and the device may need TPM hardware replacement or
retirement from the fleet.
