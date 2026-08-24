<#
.SYNOPSIS
    Audit Azure AD (Entra ID) guest users for security and compliance.

.DESCRIPTION
    Connects to Microsoft Graph and analyzes every guest user for inactivity, disabled
    accounts, missing sign-in activity, privileged (administrator) role assignments, external
    domain representation, and creation dates. Optionally exports the findings to HTML or CSV
    under the user's Documents\Reports folder. Returns exit code 0 on success; exit code 1 on
    connection or retrieval failure, and also when -CheckPrivilegedGuests finds at least one
    guest with an administrator role so remediation pipelines can react to the finding.

.PARAMETER InactivityDays
    Days since last sign-in after which a guest is considered inactive (default: 90).

.PARAMETER CheckPrivilegedGuests
    Identify guest users with administrator role assignments via unified RBAC.

.PARAMETER GroupByDomain
    Group guests by their external domain in the summary output.

.PARAMETER ExportHTML
    Export results to an HTML report file.

.PARAMETER ExportCSV
    Export results to a CSV file.

.EXAMPLE
    PS C:\> .\Get-AzureADGuestAudit.ps1

    Runs a basic guest user audit against the tenant.

.EXAMPLE
    PS C:\> .\Get-AzureADGuestAudit.ps1 -CheckPrivilegedGuests -GroupByDomain -ExportHTML

    Runs a comprehensive guest audit with privilege and domain analysis plus an HTML report.

.NOTES
    File Name  : Get-AzureADGuestAudit.ps1
    Author     : Bug-Free Umbrella
    Prerequisite: PowerShell 7.0
    Version    : 1.0.0
    Date       : 2026-08-23

    Requires Microsoft Graph PowerShell module.
    Requires User.Read.All, AuditLog.Read.All, Directory.Read.All permissions.
    Compatible with Azure AD / Entra ID (Microsoft 365).
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [ValidateRange(1, [int]::MaxValue)]
    [int]$InactivityDays = 90,

    [Parameter(Mandatory = $false)]
    [switch]$CheckPrivilegedGuests,

    [Parameter(Mandatory = $false)]
    [switch]$GroupByDomain,

    [Parameter(Mandatory = $false)]
    [switch]$ExportHTML,

    [Parameter(Mandatory = $false)]
    [switch]$ExportCSV
)

$ErrorActionPreference = 'Stop'

# Resolve (and create if needed) the Documents\Reports directory used by export switches.
function Get-ReportDirectory {
    $reportDir = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Reports'
    if ([string]::IsNullOrWhiteSpace($reportDir) -or
        $reportDir -match '(^|[\\/])\.\.([\\/]|$)' -or
        $reportDir -match '^(\\\\|//)') {
        throw "Unsafe report path: $reportDir. Report path must be a local absolute path without '..' traversal."
    }
    $fullReportDir = [System.IO.Path]::GetFullPath($reportDir)
    if (-not (Test-Path -LiteralPath $fullReportDir -PathType Container)) {
        New-Item -ItemType Directory -Path $fullReportDir -Force -ErrorAction Stop | Out-Null
    }
    return $fullReportDir
}

