<#
.SYNOPSIS
    Identifies and reports on inactive Active Directory user accounts.

.DESCRIPTION
    This script finds inactive user accounts based on various criteria:
    - Last logon timestamp
    - Password last set date
    - Account creation date
    - Account enabled/disabled status
    - Group memberships (privileged accounts highlighted)
    - Export options for remediation planning

.PARAMETER DaysInactive
    Number of days since last logon to consider inactive (default: 90).

.PARAMETER IncludeDisabled
    Include already disabled accounts in the report.

.PARAMETER SearchBase
    Active Directory OU to search (default: entire domain).

.PARAMETER ExcludeServiceAccounts
    Exclude accounts identified as service accounts.

.PARAMETER HighlightPrivileged
    Highlight accounts with administrative privileges.

.PARAMETER ExportHTML
    Export results to HTML report.

.PARAMETER ExportCSV
    Export results to CSV file.

.PARAMETER WhatIfDisable
    Show what would happen if inactive accounts were disabled.

.EXAMPLE
    .\Get-InactiveUserReport.ps1 -DaysInactive 90
    Finds users who haven't logged in for 90 days.

.EXAMPLE
    .\Get-InactiveUserReport.ps1 -DaysInactive 180 -HighlightPrivileged -ExportHTML
    Finds inactive users for 180 days and highlights privileged accounts.

.EXAMPLE
    .\Get-InactiveUserReport.ps1 -SearchBase "OU=Employees,DC=domain,DC=com" -ExcludeServiceAccounts
    Searches specific OU and excludes service accounts.

.NOTES
    Requires Active Directory PowerShell module
    Requires appropriate AD read permissions
    Compatible with Windows Server 2016, 2019, 2022
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [int]$DaysInactive = 90,

    [Parameter(Mandatory=$false)]
    [switch]$IncludeDisabled,

    [Parameter(Mandatory=$false)]
    [string]$SearchBase,

    [Parameter(Mandatory=$false)]
    [switch]$ExcludeServiceAccounts,

    [Parameter(Mandatory=$false)]
    [switch]$HighlightPrivileged,

    [Parameter(Mandatory=$false)]
    [switch]$ExportHTML,

    [Parameter(Mandatory=$false)]
    [switch]$ExportCSV,

    [Parameter(Mandatory=$false)]
    [switch]$WhatIfDisable
)

#Requires -Modules ActiveDirectory

$ErrorActionPreference = "Continue"
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$cutoffDate = (Get-Date).AddDays(-$DaysInactive)

Write-Host "`n=== Inactive User Account Report ===" -ForegroundColor Cyan
Write-Host "Inactivity Threshold: $DaysInactive days (since $($cutoffDate.ToShortDateString()))" -ForegroundColor Yellow
Write-Host "Domain: $env:USERDNSDOMAIN" -ForegroundColor Yellow
Write-Host ""

# Build search parameters
$searchParams = @{
    Filter = "*"
    Properties = "LastLogonDate", "PasswordLastSet", "Created", "MemberOf", "Description", "Enabled", "DistinguishedName", "whenChanged"
}

if ($SearchBase) {
    $searchParams.SearchBase = $SearchBase
    Write-Host "[*] Searching in: $SearchBase" -ForegroundColor Cyan
}

Write-Host "[*] Retrieving user accounts..." -ForegroundColor Cyan

