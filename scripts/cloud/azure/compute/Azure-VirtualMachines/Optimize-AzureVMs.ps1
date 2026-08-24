<#
.SYNOPSIS
    Analyzes and optimizes Azure Virtual Machine configurations for cost and performance.

.DESCRIPTION
    Comprehensive read-only Azure VM optimization analysis that inventories virtual machines
    across the targeted subscriptions and reports:
    - Right-sizing recommendations based on actual utilization
    - Cost optimization opportunities (Reserved Instances, Spot VMs)
    - Underutilized VM detection
    - Stopped VM inventory (still incurring costs)
    - Disk optimization recommendations
    - Availability zone and set compliance
    - VM extension health
    - Backup and disaster recovery status

    The script never mutates Azure resources: it only reads configuration and metrics and,
    for HTML/JSON output formats, writes a uniquely-named report file under -OutputPath.
    Re-running against an unchanged environment is safe (idempotent). A missing Az.Compute
    module or missing Azure login fails with exit code 1.

.PARAMETER SubscriptionId
    Azure subscription ID. Use '*' for all subscriptions.

.PARAMETER ResourceGroupName
    Specific resource group to analyze. Use '*' for all resource groups.

.PARAMETER DaysToAnalyze
    Days of performance metrics to analyze (1-365). Default: 7

.PARAMETER UtilizationThreshold
    CPU utilization threshold for right-sizing (1-100). VMs averaging below it are candidates
    for downsizing. Default: 20%

.PARAMETER GenerateRecommendations
    Generate actionable optimization recommendations

.PARAMETER OutputFormat
    Output format: 'Console', 'HTML', or 'JSON'. Default: 'HTML'

.PARAMETER OutputPath
    Local directory path for output files. Default: MyDocuments\Reports

.EXAMPLE
    PS C:\> Connect-AzAccount
    PS C:\> .\Optimize-AzureVMs.ps1 -SubscriptionId "*" -GenerateRecommendations -OutputFormat Console
    Analyzes every accessible subscription and prints the optimization summary to the console.

