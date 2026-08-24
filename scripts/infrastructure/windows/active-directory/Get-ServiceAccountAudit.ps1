<#
.SYNOPSIS
    Audits service accounts in Active Directory for security and compliance.

.DESCRIPTION
    This script identifies and audits service accounts including standard user accounts used as
    service accounts (by naming convention and SPN presence), Managed Service Accounts (MSAs),
    Group Managed Service Accounts (gMSAs), service accounts holding privileged group memberships,
    service accounts with weak configurations (password never expires, password not required, stale
    passwords), and Kerberos delegation exposure. Results are summarized to the console and rendered
    as an HTML report, with optional per-category CSV export.

    Behavior notes:
    - Exits with 0 when the audit completes and 1 when a fatal error occurs (including unsafe output paths).
    - The script is read-only against Active Directory and safe to re-run at any time.
    - OutputPath must be a local absolute path without '..' traversal; UNC paths are rejected.

.PARAMETER OutputPath
    Path where the audit report will be saved.

.PARAMETER IncludeSPNAnalysis
    Switch to include detailed Service Principal Name analysis.

.PARAMETER CheckKerberosDelegation
    Switch to check for Kerberos delegation settings.

.PARAMETER ExportToCSV
    Switch to export results to CSV format.

.EXAMPLE
    PS C:\> .\Get-ServiceAccountAudit.ps1 -OutputPath "C:\Reports"
    Performs standard service account audit.

.EXAMPLE
    PS C:\> .\Get-ServiceAccountAudit.ps1 -IncludeSPNAnalysis -CheckKerberosDelegation -ExportToCSV
    Performs comprehensive audit with SPN analysis and Kerberos delegation check.

.NOTES
    File Name     : Get-ServiceAccountAudit.ps1
    Author        : Server Management Team
    Prerequisite  : PowerShell 5.1+
    Version       : 1.0.0
    Date          : 2026-08-23
    Requires      : ActiveDirectory PowerShell module and appropriate AD permissions
#>