# Write-Host is intentional throughout: AGENTS.md requires user-facing colored [+] [!] [-] [*] console output.
function Main {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [ValidateRange(1, [int]::MaxValue)]
        [int]$InactivityDays = 90,

        [Parameter(Mandatory = $false)]
        [switch]$CheckPrivilegedGuests,

        [Parameter(Mandatory = $false)]
        [switch]$GroupByDomain,

        [Parameter(Mandatory = $false)]
        [switch]$ExportHTML,

        [Parameter(Mandatory = $false)]
        [switch]$ExportCSV
    )

    try {
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"

        Write-Host "`n=== Azure AD Guest User Audit ===" -ForegroundColor Cyan
        Write-Host "Inactivity Threshold: $InactivityDays days" -ForegroundColor Yellow
        Write-Host "Timestamp: $(Get-Date)" -ForegroundColor Gray
        Write-Host ""

        # Connect to Microsoft Graph
        try {
            Write-Host "[*] Connecting to Microsoft Graph..." -ForegroundColor Cyan

            $scopes = @("User.Read.All", "AuditLog.Read.All", "Directory.Read.All")
            Connect-MgGraph -Scopes $scopes -NoWelcome -ErrorAction Stop

            Write-Host "[+] Connected to Microsoft Graph" -ForegroundColor Green
        }
        catch {
            Write-Host "[-] Error connecting: $($_.Exception.Message)" -ForegroundColor Red
            return 1
        }

        Write-Host ""

        # Get guest users
        Write-Host "[*] Retrieving guest users..." -ForegroundColor Cyan

        try {
            $guestUsers = @(Get-MgUser -Filter "userType eq 'Guest'" -All `
                -Property DisplayName, UserPrincipalName, Mail, UserType, CreatedDateTime, `
                    SignInActivity, AccountEnabled `
                -ErrorAction Stop)

            Write-Host "[+] Found $($guestUsers.Count) guest user(s)" -ForegroundColor Green
        }
        catch {
            Write-Host "[-] Error retrieving guests: $($_.Exception.Message)" -ForegroundColor Red
            return 1
        }

        Write-Host ""

        $results = @()
        $inactiveGuests = 0
        $privilegedGuests = 0
        $disabledGuests = 0
        $neverSignedIn = 0
        $inactivityThreshold = (Get-Date).AddDays(-$InactivityDays)

        $i = 0
        foreach ($guest in $guestUsers) {
            $i++
            $progressStatus = "$i of $($guestUsers.Count): $($guest.DisplayName)"
            Write-Progress -Activity "Analyzing Guest Users" -Status $progressStatus `
                -PercentComplete (($i / $guestUsers.Count) * 100)

            # Get sign-in activity
            $lastSignIn = $guest.SignInActivity.LastSignInDateTime

            $isInactive = $false
            if ($lastSignIn) {
                if ($lastSignIn -lt $inactivityThreshold) {
                    $isInactive = $true
                    $inactiveGuests++
                }
            }
            else {
                $isInactive = $true
                $neverSignedIn++
            }

            # Check if disabled
            if (-not $guest.AccountEnabled) {
                $disabledGuests++
            }

            # Extract domain
            $domain = "Unknown"
            if ($guest.Mail) {
                $domain = $guest.Mail.Split('@')[1]
            }
            elseif ($guest.UserPrincipalName) {
                $upnParts = $guest.UserPrincipalName.Split('#')
                if ($upnParts.Count -gt 1) {
                    $domain = $upnParts[1].Split('_')[0]
                }
            }

            # Check for privileged roles
            $isPrivileged = $false
            $roles = @()
            if ($CheckPrivilegedGuests) {
                try {
                    # Get-MgDirectoryRole (legacy directory roles) is discouraged; use unified RBAC:
                    # role assignments, with role display names resolved from the role definition.
                    $roleFilter = "principalId eq '$($guest.Id)'"
                    $roleAssignments = Get-MgRoleManagementDirectoryRoleAssignment -Filter $roleFilter `
                        -All -ErrorAction SilentlyContinue

                    if ($roleAssignments) {
                        $isPrivileged = $true
                        $privilegedGuests++
                        $roles = $roleAssignments | ForEach-Object {
                            $roleDefinition = Get-MgRoleManagementDirectoryRoleDefinition `
                                -UnifiedRoleDefinitionId $_.RoleDefinitionId -ErrorAction SilentlyContinue
                            if ($roleDefinition) { $roleDefinition.DisplayName }
                        } | Where-Object { $_ }
                    }
                }
                catch {
                    Write-Verbose "Handled exception: $($_.Exception.Message)" -Verbose:$false
                }
            }

            $result = [PSCustomObject]@{
                DisplayName = $guest.DisplayName
                UserPrincipalName = $guest.UserPrincipalName
                Email = $guest.Mail
                Domain = $domain
                CreatedDate = $guest.CreatedDateTime
                LastSignIn = $lastSignIn
                IsInactive = $isInactive
                AccountEnabled = $guest.AccountEnabled
                IsPrivileged = $isPrivileged
                Roles = $roles -join '; '
                DaysSinceLastSignIn = if ($lastSignIn) { ((Get-Date) - $lastSignIn).Days } else { "Never" }
            }

            $results += $result
        }

        Write-Progress -Activity "Analyzing Guest Users" -Completed

        Write-Host ""

        # Summary
        Write-Host "=== Summary ===" -ForegroundColor Cyan
        Write-Host "Total Guest Users: $($results.Count)" -ForegroundColor White
        Write-Host "Inactive Guests (> $InactivityDays days): $inactiveGuests" -ForegroundColor Yellow
        Write-Host "Never Signed In: $neverSignedIn" -ForegroundColor Yellow
        Write-Host "Disabled Accounts: $disabledGuests" -ForegroundColor Gray
        if ($CheckPrivilegedGuests) {
            $privColor = if ($privilegedGuests -gt 0) { "Red" } else { "Green" }
            Write-Host "Privileged Guests (CRITICAL): $privilegedGuests" -ForegroundColor $privColor
        }
        Write-Host ""

        # Domain breakdown
        if ($GroupByDomain) {
            Write-Host "=== Guests by Domain ===" -ForegroundColor Cyan
            $results | Group-Object Domain | Sort-Object Count -Descending | Select-Object -First 10 |
                ForEach-Object {
                    Write-Host "  $($_.Name): $($_.Count) guest(s)" -ForegroundColor White
                }
            Write-Host ""
        }

        # Show privileged guests
        if ($CheckPrivilegedGuests -and $privilegedGuests -gt 0) {
            Write-Host "=== Privileged Guest Users (CRITICAL) ===" -ForegroundColor Red
            $results | Where-Object { $_.IsPrivileged -eq $true } |
                Select-Object DisplayName, Email, Roles |
                Format-Table -AutoSize
        }

        # Show inactive guests
        if ($inactiveGuests -gt 0) {
            Write-Host "`n=== Top 10 Inactive Guest Users ===" -ForegroundColor Yellow
            $results | Where-Object { $_.IsInactive -eq $true } |
                Sort-Object LastSignIn |
                Select-Object -First 10 DisplayName, Email, LastSignIn, DaysSinceLastSignIn |
                Format-Table -AutoSize
        }

        # Export
        if ($ExportHTML) {
            $reportDir = Get-ReportDirectory
            $htmlPath = Join-Path $reportDir "GuestUserAudit_$timestamp.html"

            $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>Guest User Audit - $timestamp</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        h1 { color: #0078d4; }
        .summary { background-color: #f0f0f0; padding: 15px; border-radius: 5px; margin: 20px 0; }
        table { border-collapse: collapse; width: 100%; margin-top: 10px; font-size: 12px; }
        th { background-color: #0078d4; color: white; padding: 10px; text-align: left; }
        td { border: 1px solid #ddd; padding: 8px; }
        tr:nth-child(even) { background-color: #f2f2f2; }
        .critical { background-color: #ffe6e6; }
        .inactive { background-color: #fff3cd; }
    </style>
</head>
<body>
    <h1>Azure AD Guest User Audit Report</h1>
    <div class="summary">
        <strong>Generated:</strong> $(Get-Date)<br>
        <strong>Total Guest Users:</strong> $($results.Count)<br>
        <strong>Inactive:</strong> $inactiveGuests<br>
        <strong>Never Signed In:</strong> $neverSignedIn<br>
        <strong>Disabled:</strong> $disabledGuests<br>
        <strong>Privileged:</strong> $privilegedGuests
    </div>

    <h2>Guest User Details</h2>
    <table>
        <tr>
            <th>Display Name</th>
            <th>Email</th>
            <th>Domain</th>
            <th>Last Sign-In</th>
            <th>Days Inactive</th>
            <th>Enabled</th>
            <th>Privileged</th>
        </tr>
"@

            foreach ($result in ($results | Sort-Object DisplayName)) {
                $rowClass = ""
                if ($result.IsPrivileged) { $rowClass = "critical" }
                elseif ($result.IsInactive) { $rowClass = "inactive" }
                $html += @"
        <tr class="$rowClass">
            <td>$($result.DisplayName)</td>
            <td>$($result.Email)</td>
            <td>$($result.Domain)</td>
            <td>$($result.LastSignIn)</td>
            <td>$($result.DaysSinceLastSignIn)</td>
            <td>$($result.AccountEnabled)</td>
            <td>$($result.IsPrivileged)</td>
        </tr>
"@
            }

            $html += "</table></body></html>"
            $html | Out-File -FilePath $htmlPath -Encoding UTF8 -ErrorAction Stop
            Write-Host "[+] HTML report saved to: $htmlPath" -ForegroundColor Green
        }

        if ($ExportCSV) {
            $reportDir = Get-ReportDirectory
            $csvPath = Join-Path $reportDir "GuestUserAudit_$timestamp.csv"
            $results | Export-Csv -Path $csvPath -NoTypeInformation -ErrorAction Stop
            Write-Host "[+] CSV export saved to: $csvPath" -ForegroundColor Green
        }

        Write-Host "`n[+] Audit completed!" -ForegroundColor Green

        Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null

        if ($privilegedGuests -gt 0) {
            return 1
        }

        return 0
    }
    catch {
        Write-Host "[-] Error: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main @PSBoundParameters) }
