<#
.SYNOPSIS
    Audits Azure VM security configuration and compliance.

.DESCRIPTION
    Read-only security configuration audit of Azure virtual machines covering:
    - Disk encryption status (Azure Disk Encryption)
    - Network security group (NSG) assignments
    - Public IP exposure
    - Boot diagnostics configuration
    - Managed identity usage
    - VM extensions security status

    Each VM receives a security score (starting at 100, reduced per finding) and a rating of
    Excellent/Good/Fair/Poor. The script never mutates Azure resources; for HTML/JSON output
    formats it writes a uniquely-named report file under -OutputPath, so re-running against an
    unchanged environment is safe (idempotent). A missing Az.Compute module or missing Azure
    login fails with exit code 1.

.PARAMETER SubscriptionId
    Azure subscription ID. Use '*' for all subscriptions.

.PARAMETER ResourceGroupName
    Specific resource group. Use '*' for all resource groups.

.PARAMETER CheckEncryption
    Verify disk encryption status

.PARAMETER CheckNetworkSecurity
    Analyze network security configuration

.PARAMETER OutputFormat
    Output format: 'Console', 'HTML', or 'JSON'. Default: 'HTML'

.PARAMETER OutputPath
    Local directory path for output files. Default: MyDocuments\Reports

.EXAMPLE
    PS C:\> Connect-AzAccount
    PS C:\> .\Get-VMSecurityConfig.ps1 -SubscriptionId "*" -CheckEncryption -CheckNetworkSecurity
    Audits encryption and network security for every accessible subscription.

