<#
.SYNOPSIS
    Performs a comprehensive audit of Active Directory user accounts.

.DESCRIPTION
    This script audits AD user accounts for security and compliance issues including inactive
    accounts, accounts whose passwords never expire, privileged group memberships, recently
    created or modified accounts, locked-out accounts, expired accounts, and enabled accounts
    that have never logged on. Results are summarized to the console and rendered as an HTML
    report, with optional per-category CSV export.

    Behavior notes:
    - Exits with 0 when the audit completes and 1 when a fatal error occurs (including unsafe output paths).
    - The script is read-only against Active Directory and safe to re-run at any time.
    - OutputPath must be a local absolute path without '..' traversal; UNC paths are rejected.

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
    PS C:\> .\Get-ADUserAudit.ps1 -OutputPath "C:\Reports"
    Performs standard user account audit.

.EXAMPLE
    PS C:\> .\Get-ADUserAudit.ps1 -InactiveDays 60 -CheckPrivilegedAccounts -ExportToCSV
    Audits with 60-day inactive threshold, checks privileged accounts, exports CSV.

.NOTES
    File Name     : Get-ADUserAudit.ps1
    Author        : Server Management Team
    Prerequisite  : PowerShell 5.1+
    Version       : 1.0.0
    Date          : 2026-08-23
    Requires      : ActiveDirectory PowerShell module; Domain Admin or equivalent permissions
#>

[CmdletBinding()]
param(
# Note: these script parameters are consumed by nested functions through PowerShell dynamic
# scoping, which PSScriptAnalyzer cannot see; PSReviewUnusedParameter is a false positive here.
    [Parameter(Mandatory = $false)]
    [ValidateRange(1, [int]::MaxValue)]
    [int]$InactiveDays = 90,

    [Parameter(Mandatory = $false)]
    [string]$OutputPath,

    [Parameter(Mandatory = $false)]
    [switch]$IncludeDisabledAccounts,

    [Parameter(Mandatory = $false)]
    [switch]$CheckPrivilegedAccounts,

    [Parameter(Mandatory = $false)]
    [switch]$ExportToCSV
)

$ErrorActionPreference = 'Stop'

# Write-Host is intentional: interactive console reporting with the color/prefix convention
# mandated by RELAUNCH-SPEC §3 (justifies PSAvoidUsingWriteHost).
function Test-ADModule {
    [CmdletBinding()]
    param()

    try {
        Import-Module ActiveDirectory -ErrorAction Stop
        return $true
    }
    catch {
        Write-Host "[-] ERROR: Active Directory PowerShell module not available" -ForegroundColor Red
        Write-Host "[-] Install RSAT tools or run from a Domain Controller" -ForegroundColor Red
        return $false
    }
}

function Resolve-AuditOutputDir {
    [CmdletBinding()]
    param()

    # Resolve default when not supplied; fall back to a temp base where MyDocuments is
    # not resolvable (e.g. Linux CI). Reject '..' traversal and UNC remote paths.
    $root = $OutputPath
    if ([string]::IsNullOrWhiteSpace($root)) {
        $docs = [Environment]::GetFolderPath('MyDocuments')
        $base = if (-not [string]::IsNullOrWhiteSpace($docs)) { $docs } else { [System.IO.Path]::GetTempPath() }
        $root = Join-Path $base 'Reports'
    }
    if ($root -match '(^|[\\/])\.\.([\\/]|$)' -or
        $root -match '^(\\\\|//)') {
        throw "Unsafe OutputPath: $root. OutputPath must be a local absolute path without '..' traversal."
    }
    $fullPath = [System.IO.Path]::GetFullPath($root)
    if (-not (Test-Path -LiteralPath $fullPath -PathType Container)) {
        New-Item -Path $fullPath -ItemType Directory -Force -ErrorAction Stop | Out-Null
    }
    return $fullPath
}

function Convert-ToHtmlText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [object]$Text
    )

    return [System.Net.WebUtility]::HtmlEncode("$Text")
}

