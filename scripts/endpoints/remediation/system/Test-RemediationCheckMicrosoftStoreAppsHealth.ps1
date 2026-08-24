<#
.SYNOPSIS
    Check Microsoft Store apps for registration and installation issues.

.DESCRIPTION
    Enumerates all AppX packages for all users and flags packages that are in a
    non-OK state, verifies that the Microsoft Store app itself is installed and
    healthy, and checks a set of common critical inbox apps (Calculator, Camera,
    People) for error states.
    Exit codes: 0 = Store apps are healthy, 1 = issues detected (or an unexpected
    error occurred). The script changes no system state, so it is safe to re-run
    at any time (idempotent).
    Intune Context: SYSTEM.

.EXAMPLE
    PS C:\> .\Test-RemediationCheckMicrosoftStoreAppsHealth.ps1

    Exits 0 when the Store apps are healthy; exits 1 when AppX package issues are
    detected.

.EXAMPLE
    PS C:\> .\Test-RemediationCheckMicrosoftStoreAppsHealth.ps1 -Verbose

    Runs the same Store app health check with verbose progress information.

.NOTES
    File Name  : Test-RemediationCheckMicrosoftStoreAppsHealth.ps1
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

        Write-Host "[*] Checking Microsoft Store app health..." -ForegroundColor Cyan

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
            Write-Host "[!] Microsoft Store apps issues detected:" -ForegroundColor Yellow
            foreach ($issue in $issues) {
                Write-Host "[!]   - $issue" -ForegroundColor Yellow
            }
            return 1
        }

        Write-Host "[+] Microsoft Store apps are healthy" -ForegroundColor Green
        return 0
    }
    catch {
        Write-Host "[-] Error checking Store apps health: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