.EXAMPLE
    PS C:\> .\Get-VMSecurityConfig.ps1 -ResourceGroupName "rg-production" `
        -OutputFormat JSON -OutputPath "C:\Temp\Audit"
    Audits rg-production and writes a JSON report to C:\Temp\Audit.

.NOTES
    File Name   : Get-VMSecurityConfig.ps1
    Author      : IT Operations
    Prerequisite: PowerShell 7.0
    Version     : 1.0.0
    Date        : 2026-08-23

    WARNING: This script has not been thoroughly tested in production environments.
    Please test in a non-production environment first and validate results before relying on this data.
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
    Justification = 'RELAUNCH-SPEC §3 mandates console status output via Write-Host with [+]/[!]/[-]/[*] prefixes.')]
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$SubscriptionId = "*",

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$ResourceGroupName = "*",

    [Parameter(Mandatory = $false)]
    [switch]$CheckEncryption,

    [Parameter(Mandatory = $false)]
    [switch]$CheckNetworkSecurity,

    [Parameter(Mandatory = $false)]
    [ValidateSet('Console', 'HTML', 'JSON')]
    [string]$OutputFormat = 'HTML',

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$OutputPath = (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Reports')
)

$ErrorActionPreference = 'Stop'

function Main {
    [CmdletBinding()]
    param(
        [ValidateNotNullOrEmpty()]
        [string]$SubscriptionId = "*",

        [ValidateNotNullOrEmpty()]
        [string]$ResourceGroupName = "*",

        [switch]$CheckEncryption,

        [switch]$CheckNetworkSecurity,

        [ValidateSet('Console', 'HTML', 'JSON')]
        [string]$OutputFormat = 'HTML',

        [ValidateNotNullOrEmpty()]
        [string]$OutputPath = (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Reports')
    )

    try {
        # Validate OutputPath: reject '..' traversal and UNC remote paths before resolution
        if ([string]::IsNullOrWhiteSpace($OutputPath) -or
            $OutputPath -match '(^|[\\/])\.\.([\\/]|$)' -or
            $OutputPath -match '^(\\\\|//)') {
            throw "Unsafe OutputPath: '$OutputPath'. OutputPath must be a local absolute path without '..' traversal."
        }
        $resolvedOutputPath = [System.IO.Path]::GetFullPath($OutputPath)
        if (-not (Test-Path -LiteralPath $resolvedOutputPath -PathType Container)) {
            New-Item -ItemType Directory -Path $resolvedOutputPath -Force -ErrorAction Stop | Out-Null
        }

        if (-not (Get-Module -ListAvailable -Name Az.Compute)) {
            throw "Az.Compute module required. Install: Install-Module Az"
        }

        Import-Module Az.Compute -ErrorAction SilentlyContinue
        Import-Module Az.Network -ErrorAction SilentlyContinue

        $results = @{
            Timestamp         = Get-Date
            VMSecurityStatus  = @()
            SecurityFindings  = @()
            Summary           = @{}
        }

        Write-Host "[*] Auditing Azure VM security configuration..." -ForegroundColor Cyan

        $context = Get-AzContext -ErrorAction Stop
        if (-not $context) {
            throw "Not logged in to Azure. Run Connect-AzAccount"
        }

        $subscriptions = if ($SubscriptionId -eq '*') {
            Get-AzSubscription -ErrorAction Stop
        }
        else {
            @(Get-AzSubscription -SubscriptionId $SubscriptionId -ErrorAction Stop)
        }

        foreach ($sub in $subscriptions) {
            Write-Host "`n[*] Analyzing subscription: $($sub.Name)" -ForegroundColor Cyan
            Set-AzContext -SubscriptionId $sub.Id -ErrorAction Stop | Out-Null

            $vms = if ($ResourceGroupName -eq '*') {
                @(Get-AzVM -Status -ErrorAction Stop)
            }
            else {
                @(Get-AzVM -ResourceGroupName $ResourceGroupName -Status -ErrorAction Stop)
            }

            Write-Host "[*] Found $($vms.Count) VMs" -ForegroundColor White

            foreach ($vm in $vms) {
                Write-Host "[*]   Auditing: $($vm.Name)" -ForegroundColor Gray

                $vmSecurity = [pscustomobject]@{
                    VMName          = $vm.Name
                    ResourceGroup   = $vm.ResourceGroupName
                    Location        = $vm.Location
                    OSType          = $vm.StorageProfile.OsDisk.OsType
                    Subscription    = $sub.Name
                    PowerState      = ($vm.Statuses | Where-Object { $_.Code -like 'PowerState/*' }).DisplayStatus
                    SecurityIssues  = @()
                    SecurityScore   = 100
                    OSDiskEncrypted = $null
                    DataDisksEncrypted = $null
                    HasPublicIP     = $false
                    HasNSG          = $false
                    BootDiagnosticsEnabled = $false
                    ManagedIdentity = ''
                    ExtensionCount  = 0
                    Extensions      = ''
                    SecurityRating  = ''
                }

                # Check disk encryption
                if ($CheckEncryption) {
                    $encryptionStatus = Get-AzVMDiskEncryptionStatus -ResourceGroupName $vm.ResourceGroupName `
                        -VMName $vm.Name -ErrorAction SilentlyContinue

                    if ($encryptionStatus) {
                        $vmSecurity.OSDiskEncrypted = $encryptionStatus.OsVolumeEncrypted
                        $vmSecurity.DataDisksEncrypted = $encryptionStatus.DataVolumesEncrypted

                        if ($encryptionStatus.OsVolumeEncrypted -ne 'Encrypted') {
                            $vmSecurity.SecurityIssues += "OS disk not encrypted"
                            $vmSecurity.SecurityScore -= 20
                            $results.SecurityFindings += [pscustomobject]@{
                                VMName         = $vm.Name
                                Severity       = "High"
                                Finding        = "OS disk encryption not enabled"
                                Recommendation = "Enable Azure Disk Encryption"
                            }
                        }
                    }
                    else {
                        $vmSecurity.SecurityIssues += "Encryption status unknown"
                        $vmSecurity.SecurityScore -= 10
                    }
                }

                # Check network configuration
                if ($CheckNetworkSecurity) {
                    # Get network interfaces
                    $nics = $vm.NetworkProfile.NetworkInterfaces

                    $hasPublicIP = $false
                    $hasNSG = $false

                    foreach ($nicRef in $nics) {
                        $nicId = $nicRef.Id
                        $nic = Get-AzNetworkInterface -ResourceId $nicId -ErrorAction SilentlyContinue

                        if ($nic) {
                            # Check for public IP
                            if ($nic.IpConfigurations.PublicIpAddress) {
                                $hasPublicIP = $true
                                $vmSecurity.SecurityIssues += "Has public IP address"
                                $vmSecurity.SecurityScore -= 15

                                $results.SecurityFindings += [pscustomobject]@{
                                    VMName         = $vm.Name
                                    Severity       = "Medium"
                                    Finding        = "VM has public IP address"
                                    Recommendation = "Consider using Azure Bastion or VPN for remote access"
                                }
                            }

                            # Check for NSG
                            if ($nic.NetworkSecurityGroup) {
                                $hasNSG = $true
                            }
                        }
                    }

                    $vmSecurity.HasPublicIP = $hasPublicIP
                    $vmSecurity.HasNSG = $hasNSG

                    if (-not $hasNSG) {
                        $vmSecurity.SecurityIssues += "No Network Security Group assigned"
                        $vmSecurity.SecurityScore -= 25

                        $results.SecurityFindings += [pscustomobject]@{
                            VMName         = $vm.Name
                            Severity       = "High"
                            Finding        = "No NSG protection"
                            Recommendation = "Assign Network Security Group to restrict traffic"
                        }
                    }
                }

                # Check boot diagnostics
                if ($vm.DiagnosticsProfile.BootDiagnostics.Enabled) {
                    $vmSecurity.BootDiagnosticsEnabled = $true
                }
                else {
                    $vmSecurity.BootDiagnosticsEnabled = $false
                    $vmSecurity.SecurityIssues += "Boot diagnostics disabled"
                    $vmSecurity.SecurityScore -= 5
                }

                # Check managed identity
                if ($vm.Identity) {
                    $vmSecurity.ManagedIdentity = $vm.Identity.Type
                }
                else {
                    $vmSecurity.ManagedIdentity = "None"
                }

                # Check VM extensions
                $extensions = Get-AzVMExtension -ResourceGroupName $vm.ResourceGroupName `
                    -VMName $vm.Name -ErrorAction SilentlyContinue

                $vmSecurity.ExtensionCount = @($extensions).Count
                $vmSecurity.Extensions = (@($extensions) | Select-Object -ExpandProperty Name) -join ', '

                # Security score assessment
                $vmSecurity.SecurityRating = if ($vmSecurity.SecurityScore -ge 90) { 'Excellent' }
                elseif ($vmSecurity.SecurityScore -ge 75) { 'Good' }
                elseif ($vmSecurity.SecurityScore -ge 60) { 'Fair' }
                else { 'Poor' }

                $vmSecurity.SecurityIssues = $vmSecurity.SecurityIssues -join '; '
                $results.VMSecurityStatus += $vmSecurity
            }
        }

        # Calculate summary
        $totalVMs = $results.VMSecurityStatus.Count
        $excellentVMs = ($results.VMSecurityStatus | Where-Object { $_.SecurityRating -eq 'Excellent' }).Count
        $poorVMs = ($results.VMSecurityStatus | Where-Object { $_.SecurityRating -eq 'Poor' }).Count
        $highSeverityFindings = ($results.SecurityFindings | Where-Object { $_.Severity -eq 'High' }).Count

        $avgSecurityScore = if ($totalVMs -gt 0) {
            [math]::Round(($results.VMSecurityStatus.SecurityScore | Measure-Object -Average).Average, 2)
        }
        else { 0 }

        $results.Summary = @{
            TotalVMs             = $totalVMs
            ExcellentSecurityVMs = $excellentVMs
            PoorSecurityVMs      = $poorVMs
            AverageSecurityScore = $avgSecurityScore
            HighSeverityFindings = $highSeverityFindings
            TotalFindings        = $results.SecurityFindings.Count
        }

        # Run-scoped stamp to avoid filename collisions on rapid re-runs
        $RunTimestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $RunId = [Guid]::NewGuid().ToString('N').Substring(0, 8)

        # Output
        switch ($OutputFormat) {
            'Console' {
                Write-Host "`n=== Azure VM Security Configuration Summary ===" -ForegroundColor Cyan
                Write-Host "[*] Total VMs: $totalVMs" -ForegroundColor White
                Write-Host "[*] Average Security Score: $avgSecurityScore/100" -ForegroundColor White
                Write-Host "[*] Excellent: $excellentVMs | Poor: $poorVMs" -ForegroundColor White
                $findingPrefix = if ($highSeverityFindings -gt 0) { '[!]' } else { '[+]' }
                $findingColor = if ($highSeverityFindings -gt 0) { 'Red' } else { 'Green' }
                Write-Host "$findingPrefix Security Findings: $($results.SecurityFindings.Count)" `
                    "($highSeverityFindings high severity)" -ForegroundColor $findingColor

                if ($highSeverityFindings -gt 0) {
                    Write-Host "`n=== High Severity Findings ===" -ForegroundColor Red
                    $highFindings = @($results.SecurityFindings | Where-Object { $_.Severity -eq 'High' })
                    foreach ($finding in ($highFindings | Select-Object -First 10)) {
                        Write-Host "[-]   [$($finding.VMName)] $($finding.Finding)" -ForegroundColor Red
                        Write-Host "[!]     Recommendation: $($finding.Recommendation)" -ForegroundColor Yellow
                    }
                }
            }

            'HTML' {
                $htmlFile = Join-Path $resolvedOutputPath "Azure-VM-Security-${RunTimestamp}_${RunId}.html"

                $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>Azure VM Security Configuration Report</title>
    <style>
        body { font-family: 'Segoe UI', Arial, sans-serif; margin: 20px; background: #f5f5f5; }
        h1 { color: #0078d4; }
        .summary { background: white; padding: 20px; border-radius: 8px; margin-bottom: 20px; }
        table { border-collapse: collapse; width: 100%; background: white; margin: 10px 0; }
        th { background: #0078d4; color: white; padding: 10px; }
        td { padding: 8px; border-bottom: 1px solid #ddd; }
        .excellent { background-color: #d4edda; }
        .good { background-color: #d1ecf1; }
        .fair { background-color: #fff3cd; }
        .poor { background-color: #f8d7da; }
    </style>
</head>
<body>
    <h1>Azure VM Security Configuration Report</h1>
    <div class="summary">
        <strong>Generated:</strong> $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')<br>
        <strong>Average Security Score:</strong> $avgSecurityScore/100<br>
        <strong>Total VMs:</strong> $totalVMs | <strong>High Severity Findings:</strong> $highSeverityFindings
    </div>

    <h2>VM Security Status</h2>
    <table>
        <tr><th>VM Name</th><th>Security Score</th><th>Rating</th><th>Issues</th></tr>
"@

                foreach ($vm in ($results.VMSecurityStatus | Sort-Object SecurityScore)) {
                    $rowClass = $vm.SecurityRating.ToLower()
                    $html += "<tr class='$rowClass'><td>$([System.Net.WebUtility]::HtmlEncode("$($vm.VMName)"))</td>" +
                        "<td>$($vm.SecurityScore)</td>" +
                        "<td>$([System.Net.WebUtility]::HtmlEncode("$($vm.SecurityRating)"))</td>" +
                        "<td>$([System.Net.WebUtility]::HtmlEncode("$($vm.SecurityIssues)"))</td></tr>"
                }

                $html += "</table><p style='margin-top: 30px; text-align: center; color: #666; font-size: 12px;'>" +
                    "<strong>Note:</strong> This report has not been thoroughly tested.</p></body></html>"
                $html | Out-File -FilePath $htmlFile -Encoding UTF8 -ErrorAction Stop
                Write-Host "`n[+] HTML saved to: $htmlFile" -ForegroundColor Green
            }

            'JSON' {
                $jsonFile = Join-Path $resolvedOutputPath "Azure-VM-Security-${RunTimestamp}_${RunId}.json"
                $results | ConvertTo-Json -Depth 10 | Out-File -FilePath $jsonFile -ErrorAction Stop
                Write-Host "`n[+] JSON saved to: $jsonFile" -ForegroundColor Green
            }
        }

        Write-Host "`n[+] Azure VM security configuration audit complete!" -ForegroundColor Green
        return 0
    }
    catch {
        Write-Host "[-] Error: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Justification for PSUseOutputTypeCorrectly: Main returns an int exit code consumed by the guard below.
# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main @PSBoundParameters) }
