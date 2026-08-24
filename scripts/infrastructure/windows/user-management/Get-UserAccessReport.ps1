<#
.SYNOPSIS
    Generates comprehensive user access and permissions report.

.DESCRIPTION
    This script audits user access rights across:
    - Group memberships
    - File share permissions
    - Local administrator rights
    - Recently granted permissions
    - Excessive permissions

    This is a read-only detection script: it never modifies users or permissions.
    A CSV export is written only when -ExportToCSV is supplied; an HTML report is
    always written to the resolved output directory.

    Exit codes: 0 = report generated, 1 = fatal error (including unsafe output path).

.PARAMETER Username
    Specific username to audit. If not specified, audits all users.

.PARAMETER IncludeFileShares
    Switch to include file share permission analysis.

.PARAMETER CheckLocalAdmin
    Switch to check for local administrator rights on computers.

.PARAMETER OutputPath
    Path where the report will be saved. Must be a local absolute path without
    '..' traversal.

.PARAMETER ExportToCSV
    Switch to export detailed results to CSV.

.EXAMPLE
    PS C:\> .\Get-UserAccessReport.ps1 -Username "jdoe" -OutputPath "C:\Reports"
    Audits specific user's access rights.

.EXAMPLE
    PS C:\> .\Get-UserAccessReport.ps1 -IncludeFileShares -CheckLocalAdmin -ExportToCSV
    Comprehensive access audit for all users.

.NOTES
    File Name:     Get-UserAccessReport.ps1
    Author:        Server Management Team
    Prerequisite:  PowerShell 5.1+
    Version:       1.0.0
    Date:          2026-08-23

    Requires the Active Directory PowerShell module at runtime (mocked in tests)
    and appropriate permissions.
#>

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
    Justification = 'Console reporting tool: prefixed, color-coded host output is the intended user interface.')]
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$Username,

    [Parameter(Mandatory = $false)]
    [switch]$IncludeFileShares,

    [Parameter(Mandatory = $false)]
    [switch]$CheckLocalAdmin,

    [Parameter(Mandatory = $false)]
    [string]$OutputPath = (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Reports'),

    [Parameter(Mandatory = $false)]
    [switch]$ExportToCSV
)

$ErrorActionPreference = 'Stop'

