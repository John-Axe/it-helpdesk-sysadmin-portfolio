# TICKET-002 — Outlook / Microsoft 365 mailbox stuck, not syncing

> Lab scenario. Environment: fictitious `contoso.onmicrosoft.com` M365 tenant,
> Outlook 2021 (desktop, Windows 11). Not a real employer/customer ticket.

## Summary

| Field | Value |
|---|---|
| Priority | P2 — High (user blocked from email) |
| Category | Microsoft 365 / Outlook |
| Reported by | End user, Sales department |
| Affected system | Outlook desktop client, `k.tan@contoso.onmicrosoft.com` |

## Symptom

User reports Outlook has shown "Trying to connect..." in the status bar for
over an hour. No new mail is arriving, and mail composed and sent an hour ago
is still sitting in the Outbox. Webmail (`outlook.office.com`) works fine
from a browser on the same machine — mail is there, sending works.

## Triage steps

1. Confirmed webmail works → tenant/mailbox itself is healthy, so this is a
   local client/profile/connectivity issue, not a service outage.
2. Checked Outlook's connection status: `Ctrl` + right-click the Outlook
   icon in the system tray → **Connection Status**. Showed the Exchange
   connection with a `Conn State` of `Disconnected` and repeated retry
   attempts.
3. Ran Outlook in safe mode to rule out an add-in:
   `outlook.exe /safe` — same symptom, so not an add-in conflict.
4. Checked **Windows Credential Manager** (`Control Panel` → `Credential
   Manager` → `Windows Credentials`) for a stale `MicrosoftOffice16_Data:
   ...` entry. Found one — it still referenced an *old* password from
   before the user's scheduled M365 password rotation two days earlier.
5. Confirmed via `Get-MsolUser` (admin session) that the account itself was
   `BlockCredential: False` and not locked at the tenant level — ruled out
   a Conditional Access block.

## Root cause

Outlook was silently retrying with a cached credential that predated the
user's M365 password change. Because Modern Auth token refresh had also
expired around the same time, Outlook fell back to the stale cached
password instead of prompting for re-authentication, and never surfaced a
visible sign-in prompt to the user.

## Resolution

1. Closed Outlook completely (verified via Task Manager — `OUTLOOK.EXE` had
   a lingering background process).
2. In Credential Manager, removed all `MicrosoftOffice16_Data:` and
   `MicrosoftOffice16_Auth:` entries tied to the user's UPN.
3. Relaunched Outlook — it correctly prompted for fresh sign-in with Modern
   Auth (including the org's MFA push), user re-authenticated.
4. Connection Status showed `Conn State: Established` within ~30 seconds;
   Outbox drained immediately.

## Follow-up / prevention

- Verified the user was enrolled in **Single Sign-On (SSO)** via the
  company's Azure AD Seamless SSO config so future password rotations
  propagate without a stale-cache issue — this user's device had SSO
  configured but had been offline during the last GPO refresh, so it
  hadn't picked up the updated policy yet.
- Documented the "clear stale credentials after a scheduled password
  rotation" step as a proactive support-desk KB article
  (`knowledge-base/outlook-search-not-returning-results.md` covers a
  related Outlook cache issue; this one is intentionally logged separately
  since root cause differs — credential cache vs. search index).
