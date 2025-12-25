<#
.SYNOPSIS
    Performs comprehensive audit of Active Directory user accounts.

.DESCRIPTION
    This script audits AD user accounts for security and compliance issues including:
    - Inactive accounts
    - Accounts with passwords that never expire
    - Accounts with weak password policies
    - Privileged accounts
    - Recently created/modified accounts
    - Accounts with suspicious attributes

.PARAMETER InactiveDays
    Number of days to consider an account inactive. Default is 90 days.

.PARAMETER OutputPath
    Path where the audit report will be saved.

.PARAMETER IncludeDisabledAccounts
    Switch to include disabled accounts in the report.

.PARAMETER CheckPrivilegedAccounts
    Switch to specifically audit privileged accounts (Domain Admins, etc.).

.PARAMETER ExportToCSV
    Switch to export detailed results to CSV.

.EXAMPLE
    .\Get-ADUserAudit.ps1 -OutputPath "C:\Reports"
    Performs standard user account audit.

.EXAMPLE
    .\Get-ADUserAudit.ps1 -InactiveDays 60 -CheckPrivilegedAccounts -ExportToCSV
    Audits with 60-day inactive threshold, checks privileged accounts, exports CSV.

.NOTES
    Author: Server Management Team
    Requires: ActiveDirectory PowerShell module, Domain Admin or equivalent permissions
    Version: 1.0
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [int]$InactiveDays = 90,

    [Parameter(Mandatory = $false)]
    [string]$OutputPath = "$env:TEMP\ADUserAudit_$(Get-Date -Format 'yyyyMMdd_HHmmss')",

    [Parameter(Mandatory = $false)]
    [switch]$IncludeDisabledAccounts,

    [Parameter(Mandatory = $false)]
    [switch]$CheckPrivilegedAccounts,

    [Parameter(Mandatory = $false)]
    [switch]$ExportToCSV
)

#Requires -Module ActiveDirectory

Write-Host "`n=== Active Directory User Account Audit ===" -ForegroundColor Cyan
Write-Host "Start Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray

# Create output directory
if (-not (Test-Path -Path $OutputPath)) {
    New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
}

