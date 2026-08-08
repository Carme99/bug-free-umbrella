<#
.SYNOPSIS
    Checks page file configuration.

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

    See https://learn.microsoft.com/en-us/troubleshoot/windows-client/performance/how-to-determine-the-appropriate-page-file-size-for-64-bit-versions-of-windows

.NOTES
    Author: Intune Admin
    Version: 1.1
    Intune Context: SYSTEM
    Exit 0: Page file properly configured
    Exit 1: Issues detected

.PARAMETER MinRatio
    Minimum initial size of a custom-configured page file, as a ratio of
    physical RAM (default: 1.0). Only applies to explicitly custom page files.
#>

param(
    [double]$MinRatio = 1.0
)

try {
    $issues = @()
    $notes = @()

    # Get page file configuration
    $pageFile = Get-WmiObject -Class Win32_PageFileSetting -ErrorAction SilentlyContinue

    if (-not $pageFile) {
        # Check if page file is system-managed
        $compSys = Get-WmiObject -Class Win32_ComputerSystem
        if ($compSys.AutomaticManagedPagefile -eq $false) {
            $issues += "Page file is disabled (not recommended)"
        }
    } else {
        # Explicitly configured (custom) page file - report as informational;
        # only flag when the initial size is below the configurable ratio.
        $totalRAM = (Get-WmiObject -Class Win32_ComputerSystem).TotalPhysicalMemory / 1GB
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
        $compSys = Get-WmiObject -Class Win32_ComputerSystem
        if ($compSys.AutomaticManagedPagefile -eq $false) {
            $issues += "Page file not found on system drive"
        }
    }

    if ($issues.Count -gt 0) {
        Write-Host "Page file configuration issues:"
        foreach ($issue in $issues) {
            Write-Host "  - $issue"
        }
        exit 1
    }

    foreach ($note in $notes) {
        Write-Host "  - $note"
    }

    Write-Host "Page file is properly configured"
    exit 0

} catch {
    Write-Host "Error checking page file configuration: $_"
    exit 1
}
