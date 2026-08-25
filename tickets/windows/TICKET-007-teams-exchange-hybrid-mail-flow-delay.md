# TICKET-007 — Email from Teams meeting invites delayed 20-40 minutes

> Lab scenario. Environment: fictitious hybrid Exchange setup — on-prem
> Exchange 2019 hybrid server relaying to Exchange Online for
> `contoso.onmicrosoft.com`. Not a real employer/customer ticket.

## Summary

| Field | Value |
|---|---|
| Priority | P3 — Medium (annoying, not blocking, but company-wide) |
| Category | Exchange / Mail Flow |
| Reported by | Multiple users, escalated by a department manager |
| Affected system | Hybrid mail flow, `contoso-hybrid01` on-prem connector |

## Symptom

Users scheduling Teams meetings noticed calendar invites and meeting
update emails arriving 20-40 minutes after being sent, instead of within
seconds as usual. Regular person-to-person email was unaffected — only
Teams/calendar-generated messages were delayed. Complaints started the
same week IT had migrated a subset of mailboxes from on-prem Exchange to
Exchange Online as part of an ongoing phased migration.

## Triage steps

1. Confirmed the pattern wasn't universal: sent a manual test email
   between two cloud-only mailboxes — arrived instantly. Sent a Teams
   meeting invite from a still-on-prem mailbox to a migrated (cloud)
   mailbox — delayed ~30 minutes, reproducing the issue.
2. Checked **Exchange Online admin center** → **Mail flow** → **Message
   trace** for one of the delayed invites, filtered by sender/recipient
   and the approximate time window.
3. Message trace showed the message sitting in a `Pending` status for the
   bulk of the delay, then a final event of `Delivered` — not a bounce or
   rejection, just a long queue dwell time.
4. Cross-checked the on-prem side: on `contoso-hybrid01`, ran:

   ```
   Get-Queue | Where-Object {$_.NextHopDomain -like "*mail.protection.outlook.com*"}
   ```

   Found a queue with several hundred messages and a retry count
   climbing — the on-prem hybrid server's outbound connector to
   Exchange Online was retrying, not failing outright, consistent with
   the ~30 minute delay pattern (a few retry cycles at growing backoff
   intervals before eventually succeeding).
5. Checked `Get-SendConnector` on the hybrid server and compared its
   configured smart host / TLS settings against Microsoft's current
   hybrid connector documentation — found the send connector's
   **MaxMessageSize** and TLS cert were both fine, but a scheduled
   certificate rotation two weeks earlier (unrelated maintenance) had
   installed a new cert without also re-running the
   **Hybrid Configuration Wizard (HCW)** to re-bind the updated cert to
   the hybrid connector's TLS auth cert thumbprint.
6. Confirmed by checking the connector's certificate thumbprint against
   the currently valid cert:

   ```
   Get-SendConnector "Outbound to Office 365" | Select-Object -ExpandProperty TlsCertificateName
   ```

   The thumbprint referenced was the **old**, since-replaced certificate
   — meaning outbound TLS auth to Exchange Online was periodically
   failing on some connection attempts (intermittent, not constant,
   which explained why *some* mail flowed fine while other messages
   queued and retried).

## Root cause

A routine certificate renewal on the on-prem hybrid server replaced the
TLS certificate used for authenticated relay to Exchange Online, but the
hybrid connector configuration (`TlsCertificateName` on the send
connector) still pointed at the old certificate's thumbprint. Connections
using the stale reference intermittently failed TLS auth on the
Microsoft 365 side, triggering SMTP retry/backoff — the queue eventually
drained on each retry cycle, which is why messages were delayed rather
than permanently stuck, and why the issue disproportionately affected
Teams/calendar traffic (higher message volume during the affected window
made the queuing more visible than for lower-volume person-to-person mail).

## Resolution

1. Re-ran the **Hybrid Configuration Wizard** from the on-prem Exchange
   management console to re-detect and re-bind the current, valid
   certificate to both the receive and send connectors used for hybrid
   mail flow.
2. Verified the updated thumbprint:

   ```
   Get-SendConnector "Outbound to Office 365" | Select-Object Identity, TlsCertificateName
   ```

   matched `Get-ExchangeCertificate` output for the currently valid,
   non-expired cert.
3. Flushed the retry queue manually to avoid waiting out the existing
   backoff timers:

   ```
   Retry-Queue -Identity "contoso-hybrid01\Outbound to Office 365"
   ```

4. Sent a fresh test Teams invite between an on-prem and a migrated
   mailbox — delivered within seconds, confirming the fix.

## Follow-up / prevention

- Documented in the change-management runbook that any certificate
  rotation on a hybrid Exchange server must be followed by re-running the
  HCW (or manually updating `TlsCertificateName` on affected connectors)
  as a **required** step, not an optional one — this had been missed
  because the cert renewal was handled by a different team than the
  Exchange hybrid owner.
- Set a calendar reminder tied to the cert's expiration date, six months
  out, to proactively re-run HCW ahead of the *next* renewal rather than
  reactively after complaints.
- Added a monitoring check on queue depth for the hybrid connector
  (`Get-Queue` count threshold) so a growing queue triggers an alert
  before it becomes a user-visible delay pattern.
