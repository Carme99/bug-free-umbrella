<#
.SYNOPSIS
    Detects Microsoft Store apps registration issues.

.DESCRIPTION
    Checks for AppX packages that are registered but not properly installed
    or have registration errors.

.NOTES
    Author: Intune Admin
    Version: 1.0
    Intune Context: SYSTEM
    Exit 0: Store apps are healthy
    Exit 1: Issues detected
#>

try {
    $issues = @()

    # Get all AppX packages for all users
    $appxPackages = Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue

    # Check for packages in error state
    $errorPackages = $appxPackages | Where-Object { $_.Status -ne "Ok" }

    if ($errorPackages) {
        $issues += "Found $($errorPackages.Count) AppX packages with errors"
    }

    # Check for Store app specifically
    $storeApp = Get-AppxPackage -Name "Microsoft.WindowsStore" -AllUsers -ErrorAction SilentlyContinue

    if (-not $storeApp) {
        $issues += "Microsoft Store app is not installed"
    }
    elseif ($storeApp.Status -ne "Ok") {
        $issues += "Microsoft Store app is in error state: $($storeApp.Status)"
    }

    # Check for common critical apps
    $criticalApps = @(
        "Microsoft.WindowsCalculator",
        "Microsoft.WindowsCamera",
        "Microsoft.People"
    )

    foreach ($appName in $criticalApps) {
        $app = Get-AppxPackage -Name $appName -AllUsers -ErrorAction SilentlyContinue
        if ($app -and $app.Status -ne "Ok") {
            $issues += "$appName is in error state"
        }
    }

    if ($issues.Count -gt 0) {
        Write-Host "Microsoft Store apps issues detected:"
        foreach ($issue in $issues) {
            Write-Host "  - $issue"
        }
        exit 1
    }

    Write-Host "Microsoft Store apps are healthy"
    exit 0

}
catch {
    Write-Host "Error checking Store apps health: $_"
    exit 1
}
