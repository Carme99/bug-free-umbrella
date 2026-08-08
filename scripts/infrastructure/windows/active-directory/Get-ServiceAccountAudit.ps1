<#
.SYNOPSIS
    Audits service accounts in Active Directory for security and compliance.

.DESCRIPTION
    This script identifies and audits service accounts including:
    - Standard user accounts used as service accounts
    - Managed Service Accounts (MSAs)
    - Group Managed Service Accounts (gMSAs)
    - Service accounts with excessive privileges
    - Service accounts with weak configurations
    - Service Principal Names (SPNs)

.PARAMETER OutputPath
    Path where the audit report will be saved.

.PARAMETER IncludeSPNAnalysis
    Switch to include detailed Service Principal Name analysis.

.PARAMETER CheckKerberosDelegation
    Switch to check for Kerberos delegation settings.

.PARAMETER ExportToCSV
    Switch to export results to CSV format.

.EXAMPLE
    .\Get-ServiceAccountAudit.ps1 -OutputPath "C:\Reports"
    Performs standard service account audit.

.EXAMPLE
    .\Get-ServiceAccountAudit.ps1 -IncludeSPNAnalysis -CheckKerberosDelegation -ExportToCSV
    Performs comprehensive audit with SPN analysis and Kerberos delegation check.

.NOTES
    Author: Server Management Team
    Requires: ActiveDirectory PowerShell module, appropriate permissions
    Version: 1.0
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$OutputPath = (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Reports'),

    [Parameter(Mandatory = $false)]
    [switch]$IncludeSPNAnalysis,

    [Parameter(Mandatory = $false)]
    [switch]$CheckKerberosDelegation,

    [Parameter(Mandatory = $false)]
    [switch]$ExportToCSV
)

#Requires -Module ActiveDirectory

# Validate OutputPath: reject '..' traversal and UNC remote paths before resolution
if ([string]::IsNullOrWhiteSpace($OutputPath) -or
    $OutputPath -match '(^|[\\/])\.\.([\\/]|$)' -or
    $OutputPath -match '^(\\\\|//)') {
    Write-Error "Unsafe OutputPath: $OutputPath. OutputPath must be a local absolute path without '..' traversal."
    exit 1
}
$OutputPath = [System.IO.Path]::GetFullPath($OutputPath)

$RunTimestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$RunId = [Guid]::NewGuid().ToString('N').Substring(0, 8)

Write-Host "`n=== Service Account Audit ===" -ForegroundColor Cyan
Write-Host "Start Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray

# Create output directory
if (-not (Test-Path -LiteralPath $OutputPath -PathType Container)) {
    New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
}

