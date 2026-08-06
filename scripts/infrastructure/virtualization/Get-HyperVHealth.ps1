<#
.SYNOPSIS
    Performs comprehensive health check of Hyper-V host and virtual machines.

.DESCRIPTION
    This script checks Hyper-V infrastructure health including:
    - Host resource utilization
    - Virtual machine status
    - Virtual switch configuration
    - Storage and disk usage
    - Snapshot/checkpoint status
    - Replication health
    - Integration services status
    - Memory pressure
    - Virtual processor allocation

.PARAMETER IncludeVMs
    Include detailed VM health checks.

.PARAMETER CheckReplication
    Check Hyper-V Replica status (if configured).

.PARAMETER CheckSnapshots
    Identify VMs with snapshots/checkpoints.

.PARAMETER ExportHTML
    Export results to HTML report.

.PARAMETER ExportCSV
    Export results to CSV file.

.EXAMPLE
    .\Get-HyperVHealth.ps1
    Basic Hyper-V host health check.

.EXAMPLE
    .\Get-HyperVHealth.ps1 -IncludeVMs -CheckSnapshots -ExportHTML
    Comprehensive check including VMs and snapshots.

.EXAMPLE
    .\Get-HyperVHealth.ps1 -CheckReplication
    Checks Hyper-V Replica health.

.NOTES
    Requires Hyper-V PowerShell module
    Requires Administrator privileges
    Compatible with Windows Server 2016, 2019, 2022
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [switch]$IncludeVMs,

    [Parameter(Mandatory=$false)]
    [switch]$CheckReplication,

    [Parameter(Mandatory=$false)]
    [switch]$CheckSnapshots,

    [Parameter(Mandatory=$false)]
    [switch]$ExportHTML,

    [Parameter(Mandatory=$false)]
    [switch]$ExportCSV
)

#Requires -RunAsAdministrator
#Requires -Modules Hyper-V

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

Write-Host "`n=== Hyper-V Health Check ===" -ForegroundColor Cyan
Write-Host "Host: $env:COMPUTERNAME" -ForegroundColor Yellow
Write-Host "Timestamp: $(Get-Date)" -ForegroundColor Gray
Write-Host ""

$results = @()
$issueCount = 0
$warningCount = 0

# 1. Check Hyper-V service
Write-Host "[*] Checking Hyper-V service..." -ForegroundColor Cyan

$vmmsService = Get-Service -Name vmms -ErrorAction SilentlyContinue

if ($vmmsService -and $vmmsService.Status -eq 'Running') {
    Write-Host "[+] Hyper-V Virtual Machine Management service is running" -ForegroundColor Green

    $results += [PSCustomObject]@{
        Category = "Service"
        Item = "VMMS"
        Status = "Pass"
        Finding = "Service is running"
        Details = "Startup: $($vmmsService.StartType)"
    }
}
else {
    Write-Host "[-] Hyper-V service is not running!" -ForegroundColor Red
    $issueCount++
}

Write-Host ""

# 2. Check host resources
Write-Host "[*] Checking host resources..." -ForegroundColor Cyan

$hostInfo = Get-VMHost

Write-Host "    Physical Processors: $($hostInfo.LogicalProcessorCount)" -ForegroundColor Gray
Write-Host "    Memory Total: $([math]::Round($hostInfo.MemoryCapacity / 1GB, 2)) GB" -ForegroundColor Gray

$memUsagePercent = [math]::Round(($hostInfo.MemoryCapacity - (Get-Counter '\Memory\Available Bytes').CounterSamples.CookedValue) / $hostInfo.MemoryCapacity * 100, 2)

Write-Host "    Memory Used: $memUsagePercent%" -ForegroundColor $(if ($memUsagePercent -lt 80) { "Green" } elseif ($memUsagePercent -lt 90) { "Yellow" } else { "Red" })

if ($memUsagePercent -ge 90) {
    $issueCount++
}
elseif ($memUsagePercent -ge 80) {
    $warningCount++
}

$results += [PSCustomObject]@{
    Category = "Host Resources"
    Item = "Memory Usage"
    Status = if ($memUsagePercent -lt 80) { "Pass" } elseif ($memUsagePercent -lt 90) { "Warning" } else { "Fail" }
    Finding = "$memUsagePercent% used"
    Details = "Total: $([math]::Round($hostInfo.MemoryCapacity / 1GB, 2)) GB"
}

Write-Host ""