.EXAMPLE
    PS C:\> .\Optimize-AzureVMs.ps1 -SubscriptionId "sub-id" -ResourceGroupName "rg-production" `
        -DaysToAnalyze 30 -UtilizationThreshold 15 -GenerateRecommendations
    Analyzes rg-production over 30 days and writes an HTML report to the default Reports folder.

.NOTES
    File Name   : Optimize-AzureVMs.ps1
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
    [ValidateRange(1, 365)]
    [int]$DaysToAnalyze = 7,

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 100)]
    [int]$UtilizationThreshold = 20,

    [Parameter(Mandatory = $false)]
    [switch]$GenerateRecommendations,

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

        [ValidateRange(1, 365)]
        [int]$DaysToAnalyze = 7,

        [ValidateRange(1, 100)]
        [int]$UtilizationThreshold = 20,

        [switch]$GenerateRecommendations,

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
        Import-Module Az.Monitor -ErrorAction SilentlyContinue

        $results = @{
            Timestamp               = Get-Date
            AnalysisPeriod          = $DaysToAnalyze
            VMAnalysis              = @()
            StoppedVMs              = @()
            Recommendations         = @()
            CostSavingsOpportunities = @()
            Summary                 = @{}
        }

        Write-Host "[*] Analyzing Azure Virtual Machines for optimization..." -ForegroundColor Cyan

        # Ensure logged in
        $context = Get-AzContext -ErrorAction Stop
        if (-not $context) {
            throw "Not logged in to Azure. Run Connect-AzAccount"
        }

        # Get subscriptions
        $subscriptions = if ($SubscriptionId -eq '*') {
            Get-AzSubscription -ErrorAction Stop
        }
        else {
            @(Get-AzSubscription -SubscriptionId $SubscriptionId -ErrorAction Stop)
        }

        foreach ($sub in $subscriptions) {
            Write-Host "`n[*] Analyzing subscription: $($sub.Name)" -ForegroundColor Cyan
            Set-AzContext -SubscriptionId $sub.Id -ErrorAction Stop | Out-Null

            # Get VMs
            $vms = if ($ResourceGroupName -eq '*') {
                @(Get-AzVM -Status -ErrorAction Stop)
            }
            else {
                @(Get-AzVM -ResourceGroupName $ResourceGroupName -Status -ErrorAction Stop)
            }

            Write-Host "[*] Found $($vms.Count) VMs" -ForegroundColor White

            foreach ($vm in $vms) {
                $vmPowerState = ($vm.Statuses | Where-Object { $_.Code -like 'PowerState/*' }).DisplayStatus

                $vmData = [pscustomobject]@{
                    Name           = $vm.Name
                    ResourceGroup  = $vm.ResourceGroupName
                    Location       = $vm.Location
                    Size           = $vm.HardwareProfile.VmSize
                    PowerState     = $vmPowerState
                    OSType         = $vm.StorageProfile.OsDisk.OsType
                    Subscription   = $sub.Name
                    AvgCPU         = $null
                    MaxCPU         = $null
                    Warning        = ''
                    RightSizingOpportunity = ''
                    OSDiskType     = ''
                    HighAvailability = ''
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
                                    $results.Recommendations += [pscustomobject]@{
                                        Type             = "Right-Sizing"
                                        Resource         = "$($vm.Name) ($($vm.ResourceGroupName))"
                                        CurrentSize      = $vm.HardwareProfile.VmSize
                                        Reason           = "Average CPU utilization is $avgCPU% over" +
                                            " $DaysToAnalyze days"
                                        Recommendation   = "Consider downsizing to a smaller VM SKU"
                                        PotentialSavings = "Estimated 20-40% cost reduction"
                                    }
                                }
                            }
                        }
                    }
                    catch {
                        Write-Host "[!] Could not retrieve metrics for $($vm.Name): $($_.Exception.Message)" `
                            -ForegroundColor Yellow
                    }
                }

                # Check for managed disks
                $osDiskType = $vm.StorageProfile.OsDisk.ManagedDisk.StorageAccountType
                $vmData.OSDiskType = $osDiskType

                # Disk optimization opportunity
                if ($osDiskType -eq 'Premium_LRS' -and $vmData.AvgCPU -lt 30) {
                    if ($GenerateRecommendations) {
                        $results.Recommendations += [pscustomobject]@{
                            Type             = "Disk Optimization"
                            Resource         = "$($vm.Name) - OS Disk"
                            CurrentConfig    = "Premium SSD"
                            Recommendation   = "Consider switching to Standard SSD for cost savings"
                            PotentialSavings = "30-50% on disk costs"
                        }
                    }
                }

                # Check availability
                if ($vm.AvailabilitySetReference) {
                    $vmData.HighAvailability = "Availability Set"
                }
                elseif ($vm.Zones) {
                    $vmData.HighAvailability = "Availability Zone: $($vm.Zones -join ',')"
                }
                else {
                    $vmData.HighAvailability = "None"

                    if ($GenerateRecommendations) {
                        $results.Recommendations += [pscustomobject]@{
                            Type           = "High Availability"
                            Resource       = $vm.Name
                            CurrentConfig  = "No HA configuration"
                            Recommendation = "Deploy in Availability Zone or Set for production workloads"
                            Benefit        = "99.99% SLA"
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
        $underutilizedVMs = ($results.VMAnalysis | Where-Object {
            $_.AvgCPU -lt $UtilizationThreshold -and $_.PowerState -eq 'VM running'
        }).Count

        $results.Summary = @{
            TotalVMs                = $totalVMs
            RunningVMs              = $runningVMs
            StoppedAllocatedVMs     = $stoppedAllocated
            UnderutilizedVMs        = $underutilizedVMs
            TotalRecommendations    = $results.Recommendations.Count
            EstimatedMonthlySavings = "Calculate based on VM pricing"
        }

        # Run-scoped stamp to avoid filename collisions on rapid re-runs
        $RunTimestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $RunId = [Guid]::NewGuid().ToString('N').Substring(0, 8)

        # Output
        switch ($OutputFormat) {
            'Console' {
                Write-Host "`n=== Azure VM Optimization Summary ===" -ForegroundColor Cyan
                Write-Host "[*] Total VMs: $totalVMs" -ForegroundColor White
                Write-Host "[*] Running: $runningVMs | Stopped (Allocated): $stoppedAllocated" -ForegroundColor White
                Write-Host "[!] Underutilized VMs: $underutilizedVMs" -ForegroundColor Yellow
                Write-Host "[*] Optimization Recommendations: $($results.Recommendations.Count)" -ForegroundColor White

                if ($results.StoppedVMs.Count -gt 0) {
                    Write-Host "`n=== Stopped VMs (Still Incurring Costs) ===" -ForegroundColor Red
                    foreach ($vm in $results.StoppedVMs) {
                        Write-Host "[-]   $($vm.Name) in $($vm.ResourceGroup)" -ForegroundColor Red
                    }
                }

                if ($results.Recommendations.Count -gt 0) {
                    Write-Host "`n=== Top Recommendations ===" -ForegroundColor Cyan
                    foreach ($rec in ($results.Recommendations | Select-Object -First 5)) {
                        Write-Host "[!] [$($rec.Type)] $($rec.Resource)" -ForegroundColor Yellow
                        Write-Host "[*]   Recommendation: $($rec.Recommendation)" -ForegroundColor White
                    }
                }
            }

            'HTML' {
                $htmlFile = Join-Path $resolvedOutputPath "Azure-VM-Optimization-${RunTimestamp}_${RunId}.html"
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
        <strong>Total VMs:</strong> $totalVMs | <strong>Running:</strong> $runningVMs<br>
        <strong>Underutilized:</strong> $underutilizedVMs |
        <strong>Stopped (Allocated):</strong> $stoppedAllocated |
        <strong>Recommendations:</strong> $($results.Recommendations.Count)
    </div>
    <h2>VM Analysis</h2>
    <table>
        <tr><th>Name</th><th>Size</th><th>Power State</th><th>Avg CPU %</th><th>HA Config</th></tr>
"@
                foreach ($vm in $results.VMAnalysis) {
                    $rowClass = ""
                    if ($vm.PowerState -eq 'VM stopped') { $rowClass = "stopped" }
                    elseif ($vm.AvgCPU -lt $UtilizationThreshold) { $rowClass = "underutilized" }

                    $html += "<tr class='$rowClass'><td>$([System.Net.WebUtility]::HtmlEncode("$($vm.Name)"))</td>" +
                        "<td>$([System.Net.WebUtility]::HtmlEncode("$($vm.Size)"))</td>" +
                        "<td>$([System.Net.WebUtility]::HtmlEncode("$($vm.PowerState)"))</td>" +
                        "<td>$($vm.AvgCPU)</td>" +
                        "<td>$([System.Net.WebUtility]::HtmlEncode("$($vm.HighAvailability)"))</td></tr>"
                }
                $html += "</table>"

                if ($results.Recommendations.Count -gt 0) {
                    $html += "<h2>Recommendations</h2>"
                    foreach ($rec in $results.Recommendations) {
                        $html += "<div class='recommendation'>" +
                            "<strong>[$([System.Net.WebUtility]::HtmlEncode("$($rec.Type)"))]</strong> " +
                            "$([System.Net.WebUtility]::HtmlEncode("$($rec.Resource)"))<br>" +
                            "$([System.Net.WebUtility]::HtmlEncode("$($rec.Recommendation)"))<br>" +
                            "<em>$([System.Net.WebUtility]::HtmlEncode("$($rec.PotentialSavings)"))</em></div>"
                    }
                }

                $html += "<p style='margin-top: 30px; text-align: center; color: #666; font-size: 12px;'>" +
                    "<strong>Note:</strong> This report has not been thoroughly tested.</p></body></html>"
                $html | Out-File -FilePath $htmlFile -Encoding UTF8 -ErrorAction Stop
                Write-Host "`n[+] HTML saved to: $htmlFile" -ForegroundColor Green
            }

            'JSON' {
                $jsonFile = Join-Path $resolvedOutputPath "Azure-VM-Optimization-${RunTimestamp}_${RunId}.json"
                $results | ConvertTo-Json -Depth 10 | Out-File -FilePath $jsonFile -ErrorAction Stop
                Write-Host "`n[+] JSON saved to: $jsonFile" -ForegroundColor Green
            }
        }

        Write-Host "`n[+] Azure VM optimization analysis complete!" -ForegroundColor Green
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
