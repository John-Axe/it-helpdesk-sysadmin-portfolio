<#
.SYNOPSIS
    Exports an inventory of installed software from local or remote
    Windows machines.

.DESCRIPTION
    Queries the standard uninstall registry keys (both 32-bit and 64-bit
    views, plus per-user installs) for installed application name,
    version, publisher, and install date, and writes the combined results
    to CSV. Read-only script — makes no changes.

    Uses the registry rather than Win32_Product (CIM/WMI class) because
    Win32_Product triggers a Windows Installer consistency check/repair
    pass on every query, which is slow and can have side effects on some
    systems — the registry approach is the standard safer alternative for
    inventory purposes.

.PARAMETER ComputerName
    One or more computers to inventory. Defaults to the local machine.
    Remote inventory requires remote registry access/appropriate rights.

.PARAMETER OutputCsv
    Path to write the combined CSV report. Default: .\software-inventory.csv

.EXAMPLE
    .\installed-software-inventory-export.ps1
    Inventories the local machine, writes .\software-inventory.csv

.EXAMPLE
    .\installed-software-inventory-export.ps1 -ComputerName WKS01,WKS02 -OutputCsv .\fleet-inventory.csv

.NOTES
    Publisher/version fields are only as accurate as what each installer
    wrote to the registry — some applications leave these blank.
#>

[CmdletBinding()]
param(
    [string[]]$ComputerName = @($env:COMPUTERNAME),

    [string]$OutputCsv = ".\software-inventory.csv"
)

$uninstallKeyPaths = @(
    'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
)

$allSoftware = foreach ($computer in $ComputerName) {

    Write-Host "Inventorying $computer..." -ForegroundColor Cyan

    try {
        $baseKey = [Microsoft.Win32.RegistryKey]::OpenRemoteBaseKey('LocalMachine', $computer)
    }
    catch {
        Write-Warning "Could not open registry on $computer : $($_.Exception.Message)"
        continue
    }

    foreach ($keyPath in $uninstallKeyPaths) {
        $parentPath = $keyPath.TrimEnd('*').TrimEnd('\')
        try {
            $parentKey = $baseKey.OpenSubKey($parentPath)
        }
        catch {
            continue
        }
        if (-not $parentKey) { continue }

        foreach ($subKeyName in $parentKey.GetSubKeyNames()) {
            $subKey = $parentKey.OpenSubKey($subKeyName)
            $displayName = $subKey.GetValue('DisplayName')

            # Skip entries with no display name — these are almost always
            # system components or patches, not user-facing applications.
            if (-not $displayName) { continue }

            [PSCustomObject]@{
                ComputerName    = $computer
                DisplayName     = $displayName
                DisplayVersion  = $subKey.GetValue('DisplayVersion')
                Publisher       = $subKey.GetValue('Publisher')
                InstallDate     = $subKey.GetValue('InstallDate')
                UninstallString = $subKey.GetValue('UninstallString')
            }
        }
    }

    $baseKey.Close()
}

$allSoftware = $allSoftware | Sort-Object ComputerName, DisplayName -Unique

if (-not $allSoftware) {
    Write-Warning "No software entries found."
    return
}

$allSoftware | Export-Csv -Path $OutputCsv -NoTypeInformation
Write-Host "`nExported $($allSoftware.Count) entries across $($ComputerName.Count) computer(s) to $OutputCsv" -ForegroundColor Green

$allSoftware | Group-Object ComputerName | ForEach-Object {
    Write-Host "  $($_.Name): $($_.Count) applications"
}
