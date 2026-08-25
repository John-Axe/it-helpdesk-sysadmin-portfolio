# TICKET-008 — Shared team calendar showing free/busy only, not event details

> Lab scenario. Environment: fictitious `contoso.onmicrosoft.com` tenant,
> Exchange Online, Outlook desktop + OWA. Not a real employer/customer
> ticket.

## Summary

| Field | Value |
|---|---|
| Priority | P3 — Medium |
| Category | Exchange / Calendar Permissions |
| Reported by | Department manager |
| Affected system | Shared calendar `Marketing Team Calendar`, resource mailbox |

## Symptom

A newly hired employee added to the Marketing team was told they'd have
full visibility into the shared "Marketing Team Calendar" like the rest
of the team. Instead, they could only see time blocked out as
**Busy/Free/Tentative/Out of Office** with no subject, location, or
attendee details — every event just showed as a gray "Busy" block. Other
team members confirmed they could see full event details fine.

## Triage steps

1. Confirmed the new employee was in fact a member of the correct
   security group / distribution list used to grant calendar access
   (`MKT-Team` — confirmed via **Microsoft 365 admin center** →
   **Groups**).
2. Checked the calendar's actual sharing permissions rather than assuming
   group membership alone granted access — the shared calendar was a
   resource mailbox, not a group calendar, so its permissions are set
   independently via mailbox folder permissions:

   ```
   Get-MailboxFolderPermission -Identity "mkt-teamcal@contoso.onmicrosoft.com:\Calendar"
   ```

3. Output showed the `MKT-Team` group had `AvailabilityOnly` access
   level, not `Reviewer` or higher — this explained the free/busy-only
   view exactly, and confirmed it was a group-level permission problem,
   not something specific to the new hire's account or a caching issue.
4. Compared against a note in the runbook history: the calendar had
   originally been shared with **individual users** at `Reviewer` level
   when it was first set up, and only later was the group-based
   permission added on top — for convenience, so future new hires
   wouldn't need a manual grant each time. The group-based grant was
   added at the wrong level by whoever set it up.
5. Confirmed the fix wouldn't regress the individually-granted users:
   `Get-MailboxFolderPermission` showed the original individual entries
   were still present at `Reviewer`, unaffected by fixing the group
   entry.

## Root cause

The `MKT-Team` security group had been granted `AvailabilityOnly`
permission on the shared calendar folder instead of `Reviewer`
(read event details) — likely a default selected without noticing during
whoever configured it originally, since `AvailabilityOnly` and `Reviewer`
sit next to each other in the folder permissions picker in Outlook and
it's an easy misclick. Individually-added users from the calendar's
original setup were unaffected because their permissions were granted
separately and correctly, which is why most of the team saw no problem
and only new hires being onboarded solely via the group grant were affected.

## Resolution

1. Updated the group's folder permission level:

   ```
   Set-MailboxFolderPermission -Identity "mkt-teamcal@contoso.onmicrosoft.com:\Calendar" `
       -User "MKT-Team" -AccessRights Reviewer
   ```

2. Had the new employee close and reopen Outlook (folder permission
   changes can take a few minutes to reflect, and a stale cached view
   sometimes needs a client restart to pick up) — confirmed full event
   details now visible.
3. Spot-checked with the manager that no other shared calendars in the
   department had the same `AvailabilityOnly`-on-a-group misconfiguration:

   ```
   Get-Mailbox -RecipientTypeDetails RoomMailbox,SharedMailbox -ResultSize Unlimited |
       ForEach-Object { Get-MailboxFolderPermission -Identity "$($_.PrimarySmtpAddress):\Calendar" } |
       Where-Object { $_.AccessRights -contains "AvailabilityOnly" -and $_.User -notmatch "Default|Anonymous" }
   ```

   Found one other shared calendar with the same issue and corrected it
   in the same maintenance window.

## Follow-up / prevention

- Documented the correct access-rights levels and what each actually
  shows (`AvailabilityOnly` vs. `LimitedDetails` vs. `Reviewer` vs.
  `Editor`) in the runbook so future calendar shares use the right level
  the first time instead of the closest-looking option.
- Recommended standardizing on group-based (not individual-user) calendar
  permissions going forward specifically because it's easier to audit and
  fix in one place — this incident happened precisely because the setup
  mixed both approaches inconsistently.
