# TICKET-001 — Recurring AD account lockout

> Lab scenario. Environment: fictitious `contoso.local` Active Directory domain,
> Windows Server 2019 DC, Windows 11 clients. Not a real employer/customer ticket.

## Summary

| Field | Value |
|---|---|
| Priority | P3 — Normal |
| Category | Active Directory / Account Access |
| Reported by | End user, Finance department |
| Affected system | `CONTOSO\j.reyes` account, domain-joined laptop `FIN-LT-014` |

## Symptom

User reports her AD account locks out roughly every 30-45 minutes throughout
the day. She can unlock via the self-service portal but it re-locks shortly
after. No password change was recently performed on her end. She works from
a laptop in the office and occasionally from a personal phone with the
company email app installed.

## Triage steps

1. Confirmed the lockout in AD Users and Computers: account showed
   `Locked out: Yes`, `Bad Logon Count: 5`.
2. Checked the PDC emulator's Security event log (`Event Viewer` →
   `Windows Logs` → `Security`, filtered on Event ID `4740` — "A user account
   was locked out") to find the source computer for each lockout.

   ```
   Get-WinEvent -ComputerName DC01 -FilterHashtable @{
       LogName = 'Security'; Id = 4740
   } | Where-Object { $_.Message -match 'j.reyes' } |
   Select-Object TimeCreated, Message
   ```

3. Every 4740 event pointed to the *same* source workstation name, but it was
   **not** `FIN-LT-014` — it was an old, decommissioned laptop name
   (`FIN-LT-002`) that should have been retired months ago.
4. Cross-referenced Event ID `4625` (failed logon) on that source machine.
   `Caller Process Name` was `svchost.exe` — consistent with a scheduled
   task or cached credential, not an interactive logon attempt.
5. Confirmed with the user: she had briefly used `FIN-LT-002` before it was
   swapped out, and had an Outlook profile and a mapped network drive
   (`net use`) configured on it that were never removed. IT had reassigned
   the machine to another employee without wiping the stored credentials
   for `j.reyes`, and it was still powered on in a back office, syncing
   Outlook on a schedule with her old (now-changed) cached password.

## Root cause

Stale cached credentials on a reassigned workstation kept retrying
authentication with an outdated password, tripping the domain's account
lockout threshold (5 bad attempts / 15-minute observation window, per
`Default Domain Policy`).

## Resolution

1. Physically located `FIN-LT-002`, logged in with local admin rights, and
   cleared the stored credential:

   ```
   cmdkey /list
   cmdkey /delete:CONTOSO\j.reyes
   ```

2. Removed the orphaned Outlook profile from that machine (`Control Panel` →
   `Mail (Microsoft Outlook)` → `Show Profiles`) and disabled the local
   Windows account that had been auto-logging in.
3. Unlocked `j.reyes` in ADUC and confirmed no further 4740 events over the
   next 2 hours.
4. Updated the asset inventory to mark `FIN-LT-002` as retired/pending wipe
   instead of "in service, reassigned" — the inventory status update had
   been skipped during the original reassignment.

## Follow-up / prevention

- Added a checklist item to the workstation-reassignment SOP: **always**
  run `cmdkey /list` and clear cached domain credentials before repurposing
  a machine, and physically confirm decommissioned machines are powered
  off/wiped, not just reassigned in the ticketing system.
- Considered enabling **Account Lockout Status** reporting via a scheduled
  script that emails IT when the same source computer generates repeat 4740
  events for different users — flags exactly this pattern (stale device,
  not a compromised password) instead of just responding ticket-by-ticket.
