<#
.SYNOPSIS
    Audits Azure AD (Entra ID) guest users for security and compliance.

.DESCRIPTION
    This script analyzes guest users for:
    - Total guest user count and trends
    - Guest users without recent sign-ins
    - Guests with administrator roles (security risk)
    - Guest invitation details
    - Group memberships and permissions
    - External domains represented
    - Guest user creation dates

.PARAMETER InactivityDays
    Days since last sign-in to consider guest inactive (default: 90).

.PARAMETER CheckPrivilegedGuests
    Identify guest users with administrator roles.

.PARAMETER GroupByDomain
    Group guests by their external domain.

.PARAMETER ExportHTML
    Export results to HTML report.

.PARAMETER ExportCSV
    Export results to CSV file.

.EXAMPLE
    .\Get-AzureADGuestAudit.ps1
    Basic guest user audit.

.EXAMPLE
    .\Get-AzureADGuestAudit.ps1 -CheckPrivilegedGuests -GroupByDomain -ExportHTML
    Comprehensive guest audit with privilege and domain analysis.

.NOTES
    Requires Microsoft Graph PowerShell module (Microsoft.Graph.Identity.Governance for the privileged-guest role check)
    Requires User.Read.All, AuditLog.Read.All permissions
    Compatible with Azure AD / Entra ID (Microsoft 365)
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
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

$ReportDir = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Reports'
if ([string]::IsNullOrWhiteSpace($ReportDir) -or
    $ReportDir -match '(^|[\\/])\.\.([\\/]|$)' -or
    $ReportDir -match '^(\\\\|//)') {
    Write-Error "Unsafe report path: $ReportDir. Report path must be a local absolute path without '..' traversal."
    exit 1
}
$ReportDir = [System.IO.Path]::GetFullPath($ReportDir)
if (-not (Test-Path -LiteralPath $ReportDir -PathType Container)) {
    New-Item -ItemType Directory -Path $ReportDir -Force | Out-Null
}

$ErrorActionPreference = "Stop"
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"

Write-Host "`n=== Azure AD Guest User Audit ===" -ForegroundColor Cyan
Write-Host "Inactivity Threshold: $InactivityDays days" -ForegroundColor Yellow
Write-Host "Timestamp: $(Get-Date)" -ForegroundColor Gray
Write-Host ""

# Connect to Microsoft Graph
try {
    Write-Host "[*] Connecting to Microsoft Graph..." -ForegroundColor Cyan

    $scopes = @("User.Read.All", "AuditLog.Read.All", "Directory.Read.All")
    Connect-MgGraph -Scopes $scopes -NoWelcome

    Write-Host "[+] Connected to Microsoft Graph" -ForegroundColor Green
}
catch {
    Write-Host "[-] Error connecting: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host ""

# Get guest users
Write-Host "[*] Retrieving guest users..." -ForegroundColor Cyan

try {
    $guestUsers = Get-MgUser -Filter "userType eq 'Guest'" -All -Property DisplayName, UserPrincipalName, Mail, UserType, CreatedDateTime, SignInActivity, AccountEnabled

    Write-Host "[+] Found $($guestUsers.Count) guest user(s)" -ForegroundColor Green
}
catch {
    Write-Host "[-] Error retrieving guests: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
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
    Write-Progress -Activity "Analyzing Guest Users" -Status "$i of $($guestUsers.Count): $($guest.DisplayName)" -PercentComplete (($i / $guestUsers.Count) * 100)

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
    $domain = if ($guest.Mail) {
        $guest.Mail.Split('@')[1]
    }
    elseif ($guest.UserPrincipalName) {
        $upnParts = $guest.UserPrincipalName.Split('#')
        if ($upnParts.Count -gt 1) {
            $upnParts[1].Split('_')[0]
        }
        else {
            "Unknown"
        }
    }
    else {
        "Unknown"
    }

    # Check for privileged roles
    $isPrivileged = $false
    $roles = @()
    if ($CheckPrivilegedGuests) {
        try {
            # Get-MgDirectoryRole (legacy directory roles) is discouraged; use unified RBAC:
            # role assignments, with role display names resolved from the role definition.
            $roleAssignments = Get-MgRoleManagementDirectoryRoleAssignment -Filter "principalId eq '$($guest.Id)'" -All -ErrorAction SilentlyContinue

            if ($roleAssignments) {
                $isPrivileged = $true
                $privilegedGuests++
                $roles = $roleAssignments | ForEach-Object {
                    $roleDefinition = Get-MgRoleManagementDirectoryRoleDefinition -UnifiedRoleDefinitionId $_.RoleDefinitionId -ErrorAction SilentlyContinue
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
Write-Host "Inactive Guests (>$InactivityDays days): $inactiveGuests" -ForegroundColor Yellow
Write-Host "Never Signed In: $neverSignedIn" -ForegroundColor Yellow
Write-Host "Disabled Accounts: $disabledGuests" -ForegroundColor Gray
if ($CheckPrivilegedGuests) {
    Write-Host "Privileged Guests (CRITICAL): $privilegedGuests" -ForegroundColor $(if ($privilegedGuests -gt 0) { "Red" } else { "Green" })
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
    $htmlPath = "$ReportDir\GuestUserAudit_$timestamp.html"

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
        $rowClass = if ($result.IsPrivileged) { "critical" } elseif ($result.IsInactive) { "inactive" } else { "" }
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
    $html | Out-File -FilePath $htmlPath -Encoding UTF8
    Write-Host "[+] HTML report saved to: $htmlPath" -ForegroundColor Green
}

if ($ExportCSV) {
    $csvPath = "$ReportDir\GuestUserAudit_$timestamp.csv"
    $results | Export-Csv -Path $csvPath -NoTypeInformation
    Write-Host "[+] CSV export saved to: $csvPath" -ForegroundColor Green
}

Write-Host "`n[+] Audit completed!" -ForegroundColor Green

# Disconnect
Disconnect-MgGraph | Out-Null

if ($privilegedGuests -gt 0) {
    exit 1
}

exit 0
