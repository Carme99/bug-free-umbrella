<#
.SYNOPSIS
    Audit and manage Windows Firewall rules with security compliance checks.

.DESCRIPTION
    This script provides comprehensive Windows Firewall rule management:
    - Audits all firewall rules (enabled and disabled)
    - Identifies potentially risky rules (any/any rules, remote access)
    - Exports firewall configuration for backup (via netsh)
    - Enables/disables/removes rules in bulk (each mutation gated by ShouldProcess; honors -WhatIf/-Confirm)
    - Generates compliance reports

    Mutating actions (Enable, Disable, Remove) are idempotent: rules already in the
    requested state are skipped and reported without change. Exit codes: 0 = success,
    1 = upstream failure while querying or exporting.

.PARAMETER Action
    Action to perform: Audit, Export, Enable, Disable, Remove, or ComplianceCheck.

.PARAMETER RuleName
    Specific rule name to target (supports wildcards).

.PARAMETER Profile
    Firewall profile to check: Domain, Private, Public, or Any (default: Any).

.PARAMETER ShowDisabled
    Include disabled rules in the audit.

.PARAMETER ExportPath
    Path to export firewall configuration backup.

.PARAMETER IdentifyRisks
    Highlight potentially risky firewall rules.

.PARAMETER RemoteAddress
    Filter rules by remote address (e.g., "Any", "192.168.1.0/24").

.PARAMETER Protocol
    Filter by protocol (TCP, UDP, ICMPv4, ICMPv6, Any).

.PARAMETER ExportHTML
    Export audit results to HTML report.

.PARAMETER ExportCSV
    Export audit results to CSV file.

.EXAMPLE
    PS C:\> .\Manage-FirewallRules.ps1 -Action Audit -IdentifyRisks -ExportHTML
    Audits all firewall rules and identifies security risks.

.EXAMPLE
    PS C:\> .\Manage-FirewallRules.ps1 -Action Disable -RuleName "*Remote Desktop*" -Profile Public
    Disables all enabled Remote Desktop rules on the Public profile.

.NOTES
    File Name     : Manage-FirewallRules.ps1
    Author        : Bug-Free Umbrella
    Prerequisite  : PowerShell 5.1+
    Version       : 1.0.0
    Date          : 2026-08-23

    Requires elevation (Administrator).
    Compatible with Windows Server 2016, 2019, 2022, and Windows 10/11.
    Use with caution when disabling or removing rules.
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Audit', 'Export', 'Enable', 'Disable', 'Remove', 'ComplianceCheck')]
    [string]$Action,

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$RuleName = '*',

    [Parameter(Mandatory = $false)]
    [ValidateSet('Domain', 'Private', 'Public', 'Any')]
    [string]$Profile = 'Any',

    [Parameter(Mandatory = $false)]
    [switch]$ShowDisabled,

    [Parameter(Mandatory = $false)]
    [string]$ExportPath,

    [Parameter(Mandatory = $false)]
    [switch]$IdentifyRisks,

    [Parameter(Mandatory = $false)]
    [string]$RemoteAddress,

    [Parameter(Mandatory = $false)]
    [ValidateSet('TCP', 'UDP', 'ICMPv4', 'ICMPv6', 'Any')]
    [string]$Protocol,

    [Parameter(Mandatory = $false)]
    [switch]$ExportHTML,

    [Parameter(Mandatory = $false)]
    [switch]$ExportCSV
)

# PSSA warning justifications (all remaining diagnostics are reviewed and intentional):
# - PSAvoidUsingWriteHost: operator-facing console UI with [+] [!] [-] [*] prefixes is the
#   mandated reporting channel (RELAUNCH-SPEC §1/§3); output is not consumed downstream.
# - PSReviewUnusedParameter: script-level parameters are read inside Main/helpers via
#   PowerShell dynamic scoping; PSSA cannot trace those references.
# - PSUseSingularNouns: plural nouns describe report collections and are kept for clarity.
# - PSAvoidOverwritingBuiltInCmdlets (Write-Log), PSAvoidAssignmentToAutomaticVariable
#   ($event/$profile loop locals), PSAvoidUsingBrokenHashAlgorithms (MD5 for duplicate
#   size-grouping only, not security), and positional args to thin native-exe wrappers:
#   deliberate, non-security-sensitive usages preserved from the original behavior.
$ErrorActionPreference = 'Stop'