# 3. Check virtual machines
if ($IncludeVMs) {
    Write-Host "[*] Checking virtual machines..." -ForegroundColor Cyan

    $vms = Get-VM

    Write-Host "[+] Total VMs: $($vms.Count)" -ForegroundColor Green

    $runningVMs = ($vms | Where-Object { $_.State -eq 'Running' }).Count
    $stoppedVMs = ($vms | Where-Object { $_.State -eq 'Off' }).Count
    $savedVMs = ($vms | Where-Object { $_.State -eq 'Saved' }).Count
    $pausedVMs = ($vms | Where-Object { $_.State -eq 'Paused' }).Count

    Write-Host "    Running: $runningVMs" -ForegroundColor Green
    Write-Host "    Stopped: $stoppedVMs" -ForegroundColor Gray
    if ($savedVMs -gt 0) { Write-Host "    Saved: $savedVMs" -ForegroundColor Yellow }
    if ($pausedVMs -gt 0) { Write-Host "    Paused: $pausedVMs" -ForegroundColor Yellow; $warningCount++ }

    # Check each VM
    foreach ($vm in $vms) {
        # Integration Services
        $integrationServices = Get-VMIntegrationService -VMName $vm.Name

        $outdatedIS = $integrationServices | Where-Object { $_.Enabled -and $_.PrimaryOperationalStatus -ne 'Ok' }

        if ($outdatedIS) {
            Write-Host "    [Warning] $($vm.Name): Integration Services need attention" -ForegroundColor Yellow
            $warningCount++

            $results += [PSCustomObject]@{
                Category = "VM Integration Services"
                Item = $vm.Name
                Status = "Warning"
                Finding = "Integration Services not optimal"
                Details = "State: $($vm.State)"
            }
        }

        # Check memory pressure
        if ($vm.State -eq 'Running' -and $vm.MemoryDemand -gt 0) {
            $memPressure = [math]::Round(($vm.MemoryDemand / $vm.MemoryAssigned) * 100, 2)

            if ($memPressure -gt 95) {
                Write-Host "    [Warning] $($vm.Name): Memory pressure $memPressure%" -ForegroundColor Yellow
                $warningCount++

                $results += [PSCustomObject]@{
                    Category = "VM Memory"
                    Item = $vm.Name
                    Status = "Warning"
                    Finding = "Memory pressure: $memPressure%"
                    Details = "Demand: $([math]::Round($vm.MemoryDemand / 1MB)) MB / Assigned: $([math]::Round($vm.MemoryAssigned / 1MB)) MB"
                }
            }
        }
    }

    Write-Host ""
}

# 4. Check snapshots/checkpoints
if ($CheckSnapshots) {
    Write-Host "[*] Checking for snapshots..." -ForegroundColor Cyan

    $vmsWithSnapshots = Get-VM | Where-Object { (Get-VMSnapshot -VMName $_.Name).Count -gt 0 }

    if ($vmsWithSnapshots) {
        Write-Host "[-] Found $($vmsWithSnapshots.Count) VM(s) with snapshots" -ForegroundColor Yellow
        $warningCount++

        foreach ($vm in $vmsWithSnapshots) {
            $snapshots = Get-VMSnapshot -VMName $vm.Name
            $oldestSnapshot = ($snapshots | Sort-Object CreationTime | Select-Object -First 1).CreationTime
            $daysSinceOldest = ((Get-Date) - $oldestSnapshot).Days

            Write-Host "    [Warning] $($vm.Name): $($snapshots.Count) snapshot(s), oldest is $daysSinceOldest days old" -ForegroundColor Yellow

            $results += [PSCustomObject]@{
                Category = "VM Snapshots"
                Item = $vm.Name
                Status = "Warning"
                Finding = "$($snapshots.Count) snapshot(s)"
                Details = "Oldest: $daysSinceOldest days old"
            }
        }
    }
    else {
        Write-Host "[+] No VMs with snapshots" -ForegroundColor Green
    }

    Write-Host ""
}

# 5. Check virtual switches
Write-Host "[*] Checking virtual switches..." -ForegroundColor Cyan

$vSwitches = Get-VMSwitch

Write-Host "[+] Found $($vSwitches.Count) virtual switch(es)" -ForegroundColor Green

foreach ($vSwitch in $vSwitches) {
    Write-Host "    - $($vSwitch.Name): $($vSwitch.SwitchType)" -ForegroundColor Gray

    $results += [PSCustomObject]@{
        Category = "Virtual Switch"
        Item = $vSwitch.Name
        Status = "Pass"
        Finding = "Type: $($vSwitch.SwitchType)"
        Details = "AllowManagement: $($vSwitch.AllowManagementOS)"
    }
}

Write-Host ""

