<#
.SYNOPSIS
    Audits and manages Windows Firewall rules with security compliance checks.

.DESCRIPTION
    This script provides comprehensive Windows Firewall rule management:
    - Audits all firewall rules (enabled and disabled)
    - Identifies potentially risky rules (any/any rules, remote access)
    - Exports firewall configuration for backup
    - Enables/disables rules in bulk
    - Removes unauthorized or suspicious rules
    - Generates compliance reports
    - Detects rules allowing broad network access

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
    .\Manage-FirewallRules.ps1 -Action Audit -IdentifyRisks -ExportHTML
    Audits all firewall rules and identifies security risks.

.EXAMPLE
    .\Manage-FirewallRules.ps1 -Action Export -ExportPath "C:\Backups\Firewall"
    Exports current firewall configuration for backup.

.EXAMPLE
    .\Manage-FirewallRules.ps1 -Action ComplianceCheck -Profile Domain
    Checks firewall rules for compliance violations on Domain profile.

.EXAMPLE
    .\Manage-FirewallRules.ps1 -Action Disable -RuleName "*Remote Desktop*" -Profile Public
    Disables all Remote Desktop rules on Public profile.

.NOTES
    Requires Administrator privileges
    Compatible with Windows Server 2016, 2019, 2022, and Windows 10/11
    Use with caution when disabling or removing rules
#>

[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [Parameter(Mandatory=$true)]
    [ValidateSet('Audit','Export','Enable','Disable','Remove','ComplianceCheck')]
    [string]$Action,

    [Parameter(Mandatory=$false)]
    [string]$RuleName = '*',

    [Parameter(Mandatory=$false)]
    [ValidateSet('Domain','Private','Public','Any')]
    [string]$Profile = 'Any',

    [Parameter(Mandatory=$false)]
    [switch]$ShowDisabled,

    [Parameter(Mandatory=$false)]
    [string]$ExportPath,

    [Parameter(Mandatory=$false)]
    [switch]$IdentifyRisks,

    [Parameter(Mandatory=$false)]
    [string]$RemoteAddress,

    [Parameter(Mandatory=$false)]
    [ValidateSet('TCP','UDP','ICMPv4','ICMPv6','Any')]
    [string]$Protocol,

    [Parameter(Mandatory=$false)]
    [switch]$ExportHTML,

    [Parameter(Mandatory=$false)]
    [switch]$ExportCSV
)

# Requires elevation
#Requires -RunAsAdministrator

$ErrorActionPreference = "Stop"
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"

# Resolve report output directory (default: MyDocuments\Reports) and validate against traversal/UNC paths
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

# Initialize results
$results = @()
$riskCount = 0
$complianceIssues = @()

Write-Host "`n=== Windows Firewall Rule Manager ===" -ForegroundColor Cyan
Write-Host "Action: $Action" -ForegroundColor Yellow
Write-Host "Timestamp: $(Get-Date)" -ForegroundColor Gray
Write-Host ""

# Get firewall rules based on criteria
Write-Host "[*] Retrieving firewall rules..." -ForegroundColor Cyan

$filterParams = @{
    Name = $RuleName
}

if ($Profile -ne 'Any') {
    $filterParams['Profile'] = $Profile
}

