<#
.SYNOPSIS
    Generates a mailbox size report for all (or specified) mailboxes in an
    Exchange Online tenant.

.DESCRIPTION
    Connects to Exchange Online, pulls mailbox statistics for every mailbox
    (or a filtered subset), and reports total size, item count, and percent
    of quota used — flagging any mailbox above a configurable warning
    threshold. Read-only script; makes no changes to any mailbox.

.PARAMETER WarningThresholdPercent
    Percent of quota at which a mailbox is flagged in the report. Default 85.

.PARAMETER Department
    Optional filter — only report mailboxes whose Department attribute
    matches this value.

.PARAMETER ExportCsv
    Optional path to export the full report as CSV.

.EXAMPLE
    .\o365-mailbox-size-report.ps1
    Reports on all mailboxes in the tenant, flags anything over 85% quota.

.EXAMPLE
    .\o365-mailbox-size-report.ps1 -Department "Sales" -WarningThresholdPercent 90 -ExportCsv .\sales-mailboxes.csv

.NOTES
    Requires the ExchangeOnlineManagement module and a connected session:

        Install-Module ExchangeOnlineManagement -Scope CurrentUser
        Connect-ExchangeOnline -UserPrincipalName admin@contoso.onmicrosoft.com

    This script is read-only — it only calls Get-* cmdlets and never
    modifies mailbox configuration or content.
#>

[CmdletBinding()]
param(
    [ValidateRange(1, 100)]
    [int]$WarningThresholdPercent = 85,

    [string]$Department,

    [string]$ExportCsv
)

if (-not (Get-Command Get-EXOMailbox -ErrorAction SilentlyContinue)) {
    throw "ExchangeOnlineManagement module not found or not connected. Run Connect-ExchangeOnline first."
}

Write-Host "Retrieving mailbox list..." -ForegroundColor Cyan

$mailboxParams = @{ ResultSize = 'Unlimited' }
$mailboxes = Get-EXOMailbox @mailboxParams -Properties Department |
    Where-Object { -not $Department -or $_.Department -eq $Department }

Write-Host "Found $($mailboxes.Count) mailbox(es). Pulling size statistics..." -ForegroundColor Cyan

$report = foreach ($mailbox in $mailboxes) {
    $stats = Get-EXOMailboxStatistics -Identity $mailbox.UserPrincipalName -ErrorAction SilentlyContinue
    if (-not $stats) {
        Write-Warning "No statistics returned for $($mailbox.UserPrincipalName) — skipping."
        continue
    }

    # TotalItemSize comes back as a formatted string like "12.34 GB (13,245,678,901 bytes)"
    # Parse out the raw byte count for reliable math/sorting.
    $sizeBytes = 0
    if ($stats.TotalItemSize.Value.ToString() -match '\(([\d,]+)\s+bytes\)') {
        $sizeBytes = [int64]($matches[1] -replace ',', '')
    }
    $sizeGB = [math]::Round($sizeBytes / 1GB, 2)

    $quotaBytes = 0
    if ($mailbox.ProhibitSendQuota -and $mailbox.ProhibitSendQuota.ToString() -match '\(([\d,]+)\s+bytes\)') {
        $quotaBytes = [int64]($matches[1] -replace ',', '')
    }

    $percentUsed = if ($quotaBytes -gt 0) {
        [math]::Round(($sizeBytes / $quotaBytes) * 100, 1)
    } else {
        $null
    }

    [PSCustomObject]@{
        UserPrincipalName = $mailbox.UserPrincipalName
        DisplayName       = $mailbox.DisplayName
        Department        = $mailbox.Department
        SizeGB            = $sizeGB
        ItemCount         = $stats.ItemCount
        PercentOfQuota    = $percentUsed
        OverThreshold     = if ($percentUsed) { $percentUsed -ge $WarningThresholdPercent } else { $false }
    }
}

$report = $report | Sort-Object SizeGB -Descending

$report | Format-Table UserPrincipalName, DisplayName, SizeGB, ItemCount, PercentOfQuota, OverThreshold -AutoSize

$flagged = $report | Where-Object OverThreshold
if ($flagged) {
    Write-Host "`n$($flagged.Count) mailbox(es) at or above $WarningThresholdPercent% of quota:" -ForegroundColor Red
    $flagged | ForEach-Object { Write-Host "  $($_.UserPrincipalName): $($_.PercentOfQuota)%" -ForegroundColor Red }
} else {
    Write-Host "`nNo mailboxes at or above the $WarningThresholdPercent% threshold." -ForegroundColor Green
}

if ($ExportCsv) {
    $report | Export-Csv -Path $ExportCsv -NoTypeInformation
    Write-Host "`nExported full report to $ExportCsv" -ForegroundColor Cyan
}