try {
    # Get domain information
    $domain = Get-ADDomain
    $domainName = $domain.DNSRoot
    Write-Host "`nDomain: $domainName" -ForegroundColor Green

    # Initialize audit data
    $auditResults = @{
        InactiveAccounts = @()
        PasswordNeverExpires = @()
        PrivilegedAccounts = @()
        RecentlyCreated = @()
        RecentlyModified = @()
        WeakPasswordPolicy = @()
        LockedOutAccounts = @()
        ExpiredAccounts = @()
        NeverLoggedIn = @()
    }

    # Get all users or only enabled users
    Write-Host "`nRetrieving user accounts..." -ForegroundColor Yellow

    $filter = if ($IncludeDisabledAccounts) { "*" } else { "Enabled -eq 'True'" }

    $allUsers = Get-ADUser -Filter $filter -Properties * |
        Where-Object { $_.ObjectClass -eq 'user' }

    $totalUsers = $allUsers.Count
    Write-Host "Found $totalUsers user account(s)" -ForegroundColor Green

    # Define thresholds
    $inactiveDate = (Get-Date).AddDays(-$InactiveDays)
    $recentDate = (Get-Date).AddDays(-30)

    $counter = 0

    # Analyze each user
    Write-Host "`nAnalyzing user accounts..." -ForegroundColor Yellow

    foreach ($user in $allUsers) {
        $counter++
        if ($counter % 100 -eq 0) {
            $percentComplete = [math]::Round(($counter / $totalUsers) * 100)
            Write-Progress -Activity "Analyzing Users" -Status "Processing $counter of $totalUsers" -PercentComplete $percentComplete
        }

        # Check for inactive accounts
        if ($user.LastLogonDate -and $user.LastLogonDate -lt $inactiveDate -and $user.Enabled) {
            $daysSinceLogon = ((Get-Date) - $user.LastLogonDate).Days

            $auditResults.InactiveAccounts += [PSCustomObject]@{
                SamAccountName = $user.SamAccountName
                DisplayName = $user.DisplayName
                LastLogon = $user.LastLogonDate
                DaysInactive = $daysSinceLogon
                Created = $user.Created
                Department = $user.Department
                Title = $user.Title
            }
        }

        # Check for accounts that never logged in
        if (-not $user.LastLogonDate -and $user.Enabled) {
            $daysSinceCreation = ((Get-Date) - $user.Created).Days

            if ($daysSinceCreation -gt 30) {
                $auditResults.NeverLoggedIn += [PSCustomObject]@{
                    SamAccountName = $user.SamAccountName
                    DisplayName = $user.DisplayName
                    Created = $user.Created
                    DaysSinceCreation = $daysSinceCreation
                    Department = $user.Department
                }
            }
        }

        # Check password never expires
        if ($user.PasswordNeverExpires -and $user.Enabled) {
            $auditResults.PasswordNeverExpires += [PSCustomObject]@{
                SamAccountName = $user.SamAccountName
                DisplayName = $user.DisplayName
                LastPasswordSet = $user.PasswordLastSet
                Created = $user.Created
                Department = $user.Department
            }
        }

        # Check recently created accounts
        if ($user.Created -gt $recentDate) {
            $auditResults.RecentlyCreated += [PSCustomObject]@{
                SamAccountName = $user.SamAccountName
                DisplayName = $user.DisplayName
                Created = $user.Created
                CreatedBy = $user.Creator
                Enabled = $user.Enabled
                Department = $user.Department
            }
        }

        # Check recently modified accounts
        if ($user.Modified -gt $recentDate -and $user.Created -lt $recentDate) {
            $auditResults.RecentlyModified += [PSCustomObject]@{
                SamAccountName = $user.SamAccountName
                DisplayName = $user.DisplayName
                Modified = $user.Modified
                Department = $user.Department
            }
        }

        # Check for locked accounts
        if ($user.LockedOut) {
            $auditResults.LockedOutAccounts += [PSCustomObject]@{
                SamAccountName = $user.SamAccountName
                DisplayName = $user.DisplayName
                LockoutTime = $user.AccountLockoutTime
                BadPasswordCount = $user.BadPwdCount
                Department = $user.Department
            }
        }

        # Check for expired accounts
        if ($user.AccountExpirationDate -and $user.AccountExpirationDate -lt (Get-Date)) {
            $auditResults.ExpiredAccounts += [PSCustomObject]@{
                SamAccountName = $user.SamAccountName
                DisplayName = $user.DisplayName
                ExpirationDate = $user.AccountExpirationDate
                Enabled = $user.Enabled
                Department = $user.Department
            }
        }
    }

    Write-Progress -Activity "Analyzing Users" -Completed

    # Check privileged accounts
    if ($CheckPrivilegedAccounts) {
        Write-Host "`nAnalyzing privileged accounts..." -ForegroundColor Yellow

        $privilegedGroups = @(
            "Domain Admins",
            "Enterprise Admins",
            "Schema Admins",
            "Administrators",
            "Account Operators",
            "Backup Operators",
            "Server Operators",
            "Print Operators"
        )

        foreach ($groupName in $privilegedGroups) {
            try {
                $group = Get-ADGroup -Identity $groupName -ErrorAction SilentlyContinue
                if ($group) {
                    $members = Get-ADGroupMember -Identity $group -Recursive |
                        Where-Object { $_.objectClass -eq 'user' }

                    foreach ($member in $members) {
                        $user = Get-ADUser -Identity $member -Properties *

                        $auditResults.PrivilegedAccounts += [PSCustomObject]@{
                            SamAccountName = $user.SamAccountName
                            DisplayName = $user.DisplayName
                            GroupName = $groupName
                            LastLogon = $user.LastLogonDate
                            PasswordLastSet = $user.PasswordLastSet
                            PasswordNeverExpires = $user.PasswordNeverExpires
                            Enabled = $user.Enabled
                            SmartcardRequired = $user.SmartcardLogonRequired
                        }
                    }
                }
            }
            catch {
                Write-Warning "Could not process group $groupName: $_"
            }
        }

        # Remove duplicates
        $auditResults.PrivilegedAccounts = $auditResults.PrivilegedAccounts |
            Sort-Object -Property SamAccountName, GroupName -Unique

        Write-Host "Found $($auditResults.PrivilegedAccounts.Count) privileged account membership(s)" -ForegroundColor Cyan
    }

    # Display summary
    Write-Host "`n=== Audit Summary ===" -ForegroundColor Cyan
    Write-Host "Total Users Analyzed: $totalUsers" -ForegroundColor White
    Write-Host ""
    Write-Host "Inactive Accounts (>$InactiveDays days): $($auditResults.InactiveAccounts.Count)" -ForegroundColor $(if ($auditResults.InactiveAccounts.Count -gt 0) { 'Yellow' } else { 'Green' })
    Write-Host "Never Logged In (>30 days old): $($auditResults.NeverLoggedIn.Count)" -ForegroundColor $(if ($auditResults.NeverLoggedIn.Count -gt 0) { 'Yellow' } else { 'Green' })
    Write-Host "Password Never Expires: $($auditResults.PasswordNeverExpires.Count)" -ForegroundColor $(if ($auditResults.PasswordNeverExpires.Count -gt 0) { 'Yellow' } else { 'Green' })
    Write-Host "Locked Out Accounts: $($auditResults.LockedOutAccounts.Count)" -ForegroundColor $(if ($auditResults.LockedOutAccounts.Count -gt 0) { 'Red' } else { 'Green' })
    Write-Host "Expired Accounts: $($auditResults.ExpiredAccounts.Count)" -ForegroundColor $(if ($auditResults.ExpiredAccounts.Count -gt 0) { 'Yellow' } else { 'Green' })
    Write-Host "Recently Created (30 days): $($auditResults.RecentlyCreated.Count)" -ForegroundColor Cyan
    Write-Host "Recently Modified (30 days): $($auditResults.RecentlyModified.Count)" -ForegroundColor Cyan

    if ($CheckPrivilegedAccounts) {
        Write-Host "Privileged Account Memberships: $($auditResults.PrivilegedAccounts.Count)" -ForegroundColor Cyan
    }

    # Export to CSV if requested
    if ($ExportToCSV) {
        Write-Host "`nExporting detailed results to CSV..." -ForegroundColor Yellow

        foreach ($category in $auditResults.Keys) {
            if ($auditResults[$category].Count -gt 0) {
                $csvPath = Join-Path -Path $OutputPath -ChildPath "$category.csv"
                $auditResults[$category] | Export-Csv -Path $csvPath -NoTypeInformation
                Write-Host "  Exported: $category.csv ($($auditResults[$category].Count) records)" -ForegroundColor Green
            }
        }
    }

    # Generate HTML report
    Write-Host "`nGenerating HTML report..." -ForegroundColor Yellow
    $htmlPath = Join-Path -Path $OutputPath -ChildPath "ADUserAuditReport.html"

    $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>AD User Audit Report - $domainName</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background-color: #f5f5f5; }
        h1 { color: #0066cc; }
        h2 { color: #0099cc; margin-top: 30px; }
        table { border-collapse: collapse; width: 100%; background-color: white; box-shadow: 0 2px 4px rgba(0,0,0,0.1); margin: 20px 0; }
        th { background-color: #0066cc; color: white; padding: 12px; text-align: left; }
        td { padding: 10px; border-bottom: 1px solid #ddd; }
        tr:hover { background-color: #f0f0f0; }
        .warning { color: #ff6600; font-weight: bold; }
        .critical { color: #cc0000; font-weight: bold; }
        .good { color: #009900; }
        .info { background-color: #e6f3ff; padding: 15px; border-left: 4px solid #0066cc; margin: 20px 0; }
    </style>
</head>
<body>
    <h1>Active Directory User Audit Report</h1>
    <div class="info">
        <strong>Domain:</strong> $domainName<br>
        <strong>Report Date:</strong> $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')<br>
        <strong>Total Users Analyzed:</strong> $totalUsers
    </div>

    <h2>Summary</h2>
    <table>
        <tr><td><strong>Inactive Accounts (&gt;$InactiveDays days)</strong></td><td class="$(if ($auditResults.InactiveAccounts.Count -gt 0) { 'warning' } else { 'good' })">$($auditResults.InactiveAccounts.Count)</td></tr>
        <tr><td><strong>Never Logged In (&gt;30 days old)</strong></td><td class="$(if ($auditResults.NeverLoggedIn.Count -gt 0) { 'warning' } else { 'good' })">$($auditResults.NeverLoggedIn.Count)</td></tr>
        <tr><td><strong>Password Never Expires</strong></td><td class="$(if ($auditResults.PasswordNeverExpires.Count -gt 0) { 'warning' } else { 'good' })">$($auditResults.PasswordNeverExpires.Count)</td></tr>
        <tr><td><strong>Locked Out Accounts</strong></td><td class="$(if ($auditResults.LockedOutAccounts.Count -gt 0) { 'critical' } else { 'good' })">$($auditResults.LockedOutAccounts.Count)</td></tr>
        <tr><td><strong>Expired Accounts</strong></td><td class="$(if ($auditResults.ExpiredAccounts.Count -gt 0) { 'warning' } else { 'good' })">$($auditResults.ExpiredAccounts.Count)</td></tr>
        <tr><td><strong>Recently Created (30 days)</strong></td><td>$($auditResults.RecentlyCreated.Count)</td></tr>
        <tr><td><strong>Recently Modified (30 days)</strong></td><td>$($auditResults.RecentlyModified.Count)</td></tr>
    </table>
"@

    # Add sections for each category with findings
    if ($auditResults.InactiveAccounts.Count -gt 0) {
        $html += "<h2>Inactive Accounts (Top 20)</h2><table><tr><th>Username</th><th>Display Name</th><th>Last Logon</th><th>Days Inactive</th><th>Department</th></tr>"
        foreach ($user in ($auditResults.InactiveAccounts | Sort-Object -Property DaysInactive -Descending | Select-Object -First 20)) {
            $html += "<tr><td>$($user.SamAccountName)</td><td>$($user.DisplayName)</td><td>$($user.LastLogon)</td><td>$($user.DaysInactive)</td><td>$($user.Department)</td></tr>"
        }
        $html += "</table>"
    }

    if ($auditResults.PasswordNeverExpires.Count -gt 0) {
        $html += "<h2>Password Never Expires (Top 20)</h2><table><tr><th>Username</th><th>Display Name</th><th>Last Password Set</th><th>Department</th></tr>"
        foreach ($user in ($auditResults.PasswordNeverExpires | Select-Object -First 20)) {
            $html += "<tr><td>$($user.SamAccountName)</td><td>$($user.DisplayName)</td><td>$($user.LastPasswordSet)</td><td>$($user.Department)</td></tr>"
        }
        $html += "</table>"
    }

    if ($CheckPrivilegedAccounts -and $auditResults.PrivilegedAccounts.Count -gt 0) {
        $html += "<h2>Privileged Accounts</h2><table><tr><th>Username</th><th>Display Name</th><th>Group</th><th>Password Never Expires</th><th>Smartcard Required</th></tr>"
        foreach ($user in ($auditResults.PrivilegedAccounts | Sort-Object -Property GroupName, SamAccountName)) {
            $pwdNeverExpires = if ($user.PasswordNeverExpires) { "<span class='warning'>Yes</span>" } else { "No" }
            $smartcard = if ($user.SmartcardRequired) { "<span class='good'>Yes</span>" } else { "<span class='warning'>No</span>" }
            $html += "<tr><td>$($user.SamAccountName)</td><td>$($user.DisplayName)</td><td>$($user.GroupName)</td><td>$pwdNeverExpires</td><td>$smartcard</td></tr>"
        }
        $html += "</table>"
    }

    $html += "</body></html>"

    $html | Out-File -FilePath $htmlPath -Encoding UTF8
    Write-Host "HTML report saved to: $htmlPath" -ForegroundColor Green

    # Open report
    Start-Process $htmlPath

}
catch {
    Write-Error "Error during audit: $_"
    Write-Error $_.ScriptStackTrace
    exit 1
}

Write-Host "`nEnd Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray
