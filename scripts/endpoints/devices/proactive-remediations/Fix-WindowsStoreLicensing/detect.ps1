<#
.SYNOPSIS
    Detects Windows Store app licensing issues.

.DESCRIPTION
    Checks for Windows Store licensing problems that can prevent apps from
    launching or updating properly.

.NOTES
    Author: Intune Admin
    Version: 1.0
    Intune Context: SYSTEM
    Exit 0: Store licensing is healthy
    Exit 1: Licensing issues detected
#>

try {
    $issues = @()

    # Check if Windows Store service is running
    $storeService = Get-Service -Name "ClipSVC" -ErrorAction SilentlyContinue  # Client License Service

    if ($storeService) {
        if ($storeService.Status -ne "Running") {
            $issues += "Client License Service (ClipSVC) is not running"
        }
    } else {
        $issues += "Client License Service (ClipSVC) is not found"
    }

    # Check Windows Update service (required for Store)
    $wuService = Get-Service -Name "wuauserv" -ErrorAction SilentlyContinue

    if ($wuService) {
        if ($wuService.Status -ne "Running" -and $wuService.StartType -eq "Disabled") {
            $issues += "Windows Update service is disabled (required for Store)"
        }
    }

    # Check for licensing cache corruption
    $licensingPath = "$env:ProgramData\Microsoft\Windows\ClipSVC\tokens.dat"

    if (Test-Path $licensingPath) {
        $fileInfo = Get-Item $licensingPath -ErrorAction SilentlyContinue
        if ($fileInfo.Length -eq 0) {
            $issues += "Store licensing cache is empty or corrupted"
        }
    }

    # Check if Store app is registered
    $storeApp = Get-AppxPackage -Name "Microsoft.WindowsStore" -AllUsers -ErrorAction SilentlyContinue

    if (-not $storeApp) {
        $issues += "Microsoft Store app is not installed or registered"
    }

    if ($issues.Count -gt 0) {
        Write-Host "Windows Store licensing issues detected:"
        foreach ($issue in $issues) {
            Write-Host "  - $issue"
        }
        exit 1
    }

    Write-Host "Windows Store licensing appears healthy"
    exit 0

} catch {
    Write-Host "Error checking Windows Store licensing: $_"
    exit 1
}
