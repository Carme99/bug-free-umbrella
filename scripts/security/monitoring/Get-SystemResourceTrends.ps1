<#
.SYNOPSIS
    Samples current system resource utilization (CPU, memory, disk).
.DESCRIPTION
    Samples live performance counters to report current CPU, memory, and disk utilization.
.EXAMPLE
    .\Get-SystemResourceTrends.ps1 -ExportHTML
.NOTES
    Samples live performance counters for utilization reporting
#>
[CmdletBinding()]
param([switch]$ExportHTML)

Write-Host "`n=== System Resource Trends ===" -ForegroundColor Cyan

Write-Host "[*] Sampling performance data..." -ForegroundColor Cyan

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

Write-Host "`nSampling complete!`n" -ForegroundColor Green
