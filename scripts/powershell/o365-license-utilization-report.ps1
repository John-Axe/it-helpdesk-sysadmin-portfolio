<#
.SYNOPSIS
    Reports Microsoft 365 license SKU utilization (assigned vs. available)
    and flags users with disabled accounts still holding a license.

.DESCRIPTION
    Queries license SKUs and per-user assignments via the Microsoft Graph
    PowerShell SDK and reports consumption against purchased seats per SKU,
    plus a list of disabled/blocked user accounts that still have one or
    more licenses assigned (a common source of avoidable license spend).
    Designed as a lab/practice script for a fictitious
    contoso.onmicrosoft.com tenant.

    Read-only by default. Reclaiming licenses from disabled accounts
    requires both -ReclaimFromDisabled AND -Apply.

.PARAMETER ReclaimFromDisabled
    Switch. Indicates intent to remove all license assignments from
    disabled user accounts found during the audit. Has no effect unless
    combined with -Apply.

.PARAMETER Apply
    Switch. Required in addition to -ReclaimFromDisabled to actually make
    changes. Without it, the script only reports.

.PARAMETER ExportCsv
    Optional path to export the per-user license report as CSV.

.EXAMPLE
    .\o365-license-utilization-report.ps1
    Reports SKU utilization and any disabled accounts still licensed.
    Makes no changes.

.EXAMPLE
    .\o365-license-utilization-report.ps1 -ReclaimFromDisabled -Apply
    Reports AND removes all licenses from disabled accounts found.

.NOTES
    Requires the Microsoft.Graph.Users and Microsoft.Graph.Identity.DirectoryManagement
    modules and an authenticated Graph session with User.Read.All and
    Organization.Read.All scopes (User.ReadWrite.All additionally required
    for -ReclaimFromDisabled -Apply):

        Connect-MgGraph -Scopes "User.Read.All","Organization.Read.All"

    SKU display names (e.g. "SPE_E3") are Microsoft's internal product
    names and don't always match the marketing name shown in the admin
    center — cross-reference against Microsoft's licensing SKU reference
    if a friendlier name is needed for reporting to non-technical stakeholders.

    This script was authored and syntax-verified but not executed against
    a real tenant — review before running against production.
#>

[CmdletBinding()]
param(
    [switch]$ReclaimFromDisabled,

    [switch]$Apply,

    [string]$ExportCsv
)

Import-Module Microsoft.Graph.Users -ErrorAction Stop
Import-Module Microsoft.Graph.Identity.DirectoryManagement -ErrorAction Stop

if (-not (Get-MgContext)) {
    Write-Error "Not connected to Microsoft Graph. Run Connect-MgGraph -Scopes 'User.Read.All','Organization.Read.All' first."
    return
}

Write-Host "Pulling license SKU inventory..." -ForegroundColor Cyan
$skus = Get-MgSubscribedSku -All

$skuReport = foreach ($sku in $skus) {
    [PSCustomObject]@{
        SkuPartNumber = $sku.SkuPartNumber
        TotalSeats    = $sku.PrepaidUnits.Enabled
        Consumed      = $sku.ConsumedUnits
        Available     = $sku.PrepaidUnits.Enabled - $sku.ConsumedUnits
        UtilizationPct = if ($sku.PrepaidUnits.Enabled -gt 0) {
            [math]::Round(($sku.ConsumedUnits / $sku.PrepaidUnits.Enabled) * 100, 1)
        } else { 0 }
    }
}

Write-Host "`n== SKU utilization ==" -ForegroundColor Cyan
$skuReport | Sort-Object UtilizationPct -Descending | Format-Table -AutoSize

Write-Host "Pulling per-user license assignments (this may take a while for a large tenant)..." -ForegroundColor Cyan
$allUsers = Get-MgUser -All -Property Id, DisplayName, UserPrincipalName, AccountEnabled, AssignedLicenses

$licensedUsers = $allUsers | Where-Object { $_.AssignedLicenses.Count -gt 0 }
$disabledLicensed = $licensedUsers | Where-Object { $_.AccountEnabled -eq $false }

$userReport = foreach ($user in $licensedUsers) {
    $skuNames = ($user.AssignedLicenses | ForEach-Object {
        ($skus | Where-Object { $_.SkuId -eq $_.SkuId }).SkuPartNumber
    }) -join ', '

    [PSCustomObject]@{
        DisplayName       = $user.DisplayName
        UserPrincipalName = $user.UserPrincipalName
        AccountEnabled    = $user.AccountEnabled
        LicenseCount      = $user.AssignedLicenses.Count
        UserId            = $user.Id
    }
}

Write-Host "`n== Disabled accounts still holding a license ==" -ForegroundColor Yellow
if ($disabledLicensed) {
    $userReport | Where-Object { $_.AccountEnabled -eq $false } | Format-Table DisplayName, UserPrincipalName, LicenseCount -AutoSize
    Write-Host "Found $($disabledLicensed.Count) disabled account(s) with a license still assigned." -ForegroundColor Red
}
else {
    Write-Host "None found — no license reclamation opportunity from disabled accounts." -ForegroundColor Green
}

if ($ExportCsv) {
    $userReport | Export-Csv -Path $ExportCsv -NoTypeInformation
    Write-Host "`nExported per-user license report to $ExportCsv" -ForegroundColor Cyan
}

if ($ReclaimFromDisabled -and $Apply) {
    if (-not $disabledLicensed) {
        Write-Host "`nNo disabled/licensed accounts to reclaim from." -ForegroundColor Green
    }
    else {
        Write-Host "`nRemoving all license assignments from $($disabledLicensed.Count) disabled account(s)..." -ForegroundColor Red
        foreach ($user in $disabledLicensed) {
            try {
                $skuIdsToRemove = $user.AssignedLicenses | Select-Object -ExpandProperty SkuId
                Set-MgUserLicense -UserId $user.Id -AddLicenses @() -RemoveLicenses $skuIdsToRemove -ErrorAction Stop
                Write-Host "  Reclaimed license(s) from $($user.UserPrincipalName)" -ForegroundColor DarkYellow
            }
            catch {
                Write-Warning "  Failed to reclaim license(s) from $($user.UserPrincipalName): $($_.Exception.Message)"
            }
        }
    }
}
elseif ($ReclaimFromDisabled -and -not $Apply) {
    Write-Host "`n-ReclaimFromDisabled was passed without -Apply — no licenses were removed. Add -Apply to actually reclaim them." -ForegroundColor Yellow
}
else {
    Write-Host "`nReport-only run. Pass -ReclaimFromDisabled -Apply together to remove licenses from disabled accounts." -ForegroundColor DarkGray
}