[CmdletBinding()]
param(
# Note: these script parameters are consumed by nested functions through PowerShell dynamic
# scoping, which PSScriptAnalyzer cannot see; PSReviewUnusedParameter is a false positive here.
    [Parameter(Mandatory = $false)]
    [string]$OutputPath,

    [Parameter(Mandatory = $false)]
    [switch]$IncludeSPNAnalysis,

    [Parameter(Mandatory = $false)]
    [switch]$CheckKerberosDelegation,

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
        Write-Host "`n[*] === Service Account Audit ===" -ForegroundColor Cyan
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
            Write-Host "`n[*] Scanning for service accounts..." -ForegroundColor Cyan

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

            $allUsers = Get-ADUser -Filter * -Properties * -ErrorAction Stop

            # Identify service accounts by naming convention
            Write-Host "[*] Identifying accounts by naming convention..." -ForegroundColor Cyan
            $potentialServiceAccounts = @()

            foreach ($pattern in $serviceAccountPatterns) {
                $patternMatches = @($allUsers | Where-Object {
                        $_.SamAccountName -like $pattern -or
                        $_.Name -like $pattern -or
                        $_.Description -like "*service*"
                    })
                $potentialServiceAccounts += $patternMatches
            }

            # Remove duplicates
            $potentialServiceAccounts = @($potentialServiceAccounts |
                Sort-Object -Property SamAccountName -Unique)

            $potentialCount = $potentialServiceAccounts.Count
            Write-Host "[*] Found $potentialCount potential service accounts by naming" -ForegroundColor Cyan

            # Get accounts with SPNs (definite service accounts)
            Write-Host "[*] Identifying accounts with Service Principal Names..." -ForegroundColor Cyan

            $spnAccounts = @($allUsers | Where-Object {
                    $_.ServicePrincipalNames.Count -gt 0
                })

            Write-Host "[*] Found $($spnAccounts.Count) accounts with SPNs" -ForegroundColor Cyan

            if ($IncludeSPNAnalysis) {
                Write-Host "[*] SPN analysis:" -ForegroundColor Cyan
                foreach ($spnAccount in $spnAccounts) {
                    foreach ($spn in $spnAccount.ServicePrincipalNames) {
                        Write-Host "    $($spnAccount.SamAccountName): $spn" -ForegroundColor Gray
                    }
                }
            }

            # Combine and deduplicate
            $allServiceAccounts = @(($potentialServiceAccounts + $spnAccounts) |
                Sort-Object -Property SamAccountName -Unique)

            Write-Host "`n[+] Total service accounts identified: $($allServiceAccounts.Count)" -ForegroundColor Green

            # Analyze each service account
            Write-Host "`n[*] Analyzing service accounts..." -ForegroundColor Cyan

            $counter = 0
            foreach ($account in $allServiceAccounts) {
                $counter++
                $progressStatus = "Processing $($account.SamAccountName) ($counter of $($allServiceAccounts.Count))"
                $percentComplete = ($counter / $allServiceAccounts.Count) * 100
                Write-Progress -Activity "Analyzing Service Accounts" `
                    -Status $progressStatus -PercentComplete $percentComplete

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

                $accountGroups = Get-ADPrincipalGroupMembership -Identity $account -ErrorAction Stop |
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
                    PasswordAge = if ($account.PasswordLastSet) {
                        ((Get-Date) - $account.PasswordLastSet).Days
                    }
                    else {
                        "N/A"
                    }
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
            Write-Host "`n[*] Scanning for Managed Service Accounts..." -ForegroundColor Cyan

            try {
                $msas = Get-ADServiceAccount -Filter * -Properties * -ErrorAction Stop

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

                Write-Host "[*] Found $($auditResults.ManagedServiceAccounts.Count) MSAs" -ForegroundColor Cyan
                Write-Host "[*] Found $($auditResults.GroupManagedServiceAccounts.Count) gMSAs" -ForegroundColor Cyan
            }
            catch {
                Write-Host "[!] Could not retrieve Managed Service Accounts: $_" -ForegroundColor Yellow
            }

            # Check Kerberos delegation
            if ($CheckKerberosDelegation) {
                Write-Host "`n[*] Checking Kerberos delegation settings..." -ForegroundColor Cyan

                $delegationAccounts = @($allServiceAccounts | Where-Object {
                        $_.TrustedForDelegation -or
                        $_.TrustedToAuthForDelegation
                    })

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

                $delegationCount = $delegationAccounts.Count
                $delegationColor = if ($delegationCount -gt 0) { 'Yellow' } else { 'Green' }
                $delegationPrefix = if ($delegationCount -gt 0) { '[!]' } else { '[+]' }
                $delegationText = "$delegationPrefix Found $delegationCount accounts with delegation enabled"
                Write-Host $delegationText -ForegroundColor $delegationColor
            }

            # Display summary
            $stdCount = $auditResults.StandardServiceAccounts.Count
            $msaCount = $auditResults.ManagedServiceAccounts.Count
            $gmsaCount = $auditResults.GroupManagedServiceAccounts.Count
            $spnCount = $auditResults.AccountsWithSPNs.Count
            $privCount = $auditResults.PrivilegedServiceAccounts.Count
            $secIssueCount = $auditResults.SecurityIssues.Count
            $delCount = $auditResults.DelegationIssues.Count

            Write-Host "`n[*] === Audit Summary ===" -ForegroundColor Cyan
            Write-Host "Standard Service Accounts: $stdCount" -ForegroundColor White
            Write-Host "Managed Service Accounts (MSA): $msaCount" -ForegroundColor White
            Write-Host "Group Managed Service Accounts (gMSA): $gmsaCount" -ForegroundColor White
            Write-Host "Accounts with SPNs: $spnCount" -ForegroundColor Cyan
            $privColor = if ($privCount -gt 0) { 'Red' } else { 'Green' }
            $privPrefix = if ($privCount -gt 0) { '[-]' } else { '[+]' }
            Write-Host "$privPrefix Privileged Service Accounts: $privCount" -ForegroundColor $privColor
            $secColor = if ($secIssueCount -gt 0) { 'Yellow' } else { 'Green' }
            $secPrefix = if ($secIssueCount -gt 0) { '[!]' } else { '[+]' }
            Write-Host "$secPrefix Accounts with Security Issues: $secIssueCount" -ForegroundColor $secColor

            if ($CheckKerberosDelegation) {
                $delColor = if ($delCount -gt 0) { 'Yellow' } else { 'Green' }
                $delPrefix = if ($delCount -gt 0) { '[!]' } else { '[+]' }
                Write-Host "$delPrefix Accounts with Delegation: $delCount" -ForegroundColor $delColor
            }

            # Export to CSV
            if ($ExportToCSV) {
                Write-Host "`n[*] Exporting to CSV..." -ForegroundColor Cyan

                foreach ($category in $auditResults.Keys) {
                    if (@($auditResults[$category]).Count -gt 0) {
                        $csvName = "${category}_${RunTimestamp}_${RunId}.csv"
                        $csvPath = Join-Path -Path $script:OutputRoot -ChildPath $csvName
                        $auditResults[$category] |
                            Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8 -ErrorAction Stop
                        Write-Host "[+] Exported: $csvName" -ForegroundColor Green
                    }
                }
            }

            # Generate HTML report
            Write-Host "`n[*] Generating HTML report..." -ForegroundColor Cyan
            $reportName = "ServiceAccountAuditReport_${RunTimestamp}_${RunId}.html"
            $htmlPath = Join-Path -Path $script:OutputRoot -ChildPath $reportName

            $privCellClass = if ($privCount -gt 0) { 'warning' } else { '' }
            $secCellClass = if ($secIssueCount -gt 0) { 'warning' } else { '' }

            $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>Service Account Audit - $domainName</title>
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
            font-size: 12px;
        }
        th {
            background-color: #0066cc;
            color: white;
            padding: 10px;
            text-align: left;
        }
        td {
            padding: 8px;
            border-bottom: 1px solid #ddd;
        }
        tr:hover {
            background-color: #f0f0f0;
        }
        .critical {
            background-color: #ffcccc;
        }
        .warning {
            background-color: #fff3cd;
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
    <h1>Service Account Audit Report</h1>
    <div class="info">
        <strong>Domain:</strong> $(Convert-ToHtmlText -Text $domainName)<br>
        <strong>Report Date:</strong> $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | <strong>Run ID:</strong> $RunId<br>
        <strong>Total Service Accounts:</strong> $($auditResults.StandardServiceAccounts.Count)
    </div>

    <h2>Summary</h2>
    <table>
        <tr><td><strong>Standard Service Accounts</strong></td><td>$stdCount</td></tr>
        <tr><td><strong>Managed Service Accounts (MSA)</strong></td><td>$msaCount</td></tr>
        <tr><td><strong>Group Managed Service Accounts (gMSA)</strong></td><td>$gmsaCount</td></tr>
        <tr><td><strong>Accounts with SPNs</strong></td><td>$spnCount</td></tr>
        <tr><td><strong>Privileged Service Accounts</strong></td><td class="$privCellClass">$privCount</td></tr>
        <tr><td><strong>Accounts with Security Issues</strong></td><td class="$secCellClass">$secIssueCount</td></tr>
    </table>
"@

            # Add privileged service accounts section
            if ($auditResults.PrivilegedServiceAccounts.Count -gt 0) {
                $html += "<h2>Privileged Service Accounts (HIGH RISK)</h2><table><tr><th>Account</th>" +
                    "<th>Display Name</th><th>Privileged Groups</th><th>Enabled</th><th>Issues</th></tr>"
                foreach ($account in $auditResults.PrivilegedServiceAccounts) {
                    $rowClass = if ($account.Enabled) { "critical" } else { "warning" }
                    $nameCell = Convert-ToHtmlText -Text $account.SamAccountName
                    $displayCell = Convert-ToHtmlText -Text $account.DisplayName
                    $groupsCell = Convert-ToHtmlText -Text $account.PrivilegedGroups
                    $issuesCell = Convert-ToHtmlText -Text $account.Issues
                    $html += "<tr class='$rowClass'><td>$nameCell</td><td>$displayCell</td>" +
                        "<td>$groupsCell</td><td>$($account.Enabled)</td><td>$issuesCell</td></tr>"
                }
                $html += "</table>"
            }

            # Add security issues section
            if ($auditResults.SecurityIssues.Count -gt 0) {
                $html += "<h2>Service Accounts with Security Issues</h2><table><tr><th>Account</th>" +
                    "<th>Description</th><th>Password Age</th><th>Issues</th></tr>"
                foreach ($account in ($auditResults.SecurityIssues | Select-Object -First 50)) {
                    $nameCell = Convert-ToHtmlText -Text $account.SamAccountName
                    $descCell = Convert-ToHtmlText -Text $account.Description
                    $issuesCell = Convert-ToHtmlText -Text $account.Issues
                    $html += "<tr class='warning'><td>$nameCell</td><td>$descCell</td>" +
                        "<td>$($account.PasswordAge) days</td><td>$issuesCell</td></tr>"
                }
                $html += "</table>"
            }

            # Add gMSA section
            if ($auditResults.GroupManagedServiceAccounts.Count -gt 0) {
                $html += "<h2>Group Managed Service Accounts (Recommended)</h2><table><tr><th>Name</th>" +
                    "<th>Enabled</th><th>Created</th><th>SPNs</th></tr>"
                foreach ($gmsa in $auditResults.GroupManagedServiceAccounts) {
                    $nameCell = Convert-ToHtmlText -Text $gmsa.Name
                    $createdCell = Convert-ToHtmlText -Text $gmsa.Created
                    $spnsCell = Convert-ToHtmlText -Text $gmsa.SPNs
                    $html += "<tr><td>$nameCell</td><td>$($gmsa.Enabled)</td><td>$createdCell</td>" +
                        "<td>$spnsCell</td></tr>"
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

            $html | Out-File -FilePath $htmlPath -Encoding UTF8 -ErrorAction Stop
            Write-Host "[+] HTML report saved to: $htmlPath" -ForegroundColor Green
        }
        catch {
            Write-Host "[-] Error during audit: $($_.Exception.Message)" -ForegroundColor Red
            Write-Verbose $_.ScriptStackTrace
            throw
        }

        Write-Host "`n[+] End Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray
        Write-Host "[+] Service account audit completed successfully" -ForegroundColor Green
        return 0
    }
    catch {
        Write-Host "[-] Error: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