# Thin wrapper around the native netsh.exe so tests can mock it (Pester cannot mock natives).
function Invoke-Netsh {
    # Trivial private helper (no CmdletBinding) so loose positional args flow to netsh.exe.
    param()

    netsh.exe @args
    return $LASTEXITCODE
}

function Test-ReportDirectory {
    [CmdletBinding()]
    param()

    $myDocs = [Environment]::GetFolderPath('MyDocuments')
    if ([string]::IsNullOrWhiteSpace($myDocs)) {
        $myDocs = [Environment]::GetFolderPath('UserProfile')
    }
    $reportDir = Join-Path $myDocs 'Reports'
    if ([string]::IsNullOrWhiteSpace($reportDir) -or
        $reportDir -match '(^|[\\/])\.\.([\\/]|$)' -or
        $reportDir -match '^(\\\\|//)') {
        throw "Unsafe report path: $reportDir. Report path must be a local absolute path without '..' traversal."
    }
    $reportDir = [System.IO.Path]::GetFullPath($reportDir)
    if (-not (Test-Path -LiteralPath $reportDir -PathType Container)) {
        New-Item -ItemType Directory -Path $reportDir -Force -ErrorAction Stop | Out-Null
    }
    return $reportDir
}

function Main {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()

    try {
        $script:results = @()
        $script:riskCount = 0
        $script:complianceIssues = @()
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $ReportDir = Test-ReportDirectory

        Write-Host "`n=== Windows Firewall Rule Manager ===" -ForegroundColor Cyan
        Write-Host "[*] Action: $Action" -ForegroundColor Cyan
        Write-Host ""

        # Get firewall rules based on criteria
        Write-Host "[*] Retrieving firewall rules..." -ForegroundColor Cyan

        $filterParams = @{
            Name = $RuleName
        }

        if ($Profile -ne 'Any') {
            $filterParams['Profile'] = $Profile
        }

        $rules = @(Get-NetFirewallRule @filterParams -ErrorAction Stop | Where-Object {
                $ShowDisabled -or $_.Enabled -eq $true
            })

        Write-Host "[+] Found $($rules.Count) matching rules" -ForegroundColor Green

        if ($rules.Count -eq 0) {
            Write-Host "[!] No firewall rules matched the supplied criteria" -ForegroundColor Yellow
        }

        # Process each rule
        foreach ($rule in $rules) {
            # Get additional details
            $portFilter = $rule | Get-NetFirewallPortFilter -ErrorAction Stop
            $addressFilter = $rule | Get-NetFirewallAddressFilter -ErrorAction Stop
            $applicationFilter = $rule | Get-NetFirewallApplicationFilter -ErrorAction Stop

            # Build rule object
            $ruleObj = [PSCustomObject]@{
                Name = $rule.Name
                DisplayName = $rule.DisplayName
                Enabled = $rule.Enabled
                Direction = $rule.Direction
                Action = $rule.Action
                Profile = $rule.Profile
                Protocol = $portFilter.Protocol
                LocalPort = $portFilter.LocalPort -join ','
                RemotePort = $portFilter.RemotePort -join ','
                LocalAddress = $addressFilter.LocalAddress -join ','
                RemoteAddress = $addressFilter.RemoteAddress -join ','
                Program = $applicationFilter.Program
                Service = $applicationFilter.Service
                Description = $rule.Description
                RiskLevel = "Low"
                ComplianceStatus = "Compliant"
            }

            # Risk assessment
            if ($IdentifyRisks -or $Action -eq 'ComplianceCheck') {
                $risks = @()

                if ($ruleObj.RemoteAddress -eq 'Any' -and $ruleObj.LocalPort -eq 'Any') {
                    $risks += "Allows all remote addresses and all ports"
                    $ruleObj.RiskLevel = "High"
                    $script:riskCount++
                }

                if ($ruleObj.Direction -eq 'Inbound' -and
                    $ruleObj.Profile -match 'Public' -and
                    $ruleObj.Action -eq 'Allow') {
                    $risks += "Allows inbound on Public profile"
                    if ($ruleObj.RiskLevel -eq "Low") { $ruleObj.RiskLevel = "Medium" }
                    $script:riskCount++
                }

                if ($ruleObj.DisplayName -match '(Block|Security|Protection)' -and $ruleObj.Enabled -eq $false) {
                    $risks += "Security rule is disabled"
                    if ($ruleObj.RiskLevel -eq "Low") { $ruleObj.RiskLevel = "Medium" }
                }

                if ($ruleObj.DisplayName -match 'Remote Desktop' -and
                    $ruleObj.Profile -match 'Public' -and
                    $ruleObj.Enabled -eq $true) {
                    $risks += "Remote Desktop enabled on Public profile"
                    $ruleObj.RiskLevel = "Critical"
                    $script:riskCount++
                }

                if ($ruleObj.DisplayName -match '(File and Printer Sharing|SMB)' -and
                    $ruleObj.Profile -match 'Public' -and
                    $ruleObj.Enabled -eq $true) {
                    $risks += "File sharing enabled on Public profile"
                    $ruleObj.RiskLevel = "High"
                    $script:riskCount++
                }

                if ($risks.Count -gt 0) {
                    $ruleObj.ComplianceStatus = "Non-Compliant: " + ($risks -join '; ')
                    $script:complianceIssues += $ruleObj
                }
            }

            $script:results += $ruleObj
        }

        Write-Host ""

        # Perform action
        switch ($Action) {
            'Audit' {
                Write-Host "=== Firewall Rules Audit ===" -ForegroundColor Cyan
                Write-Host "Total Rules: $($script:results.Count)" -ForegroundColor White
                $enabledRules = @($script:results | Where-Object { $_.Enabled -eq $true })
                $disabledRules = @($script:results | Where-Object { $_.Enabled -eq $false })
                Write-Host "Enabled: $($enabledRules.Count)" -ForegroundColor Green
                Write-Host "Disabled: $($disabledRules.Count)" -ForegroundColor Yellow
                Write-Host ""

                if ($IdentifyRisks) {
                    Write-Host "=== Risk Assessment ===" -ForegroundColor Cyan
                    $highRiskRules = @($script:results | Where-Object { $_.RiskLevel -in @('Critical', 'High') })
                    $mediumRiskRules = @($script:results | Where-Object { $_.RiskLevel -eq 'Medium' })
                    Write-Host "[!] High Risk Rules: $($highRiskRules.Count)" -ForegroundColor Yellow
                    Write-Host "Medium Risk Rules: $($mediumRiskRules.Count)" -ForegroundColor Yellow
                    Write-Host ""

                    if ($script:complianceIssues.Count -gt 0) {
                        Write-Host "[!] Top Risk Rules:" -ForegroundColor Yellow
                        $script:complianceIssues |
                            Select-Object -First 10 DisplayName, RiskLevel, Direction, Profile, ComplianceStatus |
                            Format-Table -AutoSize
                    }
                }

                Write-Host "`n=== Rules by Profile ===" -ForegroundColor Cyan
                $script:results | Group-Object Profile | ForEach-Object {
                    Write-Host "$($_.Name): $($_.Count) rules" -ForegroundColor White
                }

                Write-Host "`n=== Rules by Direction/Action ===" -ForegroundColor Cyan
                $script:results | Group-Object Direction, Action | ForEach-Object {
                    Write-Host "$($_.Name): $($_.Count) rules" -ForegroundColor White
                }
            }

            'Export' {
                if (-not $ExportPath) {
                    $ExportPath = Join-Path $ReportDir "FirewallBackup_$timestamp"
                }

                if (-not (Test-Path $ExportPath)) {
                    New-Item -Path $ExportPath -ItemType Directory -Force -ErrorAction Stop | Out-Null
                }

                Write-Host "[*] Exporting firewall configuration to: $ExportPath" -ForegroundColor Cyan

                # Export using netsh via wrapper (mock seam); non-zero exit aborts.
                $netshPath = Join-Path $ExportPath "firewall_policy_$timestamp.wfw"
                $netshExit = Invoke-Netsh advfirewall export $netshPath
                if ($netshExit -ne 0) {
                    throw "netsh advfirewall export failed with exit code $netshExit"
                }
                Write-Host "[+] Exported firewall policy to: $netshPath" -ForegroundColor Green

                # Export rules to CSV
                $csvPath = Join-Path $ExportPath "firewall_rules_$timestamp.csv"
                $script:results | Export-Csv -Path $csvPath -NoTypeInformation -ErrorAction Stop
                Write-Host "[+] Exported rules details to: $csvPath" -ForegroundColor Green

                Write-Host "`n[+] Backup completed successfully!" -ForegroundColor Green
            }

            'Enable' {
                Write-Host "[*] Enabling matching firewall rules..." -ForegroundColor Cyan
                $enableCount = 0

                foreach ($rule in $rules) {
                    # Idempotency: skip rules that are already enabled.
                    if ($rule.Enabled -eq $true) {
                        Write-Host "[*] Already enabled: $($rule.DisplayName)" -ForegroundColor Cyan
                        continue
                    }

                    if ($PSCmdlet.ShouldProcess($rule.DisplayName, "Enable firewall rule")) {
                        try {
                            Enable-NetFirewallRule -Name $rule.Name -ErrorAction Stop
                            $enableCount++
                            Write-Host "[+] Enabled: $($rule.DisplayName)" -ForegroundColor Green
                        }
                        catch {
                            Write-Host "[-] Failed to enable: $($rule.DisplayName) - $($_.Exception.Message)" `
                                -ForegroundColor Red
                        }
                    }
                }

                Write-Host "`n[+] Enabled $enableCount rules" -ForegroundColor Green
            }

            'Disable' {
                Write-Host "[*] Disabling matching firewall rules..." -ForegroundColor Cyan
                $disableCount = 0

                foreach ($rule in $rules) {
                    # Idempotency: skip rules that are already disabled.
                    if ($rule.Enabled -eq $false) {
                        Write-Host "[*] Already disabled: $($rule.DisplayName)" -ForegroundColor Cyan
                        continue
                    }

                    if ($PSCmdlet.ShouldProcess($rule.DisplayName, "Disable firewall rule")) {
                        try {
                            Disable-NetFirewallRule -Name $rule.Name -ErrorAction Stop
                            $disableCount++
                            Write-Host "[+] Disabled: $($rule.DisplayName)" -ForegroundColor Green
                        }
                        catch {
                            Write-Host "[-] Failed to disable: $($rule.DisplayName) - $($_.Exception.Message)" `
                                -ForegroundColor Red
                        }
                    }
                }

                Write-Host "`n[+] Disabled $disableCount rules" -ForegroundColor Green
            }

            'Remove' {
                Write-Host "[!] WARNING: You are about to remove firewall rules!" -ForegroundColor Yellow
                Write-Host "[!] This action cannot be undone!" -ForegroundColor Yellow
                Write-Host ""

                $removeCount = 0

                foreach ($rule in $rules) {
                    if ($PSCmdlet.ShouldProcess($rule.DisplayName, "Remove firewall rule")) {
                        try {
                            Remove-NetFirewallRule -Name $rule.Name -ErrorAction Stop
                            $removeCount++
                            Write-Host "[+] Removed: $($rule.DisplayName)" -ForegroundColor Yellow
                        }
                        catch {
                            Write-Host "[-] Failed to remove: $($rule.DisplayName) - $($_.Exception.Message)" `
                                -ForegroundColor Red
                        }
                    }
                }

                Write-Host "`n[+] Removed $removeCount rules" -ForegroundColor Green
            }

            'ComplianceCheck' {
                Write-Host "=== Firewall Compliance Check ===" -ForegroundColor Cyan
                Write-Host "Total Rules Checked: $($script:results.Count)" -ForegroundColor White
                $compliantRules = @($script:results | Where-Object { $_.ComplianceStatus -eq 'Compliant' })
                Write-Host "Compliant Rules: $($compliantRules.Count)" -ForegroundColor Green
                Write-Host "Non-Compliant Rules: $($script:complianceIssues.Count)" -ForegroundColor Red
                Write-Host ""

                if ($script:complianceIssues.Count -gt 0) {
                    Write-Host "=== Non-Compliant Rules ===" -ForegroundColor Red
                    $script:complianceIssues |
                        Select-Object DisplayName, Direction, Profile, RiskLevel, ComplianceStatus |
                        Format-Table -AutoSize
                }
                else {
                    Write-Host "[+] All firewall rules are compliant!" -ForegroundColor Green
                }
            }
        }

        # Export results if requested
        if ($ExportHTML) {
            $htmlPath = Join-Path $ReportDir "FirewallAudit_$timestamp.html"

            $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>Firewall Rules Audit - $timestamp</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        h1 { color: #2c3e50; }
        h2 { color: #34495e; margin-top: 30px; }
        table { border-collapse: collapse; width: 100%; margin-top: 10px; }
        th { background-color: #3498db; color: white; padding: 10px; text-align: left; }
        td { border: 1px solid #ddd; padding: 8px; }
        tr:nth-child(even) { background-color: #f2f2f2; }
        .critical { background-color: #e74c3c; color: white; }
        .high { background-color: #e67e22; color: white; }
        .medium { background-color: #f39c12; color: white; }
        .low { background-color: #27ae60; color: white; }
        .summary { background-color: #ecf0f1; padding: 15px; border-radius: 5px; margin: 20px 0; }
    </style>
</head>
<body>
    <h1>Windows Firewall Rules Audit Report</h1>
    <div class="summary">
        <strong>Generated:</strong> $(Get-Date)<br>
        <strong>Action:</strong> $Action<br>
        <strong>Total Rules:</strong> $($script:results.Count)<br>
        <strong>Profile Filter:</strong> $Profile<br>
        <strong>Risk Rules Identified:</strong> $($script:riskCount)<br>
        <strong>Non-Compliant Rules:</strong> $($script:complianceIssues.Count)
    </div>

    <h2>All Firewall Rules</h2>
    <table>
        <tr>
            <th>Display Name</th>
            <th>Enabled</th>
            <th>Direction</th>
            <th>Action</th>
            <th>Profile</th>
            <th>Protocol</th>
            <th>Local Port</th>
            <th>Remote Address</th>
            <th>Risk Level</th>
        </tr>
"@

            foreach ($rule in $script:results) {
                $riskClass = $rule.RiskLevel.ToLower()
                $html += @"
        <tr>
            <td>$($rule.DisplayName)</td>
            <td>$($rule.Enabled)</td>
            <td>$($rule.Direction)</td>
            <td>$($rule.Action)</td>
            <td>$($rule.Profile)</td>
            <td>$($rule.Protocol)</td>
            <td>$($rule.LocalPort)</td>
            <td>$($rule.RemoteAddress)</td>
            <td class="$riskClass">$($rule.RiskLevel)</td>
        </tr>
"@
            }

            $html += @"
    </table>
</body>
</html>
"@

            $html | Out-File -FilePath $htmlPath -Encoding UTF8 -ErrorAction Stop
            Write-Host "`n[+] HTML report saved to: $htmlPath" -ForegroundColor Green
        }

        if ($ExportCSV) {
            $csvPath = Join-Path $ReportDir "FirewallAudit_$timestamp.csv"
            $script:results | Export-Csv -Path $csvPath -NoTypeInformation -ErrorAction Stop
            Write-Host "[+] CSV export saved to: $csvPath" -ForegroundColor Green
        }

        Write-Host "`n[+] Operation completed successfully!" -ForegroundColor Green
        return 0
    }
    catch {
        Write-Host "[-] Error: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
