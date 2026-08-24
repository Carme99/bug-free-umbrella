<#
.SYNOPSIS
    Check the system for memory errors and failing RAM indicators.

.DESCRIPTION
    Scans the System event log for memory diagnostic errors, bad memory pages
    (Kernel-General event 19) and unexpected reboots (Kernel-Power event 41)
    that could indicate failing RAM, and queries the status of every physical
    memory module via Win32_PhysicalMemory.
    Exit codes: 0 = no memory errors detected, 1 = memory errors found (or an
    unexpected error occurred). The script changes no system state, so it is
    safe to re-run at any time (idempotent).
    Intune Context: SYSTEM.

.EXAMPLE
    PS C:\> .\Test-RemediationCheckMemoryDiagnostics.ps1

    Exits 0 when no memory errors are detected; exits 1 when memory issues are
    found.

.EXAMPLE
    PS C:\> .\Test-RemediationCheckMemoryDiagnostics.ps1 -Verbose

    Runs the same memory diagnostics check with verbose progress information.

.NOTES
    File Name  : Test-RemediationCheckMemoryDiagnostics.ps1
    Author     : Intune Admin
    Prerequisite: PowerShell 7.0
    Version    : 1.0.0
    Date       : 2026-08-23
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

function Main {
    try {
        $issues = @()

        Write-Host "[*] Checking for memory errors..." -ForegroundColor Cyan

        # Check for memory errors in System event log
        $memoryErrors = Get-WinEvent -FilterHashtable @{
            LogName      = 'System'
            ProviderName = 'Microsoft-Windows-MemoryDiagnostics-Results'
            Level        = 2, 3  # Error and Warning
            StartTime    = (Get-Date).AddDays(-30)
        } -MaxEvents 10 -ErrorAction SilentlyContinue

        if ($memoryErrors) {
            $issues += "Found $($memoryErrors.Count) memory diagnostic errors in last 30 days"
        }

        # Check for hardware errors (Event ID 19 - Bad memory page)
        $hardwareErrors = Get-WinEvent -FilterHashtable @{
            LogName      = 'System'
            ProviderName = 'Microsoft-Windows-Kernel-General'
            ID           = 19
            StartTime    = (Get-Date).AddDays(-30)
        } -MaxEvents 10 -ErrorAction SilentlyContinue

        if ($hardwareErrors) {
            $issues += "Bad memory pages detected (potential RAM failure)"
        }

        # Check for unexpected reboots that could be memory-related
        $unexpectedReboots = Get-WinEvent -FilterHashtable @{
            LogName      = 'System'
            ProviderName = 'Microsoft-Windows-Kernel-Power'
            ID           = 41  # System rebooted without cleanly shutting down
            StartTime    = (Get-Date).AddDays(-7)
        } -MaxEvents 5 -ErrorAction SilentlyContinue

        if ($unexpectedReboots) {
            $issues += "Unexpected system reboots detected (may be memory-related)"
        }

        # Check physical memory status using WMI
        $memoryDevices = Get-CimInstance -ClassName Win32_PhysicalMemory -ErrorAction SilentlyContinue
        foreach ($mem in $memoryDevices) {
            if ($mem.Status -ne "OK") {
                $issues += "Memory module $($mem.DeviceLocator) status: $($mem.Status)"
            }
        }

        if ($issues.Count -gt 0) {
            Write-Host "[!] Memory diagnostic issues detected:" -ForegroundColor Yellow
            foreach ($issue in $issues) {
                Write-Host "[!]   - $issue" -ForegroundColor Yellow
            }
            return 1
        }

        Write-Host "[+] No memory errors detected" -ForegroundColor Green
        return 0
    }
    catch {
        Write-Host "[-] Error checking memory diagnostics: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
