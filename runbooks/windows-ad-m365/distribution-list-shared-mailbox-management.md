# SOP — Distribution list & shared mailbox management

> Lab/practice SOP against a fictitious `contoso.onmicrosoft.com` Exchange
> Online tenant. Not a real employer's procedure.

## Scope

Covers creating and managing both a **distribution list** (DL, for email
broadcast to a group) and a **shared mailbox** (a mailbox multiple people
can send/receive from, e.g. `support@contoso.com`), plus the day-to-day
requests: adding/removing members, granting Send As vs. Send on Behalf,
and converting a user mailbox to shared for an offboarding case.

All commands assume an active Exchange Online PowerShell session:

```powershell
Connect-ExchangeOnline -UserPrincipalName admin@contoso.onmicrosoft.com
```

## Part 1 — Creating a distribution list

### Via Exchange admin center (EAC)

1. **admin.exchange.microsoft.com** → **Recipients** → **Groups** →
   **Add a group**.
2. Choose **Distribution list** (not Security group or M365 group — DLs
   are simplest for pure email-broadcast use cases with no shared
   files/calendar needed).
3. Name it clearly, e.g. `DL-Sales-Team`. Set the email address.
4. Add owners (who can manage membership going forward) and initial
   members.
5. Under **Group settings**, decide **Sender approval** — for a
   company-wide list, require approval to prevent spam/misuse; for a small
   team list, allow anyone to send.

### Via PowerShell

```powershell
New-DistributionGroup -Name "DL-Sales-Team" `
    -DisplayName "Sales Team" `
    -PrimarySmtpAddress "sales-team@contoso.onmicrosoft.com" `
    -Type Distribution

Add-DistributionGroupMember -Identity "DL-Sales-Team" -Member "jsmith@contoso.onmicrosoft.com"
```

### Adding/removing members (routine request)

```powershell
Add-DistributionGroupMember -Identity "DL-Sales-Team" -Member "new.hire@contoso.onmicrosoft.com"
Remove-DistributionGroupMember -Identity "DL-Sales-Team" -Member "departed.user@contoso.onmicrosoft.com" -Confirm:$false
```

Verify current membership before closing the ticket:

```powershell
Get-DistributionGroupMember -Identity "DL-Sales-Team" | Select-Object Name, PrimarySmtpAddress
```

## Part 2 — Creating a shared mailbox

Shared mailboxes don't require a license for basic use (under the
per-tenant free storage allowance) as long as no one needs an Exchange
Online Plan without it, or in-place archive/litigation hold, which does
require licensing that mailbox.

### Via EAC

1. **admin.exchange.microsoft.com** → **Recipients** → **Mailboxes** →
   **Add a shared mailbox**.
2. Name: `Support Team`, email: `support@contoso.onmicrosoft.com`.
3. After creation, click into it → **Delegation** → add members under
   **Read and manage permissions** (this grants both Send As and Full
   Access in one step via the EAC's simplified flow) or configure the two
   separately for more granular control (see below).

### Via PowerShell

```powershell
New-Mailbox -Shared -Name "Support Team" `
    -DisplayName "Support Team" `
    -PrimarySmtpAddress "support@contoso.onmicrosoft.com"
```

### Granting access: Full Access vs. Send As vs. Send on Behalf

These are three distinct permissions and requests often conflate them —
worth clarifying with the requester which one they actually need:

```powershell
# Full Access — can open the mailbox, read/organize mail, but sent mail
# shows as coming from the shared mailbox itself with no "on behalf of" tag
Add-MailboxPermission -Identity "support@contoso.onmicrosoft.com" `
    -User "jsmith@contoso.onmicrosoft.com" -AccessRights FullAccess -InheritanceType All

# Send As — mail sent through this mailbox appears to come directly from
# it, no indication a delegate sent it
Add-RecipientPermission -Identity "support@contoso.onmicrosoft.com" `
    -Trustee "jsmith@contoso.onmicrosoft.com" -AccessRights SendAs -Confirm:$false

# Send on Behalf — recipients see "jsmith on behalf of Support Team" —
# useful when accountability for who actually sent it matters
Set-Mailbox -Identity "support@contoso.onmicrosoft.com" `
    -GrantSendOnBehalfTo @{Add="jsmith@contoso.onmicrosoft.com"}
```

Most help desk requests for "add me to the support inbox" mean **Full
Access**; only grant **Send As** when the requester specifically needs
outbound mail to look fully native to that mailbox.

## Part 3 — Converting a user mailbox to shared (offboarding)

Common request when someone leaves but the team still needs historical
access to their mail (e.g. a departed account manager's inbox).

```powershell
# Convert the mailbox type
Set-Mailbox -Identity "departed.user@contoso.onmicrosoft.com" -Type Shared

# Grant the relevant manager/team Full Access
Add-MailboxPermission -Identity "departed.user@contoso.onmicrosoft.com" `
    -User "manager@contoso.onmicrosoft.com" -AccessRights FullAccess -InheritanceType All

# Remove the now-unneeded license (shared mailboxes over ~50GB in some
# tenant tiers still need a license, but converting reclaims the license
# seat in most standard cases — verify current tenant sizing before removing)
Set-MgUserLicense -UserId "departed.user@contoso.onmicrosoft.com" `
    -AddLicenses @() -RemoveLicenses @((Get-MgSubscribedSku | Where-Object SkuPartNumber -eq "SPE_E3").SkuId)
```

## Cleanup / periodic review

- Quarterly: run `Get-DistributionGroup | Get-DistributionGroupMember` and
  cross-check membership against current org chart / active employees —
  DLs accumulate departed-user entries if offboarding doesn't
  systematically clean them up (see
  `runbooks/linux/user-provisioning-and-offboarding.md`'s Windows-side
  equivalent for the offboarding checklist this should be part of).
- Audit shared mailboxes for Full Access grants that are no longer needed
  (role changes, team reorgs) — stale access here is a common finding in
  access reviews.