try {
    # Get domain information
    $domain = Get-ADDomain
    $domainName = $domain.DNSRoot
    Write-Host "`nDomain: $domainName" -ForegroundColor Green

    # Initialize results
    $auditResults = @{
        StandardServiceAccounts = @()
        ManagedServiceAccounts = @()
        GroupManagedServiceAccounts = @()
        AccountsWithSPNs = @()
        PrivilegedServiceAccounts = @()
        DelegationIssues = @()
        SecurityIssues = @()
    }

    # Get all user accounts (potential service accounts)
    Write-Host "`nScanning for service accounts..." -ForegroundColor Yellow

    # Common service account patterns
    $serviceAccountPatterns = @(
        "svc*",
        "*service*",
        "*admin*",
        "sa_*",
        "*_svc",
        "sqlservice*",
        "iis*"
    )

    $allUsers = Get-ADUser -Filter * -Properties *

    # Identify service accounts by naming convention
    Write-Host "Identifying accounts by naming convention..." -ForegroundColor Yellow
    $potentialServiceAccounts = @()

    foreach ($pattern in $serviceAccountPatterns) {
        $matches = $allUsers | Where-Object {
            $_.SamAccountName -like $pattern -or
            $_.Name -like $pattern -or
            $_.Description -like "*service*"
        }
        $potentialServiceAccounts += $matches
    }

    # Remove duplicates
    $potentialServiceAccounts = $potentialServiceAccounts | Sort-Object -Property SamAccountName -Unique

    Write-Host "Found $($potentialServiceAccounts.Count) potential service accounts by naming" -ForegroundColor Cyan

    # Get accounts with SPNs (definite service accounts)
    Write-Host "Identifying accounts with Service Principal Names..." -ForegroundColor Yellow

    $accountsWithSPNs = $allUsers | Where-Object {
        $_.ServicePrincipalNames.Count -gt 0
    }

    Write-Host "Found $($accountsWithSPNs.Count) accounts with SPNs" -ForegroundColor Cyan

    # Combine and deduplicate
    $allServiceAccounts = ($potentialServiceAccounts + $accountsWithSPNs) |
        Sort-Object -Property SamAccountName -Unique

    Write-Host "`nTotal service accounts identified: $($allServiceAccounts.Count)" -ForegroundColor Green

    # Analyze each service account
    Write-Host "`nAnalyzing service accounts..." -ForegroundColor Yellow

    $counter = 0
    foreach ($account in $allServiceAccounts) {
        $counter++
        Write-Progress -Activity "Analyzing Service Accounts" -Status "Processing $($account.SamAccountName) ($counter of $($allServiceAccounts.Count))" -PercentComplete (($counter / $allServiceAccounts.Count) * 100)

        $issues = @()

        # Check password settings
        if ($account.PasswordNeverExpires) {
            $issues += "Password never expires"
        }

        if ($account.PasswordNotRequired) {
            $issues += "Password not required"
        }

        # Check password age
        if ($account.PasswordLastSet) {
            $passwordAge = ((Get-Date) - $account.PasswordLastSet).Days
            if ($passwordAge -gt 365) {
                $issues += "Password older than 1 year ($passwordAge days)"
            }
        }

        # Check if account is enabled but never logged in
        if ($account.Enabled -and -not $account.LastLogonDate) {
            $issues += "Never logged in"
        }

        # Check for privileged group membership
        $privilegedGroups = @(
            "Domain Admins",
            "Enterprise Admins",
            "Schema Admins",
            "Administrators"
        )

        $accountGroups = Get-ADPrincipalGroupMembership -Identity $account |
            Select-Object -ExpandProperty Name

        $isPrivileged = $false
        $privilegedMemberships = @()

        foreach ($privGroup in $privilegedGroups) {
            if ($accountGroups -contains $privGroup) {
                $isPrivileged = $true
                $privilegedMemberships += $privGroup
                $issues += "Member of $privGroup"
            }
        }

        # Build service account record
        $serviceAccountRecord = [PSCustomObject]@{
            SamAccountName = $account.SamAccountName
            DisplayName = $account.DisplayName
            Description = $account.Description
            Enabled = $account.Enabled
            Created = $account.Created
            LastLogon = $account.LastLogonDate
            PasswordLastSet = $account.PasswordLastSet
            PasswordNeverExpires = $account.PasswordNeverExpires
            PasswordAge = if ($account.PasswordLastSet) { ((Get-Date) - $account.PasswordLastSet).Days } else { "N/A" }
            SPNCount = $account.ServicePrincipalNames.Count
            SPNs = ($account.ServicePrincipalNames -join "; ")
            IsPrivileged = $isPrivileged
            PrivilegedGroups = ($privilegedMemberships -join ", ")
            TrustedForDelegation = $account.TrustedForDelegation
            Issues = ($issues -join "; ")
        }

        $auditResults.StandardServiceAccounts += $serviceAccountRecord

        if ($isPrivileged) {
            $auditResults.PrivilegedServiceAccounts += $serviceAccountRecord
        }

        if ($account.ServicePrincipalNames.Count -gt 0) {
            $auditResults.AccountsWithSPNs += $serviceAccountRecord
        }

        if ($issues.Count -gt 0) {
            $auditResults.SecurityIssues += $serviceAccountRecord
        }
    }

    Write-Progress -Activity "Analyzing Service Accounts" -Completed

    # Get Managed Service Accounts
    Write-Host "`nScanning for Managed Service Accounts..." -ForegroundColor Yellow

    try {
        $msas = Get-ADServiceAccount -Filter * -Properties *

        foreach ($msa in $msas) {
            $msaRecord = [PSCustomObject]@{
                Name = $msa.Name
                SamAccountName = $msa.SamAccountName
                Type = if ($msa.ObjectClass -eq 'msDS-GroupManagedServiceAccount') { "gMSA" } else { "MSA" }
                Enabled = $msa.Enabled
                Created = $msa.Created
                LastLogon = $msa.LastLogonDate
                SPNs = ($msa.ServicePrincipalNames -join "; ")
                PrincipalsAllowedToRetrieve = if ($msa.'PrincipalsAllowedToRetrieveManagedPassword') {
                    ($msa.'PrincipalsAllowedToRetrieveManagedPassword' -join "; ")
                }
                else {
                    "None"
                }
            }

            if ($msa.ObjectClass -eq 'msDS-GroupManagedServiceAccount') {
                $auditResults.GroupManagedServiceAccounts += $msaRecord
            }
            else {
                $auditResults.ManagedServiceAccounts += $msaRecord
            }
        }

        Write-Host "Found $($auditResults.ManagedServiceAccounts.Count) MSAs" -ForegroundColor Cyan
        Write-Host "Found $($auditResults.GroupManagedServiceAccounts.Count) gMSAs" -ForegroundColor Cyan
    }
    catch {
        Write-Warning "Could not retrieve Managed Service Accounts: $_"
    }

    # Check Kerberos delegation
    if ($CheckKerberosDelegation) {
        Write-Host "`nChecking Kerberos delegation settings..." -ForegroundColor Yellow

        $delegationAccounts = $allServiceAccounts | Where-Object {
            $_.TrustedForDelegation -or
            $_.TrustedToAuthForDelegation
        }

        foreach ($account in $delegationAccounts) {
            $delegationType = @()
            if ($account.TrustedForDelegation) {
                $delegationType += "Unconstrained"
            }
            if ($account.TrustedToAuthForDelegation) {
                $delegationType += "Constrained"
            }

            $auditResults.DelegationIssues += [PSCustomObject]@{
                SamAccountName = $account.SamAccountName
                DisplayName = $account.DisplayName
                DelegationType = ($delegationType -join ", ")
                Enabled = $account.Enabled
                SPNs = ($account.ServicePrincipalNames -join "; ")
            }
        }

        Write-Host "Found $($delegationAccounts.Count) accounts with delegation enabled" -ForegroundColor $(if ($delegationAccounts.Count -gt 0) { 'Yellow' } else { 'Green' })
    }

    # Display summary
    Write-Host "`n=== Audit Summary ===" -ForegroundColor Cyan
    Write-Host "Standard Service Accounts: $($auditResults.StandardServiceAccounts.Count)" -ForegroundColor White
    Write-Host "Managed Service Accounts (MSA): $($auditResults.ManagedServiceAccounts.Count)" -ForegroundColor White
    Write-Host "Group Managed Service Accounts (gMSA): $($auditResults.GroupManagedServiceAccounts.Count)" -ForegroundColor White
    Write-Host "Accounts with SPNs: $($auditResults.AccountsWithSPNs.Count)" -ForegroundColor Cyan
    Write-Host "Privileged Service Accounts: $($auditResults.PrivilegedServiceAccounts.Count)" -ForegroundColor $(if ($auditResults.PrivilegedServiceAccounts.Count -gt 0) { 'Red' } else { 'Green' })
    Write-Host "Accounts with Security Issues: $($auditResults.SecurityIssues.Count)" -ForegroundColor $(if ($auditResults.SecurityIssues.Count -gt 0) { 'Yellow' } else { 'Green' })

    if ($CheckKerberosDelegation) {
        Write-Host "Accounts with Delegation: $($auditResults.DelegationIssues.Count)" -ForegroundColor $(if ($auditResults.DelegationIssues.Count -gt 0) { 'Yellow' } else { 'Green' })
    }

    # Export to CSV
    if ($ExportToCSV) {
        Write-Host "`nExporting to CSV..." -ForegroundColor Yellow

        foreach ($category in $auditResults.Keys) {
            if ($auditResults[$category].Count -gt 0) {
                $csvPath = Join-Path -Path $OutputPath -ChildPath "${category}_${RunTimestamp}_${RunId}.csv"
                $auditResults[$category] | Export-Csv -Path $csvPath -NoTypeInformation
                Write-Host "  Exported: ${category}_${RunTimestamp}_${RunId}.csv" -ForegroundColor Green
            }
        }
    }

    # Generate HTML report
    Write-Host "`nGenerating HTML report..." -ForegroundColor Yellow
    $htmlPath = Join-Path -Path $OutputPath -ChildPath "ServiceAccountAuditReport_${RunTimestamp}_${RunId}.html"

    $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>Service Account Audit - $domainName</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background-color: #f5f5f5; }
        h1 { color: #0066cc; }
        h2 { color: #0099cc; margin-top: 30px; }
        table { border-collapse: collapse; width: 100%; background-color: white; box-shadow: 0 2px 4px rgba(0,0,0,0.1); margin: 20px 0; font-size: 12px; }
        th { background-color: #0066cc; color: white; padding: 10px; text-align: left; }
        td { padding: 8px; border-bottom: 1px solid #ddd; }
        tr:hover { background-color: #f0f0f0; }
        .critical { background-color: #ffcccc; }
        .warning { background-color: #fff3cd; }
        .good { color: #009900; }
        .info { background-color: #e6f3ff; padding: 15px; border-left: 4px solid #0066cc; margin: 20px 0; }
    </style>
</head>
<body>
    <h1>Service Account Audit Report</h1>
    <div class="info">
        <strong>Domain:</strong> $([System.Net.WebUtility]::HtmlEncode("$domainName"))<br>
        <strong>Report Date:</strong> $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | <strong>Run ID:</strong> $RunId<br>
        <strong>Total Service Accounts:</strong> $($auditResults.StandardServiceAccounts.Count)
    </div>

    <h2>Summary</h2>
    <table>
        <tr><td><strong>Standard Service Accounts</strong></td><td>$($auditResults.StandardServiceAccounts.Count)</td></tr>
        <tr><td><strong>Managed Service Accounts (MSA)</strong></td><td>$($auditResults.ManagedServiceAccounts.Count)</td></tr>
        <tr><td><strong>Group Managed Service Accounts (gMSA)</strong></td><td>$($auditResults.GroupManagedServiceAccounts.Count)</td></tr>
        <tr><td><strong>Accounts with SPNs</strong></td><td>$($auditResults.AccountsWithSPNs.Count)</td></tr>
        <tr><td><strong>Privileged Service Accounts</strong></td><td class="$(if ($auditResults.PrivilegedServiceAccounts.Count -gt 0) { 'warning' })">$($auditResults.PrivilegedServiceAccounts.Count)</td></tr>
        <tr><td><strong>Accounts with Security Issues</strong></td><td class="$(if ($auditResults.SecurityIssues.Count -gt 0) { 'warning' })">$($auditResults.SecurityIssues.Count)</td></tr>
    </table>
"@

    # Add privileged service accounts section
    if ($auditResults.PrivilegedServiceAccounts.Count -gt 0) {
        $html += "<h2>Privileged Service Accounts (HIGH RISK)</h2><table><tr><th>Account</th><th>Display Name</th><th>Privileged Groups</th><th>Enabled</th><th>Issues</th></tr>"
        foreach ($account in $auditResults.PrivilegedServiceAccounts) {
            $rowClass = if ($account.Enabled) { "critical" } else { "warning" }
            $html += "<tr class='$rowClass'><td>$([System.Net.WebUtility]::HtmlEncode("$($account.SamAccountName)"))</td><td>$([System.Net.WebUtility]::HtmlEncode("$($account.DisplayName)"))</td><td>$([System.Net.WebUtility]::HtmlEncode("$($account.PrivilegedGroups)"))</td><td>$($account.Enabled)</td><td>$([System.Net.WebUtility]::HtmlEncode("$($account.Issues)"))</td></tr>"
        }
        $html += "</table>"
    }

    # Add security issues section
    if ($auditResults.SecurityIssues.Count -gt 0) {
        $html += "<h2>Service Accounts with Security Issues</h2><table><tr><th>Account</th><th>Description</th><th>Password Age</th><th>Issues</th></tr>"
        foreach ($account in ($auditResults.SecurityIssues | Select-Object -First 50)) {
            $html += "<tr class='warning'><td>$([System.Net.WebUtility]::HtmlEncode("$($account.SamAccountName)"))</td><td>$([System.Net.WebUtility]::HtmlEncode("$($account.Description)"))</td><td>$($account.PasswordAge) days</td><td>$([System.Net.WebUtility]::HtmlEncode("$($account.Issues)"))</td></tr>"
        }
        $html += "</table>"
    }

    # Add gMSA section
    if ($auditResults.GroupManagedServiceAccounts.Count -gt 0) {
        $html += "<h2>Group Managed Service Accounts (Recommended)</h2><table><tr><th>Name</th><th>Enabled</th><th>Created</th><th>SPNs</th></tr>"
        foreach ($gmsa in $auditResults.GroupManagedServiceAccounts) {
            $html += "<tr><td>$([System.Net.WebUtility]::HtmlEncode("$($gmsa.Name)"))</td><td>$($gmsa.Enabled)</td><td>$([System.Net.WebUtility]::HtmlEncode("$($gmsa.Created)"))</td><td>$([System.Net.WebUtility]::HtmlEncode("$($gmsa.SPNs)"))</td></tr>"
        }
        $html += "</table>"
    }

    $html += @"
    <h2>Recommendations</h2>
    <ul>
        <li>Migrate standard service accounts to Group Managed Service Accounts (gMSA) where possible</li>
        <li>Remove service accounts from privileged groups (Domain Admins, etc.)</li>
        <li>Ensure service account passwords are rotated regularly</li>
        <li>Disable or remove unused service accounts</li>
        <li>Review and minimize Kerberos delegation where possible</li>
        <li>Use strong, unique passwords for each service account</li>
        <li>Document all service accounts and their purposes</li>
    </ul>
</body>
</html>
"@

    $html | Out-File -FilePath $htmlPath -Encoding UTF8
    Write-Host "HTML report saved to: $htmlPath" -ForegroundColor Green

}
catch {
    Write-Error "Error during audit: $_"
    Write-Error $_.ScriptStackTrace
    exit 1
}

Write-Host "`nEnd Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray
