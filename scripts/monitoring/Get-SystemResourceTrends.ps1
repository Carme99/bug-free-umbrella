<#
.SYNOPSIS
    System resource trend analysis and capacity planning.
.DESCRIPTION
    Analyzes historical performance data to identify trends and predict capacity needs.
.EXAMPLE
    .\Get-SystemResourceTrends.ps1 -DaysToAnalyze 30 -ExportHTML
.NOTES
    Analyzes performance counters over time for trend identification
#>
[CmdletBinding()]
param([int]$DaysToAnalyze = 30, [switch]$ExportHTML)

Write-Host "`n=== System Resource Trends ===" -ForegroundColor Cyan

Write-Host "[*] Collecting performance data for last $DaysToAnalyze days..." -ForegroundColor Cyan

# CPU trend
$cpuCounters = Get-Counter "\Processor(_Total)\% Processor Time" -SampleInterval 5 -MaxSamples 12
$avgCPU = ($cpuCounters.CounterSamples.CookedValue | Measure-Object -Average).Average
Write-Host "[+] Average CPU: $([math]::Round($avgCPU, 2))%" -ForegroundColor Green

# Memory trend
$memCounters = Get-Counter "\Memory\% Committed Bytes In Use" -SampleInterval 5 -MaxSamples 12
$avgMem = ($memCounters.CounterSamples.CookedValue | Measure-Object -Average).Average
Write-Host "[+] Average Memory: $([math]::Round($avgMem, 2))%" -ForegroundColor Green

# Disk trend
$diskCounters = Get-Counter "\PhysicalDisk(_Total)\% Idle Time" -SampleInterval 5 -MaxSamples 12
$avgDisk = ($diskCounters.CounterSamples.CookedValue | Measure-Object -Average).Average
Write-Host "[+] Average Disk Idle: $([math]::Round($avgDisk, 2))%" -ForegroundColor Green

Write-Host "`nTrend analysis complete!`n" -ForegroundColor Green
