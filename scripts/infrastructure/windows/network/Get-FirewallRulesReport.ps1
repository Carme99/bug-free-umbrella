<#
.SYNOPSIS
    Documents and exports Windows Firewall rules for Windows Server 2016-2022.

.DESCRIPTION
    This script comprehensively documents firewall configuration:
    - All firewall rules (inbound and outbound)
    - Rule details (ports, protocols, programs, services)
    - Profile assignments (Domain, Private, Public)
    - Enabled/disabled status
    - Action (Allow/Block)
    - Filter by status, direction, or action
    - Export to HTML or CSV

.PARAMETER Direction
    Filter by direction: 'Inbound', 'Outbound', or 'All' (default: 'All').

.PARAMETER Enabled
    Filter by enabled status: 'Enabled', 'Disabled', or 'All' (default: 'Enabled').

.PARAMETER Action
    Filter by action: 'Allow', 'Block', or 'All' (default: 'All').

.PARAMETER Profile
    Filter by profile: 'Domain', 'Private', 'Public', 'Any', or 'All' (default: 'All').

.PARAMETER ExportHTML
    Export report to HTML file.

.PARAMETER ExportCSV
    Export rules to CSV file.

.EXAMPLE
    PS C:\> .\Get-FirewallRulesReport.ps1
    Lists all enabled firewall rules.

.EXAMPLE
    PS C:\> .\Get-FirewallRulesReport.ps1 -Direction Inbound -Action Allow -ExportHTML
    Documents all inbound allow rules and exports to HTML.

.EXAMPLE
    PS C:\> .\Get-FirewallRulesReport.ps1 -Enabled All -ExportCSV
    Exports all firewall rules (enabled and disabled) to CSV.

.NOTES
    File Name     : Get-FirewallRulesReport.ps1
    Author        : Bug-Free Umbrella
    Prerequisite  : PowerShell 5.1+
    Version       : 1.0.0
    Date          : 2026-08-23

    Administrator privileges are required; the elevation check runs inside Main (not via
    #Requires) so the script can be safely loaded for testing. Compatible with Windows
    Server 2016, 2019, and 2022. Useful for security audits and documentation.
#>

[CmdletBinding()]
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
            Justification = 'Colored Write-Host prefix output is the specified console UX.')]
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '',
            Justification = 'Parameters are consumed by helper functions via dynamic scoping.')]
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '',
            Justification = 'Plural nouns are intentional: functions aggregate collections.')]
param(
    [Parameter(Mandatory = $false)]
    [ValidateSet('Inbound', 'Outbound', 'All')]
    [string]$Direction = 'All',

    [Parameter(Mandatory = $false)]
    [ValidateSet('Enabled', 'Disabled', 'All')]
    [string]$Enabled = 'Enabled',

    [Parameter(Mandatory = $false)]
    [ValidateSet('Allow', 'Block', 'All')]
    [string]$Action = 'All',

    [Parameter(Mandatory = $false)]
    [ValidateSet('Domain', 'Private', 'Public', 'Any', 'All')]
    [string]$Profile = 'All',

    [Parameter(Mandatory = $false)]
    [switch]$ExportHTML,

    [Parameter(Mandatory = $false)]
    [switch]$ExportCSV
)

$ErrorActionPreference = 'Stop'


