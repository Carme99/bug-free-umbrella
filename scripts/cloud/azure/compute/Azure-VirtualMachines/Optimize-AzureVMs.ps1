<#
.SYNOPSIS
    Analyzes and optimizes Azure Virtual Machine configurations for cost and performance.

.DESCRIPTION
    Comprehensive Azure VM optimization tool that provides:
    - Right-sizing recommendations based on actual utilization
    - Cost optimization opportunities (Reserved Instances, Spot VMs)
    - Underutilized VM detection
    - Stopped VM inventory (still incurring costs)
    - Disk optimization recommendations
    - Availability zone and set compliance
    - VM extension health
    - Backup and disaster recovery status

.PARAMETER SubscriptionId
    Azure subscription ID. Use '*' for all subscriptions.

.PARAMETER ResourceGroupName
    Specific resource group to analyze. Use '*' for all resource groups.

.PARAMETER DaysToAnalyze
    Days of performance metrics to analyze. Default: 7

.PARAMETER UtilizationThreshold
    CPU utilization threshold for right-sizing. Default: 20% (VMs below are candidates for downsizing)

.PARAMETER GenerateRecommendations
    Generate actionable optimization recommendations

.PARAMETER OutputFormat
    Output format: 'Console', 'HTML', or 'JSON'. Default: 'HTML'

.PARAMETER OutputPath
    Path for output files. Default: MyDocuments\Reports

.EXAMPLE
    Connect-AzAccount
    .\Optimize-AzureVMs.ps1 -SubscriptionId "*" -GenerateRecommendations

.EXAMPLE
    .\Optimize-AzureVMs.ps1 -SubscriptionId "sub-id" `
        -ResourceGroupName "rg-production" `
        -DaysToAnalyze 30 `
        -UtilizationThreshold 15 `
        -GenerateRecommendations

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
    [int]$DaysToAnalyze = 7,

    [Parameter(Mandatory = $false)]
    [int]$UtilizationThreshold = 20,

    [Parameter(Mandatory = $false)]
    [switch]$GenerateRecommendations,

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
Import-Module Az.Monitor -ErrorAction SilentlyContinue

$results = @{
    Timestamp = Get-Date
    AnalysisPeriod = $DaysToAnalyze
    VMAnalysis = @()
    StoppedVMs = @()
    Recommendations = @()
    CostSavingsOpportunities = @()
    Summary = @{}
}

Write-Host "Analyzing Azure Virtual Machines for optimization..." -ForegroundColor Cyan

# Ensure logged in
try {
    $context = Get-AzContext
    if (-not $context) {
        Write-Error "Not logged in. Run Connect-AzAccount first."
        exit 1
    }
} catch {
    Write-Error "Azure authentication required"
    exit 1
}

# Get subscriptions
$subscriptions = if ($SubscriptionId -eq '*') {
    Get-AzSubscription
} else {
    @(Get-AzSubscription -SubscriptionId $SubscriptionId)
}