function Main {
    try {
        Write-Host "`n[*] === Active Directory User Account Audit ===" -ForegroundColor Cyan
        Write-Host "[*] Start Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray

        if (-not (Test-ADModule)) {
            return 1
        }

        $script:OutputRoot = Resolve-AuditOutputDir

        $RunTimestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $RunId = [Guid]::NewGuid().ToString('N').Substring(0, 8)

        try {
            # Get domain information
            $domain = Get-ADDomain -ErrorAction Stop
            $domainName = $domain.DNSRoot
            Write-Host "`n[+] Domain: $domainName" -ForegroundColor Green

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
            Write-Host "`n[*] Retrieving user accounts..." -ForegroundColor Cyan

            $filter = if ($IncludeDisabledAccounts) { "*" } else { "Enabled -eq 'True'" }

            $allUsers = @(Get-ADUser -Filter $filter -Properties * -ErrorAction Stop |
                Where-Object { $_.ObjectClass -eq 'user' })

            $totalUsers = $allUsers.Count
            Write-Host "[+] Found $totalUsers user account(s)" -ForegroundColor Green

            # Define thresholds
            $inactiveDate = (Get-Date).AddDays(-$InactiveDays)
            $recentDate = (Get-Date).AddDays(-30)

            $counter = 0

            # Analyze each user
            Write-Host "`n[*] Analyzing user accounts..." -ForegroundColor Cyan

            foreach ($user in $allUsers) {
                $counter++
                if ($counter % 100 -eq 0) {
                    $percentComplete = [math]::Round(($counter / $totalUsers) * 100)
                    $progressStatus = "Processing $counter of $totalUsers"
                    Write-Progress -Activity "Analyzing Users" -Status $progressStatus `
                        -PercentComplete $percentComplete
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
                Write-Host "`n[*] Analyzing privileged accounts..." -ForegroundColor Cyan

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
                            $members = Get-ADGroupMember -Identity $group -Recursive -ErrorAction Stop |
                                Where-Object { $_.objectClass -eq 'user' }

                            foreach ($member in $members) {
                                $memberUser = Get-ADUser -Identity $member -Properties * -ErrorAction Stop

                                $auditResults.PrivilegedAccounts += [PSCustomObject]@{
                                    SamAccountName = $memberUser.SamAccountName
                                    DisplayName = $memberUser.DisplayName
                                    GroupName = $groupName
                                    LastLogon = $memberUser.LastLogonDate
                                    PasswordLastSet = $memberUser.PasswordLastSet
                                    PasswordNeverExpires = $memberUser.PasswordNeverExpires
                                    Enabled = $memberUser.Enabled
                                    SmartcardRequired = $memberUser.SmartcardLogonRequired
                                }
                            }
                        }
                    }
                    catch {
                        Write-Host "[!] Could not process group ${groupName}: $_" -ForegroundColor Yellow
                    }
                }

                # Remove duplicates
                $auditResults.PrivilegedAccounts = @($auditResults.PrivilegedAccounts |
                    Sort-Object -Property SamAccountName, GroupName -Unique)

                $privCount = $auditResults.PrivilegedAccounts.Count
                Write-Host "[*] Found $privCount privileged account membership(s)" -ForegroundColor Cyan
            }

            # Display summary
            Write-Host "`n[*] === Audit Summary ===" -ForegroundColor Cyan
            Write-Host "Total Users Analyzed: $totalUsers" -ForegroundColor White
            Write-Host ""
            $inactiveCount = $auditResults.InactiveAccounts.Count
            $inactiveColor = if ($inactiveCount -gt 0) { 'Yellow' } else { 'Green' }
            Write-Host "Inactive Accounts (>$InactiveDays days): $inactiveCount" -ForegroundColor $inactiveColor
            $neverCount = $auditResults.NeverLoggedIn.Count
            $neverColor = if ($neverCount -gt 0) { 'Yellow' } else { 'Green' }
            Write-Host "Never Logged In (>30 days old): $neverCount" -ForegroundColor $neverColor
            $pneColor = if ($auditResults.PasswordNeverExpires.Count -gt 0) { 'Yellow' } else { 'Green' }
            Write-Host "Password Never Expires: $($auditResults.PasswordNeverExpires.Count)" -ForegroundColor $pneColor
            $lockedColor = if ($auditResults.LockedOutAccounts.Count -gt 0) { 'Red' } else { 'Green' }
            Write-Host "Locked Out Accounts: $($auditResults.LockedOutAccounts.Count)" -ForegroundColor $lockedColor
            $expiredColor = if ($auditResults.ExpiredAccounts.Count -gt 0) { 'Yellow' } else { 'Green' }
            Write-Host "Expired Accounts: $($auditResults.ExpiredAccounts.Count)" -ForegroundColor $expiredColor
            Write-Host "Recently Created (30 days): $($auditResults.RecentlyCreated.Count)" -ForegroundColor Cyan
            Write-Host "Recently Modified (30 days): $($auditResults.RecentlyModified.Count)" -ForegroundColor Cyan

            if ($CheckPrivilegedAccounts) {
                Write-Host "Privileged Account Memberships: $privCount" -ForegroundColor Cyan
            }

            # Export to CSV if requested
            if ($ExportToCSV) {
                Write-Host "`n[*] Exporting detailed results to CSV..." -ForegroundColor Cyan

                foreach ($category in $auditResults.Keys) {
                    if (@($auditResults[$category]).Count -gt 0) {
                        $csvName = "${category}_${RunTimestamp}_${RunId}.csv"
                        $recordCount = @($auditResults[$category]).Count
                        $csvPath = Join-Path -Path $script:OutputRoot -ChildPath $csvName
                        $auditResults[$category] |
                            Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8 -ErrorAction Stop
                        Write-Host "[+] Exported: $csvName ($recordCount records)" -ForegroundColor Green
                    }
                }
            }

            # Generate HTML report
            Write-Host "`n[*] Generating HTML report..." -ForegroundColor Cyan
            $htmlPath = Join-Path -Path $script:OutputRoot -ChildPath "ADUserAuditReport_${RunTimestamp}_${RunId}.html"

            $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>AD User Audit Report - $domainName</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            margin: 20px;
            background-color: #f5f5f5;
        }
        h1 {
            color: #0066cc;
        }
        h2 {
            color: #0099cc;
            margin-top: 30px;
        }
        table {
            border-collapse: collapse;
            width: 100%;
            background-color: white;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
            margin: 20px 0;
        }
        th {
            background-color: #0066cc;
            color: white;
            padding: 12px;
            text-align: left;
        }
        td {
            padding: 10px;
            border-bottom: 1px solid #ddd;
        }
        tr:hover {
            background-color: #f0f0f0;
        }
        .warning {
            color: #ff6600;
            font-weight: bold;
        }
        .critical {
            color: #cc0000;
            font-weight: bold;
        }
        .good {
            color: #009900;
        }
        .info {
            background-color: #e6f3ff;
            padding: 15px;
            border-left: 4px solid #0066cc;
            margin: 20px 0;
        }
    </style>
