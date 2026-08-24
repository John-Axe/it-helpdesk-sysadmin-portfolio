# TICKET-004 — Recurring BSOD on a single workstation

> Lab scenario. Environment: fictitious `contoso.local` domain, Windows 11
> desktop `ENG-WS-021`. Not a real employer/customer ticket.

## Summary

| Field | Value |
|---|---|
| Priority | P2 — High (workstation unusable) |
| Category | Hardware / Driver |
| Reported by | End user, Engineering department |
| Affected system | `ENG-WS-021`, Windows 11 23H2 |

## Symptom

Workstation blue-screens 2-4 times a day, always mid-session, no consistent
trigger the user can identify. Stop code shown on screen: `DRIVER_IRQL_NOT_LESS_OR_EQUAL`.

## Triage steps

1. Pulled the memory dump location and confirmed dumps were being generated:
   `System Properties` → `Advanced` → `Startup and Recovery` → confirmed
   `Write debugging information: Small memory dump (256 KB)` was enabled,
   dumps landing in `C:\Windows\Minidump`.
2. Reviewed the most recent dump with **WinDbg** (`Windows SDK` debugging
   tools):

   ```
   windbg -z C:\Windows\Minidump\081924-12345-01.dmp
   ```

   Ran `!analyze -v`. Output pointed to `rtwlanu.sys` (Realtek USB wireless
   adapter driver) as the probable faulting module.
3. Checked Device Manager for the network adapter — confirmed the user had
   recently plugged in a USB Wi-Fi adapter as a workaround after their dock's
   built-in Ethernet port had come loose (a separate, unreported hardware
   issue).
4. Checked the driver version against Realtek's published driver for that
   chipset/Windows build — the installed driver was over 2 years old and
   predated several Windows 11 servicing updates.
5. Cross-referenced Event Viewer (`Windows Logs` → `System`) for Event ID
   `1001` (BugCheck) entries — all four recent crashes correlated with
   `rtwlanu.sys` in the bugcheck parameters.

## Root cause

Outdated/incompatible USB Wi-Fi adapter driver (`rtwlanu.sys`) was
triggering an IRQL fault under normal network load. The adapter itself was
only in use because the dock's Ethernet port had failed and gone
unreported — the driver crash was a symptom of an underlying hardware
issue, not just a software bug.

## Resolution

1. Uninstalled the existing Realtek driver completely via Device Manager
   (`Uninstall device` + `Delete the driver software for this device`), then
   installed the current vendor driver from Realtek's official support page
   for that exact adapter model.
2. Verified stability by running the machine under normal load
   (video calls, file transfers) for a full day with no crashes.
3. Escalated the dock's failed Ethernet port as a separate hardware ticket
   and swapped the user to a known-good dock from the spares pool, removing
   the need for the USB Wi-Fi adapter entirely.

## Follow-up / prevention

- Documented BSOD triage procedure (`runbooks/windows-ad-m365/` — this
  ticket informed the systemd/BSOD-adjacent triage checklist added to the
  runbooks) covering: confirm dump generation is enabled, use WinDbg
  `!analyze -v` to identify the faulting module, check driver dates against
  vendor's current release, and check Event Viewer System log for
  correlating Event ID 1001 entries across multiple crashes before
  concluding root cause.
- Flagged with the desktop hardware team to review dock inventory — several
  docks of the same model/batch were purchased at the same time and may be
  approaching the same failure mode.