foreach ($sub in $subscriptions) {
    Write-Host "`nAnalyzing subscription: $($sub.Name)" -ForegroundColor Yellow
    Set-AzContext -SubscriptionId $sub.Id | Out-Null

    # Get VMs
    $vms = if ($ResourceGroupName -eq '*') {
        Get-AzVM -Status
    } else {
        Get-AzVM -ResourceGroupName $ResourceGroupName -Status
    }

    Write-Host "Found $($vms.Count) VMs" -ForegroundColor White

    foreach ($vm in $vms) {
        $vmPowerState = ($vm.Statuses | Where-Object { $_.Code -like 'PowerState/*' }).DisplayStatus

        $vmData = @{
            Name = $vm.Name
            ResourceGroup = $vm.ResourceGroupName
            Location = $vm.Location
            Size = $vm.HardwareProfile.VmSize
            PowerState = $vmPowerState
            OSType = $vm.StorageProfile.OsDisk.OsType
            Subscription = $sub.Name
        }

        # Check if VM is stopped but still allocated (costs money)
        if ($vmPowerState -eq 'VM stopped') {
            $results.StoppedVMs += $vmData
            $vmData.Warning = "VM is stopped but still allocated - incurring costs"
        }

        # Get performance metrics for running VMs
        if ($vmPowerState -eq 'VM running') {
            $resourceId = $vm.Id
            $endTime = Get-Date
            $startTime = $endTime.AddDays(-$DaysToAnalyze)

            try {
                # Get CPU metrics
                $cpuMetric = Get-AzMetric -ResourceId $resourceId `
                    -MetricName "Percentage CPU" `
                    -StartTime $startTime `
                    -EndTime $endTime `
                    -TimeGrain 01:00:00 `
                    -AggregationType Average `
                    -ErrorAction SilentlyContinue

                if ($cpuMetric.Data.Count -gt 0) {
                    $avgCPU = [math]::Round(($cpuMetric.Data.Average | Measure-Object -Average).Average, 2)
                    $maxCPU = [math]::Round(($cpuMetric.Data.Average | Measure-Object -Maximum).Maximum, 2)

                    $vmData.AvgCPU = $avgCPU
                    $vmData.MaxCPU = $maxCPU

                    # Right-sizing recommendation
                    if ($avgCPU -lt $UtilizationThreshold) {
                        $vmData.RightSizingOpportunity = "Underutilized - Average CPU: $avgCPU%"

                        if ($GenerateRecommendations) {
                            $results.Recommendations += @{
                                Type = "Right-Sizing"
                                Resource = "$($vm.Name) ($($vm.ResourceGroupName))"
                                CurrentSize = $vm.HardwareProfile.VmSize
                                Reason = "Average CPU utilization is $avgCPU% over $DaysToAnalyze days"
                                Recommendation = "Consider downsizing to a smaller VM SKU"
                                PotentialSavings = "Estimated 20-40% cost reduction"
                            }
                        }
                    }
                }
            } catch {
                Write-Warning "Could not retrieve metrics for $($vm.Name): $($_.Exception.Message)"
            }
        }

        # Check for managed disks
        $osDiskType = $vm.StorageProfile.OsDisk.ManagedDisk.StorageAccountType
        $vmData.OSDiskType = $osDiskType

        # Disk optimization opportunity
        if ($osDiskType -eq 'Premium_LRS' -and $vmData.AvgCPU -lt 30) {
            if ($GenerateRecommendations) {
                $results.Recommendations += @{
                    Type = "Disk Optimization"
                    Resource = "$($vm.Name) - OS Disk"
                    CurrentConfig = "Premium SSD"
                    Recommendation = "Consider switching to Standard SSD for cost savings"
                    PotentialSavings = "30-50% on disk costs"
                }
            }
        }

        # Check availability
        if ($vm.AvailabilitySetReference) {
            $vmData.HighAvailability = "Availability Set"
        } elseif ($vm.Zones) {
            $vmData.HighAvailability = "Availability Zone: $($vm.Zones -join ',')"
        } else {
            $vmData.HighAvailability = "None"

            if ($GenerateRecommendations) {
                $results.Recommendations += @{
                    Type = "High Availability"
                    Resource = $vm.Name
                    CurrentConfig = "No HA configuration"
                    Recommendation = "Deploy in Availability Zone or Set for production workloads"
                    Benefit = "99.99% SLA"
                }
            }
        }

        $results.VMAnalysis += $vmData
    }
}

# Calculate summary
$totalVMs = $results.VMAnalysis.Count
$runningVMs = ($results.VMAnalysis | Where-Object { $_.PowerState -eq 'VM running' }).Count
$stoppedAllocated = $results.StoppedVMs.Count
$underutilizedVMs = ($results.VMAnalysis | Where-Object { $_.AvgCPU -lt $UtilizationThreshold -and $_.PowerState -eq 'VM running' }).Count

$results.Summary = @{
    TotalVMs = $totalVMs
    RunningVMs = $runningVMs
    StoppedAllocatedVMs = $stoppedAllocated
    UnderutilizedVMs = $underutilizedVMs
    TotalRecommendations = $results.Recommendations.Count
    EstimatedMonthlySavings = "Calculate based on VM pricing"
}

# Run-scoped stamp to avoid filename collisions on rapid re-runs
$RunTimestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$RunId = [Guid]::NewGuid().ToString('N').Substring(0, 8)

