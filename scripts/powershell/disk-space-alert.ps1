<#
.SYNOPSIS
    Checks local (or remote) disk free space and alerts when a volume falls
    below a configurable threshold.

.DESCRIPTION
    Queries fixed logical disks via CIM, reports free space and percent
    free per volume, and optionally sends an email alert (via -SmtpServer)
    when any volume drops below -ThresholdPercent. Read-only / monitoring
    script — takes no destructive action on any volume.

.PARAMETER ThresholdPercent
    Percent free space below which a volume is flagged. Default 15.

.PARAMETER ComputerName
    One or more computers to check. Defaults to the local machine.
    Remote checks require WinRM/CIM connectivity and appropriate rights.

.PARAMETER SmtpServer
    Optional SMTP relay hostname. If provided (along with -MailFrom and
    -MailTo), sends an alert email when any volume is below threshold.
    Without it, the script only prints/exits with a status code.

.PARAMETER MailFrom
    Sender address for the alert email. Required if -SmtpServer is used.

.PARAMETER MailTo
    Recipient address for the alert email. Required if -SmtpServer is used.

.EXAMPLE
    .\disk-space-alert.ps1
    Checks local disks, prints a report, exits 1 if any volume is under 15%
    free.

.EXAMPLE
    .\disk-space-alert.ps1 -ComputerName FILESRV01 -ThresholdPercent 10 `
        -SmtpServer smtp.contoso.local -MailFrom alerts@contoso.local -MailTo helpdesk@contoso.local
    Checks a remote server and emails helpdesk@contoso.local if any volume
    drops below 10% free.

.NOTES
    Exit code 0 = all volumes healthy. Exit code 1 = at least one volume
    below threshold. Suitable for use as a scheduled task with alerting
    wired to the exit code, independent of the optional email feature.
#>

[CmdletBinding()]
param(
    [ValidateRange(1, 99)]
    [int]$ThresholdPercent = 15,

    [string[]]$ComputerName = @($env:COMPUTERNAME),

    [string]$SmtpServer,

    [string]$MailFrom,

    [string]$MailTo
)

$allResults = foreach ($computer in $ComputerName) {
    try {
        $disks = Get-CimInstance -ClassName Win32_LogicalDisk -ComputerName $computer -Filter "DriveType=3" -ErrorAction Stop
    }
    catch {
        Write-Warning "Could not query $computer : $($_.Exception.Message)"
        continue
    }

    foreach ($disk in $disks) {
        if (-not $disk.Size -or $disk.Size -eq 0) { continue }
        $percentFree = [math]::Round(($disk.FreeSpace / $disk.Size) * 100, 1)
        [PSCustomObject]@{
            ComputerName   = $computer
            Drive          = $disk.DeviceID
            SizeGB         = [math]::Round($disk.Size / 1GB, 1)
            FreeGB         = [math]::Round($disk.FreeSpace / 1GB, 1)
            PercentFree    = $percentFree
            BelowThreshold = $percentFree -lt $ThresholdPercent
        }
    }
}

$allResults | Format-Table ComputerName, Drive, SizeGB, FreeGB, PercentFree, BelowThreshold -AutoSize

$flagged = $allResults | Where-Object BelowThreshold

if ($flagged) {
    Write-Host "`n$($flagged.Count) volume(s) below $ThresholdPercent% free space threshold." -ForegroundColor Red

    if ($SmtpServer -and $MailFrom -and $MailTo) {
        $body = "The following volumes are below $ThresholdPercent% free space:`n`n"
        $body += ($flagged | ForEach-Object {
            "  $($_.ComputerName) $($_.Drive) — $($_.PercentFree)% free ($($_.FreeGB) GB of $($_.SizeGB) GB)"
        }) -join "`n"

        try {
            Send-MailMessage -SmtpServer $SmtpServer -From $MailFrom -To $MailTo `
                -Subject "[Disk Space Alert] $($flagged.Count) volume(s) below threshold" `
                -Body $body -ErrorAction Stop
            Write-Host "Alert email sent to $MailTo" -ForegroundColor Cyan
        }
        catch {
            Write-Warning "Failed to send alert email: $($_.Exception.Message)"
        }
    }

    exit 1
}
else {
    Write-Host "`nAll volumes above $ThresholdPercent% free space." -ForegroundColor Green
    exit 0
}
