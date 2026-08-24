<#
.SYNOPSIS
    Audits Active Directory for user accounts inactive longer than a given
    threshold and, optionally, disables them.

.DESCRIPTION
    Reports enabled AD user accounts whose LastLogonTimestamp (or, if never
    logged on, whose creation date) exceeds -DaysInactive days. Designed as
    a lab/practice script for a fictitious contoso.local domain.

    Runs in report-only mode by default. Disabling accounts requires both
    -Disable AND -Apply — a deliberate two-flag guard so a single accidental
    switch can't take a destructive action.

.PARAMETER DaysInactive
    Inactivity threshold in days. Default 90.

.PARAMETER SearchBase
    AD OU/container to search. Defaults to the whole domain if omitted.

.PARAMETER Disable
    Switch. Indicates intent to disable stale accounts. Has no effect
    unless combined with -Apply.

.PARAMETER Apply
    Switch. Required in addition to -Disable to actually make changes.
    Without it, the script only reports.

.PARAMETER ExportCsv
    Optional path to export the audit results as CSV.

.EXAMPLE
    .\stale-account-audit.ps1 -DaysInactive 90
    Reports accounts inactive 90+ days. Makes no changes.

.EXAMPLE
    .\stale-account-audit.ps1 -DaysInactive 120 -Disable -Apply
    Reports AND disables accounts inactive 120+ days.

.NOTES
    Requires the ActiveDirectory module and read (and, if -Disable -Apply
    is used, write) permissions on the target accounts.

    LastLogonTimestamp is replicated between DCs (unlike LastLogon, which
    is per-DC and not replicated) but can lag the true last logon by up to
    14 days by default (ms-DS-Logon-Time-Sync-Interval). That's acceptable
    slack for a stale-account audit; it is not precise enough for
    security-incident timeline reconstruction.
#>

[CmdletBinding()]
param(
    [int]$DaysInactive = 90,

    [string]$SearchBase,

    [switch]$Disable,

    [switch]$Apply,

    [string]$ExportCsv
)

Import-Module ActiveDirectory -ErrorAction Stop

$cutoffDate = (Get-Date).AddDays(-$DaysInactive)
Write-Host "Auditing accounts with no logon since $($cutoffDate.ToString('yyyy-MM-dd')) ($DaysInactive days)..." -ForegroundColor Cyan

$getAdUserParams = @{
    Filter     = { Enabled -eq $true }
    Properties = @('LastLogonTimestamp', 'whenCreated', 'DistinguishedName', 'Description')
}
if ($SearchBase) {
    $getAdUserParams['SearchBase'] = $SearchBase
}

$allEnabledUsers = Get-ADUser @getAdUserParams

$staleAccounts = foreach ($user in $allEnabledUsers) {
    $lastLogon = if ($user.LastLogonTimestamp) {
        [DateTime]::FromFileTime($user.LastLogonTimestamp)
    } else {
        $null
    }

    $effectiveDate = if ($lastLogon) { $lastLogon } else { $user.whenCreated }
    $basis = if ($lastLogon) { "LastLogon" } else { "NeverLoggedOn-UsingCreationDate" }

    if ($effectiveDate -lt $cutoffDate) {
        $daysSince = [math]::Round(((Get-Date) - $effectiveDate).TotalDays)
        [PSCustomObject]@{
            SamAccountName    = $user.SamAccountName
            Name              = $user.Name
            LastActivity      = $effectiveDate
            Basis             = $basis
            DaysInactive      = $daysSince
            DistinguishedName = $user.DistinguishedName
        }
    }
}

$staleAccounts = $staleAccounts | Sort-Object DaysInactive -Descending

if (-not $staleAccounts) {
    Write-Host "No stale accounts found beyond the $DaysInactive-day threshold." -ForegroundColor Green
    return
}

$staleAccounts | Format-Table SamAccountName, Name, LastActivity, Basis, DaysInactive -AutoSize

Write-Host "`nFound $($staleAccounts.Count) stale account(s)." -ForegroundColor Yellow

if ($ExportCsv) {
    $staleAccounts | Export-Csv -Path $ExportCsv -NoTypeInformation
    Write-Host "Exported results to $ExportCsv" -ForegroundColor Cyan
}

if ($Disable -and $Apply) {
    Write-Host "`nDisabling $($staleAccounts.Count) account(s)..." -ForegroundColor Red
    foreach ($account in $staleAccounts) {
        try {
            Disable-ADAccount -Identity $account.SamAccountName -ErrorAction Stop
            Set-ADUser -Identity $account.SamAccountName `
                -Description "Disabled by stale-account-audit.ps1 on $(Get-Date -Format 'yyyy-MM-dd') — inactive $($account.DaysInactive) days" `
                -ErrorAction SilentlyContinue
            Write-Host "  Disabled: $($account.SamAccountName)" -ForegroundColor DarkYellow
        }
        catch {
            Write-Warning "  Failed to disable $($account.SamAccountName): $($_.Exception.Message)"
        }
    }
}
elseif ($Disable -and -not $Apply) {
    Write-Host "`n-Disable was passed without -Apply — no accounts were changed. Add -Apply to actually disable them." -ForegroundColor Yellow
}
else {
    Write-Host "`nReport-only run. Pass -Disable -Apply together to disable the accounts listed above." -ForegroundColor DarkGray
}
