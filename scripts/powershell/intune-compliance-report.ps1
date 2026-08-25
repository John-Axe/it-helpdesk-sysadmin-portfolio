<#
.SYNOPSIS
    Reports Intune-managed device compliance status, flagging non-compliant
    and stale-checkin devices.

.DESCRIPTION
    Queries Intune-managed devices via the Microsoft Graph PowerShell SDK
    and reports each device's compliance state, last check-in time, and OS.
    Designed as a lab/practice script for a fictitious
    contoso.onmicrosoft.com tenant.

    Read-only by default — reports only, never remediates. The optional
    -Remediate switch (combined with -Apply) only ever sends a
    "sync device" request to non-compliant devices to force a fresh policy
    evaluation; it does not change any device or policy configuration.

.PARAMETER StaleCheckinDays
    Flag devices whose last check-in is older than this many days, even if
    currently reported compliant (a stale check-in means compliance state
    itself may be out of date). Default 14.

.PARAMETER Remediate
    Switch. Indicates intent to trigger a remote sync on non-compliant
    devices. Has no effect unless combined with -Apply.

.PARAMETER Apply
    Switch. Required in addition to -Remediate to actually send sync
    requests. Without it, the script only reports.

.PARAMETER ExportCsv
    Optional path to export the full report as CSV.

.EXAMPLE
    .\intune-compliance-report.ps1
    Reports compliance status for all managed devices. Makes no changes.

.EXAMPLE
    .\intune-compliance-report.ps1 -Remediate -Apply
    Reports AND triggers a remote sync on every non-compliant device.

.NOTES
    Requires the Microsoft.Graph.DeviceManagement module and an
    authenticated Graph session with DeviceManagementManagedDevices.Read.All
    (and DeviceManagementManagedDevices.PrivilegedOperations.All if using
    -Remediate -Apply) scopes:

        Connect-MgGraph -Scopes "DeviceManagementManagedDevices.Read.All"

    This script was authored and syntax-verified but not executed against
    a real tenant — review before running against production.
#>

[CmdletBinding()]
param(
    [int]$StaleCheckinDays = 14,

    [switch]$Remediate,

    [switch]$Apply,

    [string]$ExportCsv
)

Import-Module Microsoft.Graph.DeviceManagement -ErrorAction Stop

if (-not (Get-MgContext)) {
    Write-Error "Not connected to Microsoft Graph. Run Connect-MgGraph -Scopes 'DeviceManagementManagedDevices.Read.All' first."
    return
}

$staleCutoff = (Get-Date).AddDays(-$StaleCheckinDays)
Write-Host "Pulling Intune managed device inventory..." -ForegroundColor Cyan

$devices = Get-MgDeviceManagementManagedDevice -All

$report = foreach ($device in $devices) {
    $lastSync = $device.LastSyncDateTime
    $isStale = $lastSync -lt $staleCutoff

    [PSCustomObject]@{
        DeviceName      = $device.DeviceName
        UserPrincipalName = $device.UserPrincipalName
        OperatingSystem = $device.OperatingSystem
        OsVersion       = $device.OsVersion
        ComplianceState = $device.ComplianceState
        LastSyncDateTime = $lastSync
        StaleCheckin    = $isStale
        ManagementAgent = $device.ManagementAgent
        DeviceId        = $device.Id
    }
}

$nonCompliant = $report | Where-Object { $_.ComplianceState -eq 'noncompliant' }
$staleDevices = $report | Where-Object { $_.StaleCheckin }

$report | Sort-Object ComplianceState, DeviceName |
    Format-Table DeviceName, UserPrincipalName, OperatingSystem, ComplianceState, LastSyncDateTime, StaleCheckin -AutoSize

Write-Host "`nSummary: $($report.Count) total devices, $($nonCompliant.Count) non-compliant, $($staleDevices.Count) with check-in older than $StaleCheckinDays days." -ForegroundColor Yellow

if ($ExportCsv) {
    $report | Export-Csv -Path $ExportCsv -NoTypeInformation
    Write-Host "Exported full report to $ExportCsv" -ForegroundColor Cyan
}

if ($Remediate -and $Apply) {
    if (-not $nonCompliant) {
        Write-Host "`nNo non-compliant devices to remediate." -ForegroundColor Green
    }
    else {
        Write-Host "`nTriggering remote sync on $($nonCompliant.Count) non-compliant device(s)..." -ForegroundColor Red
        foreach ($device in $nonCompliant) {
            try {
                Sync-MgDeviceManagementManagedDevice -ManagedDeviceId $device.DeviceId -ErrorAction Stop
                Write-Host "  Sync requested: $($device.DeviceName)" -ForegroundColor DarkYellow
            }
            catch {
                Write-Warning "  Failed to request sync for $($device.DeviceName): $($_.Exception.Message)"
            }
        }
    }
}
elseif ($Remediate -and -not $Apply) {
    Write-Host "`n-Remediate was passed without -Apply — no sync requests were sent. Add -Apply to actually trigger them." -ForegroundColor Yellow
}
else {
    Write-Host "`nReport-only run. Pass -Remediate -Apply together to trigger a remote sync on non-compliant devices." -ForegroundColor DarkGray
}