function Test-AdminPrivilege {
    # Runtime replacement for the former '#Requires -RunAsAdministrator' directive.
    # Unix platforms (offline test runners) have no elevation concept, so the check
    # passes through there; Windows hosts still require an elevated session.
    if ($PSVersionTable.ContainsKey('Platform') -and $PSVersionTable.Platform -eq 'Unix') {
        return $true
    }

    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    return ([Security.Principal.WindowsPrincipal]$identity).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Write-ColorOutput {
    param([string]$Message, [string]$Level = 'Info')

    # Mandated console prefixes: [-] error/critical, [!] warning, [+] success, [*] info.
    $prefix = switch ($Level) {
        'Critical' { '[-]' }
        'Error' { '[-]' }
        'Warning' { '[!]' }
        'Success' { '[+]' }
        default { '[*]' }
    }

    $color = switch ($Level) {
        'Critical' { 'Red' }
        'Error' { 'Red' }
        'Warning' { 'Yellow' }
        'Success' { 'Green' }
        default { 'Cyan' }
    }

    Write-Host "$prefix $Message" -ForegroundColor $color
}

function Get-FirewallRules {
    Write-Host "`nGathering firewall rules..." -ForegroundColor Cyan

    # Get all rules
    $rules = Get-NetFirewallRule

    # Apply filters
    if ($Direction -ne 'All') {
        $rules = $rules | Where-Object { $_.Direction -eq $Direction }
    }

    if ($Enabled -eq 'Enabled') {
        $rules = $rules | Where-Object { $_.Enabled -eq 'True' }
    }
    elseif ($Enabled -eq 'Disabled') {
        $rules = $rules | Where-Object { $_.Enabled -eq 'False' }
    }

    if ($Action -ne 'All') {
        $rules = $rules | Where-Object { $_.Action -eq $Action }
    }

    if ($Profile -ne 'All') {
        $rules = $rules | Where-Object { $_.Profile -match $Profile }
    }

    Write-ColorOutput "  Found $($rules.Count) matching firewall rules" -Level Info
    Write-Host "  Collecting rule details..." -ForegroundColor Gray

    $ruleCount = 0
    foreach ($rule in $rules) {
        $ruleCount++
        if ($ruleCount % 100 -eq 0) {
            Write-Progress -Activity "Processing firewall rules" `
                -Status "Processed $ruleCount of $($rules.Count)" -PercentComplete (($ruleCount / $rules.Count) * 100)
        }

        # Get additional rule details
        $portFilter = Get-NetFirewallPortFilter -AssociatedNetFirewallRule $rule -ErrorAction SilentlyContinue
        $appFilter = Get-NetFirewallApplicationFilter -AssociatedNetFirewallRule $rule -ErrorAction SilentlyContinue
        $serviceFilter = Get-NetFirewallServiceFilter -AssociatedNetFirewallRule $rule -ErrorAction SilentlyContinue
        $addressFilter = Get-NetFirewallAddressFilter -AssociatedNetFirewallRule $rule -ErrorAction SilentlyContinue

        $ruleInfo = [PSCustomObject]@{
            DisplayName = $rule.DisplayName
            Name = $rule.Name
            Enabled = $rule.Enabled
            Direction = $rule.Direction
            Action = $rule.Action
            Profile = $rule.Profile
            LocalPort = if ($portFilter.LocalPort) { $portFilter.LocalPort -join ',' } else { 'Any' }
            RemotePort = if ($portFilter.RemotePort) { $portFilter.RemotePort -join ',' } else { 'Any' }
            Protocol = if ($portFilter.Protocol) { $portFilter.Protocol } else { 'Any' }
            Program = if ($appFilter.Program) { $appFilter.Program } else { 'Any' }
            Service = if ($serviceFilter.Service) { $serviceFilter.Service } else { 'Any' }
            LocalAddress = if ($addressFilter.LocalAddress) { $addressFilter.LocalAddress -join ',' } else { 'Any' }
            RemoteAddress = if ($addressFilter.RemoteAddress) { $addressFilter.RemoteAddress -join ',' } else { 'Any' }
            Description = $rule.Description
            Group = $rule.Group
            EdgeTraversal = $rule.EdgeTraversalPolicy
        }

        $script:report.Rules += $ruleInfo

        # Update statistics
        $script:report.Summary.TotalRules++

        if ($rule.Direction -eq 'Inbound') {
            $script:report.Summary.InboundRules++
        }
        else {
            $script:report.Summary.OutboundRules++
        }

        if ($rule.Action -eq 'Allow') {
            $script:report.Summary.AllowRules++
        }
        else {
            $script:report.Summary.BlockRules++
        }

        if ($rule.Enabled -eq 'True') {
            $script:report.Summary.EnabledRules++
        }
        else {
            $script:report.Summary.DisabledRules++
        }
    }

    Write-Progress -Activity "Processing firewall rules" -Completed
}

function Get-FirewallProfiles {
    Write-Host "`nGathering firewall profile status..." -ForegroundColor Cyan

    $profiles = Get-NetFirewallProfile

    foreach ($fwProfile in $profiles) {
        $script:report.Profiles[$fwProfile.Name] = @{
            Enabled = $fwProfile.Enabled
            DefaultInboundAction = $fwProfile.DefaultInboundAction
            DefaultOutboundAction = $fwProfile.DefaultOutboundAction
            AllowInboundRules = $fwProfile.AllowInboundRules
            AllowLocalFirewallRules = $fwProfile.AllowLocalFirewallRules
            AllowLocalIPsecRules = $fwProfile.AllowLocalIPsecRules
            NotifyOnListen = $fwProfile.NotifyOnListen
            EnableStealthModeForIPsec = $fwProfile.EnableStealthModeForIPsec
            LogFileName = $fwProfile.LogFileName
            LogMaxSizeKilobytes = $fwProfile.LogMaxSizeKilobytes
            LogAllowed = $fwProfile.LogAllowed
            LogBlocked = $fwProfile.LogBlocked
            LogIgnored = $fwProfile.LogIgnored
        }

        $statusText = if ($fwProfile.Enabled) { "Enabled" } else { "Disabled" }
        $statusColor = if ($fwProfile.Enabled) { 'Success' } else { 'Warning' }
        Write-ColorOutput "  $($fwProfile.Name): $statusText (In: $($fwProfile.DefaultInboundAction), Out: `
            $($fwProfile.DefaultOutboundAction))" -Level $statusColor
    }
}

function Show-Summary {
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "  Firewall Rules Summary" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Server: $($script:report.ServerName)"
    Write-Host "Scan Time: $($script:report.ScanTime)"

    Write-Host "`nFilters Applied:" -ForegroundColor Cyan
    Write-Host "  Direction: $($script:report.Filters.Direction)"
    Write-Host "  Enabled: $($script:report.Filters.Enabled)"
    Write-Host "  Action: $($script:report.Filters.Action)"
    Write-Host "  Profile: $($script:report.Filters.Profile)"

    Write-Host "`nRule Statistics:" -ForegroundColor Cyan
    Write-Host "  Total Rules: $($script:report.Summary.TotalRules)"
    Write-Host "  Inbound: $($script:report.Summary.InboundRules) | Outbound: $($script:report.Summary.OutboundRules)"
    Write-Host "  Allow: $($script:report.Summary.AllowRules) | Block: $($script:report.Summary.BlockRules)"
    Write-Host "  Enabled: $($script:report.Summary.EnabledRules) | Disabled: $($script:report.Summary.DisabledRules)"

    Write-Host "`nFirewall Profiles:" -ForegroundColor Cyan
    foreach ($fwProfile in $script:report.Profiles.GetEnumerator()) {
        $statusText = if ($fwProfile.Value.Enabled) { "Enabled" } else { "Disabled" }
        Write-Host "  $($fwProfile.Key): $statusText"
        Write-Host "    Default Inbound: $($fwProfile.Value.DefaultInboundAction)"
        Write-Host "    Default Outbound: $($fwProfile.Value.DefaultOutboundAction)"
    }

    Write-Host "`nSample Rules (First 10):" -ForegroundColor Cyan
    $script:report.Rules | Select-Object -First 10 |
        Select-Object DisplayName, Direction, Action, Protocol, LocalPort, RemotePort |
        Format-Table -AutoSize

    Write-Host "`n========================================`n" -ForegroundColor Cyan
}

function Export-HTMLReport {
    $reportPath = "$ReportDir\FirewallRules_$($env:COMPUTERNAME)_$(Get-Date -Format 'yyyyMMdd_HHmmss').html"

    $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>Firewall Rules Report - $($script:report.ServerName)</title>
    <style>
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; margin: 20px; background-color: #f5f5f5; }
        .container { max-width: 1800px; margin: 0 auto; background-color: white; padding: 30px; border-radius: 8px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        h1 { color: #333; border-bottom: 3px solid #007bff; padding-bottom: 10px; }
        h2 { color: #555; margin-top: 30px; border-bottom: 1px solid #ddd; padding-bottom: 5px; }
        .summary { display: grid; grid-template-columns: repeat(auto-fit, minmax(180px, 1fr)); gap: 15px; margin: 20px
            0; }
        .metric { background-color: #f8f9fa; padding: 15px; border-radius: 4px; border-left: 4px solid #007bff;
            text-align: center; }
        .metric-value { font-size: 1.8em; font-weight: bold; color: #007bff; }
        table { width: 100%; border-collapse: collapse; margin: 15px 0; font-size: 0.85em; }
        th { background-color: #007bff; color: white; padding: 10px; text-align: left; position: sticky; top: 0; }
        td { padding: 8px; border-bottom: 1px solid #ddd; }
        tr:hover { background-color: #f1f1f1; }
        .action-allow { color: #28a745; font-weight: bold; }
        .action-block { color: #dc3545; font-weight: bold; }
        .enabled { color: #28a745; }
        .disabled { color: #6c757d; }
        .inbound { color: #007bff; }
        .outbound { color: #6c757d; }
        .footer { margin-top: 30px; padding-top: 20px; border-top: 1px solid #ddd; color: #777; font-size: 0.9em; }
        .filter-box { background-color: #e7f3ff; padding: 15px; border-radius: 4px; margin: 15px 0; }
    </style>
</head>
<body>
    <div class="container">
        <h1>Windows Firewall Rules Report</h1>
        <p><strong>Server:</strong> $($script:report.ServerName)<br>
        <strong>Report Date:</strong> $($script:report.ScanTime)</p>

        <div class="filter-box">
            <strong>Filters Applied:</strong>
            Direction: $($script:report.Filters.Direction) |
            Enabled: $($script:report.Filters.Enabled) |
            Action: $($script:report.Filters.Action) |
            Profile: $($script:report.Filters.Profile)
        </div>

        <div class="summary">
            <div class="metric">
                <div class="metric-value">$($script:report.Summary.TotalRules)</div>
                <div>Total Rules</div>
            </div>
            <div class="metric">
                <div class="metric-value">$($script:report.Summary.InboundRules)</div>
                <div>Inbound</div>
            </div>
            <div class="metric">
                <div class="metric-value">$($script:report.Summary.OutboundRules)</div>
                <div>Outbound</div>
            </div>
            <div class="metric">
                <div class="metric-value">$($script:report.Summary.AllowRules)</div>
                <div>Allow</div>
            </div>
            <div class="metric">
                <div class="metric-value">$($script:report.Summary.BlockRules)</div>
                <div>Block</div>
            </div>
            <div class="metric">
                <div class="metric-value">$($script:report.Summary.EnabledRules)</div>
                <div>Enabled</div>
            </div>
        </div>

        <h2>Firewall Profiles</h2>
        <table>
            <tr><th>Profile</th><th>Status</th><th>Default Inbound</th><th>Default Outbound</th><th>Allow Inbound
            Rules</th><th>Logging</th></tr>
            $(foreach($fwProfile in $script:report.Profiles.GetEnumerator()) {
                $enabledClass = if($fwProfile.Value.Enabled) { 'enabled' } else { 'disabled' }
                $enabledText = if($fwProfile.Value.Enabled) { 'Enabled' } else { 'Disabled' }
                "<tr>
                    <td>$($fwProfile.Key)</td>
                    <td class='$enabledClass'>$enabledText</td>
                    <td>$($fwProfile.Value.DefaultInboundAction)</td>
                    <td>$($fwProfile.Value.DefaultOutboundAction)</td>
                    <td>$($fwProfile.Value.AllowInboundRules)</td>
                    <td>Allowed: $($fwProfile.Value.LogAllowed), Blocked: $($fwProfile.Value.LogBlocked)</td>
                </tr>"
            })
        </table>

        <h2>Firewall Rules</h2>
        <table>
            <tr>
                <th>Display Name</th>
                <th>Enabled</th>
                <th>Direction</th>
                <th>Action</th>
                <th>Profile</th>
                <th>Protocol</th>
                <th>Local Port</th>
                <th>Remote Port</th>
                <th>Program</th>
                <th>Service</th>
            </tr>
            $(foreach($rule in $script:report.Rules) {
                $enabledClass = if($rule.Enabled -eq 'True') { 'enabled' } else { 'disabled' }
                $actionClass = if($rule.Action -eq 'Allow') { 'action-allow' } else { 'action-block' }
                $directionClass = if($rule.Direction -eq 'Inbound') { 'inbound' } else { 'outbound' }
                $program = if($rule.Program.Length -gt 50) { "..." + $rule.Program.Substring($rule.Program.Length -
            47) } else { $rule.Program }

                "<tr>
                    <td>$($rule.DisplayName)</td>
                    <td class='$enabledClass'>$($rule.Enabled)</td>
                    <td class='$directionClass'>$($rule.Direction)</td>
                    <td class='$actionClass'>$($rule.Action)</td>
                    <td>$($rule.Profile)</td>
                    <td>$($rule.Protocol)</td>
                    <td>$($rule.LocalPort)</td>
                    <td>$($rule.RemotePort)</td>
                    <td title='$($rule.Program)'>$program</td>
                    <td>$($rule.Service)</td>
                </tr>"
            })
        </table>

        <div class="footer">
            Report generated by Get-FirewallRulesReport.ps1
        </div>
    </div>
</body>
</html>
"@

    $html | Out-File -FilePath $reportPath -Encoding UTF8
    Write-ColorOutput "`nHTML report exported to: $reportPath" -Level Success
    return $reportPath
}

function Export-CSVReport {
    $reportPath = "$ReportDir\FirewallRules_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"

    $script:report.Rules | Export-Csv -Path $reportPath -NoTypeInformation -Encoding UTF8
    Write-ColorOutput "CSV report exported to: $reportPath" -Level Success
    return $reportPath
}

function Main {
    try {
        if (-not (Test-AdminPrivilege)) {
            Write-Host "[-] Administrator privileges are required to read firewall rules." -ForegroundColor Red
            return 1
        }

        $myDocs = [Environment]::GetFolderPath('MyDocuments')
        if ([string]::IsNullOrWhiteSpace($myDocs)) {
            # Profile-less contexts (CI runners, SYSTEM services): MyDocuments resolves empty;
            # fall back so report writing degrades gracefully instead of crashing.
            $myDocs = [Environment]::GetFolderPath('UserProfile')
        }
        $script:ReportDir = Join-Path $myDocs 'Reports'
        if ([string]::IsNullOrWhiteSpace($script:ReportDir) -or
            $script:ReportDir -match '(^|[\\/])\.\.([\\/]|$)' -or
            $script:ReportDir -match '^(\\\\|//)') {
            throw "Unsafe report path: $script:ReportDir. Report path must be a local absolute " +
                "path without '..' traversal."
        }
        $script:ReportDir = [System.IO.Path]::GetFullPath($script:ReportDir)
        if (-not (Test-Path -LiteralPath $script:ReportDir -PathType Container)) {
            New-Item -ItemType Directory -Path $script:ReportDir -Force -ErrorAction Stop | Out-Null
        }

        $script:report = @{
            ServerName = $env:COMPUTERNAME
            ScanTime = Get-Date
            Filters = @{
                Direction = $Direction
                Enabled = $Enabled
                Action = $Action
                Profile = $Profile
            }
            Rules = @()
            Summary = @{
                TotalRules = 0
                InboundRules = 0
                OutboundRules = 0
                AllowRules = 0
                BlockRules = 0
                EnabledRules = 0
                DisabledRules = 0
            }
            Profiles = @{}
        }

        Write-Host "`n========================================" -ForegroundColor Cyan
        Write-Host "  Windows Firewall Rules Report" -ForegroundColor Cyan
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host "Server: $($script:report.ServerName)"

        Get-FirewallProfiles
        Get-FirewallRules
        Show-Summary

        if ($ExportHTML) {
            Write-Host "Generating HTML report..." -ForegroundColor Cyan
            Export-HTMLReport | Out-Null
        }

        if ($ExportCSV) {
            Write-Host "Generating CSV report..." -ForegroundColor Cyan
            Export-CSVReport | Out-Null
        }

        Write-Host "[+] Firewall rules report completed." -ForegroundColor Green
        return 0
    }
    catch {
        Write-Host "[-] Error: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }

