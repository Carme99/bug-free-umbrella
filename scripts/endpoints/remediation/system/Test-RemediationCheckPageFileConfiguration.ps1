<#
.SYNOPSIS
    Check that the page file is present and sensibly configured.

.DESCRIPTION
    Verifies that the page file is properly configured (not disabled) and, for
    explicitly custom-configured page files, that the initial size is not below
    a configurable floor.

    Current guidance: page file sizing depends on the system crash dump setting
    and the peak system commit charge, and "can't be generalized" - a fixed
    "1.5x RAM" rule is a legacy rule of thumb that false-positives intentional
    custom configurations. System-managed page files are always considered
    compliant; custom page files are only flagged when their initial size is
    below the -MinRatio floor (default 1.0x RAM).

    Exit codes: 0 = page file properly configured, 1 = issues detected (or an
    unexpected error occurred). The script changes no system state, so it is
    safe to re-run at any time (idempotent).
    Intune Context: SYSTEM.

    See https://learn.microsoft.com/en-us/troubleshoot/windows-client/performance/how-to-determine-the-appropriate-page-file-size-for-64-bit-versions-of-windows

.PARAMETER MinRatio
    Minimum initial size of a custom-configured page file, as a ratio of
    physical RAM (default: 1.0). Only applies to explicitly custom page files.

.EXAMPLE
    PS C:\> .\Test-RemediationCheckPageFileConfiguration.ps1

    Exits 0 when the page file is properly configured; exits 1 when it is
    disabled or undersized relative to physical RAM.

.EXAMPLE
    PS C:\> .\Test-RemediationCheckPageFileConfiguration.ps1 -MinRatio 1.5

    Applies the stricter legacy rule of thumb: flags custom page files whose
    initial size is below 1.5x physical RAM.

.NOTES
    File Name  : Test-RemediationCheckPageFileConfiguration.ps1
    Author     : Intune Admin
    Prerequisite: PowerShell 7.0
    Version    : 1.0.0
    Date       : 2026-08-23
#>

[CmdletBinding()]
param(
    [double]$MinRatio = 1.0
)

$ErrorActionPreference = 'Stop'

function Main {
    try {
        $issues = @()
        $notes = @()

        Write-Host "[*] Checking page file configuration..." -ForegroundColor Cyan

        # Get page file configuration
        $pageFile = Get-CimInstance -ClassName Win32_PageFileSetting -ErrorAction SilentlyContinue

        if (-not $pageFile) {
            # Check if page file is system-managed
            $compSys = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
            if ($compSys.AutomaticManagedPagefile -eq $false) {
                $issues += "Page file is disabled (not recommended)"
            }
        }
        else {
            # Explicitly configured (custom) page file - report as informational;
            # only flag when the initial size is below the configurable ratio.
            $compSys = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
            $totalRAM = $compSys.TotalPhysicalMemory / 1GB
            $recommendedMin = [math]::Ceiling($totalRAM * $MinRatio) * 1024  # Convert to MB

            foreach ($pf in $pageFile) {
                $initialSize = $pf.InitialSize
                $maximumSize = $pf.MaximumSize

                $notes += "Custom page file configured (initial $initialSize MB, maximum $maximumSize MB) - sizing can't be generalized, informational only"

                if ($initialSize -lt $recommendedMin) {
                    $issues += "Custom page file initial size ($initialSize MB) is below the configured minimum ($recommendedMin MB at ${MinRatio}x RAM)"
                }
            }
        }

        # Check for page file on system drive
        $systemDrive = $env:SystemDrive
        $pageFileExists = Test-Path "$systemDrive\pagefile.sys" -ErrorAction SilentlyContinue

        if (-not $pageFileExists) {
            $compSys = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
            if ($compSys.AutomaticManagedPagefile -eq $false) {
                $issues += "Page file not found on system drive"
            }
        }

        if ($issues.Count -gt 0) {
            Write-Host "[!] Page file configuration issues:" -ForegroundColor Yellow
            foreach ($issue in $issues) {
                Write-Host "[!]   - $issue" -ForegroundColor Yellow
            }
            return 1
        }

        foreach ($note in $notes) {
            Write-Host "[*]   - $note" -ForegroundColor Cyan
        }

        Write-Host "[+] Page file is properly configured" -ForegroundColor Green
        return 0
    }
    catch {
        Write-Host "[-] Error checking page file configuration: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
