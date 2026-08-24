<#
.SYNOPSIS
    Samples current system resource utilization (CPU, memory, disk).

.DESCRIPTION
    Samples live performance counters to report current CPU, memory, and disk utilization. Each counter is read
    over a rolling window of 12 samples at 5-second intervals, and the average is printed to the console.
    Side effects: none; this is a read-only detector and is safe to re-run at any frequency.
    Exit codes: 0 on success; 1 on fatal error (for example, when performance counters are unavailable).

.PARAMETER ExportHTML
    Reserved for future HTML export; the current release reports sampled averages to the console only.

.EXAMPLE
    PS C:\> .\Get-SystemResourceTrends.ps1
    Samples CPU, memory, and disk utilization and prints the averages to the console.

.EXAMPLE
    PS C:\> .\Get-SystemResourceTrends.ps1 -ExportHTML
    Runs the same sampling pass; HTML export is reserved and results remain console-only.

.NOTES
    File Name   : Get-SystemResourceTrends.ps1
    Author      : Bug-Free Umbrella
    Prerequisite: PowerShell 5.1+
    Version     : 1.0.0
    Date        : 2026-08-23
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $false)]
    [switch]$ExportHTML   # reserved no-op switch; PSSA PSReviewUnusedParameter accepted
)

$ErrorActionPreference = 'Stop'

# PSSA note: Write-Host is mandated here for colorized [+]/[!]/[-]/[*] console status prefixes
# (RELAUNCH-SPEC section 3); PSAvoidUsingWriteHost warnings are accepted by design.

function Main {
    [CmdletBinding()]
    param(
        [switch]$ExportHTML
    )

    try {
        Write-Host "`n=== System Resource Trends ===" -ForegroundColor Cyan

        Write-Host "[*] Sampling performance data..." -ForegroundColor Cyan

        # CPU trend
        $cpuCounters = Get-Counter "\Processor(_Total)\% Processor Time" `
            -SampleInterval 5 -MaxSamples 12 -ErrorAction Stop
        $avgCPU = ($cpuCounters.CounterSamples.CookedValue | Measure-Object -Average).Average
        Write-Host "[+] Average CPU: $([math]::Round($avgCPU, 2))%" -ForegroundColor Green

        # Memory trend
        $memCounters = Get-Counter "\Memory\% Committed Bytes In Use" -SampleInterval 5 -MaxSamples 12 -ErrorAction Stop
        $avgMem = ($memCounters.CounterSamples.CookedValue | Measure-Object -Average).Average
        Write-Host "[+] Average Memory: $([math]::Round($avgMem, 2))%" -ForegroundColor Green

        # Disk trend
        $diskCounters = Get-Counter "\PhysicalDisk(_Total)\% Idle Time" `
            -SampleInterval 5 -MaxSamples 12 -ErrorAction Stop
        $avgDisk = ($diskCounters.CounterSamples.CookedValue | Measure-Object -Average).Average
        Write-Host "[+] Average Disk Idle: $([math]::Round($avgDisk, 2))%" -ForegroundColor Green

        Write-Host "[+] Sampling complete!" -ForegroundColor Green

        return 0
    }
    catch {
        Write-Host "[-] Error sampling system resources: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main @PSBoundParameters) }
