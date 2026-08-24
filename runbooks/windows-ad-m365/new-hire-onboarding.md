# SOP — New-hire onboarding (AD account + M365 license + Intune enrollment)

> Lab/practice SOP written against a fictitious `contoso.local` AD domain and
> `contoso.onmicrosoft.com` M365 tenant. Not a real employer's procedure.

## Scope

Provision a new employee's user account, mailbox, licensing, and device
enrollment before their start date. Assumes AD Connect is syncing on-prem AD
to Azure AD/Entra ID on a 30-minute cycle, and that a laptop has already
been imaged with the standard Autopilot-enrolled image.

## Prerequisites

- New-hire request ticket approved by the hiring manager with: full legal
  name, department, manager, start date, requested license type (E3/E5/F3),
  physical or remote location.
- A `Template_<Department>` AD user object exists for group-membership
  copying (e.g. `Template_Sales`).

## Steps

### 1. Create the AD account

On a domain controller or RSAT workstation, in **Active Directory Users and
Computers**:

1. Navigate to the correct OU (e.g. `OU=Sales,OU=Users,DC=contoso,DC=local`).
2. Right-click → **New** → **User**.
3. Fill in: First name, Last name, **User logon name** in
   `firstinitiallastname` format (e.g. `jsmith`), matching the naming
   convention documented in the team wiki.
4. Set a temporary complex password, check **User must change password at
   next logon**, leave **Account is disabled** unchecked only if the start
   date is today — otherwise leave it **checked** until the morning of
   day one.

Equivalent PowerShell (see `scripts/powershell/bulk-ad-user-creation.ps1`
for the CSV-driven bulk version of this same step):

```powershell
New-ADUser -Name "Jane Smith" -GivenName "Jane" -Surname "Smith" `
    -SamAccountName "jsmith" -UserPrincipalName "jsmith@contoso.local" `
    -Path "OU=Sales,OU=Users,DC=contoso,DC=local" `
    -AccountPassword (ConvertTo-SecureString "TempP@ssw0rd!23" -AsPlainText -Force) `
    -ChangePasswordAtLogon $true -Enabled $false
```

### 2. Copy group memberships from the department template

```powershell
$templateGroups = Get-ADUser -Identity "Template_Sales" -Properties MemberOf |
    Select-Object -ExpandProperty MemberOf
foreach ($group in $templateGroups) {
    Add-ADGroupMember -Identity $group -Members "jsmith"
}
```

Verify:

```powershell
Get-ADUser -Identity "jsmith" -Properties MemberOf |
    Select-Object -ExpandProperty MemberOf
```

### 3. Wait for AAD Connect sync (or force it)

On the AAD Connect server:

```powershell
Start-ADSyncSyncCycle -PolicyType Delta
```

Confirm the account appears in Entra ID:

```powershell
Get-MgUser -Filter "userPrincipalName eq 'jsmith@contoso.local'"
```

### 4. Assign the M365 license

In the **Microsoft 365 admin center** (`admin.microsoft.com`) →
**Users** → **Active users** → select the new user → **Licenses and Apps**
tab → select the requested SKU (e.g. `Microsoft 365 E3`) → **Save changes**.

Equivalent via PowerShell (Microsoft Graph SDK):

```powershell
Set-MgUserLicense -UserId "jsmith@contoso.local" `
    -AddLicenses @{SkuId = (Get-MgSubscribedSku | Where-Object SkuPartNumber -eq "SPE_E3").SkuId} `
    -RemoveLicenses @()
```

Wait 5-10 minutes for provisioning; confirm Exchange Online mailbox exists:

```powershell
Get-EXOMailbox -Identity "jsmith@contoso.local"
```

### 5. Enable and configure the mailbox

- Confirm the correct **mailbox database/region** and time zone default.
- Set a reasonable default calendar-sharing policy if the org uses one.
- If the role requires a shared mailbox membership (e.g. `sales@contoso...`),
  add it here — see
  `runbooks/windows-ad-m365/distribution-list-shared-mailbox-management.md`.

### 6. Assign the device via Autopilot / Intune

1. Confirm the laptop's hardware hash was uploaded to **Windows Autopilot**
   before shipping (done by imaging team, verify in **Intune admin center**
   → **Devices** → **Enrollment** → **Windows Autopilot devices**).
2. Assign the correct **Autopilot deployment profile** and **group tag**
   matching the user's department, so the right App/config groups target
   the device automatically.
3. On first boot, the user signs in with their new AD/Entra credentials;
   Autopilot completes Out-of-Box Experience (OOBE), enrolls in Intune, and
   applies the department's app/policy assignments automatically.
4. Confirm enrollment completed in **Intune admin center** → **Devices** →
   search the device name → **Compliance** should show `Compliant` within
   ~30-60 minutes of first sign-in (full walkthrough of monitoring this in
   `runbooks/windows-ad-m365/intune-device-enrollment-walkthrough.md`).

### 7. Day-one checklist

- [ ] AD account enabled the morning of start date
- [ ] Temporary password handed to manager/IT contact securely (never
      emailed in plaintext)
- [ ] Mailbox accessible, test email sent/received
- [ ] Device shows `Compliant` in Intune
- [ ] User added to any team-specific distribution lists / Teams channels
- [ ] Manager notified account is ready

## Rollback / error handling

- If AAD Connect sync doesn't pick up the account within 30 minutes of a
  forced delta sync, check
  `Get-ADSyncConnectorRunStatus` and the AAD Connect event log for sync
  errors (commonly a duplicate `proxyAddress` or `UPN` conflict).
- If licensing fails silently, check `Get-MgUser -UserId ... -Property
  AssignedLicenses` for a `licenseAssignmentStates` error — usually means
  the tenant is out of available seats for that SKU.
