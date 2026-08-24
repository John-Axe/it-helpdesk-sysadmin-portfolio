<#
.SYNOPSIS
    Bulk-creates Active Directory user accounts from a CSV file.

.DESCRIPTION
    Reads a CSV of new-hire details and creates one AD user object per row,
    optionally adding each to department-appropriate groups. Designed as a
    lab/practice script for a fictitious contoso.local domain — update the
    -SearchBase / domain values before use in any real environment.

    Runs in preview (WhatIf-style) mode by default: it prints what it would
    do and does NOT create any accounts unless -Apply is passed explicitly.

.PARAMETER CsvPath
    Path to the input CSV. Expected columns:
    FirstName,LastName,SamAccountName,Department,OUPath,TemplateUser

.PARAMETER Apply
    Switch. Without this, the script only reports what it would create
    (dry run). Pass -Apply to actually create accounts in AD.

.PARAMETER DefaultPassword
    Temporary password assigned to new accounts. Users are forced to change
    it at next logon. In a real environment, generate a unique random
    password per user instead of reusing one value — this script accepts a
    single default only to keep the example simple.

.EXAMPLE
    .\bulk-ad-user-creation.ps1 -CsvPath .\new-hires.csv
    Dry run — shows what would be created, changes nothing.

.EXAMPLE
    .\bulk-ad-user-creation.ps1 -CsvPath .\new-hires.csv -Apply
    Actually creates the AD accounts listed in the CSV.

.NOTES
    Requires the ActiveDirectory PowerShell module (RSAT) and appropriate
    delegated permissions on the target OUs. Sample CSV format:

    FirstName,LastName,SamAccountName,Department,OUPath,TemplateUser
    Jane,Smith,jsmith,Sales,"OU=Sales,OU=Users,DC=contoso,DC=local",Template_Sales
    Tom,Nguyen,tnguyen,Engineering,"OU=Engineering,OU=Users,DC=contoso,DC=local",Template_Engineering
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateScript({ Test-Path $_ -PathType Leaf })]
    [string]$CsvPath,

    [switch]$Apply,

    [string]$DefaultPassword = "ChangeMe!TempPass2026",

    [string]$UpnSuffix = "contoso.local"
)

Import-Module ActiveDirectory -ErrorAction Stop

if (-not $Apply) {
    Write-Host "DRY RUN MODE — no accounts will be created. Pass -Apply to make changes." -ForegroundColor Yellow
}

$rows = Import-Csv -Path $CsvPath
$securePassword = ConvertTo-SecureString $DefaultPassword -AsPlainText -Force

$results = foreach ($row in $rows) {

    $requiredFields = @('FirstName', 'LastName', 'SamAccountName', 'OUPath')
    $missing = $requiredFields | Where-Object { -not $row.$_ }
    if ($missing) {
        Write-Warning "Skipping row for '$($row.SamAccountName)': missing field(s) $($missing -join ', ')"
        continue
    }

    $upn = "$($row.SamAccountName)@$UpnSuffix"
    $displayName = "$($row.FirstName) $($row.LastName)"

    $existing = Get-ADUser -Filter "SamAccountName -eq '$($row.SamAccountName)'" -ErrorAction SilentlyContinue
    if ($existing) {
        [PSCustomObject]@{
            SamAccountName = $row.SamAccountName
            DisplayName    = $displayName
            Status         = "SKIPPED — account already exists"
        }
        continue
    }

    if ($Apply) {
        try {
            New-ADUser `
                -Name $displayName `
                -GivenName $row.FirstName `
                -Surname $row.LastName `
                -SamAccountName $row.SamAccountName `
                -UserPrincipalName $upn `
                -Path $row.OUPath `
                -AccountPassword $securePassword `
                -ChangePasswordAtLogon $true `
                -Enabled $false `
                -ErrorAction Stop

            if ($row.TemplateUser) {
                $templateGroups = Get-ADUser -Identity $row.TemplateUser -Properties MemberOf |
                    Select-Object -ExpandProperty MemberOf
                foreach ($group in $templateGroups) {
                    Add-ADGroupMember -Identity $group -Members $row.SamAccountName -ErrorAction SilentlyContinue
                }
            }

            [PSCustomObject]@{
                SamAccountName = $row.SamAccountName
                DisplayName    = $displayName
                Status         = "CREATED (disabled — enable on start date)"
            }
        }
        catch {
            [PSCustomObject]@{
                SamAccountName = $row.SamAccountName
                DisplayName    = $displayName
                Status         = "ERROR — $($_.Exception.Message)"
            }
        }
    }
    else {
        [PSCustomObject]@{
            SamAccountName = $row.SamAccountName
            DisplayName    = $displayName
            Status         = "WOULD CREATE in $($row.OUPath), template: $($row.TemplateUser)"
        }
    }
}

$results | Format-Table -AutoSize

$createdCount = ($results | Where-Object { $_.Status -like "CREATED*" }).Count
$skippedCount = ($results | Where-Object { $_.Status -like "SKIPPED*" }).Count
$errorCount   = ($results | Where-Object { $_.Status -like "ERROR*" }).Count

Write-Host "`nSummary: $createdCount created, $skippedCount skipped, $errorCount errors." -ForegroundColor Cyan
if (-not $Apply) {
    Write-Host "This was a dry run. Re-run with -Apply to create these accounts." -ForegroundColor Yellow
}
