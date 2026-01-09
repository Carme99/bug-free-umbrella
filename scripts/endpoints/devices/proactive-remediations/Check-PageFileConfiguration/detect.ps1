<#
.SYNOPSIS
    Checks page file configuration.

.DESCRIPTION
    Verifies that page file is properly configured (not disabled) and
    sized appropriately for system memory.

.NOTES
    Author: Intune Admin
    Version: 1.0
    Intune Context: SYSTEM
    Exit 0: Page file properly configured
    Exit 1: Issues detected
#>

try {
    $issues = @()

    # Get page file configuration
    $pageFile = Get-WmiObject -Class Win32_PageFileSetting -ErrorAction SilentlyContinue

    if (-not $pageFile) {
        # Check if page file is system-managed
        $compSys = Get-WmiObject -Class Win32_ComputerSystem
        if ($compSys.AutomaticManagedPagefile -eq $false) {
            $issues += "Page file is disabled (not recommended)"
        }
    } else {
        # Check page file size
        $totalRAM = (Get-WmiObject -Class Win32_ComputerSystem).TotalPhysicalMemory / 1GB

        foreach ($pf in $pageFile) {
            $initialSize = $pf.InitialSize
            $maximumSize = $pf.MaximumSize

            # Page file should be at least 1.5x RAM (minimum recommendation)
            $recommendedMin = [math]::Ceiling($totalRAM * 1.5) * 1024  # Convert to MB

            if ($initialSize -lt $recommendedMin) {
                $issues += "Page file initial size ($initialSize MB) is smaller than recommended ($recommendedMin MB)"
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

    Write-Host "Page file is properly configured"
    exit 0

} catch {
    Write-Host "Error checking page file configuration: $_"
    exit 1
}