try {
    $rules = @(Get-NetFirewallRule @filterParams -ErrorAction SilentlyContinue | Where-Object {
        $ShowDisabled -or $_.Enabled -eq $true
    })

    Write-Host "[+] Found $($rules.Count) matching rules" -ForegroundColor Green

    if ($rules.Count -eq 0) {
        Write-Host "[!] No firewall rules matched the supplied criteria" -ForegroundColor Yellow
    }

    # Process each rule
    foreach ($rule in $rules) {
        # Get additional details
        $portFilter = $rule | Get-NetFirewallPortFilter
        $addressFilter = $rule | Get-NetFirewallAddressFilter
        $applicationFilter = $rule | Get-NetFirewallApplicationFilter

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

            # Check for Any/Any rules
            if ($ruleObj.RemoteAddress -eq 'Any' -and $ruleObj.LocalPort -eq 'Any') {
                $risks += "Allows all remote addresses and all ports"
                $ruleObj.RiskLevel = "High"
                $riskCount++
            }

            # Check for public profile inbound rules
            if ($ruleObj.Direction -eq 'Inbound' -and $ruleObj.Profile -match 'Public' -and $ruleObj.Action -eq 'Allow') {
                $risks += "Allows inbound on Public profile"
                if ($ruleObj.RiskLevel -eq "Low") { $ruleObj.RiskLevel = "Medium" }
                $riskCount++
            }

            # Check for disabled security rules
            if ($ruleObj.DisplayName -match '(Block|Security|Protection)' -and $ruleObj.Enabled -eq $false) {
                $risks += "Security rule is disabled"
                if ($ruleObj.RiskLevel -eq "Low") { $ruleObj.RiskLevel = "Medium" }
            }

            # Check for remote desktop on public
            if ($ruleObj.DisplayName -match 'Remote Desktop' -and $ruleObj.Profile -match 'Public' -and $ruleObj.Enabled -eq $true) {
                $risks += "Remote Desktop enabled on Public profile"
                $ruleObj.RiskLevel = "Critical"
                $riskCount++
            }

            # Check for file sharing on public
            if ($ruleObj.DisplayName -match '(File and Printer Sharing|SMB)' -and $ruleObj.Profile -match 'Public' -and $ruleObj.Enabled -eq $true) {
                $risks += "File sharing enabled on Public profile"
                $ruleObj.RiskLevel = "High"
                $riskCount++
            }

            if ($risks.Count -gt 0) {
                $ruleObj.ComplianceStatus = "Non-Compliant: " + ($risks -join '; ')
                $complianceIssues += $ruleObj
            }
        }

        $results += $ruleObj
    }

    Write-Host ""

    # Perform action
    switch ($Action) {
        'Audit' {
            Write-Host "=== Firewall Rules Audit ===" -ForegroundColor Cyan
            Write-Host "Total Rules: $($results.Count)" -ForegroundColor White
            Write-Host "Enabled: $(($results | Where-Object {$_.Enabled -eq $true}).Count)" -ForegroundColor Green
            Write-Host "Disabled: $(($results | Where-Object {$_.Enabled -eq $false}).Count)" -ForegroundColor Yellow
            Write-Host ""

            if ($IdentifyRisks) {
                Write-Host "=== Risk Assessment ===" -ForegroundColor Cyan
                Write-Host "High Risk Rules: $(($results | Where-Object {$_.RiskLevel -eq 'Critical' -or $_.RiskLevel -eq 'High'}).Count)" -ForegroundColor Red
                Write-Host "Medium Risk Rules: $(($results | Where-Object {$_.RiskLevel -eq 'Medium'}).Count)" -ForegroundColor Yellow
                Write-Host ""

                if ($complianceIssues.Count -gt 0) {
                    Write-Host "Top Risk Rules:" -ForegroundColor Red
                    $complianceIssues | Select-Object -First 10 DisplayName, RiskLevel, Direction, Profile, ComplianceStatus |
                        Format-Table -AutoSize
                }
            }

            # Group by profile
            Write-Host "`n=== Rules by Profile ===" -ForegroundColor Cyan
            $results | Group-Object Profile | ForEach-Object {
                Write-Host "$($_.Name): $($_.Count) rules" -ForegroundColor White
            }

            # Group by direction and action
            Write-Host "`n=== Rules by Direction/Action ===" -ForegroundColor Cyan
            $results | Group-Object Direction, Action | ForEach-Object {
                Write-Host "$($_.Name): $($_.Count) rules" -ForegroundColor White
            }
        }

        'Export' {
            if (-not $ExportPath) {
                $ExportPath = "$env:USERPROFILE\Desktop\FirewallBackup_$timestamp"
            }

            if (-not (Test-Path $ExportPath)) {
                New-Item -Path $ExportPath -ItemType Directory -Force | Out-Null
            }

            Write-Host "[*] Exporting firewall configuration to: $ExportPath" -ForegroundColor Cyan

            # Export using netsh
            $netshPath = Join-Path $ExportPath "firewall_policy_$timestamp.wfw"
            $null = netsh advfirewall export $netshPath
            Write-Host "[+] Exported firewall policy to: $netshPath" -ForegroundColor Green

            # Export rules to CSV
            $csvPath = Join-Path $ExportPath "firewall_rules_$timestamp.csv"
            $results | Export-Csv -Path $csvPath -NoTypeInformation
            Write-Host "[+] Exported rules details to: $csvPath" -ForegroundColor Green

            Write-Host "`n[+] Backup completed successfully!" -ForegroundColor Green
        }

        'Enable' {
            Write-Host "[*] Enabling matching firewall rules..." -ForegroundColor Cyan
            $enableCount = 0

            foreach ($rule in $rules) {
                if ($PSCmdlet.ShouldProcess($rule.DisplayName, "Enable firewall rule")) {
                    try {
                        Enable-NetFirewallRule -Name $rule.Name -ErrorAction Stop
                        $enableCount++
                        Write-Host "[+] Enabled: $($rule.DisplayName)" -ForegroundColor Green
                    }
                    catch {
                        Write-Host "[-] Failed to enable: $($rule.DisplayName) - $($_.Exception.Message)" -ForegroundColor Red
                    }
                }
            }

            Write-Host "`n[+] Enabled $enableCount rules" -ForegroundColor Green
        }

        'Disable' {
            Write-Host "[*] Disabling matching firewall rules..." -ForegroundColor Cyan
            $disableCount = 0

            foreach ($rule in $rules) {
                if ($PSCmdlet.ShouldProcess($rule.DisplayName, "Disable firewall rule")) {
                    try {
                        Disable-NetFirewallRule -Name $rule.Name -ErrorAction Stop
                        $disableCount++
                        Write-Host "[+] Disabled: $($rule.DisplayName)" -ForegroundColor Yellow
                    }
                    catch {
                        Write-Host "[-] Failed to disable: $($rule.DisplayName) - $($_.Exception.Message)" -ForegroundColor Red
                    }
                }
            }

            Write-Host "`n[+] Disabled $disableCount rules" -ForegroundColor Green
        }

        'Remove' {
            Write-Host "[!] WARNING: You are about to remove firewall rules!" -ForegroundColor Red
            Write-Host "[!] This action cannot be undone!" -ForegroundColor Red
            Write-Host ""

            $removeCount = 0

            foreach ($rule in $rules) {
                if ($PSCmdlet.ShouldProcess($rule.DisplayName, "Remove firewall rule")) {
                    try {
                        Remove-NetFirewallRule -Name $rule.Name -ErrorAction Stop
                        $removeCount++
                        Write-Host "[+] Removed: $($rule.DisplayName)" -ForegroundColor Red
                    }
                    catch {
                        Write-Host "[-] Failed to remove: $($rule.DisplayName) - $($_.Exception.Message)" -ForegroundColor Red
                    }
                }
            }

            Write-Host "`n[+] Removed $removeCount rules" -ForegroundColor Green
        }

        'ComplianceCheck' {
            Write-Host "=== Firewall Compliance Check ===" -ForegroundColor Cyan
            Write-Host "Total Rules Checked: $($results.Count)" -ForegroundColor White
            Write-Host "Compliant Rules: $(($results | Where-Object {$_.ComplianceStatus -eq 'Compliant'}).Count)" -ForegroundColor Green
            Write-Host "Non-Compliant Rules: $($complianceIssues.Count)" -ForegroundColor Red
            Write-Host ""

            if ($complianceIssues.Count -gt 0) {
                Write-Host "=== Non-Compliant Rules ===" -ForegroundColor Red
                $complianceIssues | Select-Object DisplayName, Direction, Profile, RiskLevel, ComplianceStatus |
                    Format-Table -AutoSize
            }
            else {
                Write-Host "[+] All firewall rules are compliant!" -ForegroundColor Green
            }
        }
    }

    # Export results if requested
    if ($ExportHTML) {
        $htmlPath = "$env:USERPROFILE\Desktop\FirewallAudit_$timestamp.html"

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
        <strong>Total Rules:</strong> $($results.Count)<br>
        <strong>Profile Filter:</strong> $Profile<br>
        <strong>Risk Rules Identified:</strong> $riskCount<br>
        <strong>Non-Compliant Rules:</strong> $($complianceIssues.Count)
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

        foreach ($rule in $results) {
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

        $html | Out-File -FilePath $htmlPath -Encoding UTF8
        Write-Host "`n[+] HTML report saved to: $htmlPath" -ForegroundColor Green
    }

    if ($ExportCSV) {
        $csvPath = "$env:USERPROFILE\Desktop\FirewallAudit_$timestamp.csv"
        $results | Export-Csv -Path $csvPath -NoTypeInformation
        Write-Host "[+] CSV export saved to: $csvPath" -ForegroundColor Green
    }

} catch {
    Write-Host "[-] Error: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host "`n[+] Operation completed successfully!" -ForegroundColor Green

# Return results for pipeline
return $results
