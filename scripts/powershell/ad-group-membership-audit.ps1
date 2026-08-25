<#
.SYNOPSIS
    Audits membership of one or more sensitive Active Directory groups and
    flags members that don't appear on an expected-membership allowlist.

.DESCRIPTION
    Reports current (including nested, by default) membership of specified
    AD groups — intended for periodically reviewing privileged groups like
    Domain Admins — and compares against an optional allowlist CSV to flag
    unexpected additions. Designed as a lab/practice script for a
    fictitious contoso.local domain.

    Read-only by default. Removing a flagged (unexpected) member requires
    both -RemoveUnexpected AND -Apply — a deliberate two-flag guard, since
    removing someone from a privileged group is a high-impact action that
    should never happen from a single accidental flag.

.PARAMETER GroupName
    One or more AD group names to audit (e.g. "Domain Admins",
    "Enterprise Admins", "Backup Operators").

.PARAMETER AllowlistCsv
    Optional path to a CSV with a SamAccountName column listing expected
    members. Any current member NOT in this list is flagged. If omitted,
    the script reports full current membership without flagging anything.

.PARAMETER RemoveUnexpected
    Switch. Indicates intent to remove flagged (unexpected) members from
    the audited group(s). Has no effect unless combined with -Apply.

.PARAMETER Apply
    Switch. Required in addition to -RemoveUnexpected to actually make
    changes. Without it, the script only reports.

.PARAMETER ExportCsv
    Optional path to export the full audit results as CSV.

.EXAMPLE
    .\ad-group-membership-audit.ps1 -GroupName "Domain Admins"
    Reports current Domain Admins membership (including nested). No
    allowlist comparison, no changes.

.EXAMPLE
    .\ad-group-membership-audit.ps1 -GroupName "Domain Admins" -AllowlistCsv .\da-allowlist.csv
    Reports membership and flags anyone not in the allowlist.

.EXAMPLE
    .\ad-group-membership-audit.ps1 -GroupName "Domain Admins" -AllowlistCsv .\da-allowlist.csv -RemoveUnexpected -Apply
    Reports, flags, AND removes unexpected members from the group.

.NOTES
    Requires the ActiveDirectory PowerShell module and, for
    -RemoveUnexpected -Apply, rights to modify membership of the target
    group(s) — which for a group like Domain Admins is itself a
    privileged operation and should be performed by a dedicated,
    monitored admin account, not a standing daily-use account.

    Sample allowlist CSV format:
        SamAccountName
        jsmith
        svc-backup-admin
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string[]]$GroupName,

    [string]$AllowlistCsv,

    [switch]$RemoveUnexpected,

    [switch]$Apply,

    [string]$ExportCsv
)

Import-Module ActiveDirectory -ErrorAction Stop

$allowlist = $null
if ($AllowlistCsv) {
    if (-not (Test-Path $AllowlistCsv -PathType Leaf)) {
        Write-Error "Allowlist CSV not found: $AllowlistCsv"
        return
    }
    $allowlist = (Import-Csv -Path $AllowlistCsv).SamAccountName
}

$results = foreach ($group in $GroupName) {
    Write-Host "Auditing group: $group ..." -ForegroundColor Cyan

    try {
        $members = Get-ADGroupMember -Identity $group -Recursive -ErrorAction Stop |
            Where-Object { $_.objectClass -eq 'user' }
    }
    catch {
        Write-Warning "Could not read membership of '$group': $($_.Exception.Message)"
        continue
    }

    foreach ($member in $members) {
        $userDetail = Get-ADUser -Identity $member.SamAccountName -Properties Enabled, whenCreated, LastLogonDate

        $isExpected = if ($allowlist) { $allowlist -contains $member.SamAccountName } else { $null }

        [PSCustomObject]@{
            Group          = $group
            SamAccountName = $member.SamAccountName
            Name           = $member.Name
            Enabled        = $userDetail.Enabled
            LastLogonDate  = $userDetail.LastLogonDate
            ExpectedMember = $isExpected
        }
    }
}

if (-not $results) {
    Write-Host "No members found across the specified group(s)." -ForegroundColor Yellow
    return
}

$results | Sort-Object Group, SamAccountName | Format-Table Group, SamAccountName, Name, Enabled, LastLogonDate, ExpectedMember -AutoSize

$unexpected = @()
if ($allowlist) {
    $unexpected = $results | Where-Object { $_.ExpectedMember -eq $false }
    if ($unexpected) {
        Write-Host "`nFLAGGED — members not on the allowlist:" -ForegroundColor Red
        $unexpected | Format-Table Group, SamAccountName, Name -AutoSize
    }
    else {
        Write-Host "`nNo unexpected members found — all current members match the allowlist." -ForegroundColor Green
    }
}
else {
    Write-Host "`nNo -AllowlistCsv provided — reported full membership only, nothing flagged." -ForegroundColor DarkGray
}

if ($ExportCsv) {
    $results | Export-Csv -Path $ExportCsv -NoTypeInformation
    Write-Host "Exported results to $ExportCsv" -ForegroundColor Cyan
}

if ($RemoveUnexpected -and $Apply) {
    if (-not $unexpected) {
        Write-Host "`nNo unexpected members to remove." -ForegroundColor Green
    }
    else {
        Write-Host "`nRemoving $($unexpected.Count) unexpected member(s)..." -ForegroundColor Red
        foreach ($entry in $unexpected) {
            try {
                Remove-ADGroupMember -Identity $entry.Group -Members $entry.SamAccountName -Confirm:$false -ErrorAction Stop
                Write-Host "  Removed $($entry.SamAccountName) from $($entry.Group)" -ForegroundColor DarkYellow
            }
            catch {
                Write-Warning "  Failed to remove $($entry.SamAccountName) from $($entry.Group): $($_.Exception.Message)"
            }
        }
    }
}
elseif ($RemoveUnexpected -and -not $Apply) {
    Write-Host "`n-RemoveUnexpected was passed without -Apply — no members were removed. Add -Apply to actually remove them." -ForegroundColor Yellow
}
else {
    Write-Host "`nReport-only run. Pass -RemoveUnexpected -Apply together to remove flagged members from the group(s)." -ForegroundColor DarkGray
}
