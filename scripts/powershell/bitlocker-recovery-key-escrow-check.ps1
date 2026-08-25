<#
.SYNOPSIS
    Audits AD-joined computer objects for BitLocker recovery key escrow,
    flagging devices with no recovery password on file in AD.

.DESCRIPTION
    Checks each computer object under -SearchBase for at least one
    associated msFVE-RecoveryInformation object (the AD DS record created
    when a BitLocker recovery password is escrowed via Group Policy) and
    reports which devices have no escrowed key at all — a business
    continuity gap, since those devices cannot be recovered through the
    standard help-desk procedure if a user is ever locked out. Designed as
    a lab/practice script for a fictitious contoso.local domain. See
    runbooks/windows-ad-m365/bitlocker-recovery-procedure.md for the
    manual lookup and recovery process this script's findings feed into.

    Read-only by default. This script never modifies BitLocker state or
    forces re-encryption — the optional -NotifyMissing switch (with
    -Apply) only sends an email notification to the addresses in
    -NotifyTo listing devices with missing escrow, for follow-up by the
    endpoint team.

.PARAMETER SearchBase
    AD OU/container to search for computer objects. Defaults to the whole
    domain if omitted.

.PARAMETER NotifyMissing
    Switch. Indicates intent to email a summary of devices with missing
    escrow. Has no effect unless combined with -Apply.

.PARAMETER Apply
    Switch. Required in addition to -NotifyMissing to actually send the
    notification email. Without it, the script only reports to the console.

.PARAMETER NotifyTo
    Email address(es) to notify when -NotifyMissing -Apply is used.

.PARAMETER SmtpServer
    SMTP relay to use for the notification email. Required only if
    -NotifyMissing -Apply is used.

.PARAMETER ExportCsv
    Optional path to export the full audit results as CSV.

.EXAMPLE
    .\bitlocker-recovery-key-escrow-check.ps1
    Reports all AD-joined computers with no BitLocker recovery key escrowed
    in AD. Makes no changes, sends no email.

.EXAMPLE
    .\bitlocker-recovery-key-escrow-check.ps1 -NotifyMissing -Apply -NotifyTo "endpoint-team@contoso.local" -SmtpServer smtp.contoso.local
    Reports AND emails the endpoint team a summary of devices missing escrow.

.NOTES
    Requires the ActiveDirectory PowerShell module and read rights on
    msFVE-RecoveryInformation child objects under the target SearchBase.
    Does not distinguish "device isn't encrypted at all" from "device is
    encrypted but escrow failed" — cross-reference against an endpoint
    inventory/compliance source (e.g. Intune) for encryption state if that
    distinction matters for the audit.

    This script was authored and syntax-verified but not executed against
    a real tenant — review before running against production.
#>

[CmdletBinding()]
param(
    [string]$SearchBase,

    [switch]$NotifyMissing,

    [switch]$Apply,

    [string[]]$NotifyTo,

    [string]$SmtpServer,

    [string]$ExportCsv
)

Import-Module ActiveDirectory -ErrorAction Stop

$getComputerParams = @{
    Filter     = '*'
    Properties = @('DistinguishedName', 'OperatingSystem', 'LastLogonTimestamp')
}
if ($SearchBase) {
    $getComputerParams['SearchBase'] = $SearchBase
}

Write-Host "Enumerating computer objects..." -ForegroundColor Cyan
$computers = Get-ADComputer @getComputerParams

$results = foreach ($computer in $computers) {
    $recoveryObjects = Get-ADObject -Filter { objectClass -eq 'msFVE-RecoveryInformation' } `
        -SearchBase $computer.DistinguishedName -Properties whenCreated -ErrorAction SilentlyContinue

    $hasEscrow = [bool]($recoveryObjects | Measure-Object).Count
    $mostRecent = if ($recoveryObjects) {
        ($recoveryObjects | Sort-Object whenCreated -Descending | Select-Object -First 1).whenCreated
    } else { $null }

    [PSCustomObject]@{
        ComputerName      = $computer.Name
        OperatingSystem   = $computer.OperatingSystem
        HasEscrowedKey    = $hasEscrow
        RecoveryKeyCount  = ($recoveryObjects | Measure-Object).Count
        MostRecentKeyDate = $mostRecent
        DistinguishedName = $computer.DistinguishedName
    }
}

$missing = $results | Where-Object { -not $_.HasEscrowedKey }

$results | Sort-Object HasEscrowedKey, ComputerName |
    Format-Table ComputerName, OperatingSystem, HasEscrowedKey, RecoveryKeyCount, MostRecentKeyDate -AutoSize

Write-Host "`nSummary: $($results.Count) computer(s) checked, $($missing.Count) with no BitLocker recovery key escrowed in AD." -ForegroundColor Yellow

if ($missing) {
    Write-Host "`nDevices with NO escrowed recovery key:" -ForegroundColor Red
    $missing | Format-Table ComputerName, OperatingSystem -AutoSize
}

if ($ExportCsv) {
    $results | Export-Csv -Path $ExportCsv -NoTypeInformation
    Write-Host "Exported results to $ExportCsv" -ForegroundColor Cyan
}

if ($NotifyMissing -and $Apply) {
    if (-not $missing) {
        Write-Host "`nNo devices missing escrow — no notification sent." -ForegroundColor Green
    }
    elseif (-not $NotifyTo -or -not $SmtpServer) {
        Write-Warning "`n-NotifyMissing -Apply requires both -NotifyTo and -SmtpServer. No email sent."
    }
    else {
        $body = "Devices with no BitLocker recovery key escrowed in AD as of $(Get-Date -Format 'yyyy-MM-dd'):`n`n"
        $body += ($missing | ForEach-Object { "  $($_.ComputerName) ($($_.OperatingSystem))" }) -join "`n"

        try {
            Send-MailMessage -To $NotifyTo -From "bitlocker-audit@contoso.local" `
                -Subject "BitLocker escrow audit — $($missing.Count) device(s) missing recovery key" `
                -Body $body -SmtpServer $SmtpServer -ErrorAction Stop
            Write-Host "`nNotification email sent to $($NotifyTo -join ', ')" -ForegroundColor DarkYellow
        }
        catch {
            Write-Warning "Failed to send notification email: $($_.Exception.Message)"
        }
    }
}
elseif ($NotifyMissing -and -not $Apply) {
    Write-Host "`n-NotifyMissing was passed without -Apply — no email was sent. Add -Apply to actually send it." -ForegroundColor Yellow
}
else {
    Write-Host "`nReport-only run. Pass -NotifyMissing -Apply together to email a summary of devices missing escrow." -ForegroundColor DarkGray
}