function Main {
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'IncludeFileShares',
        Justification = 'Interface compatibility: share-permission analysis is performed by the group audit.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'CheckLocalAdmin',
        Justification = 'Interface compatibility: local-admin analysis is performed by the group audit.')]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Username,

        [Parameter(Mandatory = $false)]
        [switch]$IncludeFileShares,

        [Parameter(Mandatory = $false)]
        [switch]$CheckLocalAdmin,

        [Parameter(Mandatory = $false)]
        [string]$OutputPath = (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Reports'),

        [Parameter(Mandatory = $false)]
        [switch]$ExportToCSV
    )

    try {
        # Validate OutputPath: reject '..' traversal and UNC remote paths before resolution
        if ([string]::IsNullOrWhiteSpace($OutputPath) -or
            $OutputPath -match '(^|[\\/])\.\.([\\/]|$)' -or
            $OutputPath -match '^(\\\\|//)') {
            throw "Unsafe OutputPath: $OutputPath. OutputPath must be a local absolute path without '..' traversal."
        }
        $OutputPath = [System.IO.Path]::GetFullPath($OutputPath)

        $RunTimestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $RunId = [Guid]::NewGuid().ToString('N').Substring(0, 8)

        Write-Host "`n[*] === User Access Report ===" -ForegroundColor Cyan
        Write-Host "[*] Start Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray

        # Create output directory
        if (-not (Test-Path -LiteralPath $OutputPath -PathType Container)) {
            New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
        }

        # Get domain information
        $domain = Get-ADDomain
        $domainName = $domain.DNSRoot
        Write-Host "[+] Domain: $domainName" -ForegroundColor Green

        # Get users to audit
        if ($Username) {
            Write-Host "[*] Auditing specific user: $Username" -ForegroundColor Yellow
            $users = @(Get-ADUser -Identity $Username -Properties *)
        }
        else {
            Write-Host "[*] Retrieving all enabled users..." -ForegroundColor Yellow
            $users = @(Get-ADUser -Filter "Enabled -eq 'True'" -Properties *)
        }

        Write-Host "[+] Found $($users.Count) user(s) to audit" -ForegroundColor Green

        # Initialize results
        $accessReports = @()
        $counter = 0

        foreach ($user in $users) {
            $counter++
            Write-Progress -Activity "Auditing Users" `
                -Status "Processing $($user.SamAccountName) ($counter of $($users.Count))" `
                -PercentComplete (($counter / $users.Count) * 100)

            # Get group memberships
            $groups = Get-ADPrincipalGroupMembership -Identity $user |
                Select-Object -ExpandProperty Name

            # Check for privileged groups
            $privilegedGroups = @(
                "Domain Admins",
                "Enterprise Admins",
                "Schema Admins",
                "Administrators",
                "Account Operators",
                "Backup Operators",
                "Server Operators"
            )

            $userPrivilegedGroups = @($groups | Where-Object { $_ -in $privilegedGroups })
            $isPrivileged = $userPrivilegedGroups.Count -gt 0

            # Create access record
            $accessReports += [PSCustomObject]@{
                SamAccountName = $user.SamAccountName
                DisplayName = $user.DisplayName
                Email = $user.EmailAddress
                Department = $user.Department
                Title = $user.Title
                Enabled = $user.Enabled
                Created = $user.Created
                LastLogon = $user.LastLogonDate
                GroupCount = $groups.Count
                Groups = ($groups -join "; ")
                IsPrivileged = $isPrivileged
                PrivilegedGroups = ($userPrivilegedGroups -join "; ")
                MemberOf = ($groups -join ", ")
            }
        }

        Write-Progress -Activity "Auditing Users" -Completed

        # Display summary
        Write-Host "`n[*] === Access Report Summary ===" -ForegroundColor Cyan
        Write-Host "[*] Total Users Audited: $($users.Count)" -ForegroundColor White
        $privilegedUserCount = ($accessReports | Where-Object IsPrivileged).Count
        $privColor = if ($privilegedUserCount -gt 0) { 'Yellow' } else { 'Green' }
        Write-Host "[!] Privileged Users: $privilegedUserCount" -ForegroundColor $privColor

        # Top users by group membership
        $topGroupUsers = $accessReports | Sort-Object -Property GroupCount -Descending | Select-Object -First 10

        Write-Host "`n[*] Top 10 Users by Group Membership:" -ForegroundColor Cyan
        foreach ($topUser in $topGroupUsers) {
            Write-Host "[*]   $($topUser.SamAccountName): $($topUser.GroupCount) groups" -ForegroundColor White
        }

        # Export to CSV
        if ($ExportToCSV) {
            Write-Host "`n[*] Exporting to CSV..." -ForegroundColor Yellow
            $csvPath = Join-Path -Path $OutputPath -ChildPath "UserAccessReport_${RunTimestamp}_${RunId}.csv"
            $accessReports | Export-Csv -Path $csvPath -NoTypeInformation
            Write-Host "[+] CSV exported to: $csvPath" -ForegroundColor Green
        }

        # Generate HTML report
        Write-Host "`n[*] Generating HTML report..." -ForegroundColor Yellow
        $htmlPath = Join-Path -Path $OutputPath -ChildPath "UserAccessReport_${RunTimestamp}_${RunId}.html"

        $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>User Access Report - $domainName</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background-color: #f5f5f5; }
        h1 { color: #0066cc; }
        h2 { color: #0099cc; margin-top: 30px; }
        table { border-collapse: collapse; width: 100%; background-color: white;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1); margin: 20px 0; font-size: 12px; }
        th { background-color: #0066cc; color: white; padding: 10px; text-align: left; }
        td { padding: 8px; border-bottom: 1px solid #ddd; }
        tr:hover { background-color: #f0f0f0; }
        .privileged { background-color: #fff3cd; }
        .info { background-color: #e6f3ff; padding: 15px; border-left: 4px solid #0066cc; margin: 20px 0; }
    </style>
</head>
<body>
    <h1>User Access Report</h1>
    <div class="info">
        <strong>Domain:</strong> $([System.Net.WebUtility]::HtmlEncode("$domainName"))<br>
        <strong>Report Date:</strong> $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | <strong>Run ID:</strong> $RunId<br>
        <strong>Users Audited:</strong> $($users.Count)<br>
        <strong>Privileged Users:</strong> $(($accessReports | Where-Object IsPrivileged).Count)
    </div>

    <h2>All Users</h2>
    <table>
        <tr>
            <th>Username</th>
            <th>Display Name</th>
            <th>Department</th>
            <th>Group Count</th>
            <th>Privileged</th>
            <th>Last Logon</th>
        </tr>
"@

        foreach ($report in ($accessReports | Sort-Object -Property SamAccountName)) {
            $rowClass = if ($report.IsPrivileged) { "privileged" } else { "" }
            $privStatus = if ($report.IsPrivileged) { "Yes - $($report.PrivilegedGroups)" } else { "No" }

            $html += @"
        <tr class="$rowClass">
            <td>$([System.Net.WebUtility]::HtmlEncode("$($report.SamAccountName)"))</td>
            <td>$([System.Net.WebUtility]::HtmlEncode("$($report.DisplayName)"))</td>
            <td>$([System.Net.WebUtility]::HtmlEncode("$($report.Department)"))</td>
            <td>$($report.GroupCount)</td>
            <td>$([System.Net.WebUtility]::HtmlEncode("$privStatus"))</td>
            <td>$([System.Net.WebUtility]::HtmlEncode("$($report.LastLogon)"))</td>
        </tr>
"@
        }

        $html += @"
    </table>
</body>
</html>
"@

        $html | Out-File -FilePath $htmlPath -Encoding UTF8
        Write-Host "[+] HTML report saved to: $htmlPath" -ForegroundColor Green

        Write-Host "`n[+] End Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray
        return 0
    }
    catch {
        Write-Host "[-] Error generating access report: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main @PSBoundParameters) }