# 6. Check replication
if ($CheckReplication) {
    Write-Host "[*] Checking Hyper-V Replica..." -ForegroundColor Cyan

    $replicatedVMs = Get-VM | Where-Object { $_.ReplicationState -ne 'Disabled' }

    if ($replicatedVMs) {
        Write-Host "[+] Found $($replicatedVMs.Count) VM(s) with replication enabled" -ForegroundColor Green

        foreach ($vm in $replicatedVMs) {
            $repHealth = Get-VMReplication -VMName $vm.Name

            $status = if ($repHealth.Health -eq 'Normal') { "Pass" } else { "Fail" }

            if ($status -eq "Fail") { $issueCount++ }

            Write-Host "    [$status] $($vm.Name): $($repHealth.Health)" -ForegroundColor $(if ($status -eq "Pass") { "Green" } else { "Red" })

            $results += [PSCustomObject]@{
                Category = "VM Replication"
                Item = $vm.Name
                Status = $status
                Finding = "Health: $($repHealth.Health)"
                Details = "State: $($repHealth.State), Mode: $($repHealth.ReplicationMode)"
            }
        }
    }
    else {
        Write-Host "[-] No VMs with replication configured" -ForegroundColor Gray
    }

    Write-Host ""
}

# Summary
Write-Host "=== Health Check Summary ===" -ForegroundColor Cyan
Write-Host "Total Checks: $($results.Count)" -ForegroundColor White
Write-Host "Issues: $issueCount" -ForegroundColor $(if ($issueCount -eq 0) { "Green" } else { "Red" })
Write-Host "Warnings: $warningCount" -ForegroundColor Yellow

$healthScore = if ($results.Count -gt 0) {
    [math]::Round((($results.Count - $issueCount - ($warningCount * 0.5)) / $results.Count) * 100, 2)
}
else {
    100
}

Write-Host "Health Score: $healthScore%" -ForegroundColor $(if ($healthScore -ge 80) { "Green" } elseif ($healthScore -ge 60) { "Yellow" } else { "Red" })
Write-Host ""

# Export results
if ($ExportHTML) {
    $htmlPath = "$ReportDir\HyperVHealth_$timestamp.html"

    $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>Hyper-V Health Check - $timestamp</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        h1 { color: #3498db; }
        .summary { background-color: #ecf0f1; padding: 15px; border-radius: 5px; margin: 20px 0; }
        .score { font-size: 24px; font-weight: bold; color: $(if ($healthScore -ge 80) { '#27ae60' } elseif ($healthScore -ge 60) { '#f39c12' } else { '#e74c3c' }); }
        table { border-collapse: collapse; width: 100%; margin-top: 10px; }
        th { background-color: #3498db; color: white; padding: 10px; text-align: left; }
        td { border: 1px solid #ddd; padding: 8px; font-size: 12px; }
        tr:nth-child(even) { background-color: #f2f2f2; }
        .pass { background-color: #27ae60; color: white; padding: 3px 6px; border-radius: 3px; }
        .fail { background-color: #e74c3c; color: white; padding: 3px 6px; border-radius: 3px; }
        .warning { background-color: #f39c12; color: white; padding: 3px 6px; border-radius: 3px; }
    </style>
</head>
<body>
    <h1>Hyper-V Health Check Report</h1>
    <div class="summary">
        <strong>Host:</strong> $env:COMPUTERNAME<br>
        <strong>Generated:</strong> $(Get-Date)<br>
        <strong>Health Score:</strong> <span class="score">$healthScore%</span><br>
        <strong>Issues:</strong> $issueCount | <strong>Warnings:</strong> $warningCount
    </div>

    <h2>Health Check Results</h2>
    <table>
        <tr><th>Category</th><th>Item</th><th>Status</th><th>Finding</th><th>Details</th></tr>
"@

    foreach ($result in $results) {
        $statusClass = $result.Status.ToLower()
        $html += @"
        <tr>
            <td>$($result.Category)</td>
            <td>$($result.Item)</td>
            <td><span class="$statusClass">$($result.Status)</span></td>
            <td>$($result.Finding)</td>
            <td>$($result.Details)</td>
        </tr>
"@
    }

    $html += "</table></body></html>"

    $html | Out-File -FilePath $htmlPath -Encoding UTF8
    Write-Host "[+] HTML report saved to: $htmlPath" -ForegroundColor Green
}

if ($ExportCSV) {
    $csvPath = "$ReportDir\HyperVHealth_$timestamp.csv"
    $results | Export-Csv -Path $csvPath -NoTypeInformation
    Write-Host "[+] CSV export saved to: $csvPath" -ForegroundColor Green
}

Write-Host "[+] Health check completed!" -ForegroundColor Green

if ($issueCount -gt 0) {
    exit 1
}

exit 0