</head>
<body>
    <h1>Active Directory User Audit Report</h1>
    <div class="info">
        <strong>Domain:</strong> $(Convert-ToHtmlText -Text $domainName)<br>
        <strong>Report Date:</strong> $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | <strong>Run ID:</strong> $RunId<br>
        <strong>Total Users Analyzed:</strong> $totalUsers
    </div>

    <h2>Summary</h2>
    <table>
        <tr><td><strong>Inactive Accounts (&gt;$InactiveDays days)</strong></td>
            <td class="$(if ($auditResults.InactiveAccounts.Count -gt 0) { 'warning' } else { 'good' })">
                $($auditResults.InactiveAccounts.Count)</td></tr>
        <tr><td><strong>Never Logged In (&gt;30 days old)</strong></td>
            <td class="$(if ($auditResults.NeverLoggedIn.Count -gt 0) { 'warning' } else { 'good' })">
                $($auditResults.NeverLoggedIn.Count)</td></tr>
        <tr><td><strong>Password Never Expires</strong></td>
            <td class="$(if ($auditResults.PasswordNeverExpires.Count -gt 0) { 'warning' } else { 'good' })">
                $($auditResults.PasswordNeverExpires.Count)</td></tr>
        <tr><td><strong>Locked Out Accounts</strong></td>
            <td class="$(if ($auditResults.LockedOutAccounts.Count -gt 0) { 'critical' } else { 'good' })">
                $($auditResults.LockedOutAccounts.Count)</td></tr>
        <tr><td><strong>Expired Accounts</strong></td>
            <td class="$(if ($auditResults.ExpiredAccounts.Count -gt 0) { 'warning' } else { 'good' })">
                $($auditResults.ExpiredAccounts.Count)</td></tr>
        <tr><td><strong>Recently Created (30 days)</strong></td><td>$($auditResults.RecentlyCreated.Count)</td></tr>
        <tr><td><strong>Recently Modified (30 days)</strong></td><td>$($auditResults.RecentlyModified.Count)</td></tr>
    </table>
