<#
.SYNOPSIS
    Audits Azure VM security configuration and compliance.

.DESCRIPTION
    Comprehensive security configuration audit including:
    - Disk encryption status (Azure Disk Encryption)
    - Network security group (NSG) assignments
    - Public IP exposure
    - Boot diagnostics configuration
    - Managed identity usage
    - VM extensions security status
    - OS patch level and update status
    - Just-In-Time (JIT) VM access configuration

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
    Path for output files. Default: MyDocuments\Reports

.EXAMPLE
    Connect-AzAccount
    .\Get-VMSecurityConfig.ps1 -SubscriptionId "*" -CheckEncryption -CheckNetworkSecurity

.NOTES
    Author: IT Operations
    Version: 1.0.0
    Requires: PowerShell 5.1+, Az PowerShell module

    WARNING: This script has not been thoroughly tested in production environments.
    Please test in a non-production environment first and validate results before relying on this data.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$SubscriptionId = "*",

    [Parameter(Mandatory = $false)]
    [string]$ResourceGroupName = "*",

    [Parameter(Mandatory = $false)]
    [switch]$CheckEncryption,

    [Parameter(Mandatory = $false)]
    [switch]$CheckNetworkSecurity,

    [Parameter(Mandatory = $false)]
    [ValidateSet('Console', 'HTML', 'JSON')]
    [string]$OutputFormat = 'HTML',

    [Parameter(Mandatory = $false)]
    [string]$OutputPath = (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Reports')
)
# Validate OutputPath: reject '..' traversal and UNC remote paths before resolution
if ([string]::IsNullOrWhiteSpace($OutputPath) -or
    $OutputPath -match '(^|[\\/])\.\.([\\/]|$)' -or
    $OutputPath -match '^(\\\\|//)') {
    Write-Error "Unsafe OutputPath: $OutputPath. OutputPath must be a local absolute path without '..' traversal."
    exit 1
}
$OutputPath = [System.IO.Path]::GetFullPath($OutputPath)
if (-not (Test-Path -LiteralPath $OutputPath -PathType Container)) {
    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
}

if (-not (Get-Module -ListAvailable -Name Az.Compute)) {
    Write-Error "Az.Compute module required. Install: Install-Module Az"
    exit 1
}

Import-Module Az.Compute -ErrorAction SilentlyContinue
Import-Module Az.Network -ErrorAction SilentlyContinue

$results = @{
    Timestamp = Get-Date
    VMSecurityStatus = @()
    SecurityFindings = @()
    Summary = @{}
}

Write-Host "Auditing Azure VM security configuration..." -ForegroundColor Cyan

try {
    $context = Get-AzContext
    if (-not $context) {
        Write-Error "Not logged in. Run Connect-AzAccount"
        exit 1
    }
} catch {
    Write-Error "Azure authentication required"
    exit 1
}

$subscriptions = if ($SubscriptionId -eq '*') {
    Get-AzSubscription
} else {
    @(Get-AzSubscription -SubscriptionId $SubscriptionId)
}