try {
    $allUsers = Get-ADUser @searchParams

    Write-Host "[+] Found $($allUsers.Count) total user accounts" -ForegroundColor Green

    # Filter for inactive users
    $inactiveUsers = $allUsers | Where-Object {
        # Check if we should include disabled accounts
        if (-not $IncludeDisabled -and $_.Enabled -eq $false) {
            return $false
        }

        # Check last logon date
        $isInactive = $false

        if ($null -eq $_.LastLogonDate) {
            # Never logged in
            $isInactive = $true
        }
        elseif ($_.LastLogonDate -lt $cutoffDate) {
            # Last logon too old
            $isInactive = $true
        }

        return $isInactive
    }

    Write-Host "[+] Found $($inactiveUsers.Count) inactive user accounts" -ForegroundColor $(if ($inactiveUsers.Count -gt 0) { "Yellow" } else { "Green" })
    Write-Host ""

    # Process inactive users
    $results = @()
    $privilegedCount = 0
    $neverLoggedInCount = 0

    # Privileged group SIDs
    $privilegedGroups = @(
        "S-1-5-32-544",  # Administrators
        "S-1-5-32-548",  # Account Operators
        "S-1-5-32-549",  # Server Operators
        "S-1-5-32-551"   # Backup Operators
    )

    foreach ($user in $inactiveUsers) {
        # Check if service account
        if ($ExcludeServiceAccounts) {
            if ($user.Description -match "(service|svc|robot|automation)" -or
                $user.SamAccountName -match "^(svc|service)") {
                continue
            }
        }

        # Check for privileged access
        $isPrivileged = $false
        $adminGroups = @()

        if ($user.MemberOf) {
            foreach ($group in $user.MemberOf) {
                $groupObj = Get-ADGroup $group -Properties SID
                if ($privilegedGroups -contains $groupObj.SID.Value) {
                    $isPrivileged = $true
                    $adminGroups += $groupObj.Name
                }
            }
        }

        if ($isPrivileged) {
            $privilegedCount++
        }

        # Calculate inactivity days
        $daysSinceLogon = if ($user.LastLogonDate) {
            ((Get-Date) - $user.LastLogonDate).Days
        }
        else {
            $neverLoggedInCount++
            "Never"
        }

        $daysSincePasswordSet = if ($user.PasswordLastSet) {
            ((Get-Date) - $user.PasswordLastSet).Days
        }
        else {
            "N/A"
        }

        $result = [PSCustomObject]@{
            SamAccountName = $user.SamAccountName
            Name = $user.Name
            Enabled = $user.Enabled
            LastLogon = if ($user.LastLogonDate) { $user.LastLogonDate } else { "Never" }
            DaysSinceLogon = $daysSinceLogon
            PasswordLastSet = $user.PasswordLastSet
            DaysSincePasswordSet = $daysSincePasswordSet
            Created = $user.Created
            IsPrivileged = $isPrivileged
            PrivilegedGroups = $adminGroups -join "; "
            Description = $user.Description
            DistinguishedName = $user.DistinguishedName
        }

        $results += $result
    }

    # Display summary
    Write-Host "=== Summary ===" -ForegroundColor Cyan
    Write-Host "Total Inactive Users: $($results.Count)" -ForegroundColor White
    Write-Host "Privileged Accounts: $privilegedCount" -ForegroundColor $(if ($privilegedCount -gt 0) { "Red" } else { "Green" })
    Write-Host "Never Logged In: $neverLoggedInCount" -ForegroundColor Yellow
    Write-Host "Enabled Inactive: $(($results | Where-Object { $_.Enabled -eq $true }).Count)" -ForegroundColor Yellow
    Write-Host "Disabled Inactive: $(($results | Where-Object { $_.Enabled -eq $false }).Count)" -ForegroundColor Gray
    Write-Host ""

    # Show top 20 inactive users
    if ($results.Count -gt 0) {
        Write-Host "=== Top 20 Inactive Users ===" -ForegroundColor Cyan
        $results | Sort-Object LastLogon | Select-Object -First 20 SamAccountName, Name, Enabled, LastLogon, DaysSinceLogon, IsPrivileged |
            Format-Table -AutoSize
    }

    # Show privileged inactive accounts
    if ($HighlightPrivileged -and $privilegedCount -gt 0) {
        Write-Host "`n=== Privileged Inactive Accounts (CRITICAL) ===" -ForegroundColor Red
        $results | Where-Object { $_.IsPrivileged -eq $true } |
            Select-Object SamAccountName, Name, Enabled, LastLogon, DaysSinceLogon, PrivilegedGroups |
            Format-Table -AutoSize
    }

    # WhatIf disable
    if ($WhatIfDisable) {
        Write-Host "`n=== What-If: Disable Inactive Accounts ===" -ForegroundColor Cyan
        $enabledInactive = $results | Where-Object { $_.Enabled -eq $true }
        Write-Host "Would disable $($enabledInactive.Count) enabled inactive accounts:" -ForegroundColor Yellow
        $enabledInactive | Select-Object -First 10 SamAccountName, Name, LastLogon | Format-Table -AutoSize
        Write-Host "... and $($enabledInactive.Count - 10) more" -ForegroundColor Gray
    }

    # Export results
    if ($ExportHTML) {
        $htmlPath = "$env:USERPROFILE\Desktop\InactiveUsers_$timestamp.html"

        $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>Inactive User Report - $timestamp</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        h1 { color: #e67e22; }
        h2 { color: #d35400; margin-top: 30px; }
        table { border-collapse: collapse; width: 100%; margin-top: 10px; }
        th { background-color: #e67e22; color: white; padding: 10px; text-align: left; }
        td { border: 1px solid #ddd; padding: 8px; font-size: 12px; }
        tr:nth-child(even) { background-color: #f2f2f2; }
        .summary { background-color: #ecf0f1; padding: 15px; border-radius: 5px; margin: 20px 0; }
        .privileged { background-color: #e74c3c; color: white; font-weight: bold; }
        .disabled { color: #95a5a6; }
    </style>
</head>
<body>
    <h1>Inactive User Account Report</h1>
    <div class="summary">
        <strong>Generated:</strong> $(Get-Date)<br>
        <strong>Inactivity Threshold:</strong> $DaysInactive days<br>
        <strong>Total Inactive Users:</strong> $($results.Count)<br>
        <strong>Privileged Accounts:</strong> $privilegedCount<br>
        <strong>Never Logged In:</strong> $neverLoggedInCount
    </div>

    <h2>Inactive User Accounts</h2>
    <table>
        <tr>
            <th>Username</th>
            <th>Name</th>
            <th>Enabled</th>
            <th>Last Logon</th>
            <th>Days Since Logon</th>
            <th>Privileged</th>
            <th>Privileged Groups</th>
            <th>Description</th>
        </tr>
"@

        foreach ($result in ($results | Sort-Object -Property @{Expression={$_.IsPrivileged}; Descending=$true}, LastLogon)) {
            $rowClass = if ($result.IsPrivileged) { "privileged" } elseif (-not $result.Enabled) { "disabled" } else { "" }
            $html += @"
        <tr class="$rowClass">
            <td>$($result.SamAccountName)</td>
            <td>$($result.Name)</td>
            <td>$($result.Enabled)</td>
            <td>$($result.LastLogon)</td>
            <td>$($result.DaysSinceLogon)</td>
            <td>$($result.IsPrivileged)</td>
            <td>$($result.PrivilegedGroups)</td>
            <td>$($result.Description)</td>
        </tr>
"@
        }

        $html += "</table></body></html>"

        $html | Out-File -FilePath $htmlPath -Encoding UTF8
        Write-Host "[+] HTML report saved to: $htmlPath" -ForegroundColor Green
    }

    if ($ExportCSV) {
        $csvPath = "$env:USERPROFILE\Desktop\InactiveUsers_$timestamp.csv"
        $results | Export-Csv -Path $csvPath -NoTypeInformation
        Write-Host "[+] CSV export saved to: $csvPath" -ForegroundColor Green
    }

} catch {
    Write-Host "[-] Error: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host "`n[+] Report completed!" -ForegroundColor Green

# Exit with warning if privileged accounts are inactive
if ($privilegedCount -gt 0) {
    exit 1
}

exit 0