"@

            # Add sections for each category with findings
            if ($auditResults.InactiveAccounts.Count -gt 0) {
                $html += "<h2>Inactive Accounts (Top 20)</h2><table><tr><th>Username</th>" +
                    "<th>Display Name</th><th>Last Logon</th><th>Days Inactive</th><th>Department</th></tr>"
                foreach ($user in ($auditResults.InactiveAccounts | Sort-Object -Property DaysInactive -Descending |
                        Select-Object -First 20)) {
                    $nameCell = Convert-ToHtmlText -Text $user.SamAccountName
                    $displayCell = Convert-ToHtmlText -Text $user.DisplayName
                    $logonCell = Convert-ToHtmlText -Text $user.LastLogon
                    $deptCell = Convert-ToHtmlText -Text $user.Department
                    $html += "<tr><td>$nameCell</td><td>$displayCell</td><td>$logonCell</td>" +
                        "<td>$($user.DaysInactive)</td><td>$deptCell</td></tr>"
                }
                $html += "</table>"
            }

            if ($auditResults.PasswordNeverExpires.Count -gt 0) {
                $html += "<h2>Password Never Expires (Top 20)</h2><table><tr><th>Username</th>" +
                    "<th>Display Name</th><th>Last Password Set</th><th>Department</th></tr>"
                foreach ($user in ($auditResults.PasswordNeverExpires | Select-Object -First 20)) {
                    $nameCell = Convert-ToHtmlText -Text $user.SamAccountName
                    $displayCell = Convert-ToHtmlText -Text $user.DisplayName
                    $pwdCell = Convert-ToHtmlText -Text $user.LastPasswordSet
                    $deptCell = Convert-ToHtmlText -Text $user.Department
                    $html += "<tr><td>$nameCell</td><td>$displayCell</td><td>$pwdCell</td><td>$deptCell</td></tr>"
                }
                $html += "</table>"
            }

            if ($CheckPrivilegedAccounts -and $auditResults.PrivilegedAccounts.Count -gt 0) {
                $html += "<h2>Privileged Accounts</h2><table><tr><th>Username</th><th>Display Name</th>" +
                    "<th>Group</th><th>Password Never Expires</th><th>Smartcard Required</th></tr>"
                $sortedPrivileged = @($auditResults.PrivilegedAccounts |
                    Sort-Object -Property GroupName, SamAccountName)
                foreach ($user in $sortedPrivileged) {
                    $pwdNeverExpires = if ($user.PasswordNeverExpires) {
                        "<span class='warning'>Yes</span>"
                    }
                    else {
                        "No"
                    }
                    $smartcard = if ($user.SmartcardRequired) {
                        "<span class='good'>Yes</span>"
                    }
                    else {
                        "<span class='warning'>No</span>"
                    }
                    $nameCell = Convert-ToHtmlText -Text $user.SamAccountName
                    $displayCell = Convert-ToHtmlText -Text $user.DisplayName
                    $groupCell = Convert-ToHtmlText -Text $user.GroupName
                    $html += "<tr><td>$nameCell</td><td>$displayCell</td><td>$groupCell</td>" +
                        "<td>$pwdNeverExpires</td><td>$smartcard</td></tr>"
                }
                $html += "</table>"
            }

            $html += "</body></html>"

            $html | Out-File -FilePath $htmlPath -Encoding UTF8 -ErrorAction Stop
            Write-Host "[+] HTML report saved to: $htmlPath" -ForegroundColor Green
        }
        catch {
            Write-Host "[-] Error during audit: $($_.Exception.Message)" -ForegroundColor Red
            Write-Verbose $_.ScriptStackTrace
            throw
        }

        Write-Host "`n[+] End Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray
        Write-Host "[+] Active Directory user account audit completed successfully" -ForegroundColor Green
        return 0
    }
    catch {
        Write-Host "[-] Error: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