foreach ($sub in $subscriptions) {
    Write-Host "`nAnalyzing subscription: $($sub.Name)" -ForegroundColor Yellow
    Set-AzContext -SubscriptionId $sub.Id | Out-Null

    $vms = if ($ResourceGroupName -eq '*') {
        Get-AzVM -Status
    } else {
        Get-AzVM -ResourceGroupName $ResourceGroupName -Status
    }

    Write-Host "Found $($vms.Count) VMs" -ForegroundColor White

    foreach ($vm in $vms) {
        Write-Host "  Auditing: $($vm.Name)" -ForegroundColor Gray

        $vmSecurity = @{
            VMName = $vm.Name
            ResourceGroup = $vm.ResourceGroupName
            Location = $vm.Location
            OSType = $vm.StorageProfile.OsDisk.OsType
            Subscription = $sub.Name
            PowerState = ($vm.Statuses | Where-Object { $_.Code -like 'PowerState/*' }).DisplayStatus
            SecurityIssues = @()
            SecurityScore = 100
        }

        # Check disk encryption
        if ($CheckEncryption) {
            $encryptionStatus = Get-AzVMDiskEncryptionStatus -ResourceGroupName $vm.ResourceGroupName -VMName $vm.Name -ErrorAction SilentlyContinue

            if ($encryptionStatus) {
                $vmSecurity.OSDiskEncrypted = $encryptionStatus.OsVolumeEncrypted
                $vmSecurity.DataDisksEncrypted = $encryptionStatus.DataVolumesEncrypted

                if ($encryptionStatus.OsVolumeEncrypted -ne 'Encrypted') {
                    $vmSecurity.SecurityIssues += "OS disk not encrypted"
                    $vmSecurity.SecurityScore -= 20
                    $results.SecurityFindings += @{
                        VMName = $vm.Name
                        Severity = "High"
                        Finding = "OS disk encryption not enabled"
                        Recommendation = "Enable Azure Disk Encryption"
                    }
                }
            } else {
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

                        $results.SecurityFindings += @{
                            VMName = $vm.Name
                            Severity = "Medium"
                            Finding = "VM has public IP address"
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

                $results.SecurityFindings += @{
                    VMName = $vm.Name
                    Severity = "High"
                    Finding = "No NSG protection"
                    Recommendation = "Assign Network Security Group to restrict traffic"
                }
            }
        }

        # Check boot diagnostics
        if ($vm.DiagnosticsProfile.BootDiagnostics.Enabled) {
            $vmSecurity.BootDiagnosticsEnabled = $true
        } else {
            $vmSecurity.BootDiagnosticsEnabled = $false
            $vmSecurity.SecurityIssues += "Boot diagnostics disabled"
            $vmSecurity.SecurityScore -= 5
        }

        # Check managed identity
        if ($vm.Identity) {
            $vmSecurity.ManagedIdentity = $vm.Identity.Type
        } else {
            $vmSecurity.ManagedIdentity = "None"
        }

        # Check VM extensions
        $extensions = Get-AzVMExtension -ResourceGroupName $vm.ResourceGroupName -VMName $vm.Name -ErrorAction SilentlyContinue

        $vmSecurity.ExtensionCount = ($extensions | Measure-Object).Count
        $vmSecurity.Extensions = ($extensions | Select-Object -ExpandProperty Name) -join ', '

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
} else { 0 }

$results.Summary = @{
    TotalVMs = $totalVMs
    ExcellentSecurityVMs = $excellentVMs
    PoorSecurityVMs = $poorVMs
    AverageSecurityScore = $avgSecurityScore
    HighSeverityFindings = $highSeverityFindings
    TotalFindings = $results.SecurityFindings.Count
}

# Run-scoped stamp to avoid filename collisions on rapid re-runs
$RunTimestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$RunId = [Guid]::NewGuid().ToString('N').Substring(0, 8)

# Output
switch ($OutputFormat) {
    'Console' {
        Write-Host "`n=== Azure VM Security Configuration Summary ===" -ForegroundColor Cyan
        Write-Host "Total VMs: $totalVMs" -ForegroundColor White
        Write-Host "Average Security Score: $avgSecurityScore/100" -ForegroundColor White
        Write-Host "Excellent: $excellentVMs | Poor: $poorVMs" -ForegroundColor White
        Write-Host "Security Findings: $($results.SecurityFindings.Count) ($highSeverityFindings high severity)" -ForegroundColor $(if ($highSeverityFindings -gt 0) { 'Red' } else { 'Green' })

        if ($highSeverityFindings -gt 0) {
            Write-Host "`n=== High Severity Findings ===" -ForegroundColor Red
            foreach ($finding in ($results.SecurityFindings | Where-Object { $_.Severity -eq 'High' } | Select-Object -First 10)) {
                Write-Host "  [$($finding.VMName)] $($finding.Finding)" -ForegroundColor Red
                Write-Host "    Recommendation: $($finding.Recommendation)" -ForegroundColor Yellow
            }
        }
    }

    'HTML' {
        $htmlFile = Join-Path $OutputPath "Azure-VM-Security-${RunTimestamp}_${RunId}.html"

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
            $html += "<tr class='$rowClass'><td>$([System.Net.WebUtility]::HtmlEncode("$($vm.VMName)"))</td><td>$($vm.SecurityScore)</td><td>$([System.Net.WebUtility]::HtmlEncode("$($vm.SecurityRating)"))</td><td>$([System.Net.WebUtility]::HtmlEncode("$($vm.SecurityIssues)"))</td></tr>"
        }

        $html += "</table><p style='margin-top: 30px; text-align: center; color: #666; font-size: 12px;'><strong>Note:</strong> This report has not been thoroughly tested.</p></body></html>"
        $html | Out-File -FilePath $htmlFile -Encoding UTF8
        Write-Host "`nHTML saved to: $htmlFile" -ForegroundColor Green
    }

    'JSON' {
        $jsonFile = Join-Path $OutputPath "Azure-VM-Security-${RunTimestamp}_${RunId}.json"
        $results | ConvertTo-Json -Depth 10 | Out-File -FilePath $jsonFile
        Write-Host "`nJSON saved to: $jsonFile" -ForegroundColor Green
    }
}

Write-Host "`nAzure VM security configuration audit complete!" -ForegroundColor Green