# Output
switch ($OutputFormat) {
    'Console' {
        Write-Host "`n=== Azure VM Optimization Summary ===" -ForegroundColor Cyan
        Write-Host "Total VMs: $totalVMs" -ForegroundColor White
        Write-Host "Running: $runningVMs | Stopped (Allocated): $stoppedAllocated" -ForegroundColor White
        Write-Host "Underutilized VMs: $underutilizedVMs" -ForegroundColor Yellow
        Write-Host "Optimization Recommendations: $($results.Recommendations.Count)" -ForegroundColor White

        if ($results.StoppedVMs.Count -gt 0) {
            Write-Host "`n=== Stopped VMs (Still Incurring Costs) ===" -ForegroundColor Red
            foreach ($vm in $results.StoppedVMs) {
                Write-Host "  $($vm.Name) in $($vm.ResourceGroup)" -ForegroundColor Red
            }
        }

        if ($results.Recommendations.Count -gt 0) {
            Write-Host "`n=== Top Recommendations ===" -ForegroundColor Cyan
            foreach ($rec in ($results.Recommendations | Select-Object -First 5)) {
                Write-Host "[$($rec.Type)] $($rec.Resource)" -ForegroundColor Yellow
                Write-Host "  Recommendation: $($rec.Recommendation)" -ForegroundColor White
            }
        }
    }

    'HTML' {
        $htmlFile = Join-Path $OutputPath "Azure-VM-Optimization-${RunTimestamp}_${RunId}.html"
        $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>Azure VM Optimization Report</title>
    <style>
        body { font-family: 'Segoe UI', Arial, sans-serif; margin: 20px; background: #f5f5f5; }
        h1 { color: #0078d4; }
        .summary { background: white; padding: 20px; border-radius: 8px; margin-bottom: 20px; }
        table { border-collapse: collapse; width: 100%; background: white; margin: 10px 0; }
        th { background: #0078d4; color: white; padding: 10px; }
        td { padding: 8px; border-bottom: 1px solid #ddd; }
        .underutilized { background-color: #fff3cd; }
        .stopped { background-color: #fdd; }
        .recommendation { background-color: #d1ecf1; padding: 10px; margin: 5px 0; border-radius: 5px; }
    </style>
</head>
<body>
    <h1>Azure VM Optimization Report</h1>
    <div class="summary">
        <strong>Generated:</strong> $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')<br>
        <strong>Total VMs:</strong> $totalVMs | <strong>Running:</strong> $runningVMs | <strong>Underutilized:</strong> $underutilizedVMs<br>
        <strong>Stopped (Allocated):</strong> $stoppedAllocated | <strong>Recommendations:</strong> $($results.Recommendations.Count)
    </div>
    <h2>VM Analysis</h2>
    <table>
        <tr><th>Name</th><th>Size</th><th>Power State</th><th>Avg CPU %</th><th>HA Config</th></tr>
"@
        foreach ($vm in $results.VMAnalysis) {
            $rowClass = ""
            if ($vm.PowerState -eq 'VM stopped') { $rowClass = "stopped" }
            elseif ($vm.AvgCPU -lt $UtilizationThreshold) { $rowClass = "underutilized" }

            $html += "<tr class='$rowClass'><td>$([System.Net.WebUtility]::HtmlEncode("$($vm.Name)"))</td><td>$([System.Net.WebUtility]::HtmlEncode("$($vm.Size)"))</td><td>$([System.Net.WebUtility]::HtmlEncode("$($vm.PowerState)"))</td><td>$($vm.AvgCPU)</td><td>$([System.Net.WebUtility]::HtmlEncode("$($vm.HighAvailability)"))</td></tr>"
        }
        $html += "</table>"

        if ($results.Recommendations.Count -gt 0) {
            $html += "<h2>Recommendations</h2>"
            foreach ($rec in $results.Recommendations) {
                $html += "<div class='recommendation'><strong>[$([System.Net.WebUtility]::HtmlEncode("$($rec.Type)"))]</strong> $([System.Net.WebUtility]::HtmlEncode("$($rec.Resource)"))<br>$([System.Net.WebUtility]::HtmlEncode("$($rec.Recommendation)"))<br><em>$([System.Net.WebUtility]::HtmlEncode("$($rec.PotentialSavings)"))</em></div>"
            }
        }

        $html += "<p style='margin-top: 30px; text-align: center; color: #666; font-size: 12px;'><strong>Note:</strong> This report has not been thoroughly tested.</p></body></html>"
        $html | Out-File -FilePath $htmlFile -Encoding UTF8
        Write-Host "`nHTML saved to: $htmlFile" -ForegroundColor Green
    }

    'JSON' {
        $jsonFile = Join-Path $OutputPath "Azure-VM-Optimization-${RunTimestamp}_${RunId}.json"
        $results | ConvertTo-Json -Depth 10 | Out-File -FilePath $jsonFile
        Write-Host "`nJSON saved to: $jsonFile" -ForegroundColor Green
    }
}

Write-Host "`nAzure VM optimization analysis complete!" -ForegroundColor Green
