<#
.SYNOPSIS
    Detects Windows Store app licensing issues.

.DESCRIPTION
    Checks for Windows Store licensing problems that can prevent apps from launching or
    updating properly: it verifies the Client License Service (ClipSVC) exists and is running,
    verifies the Windows Update service is not disabled, checks the ClipSVC tokens.dat cache
    is not empty, and confirms the Microsoft Store app package is registered. This is a
    read-only detection script: it changes nothing, so re-running it is safe (idempotent).
    Exit codes:
    - 0: healthy - Store licensing appears healthy.
    - 1: non-compliant - licensing issues detected, or the check failed.

.EXAMPLE
    PS C:\> .\Test-RemediationFixWindowsStoreLicensing.ps1
    Checks Store services, license cache and app registration; exits 0 when healthy.

.EXAMPLE
    PS C:\> & 'C:\Program Files\Intune\ProactiveRemediations\Test-RemediationFixWindowsStoreLicensing.ps1'
    Runs the same check from the Intune Management Extension under the SYSTEM context.

.NOTES
    File Name: Test-RemediationFixWindowsStoreLicensing.ps1
    Author: Intune Admin
    Prerequisite: PowerShell 7.0
    Version: 1.0.0
    Date: 2026-08-23
#>

[CmdletBinding()]

$ErrorActionPreference = 'Stop'

#region Functions

function Main {
    try {
        $outputMsg = "[*] Checking Windows Store licensing..."
        Write-Host $outputMsg -ForegroundColor Cyan

        $issues = @()

        # Check if Windows Store service is running.
        $storeService = Get-Service -Name "ClipSVC" -ErrorAction SilentlyContinue  # Client License Service

        if ($storeService) {
            if ($storeService.Status -ne "Running") {
                $issues += "Client License Service (ClipSVC) is not running"
            }
        }
        else {
            $issues += "Client License Service (ClipSVC) is not found"
        }

        # Check Windows Update service (required for Store).
        $wuService = Get-Service -Name "wuauserv" -ErrorAction SilentlyContinue

        if ($wuService) {
            if ($wuService.Status -ne "Running" -and $wuService.StartType -eq "Disabled") {
                $issues += "Windows Update service is disabled (required for Store)"
            }
        }

        # Check for licensing cache corruption.
        $licensingPath = "$env:ProgramData\Microsoft\Windows\ClipSVC\tokens.dat"

        if (Test-Path $licensingPath) {
            $fileInfo = Get-Item $licensingPath -ErrorAction SilentlyContinue
            if ($fileInfo.Length -eq 0) {
                $issues += "Store licensing cache is empty or corrupted"
            }
        }

        # Check if Store app is registered.
        $storeApp = Get-AppxPackage -Name "Microsoft.WindowsStore" -AllUsers -ErrorAction SilentlyContinue

        if (-not $storeApp) {
            $issues += "Microsoft Store app is not installed or registered"
        }

        if ($issues.Count -gt 0) {
            $outputMsg = "[!] Windows Store licensing issues detected:"
            Write-Host $outputMsg -ForegroundColor Yellow
            foreach ($issue in $issues) {
                $outputMsg = "[!]   - $issue"
                Write-Host $outputMsg -ForegroundColor Yellow
            }
            return 1
        }

        $outputMsg = "[+] Windows Store licensing appears healthy"

        Write-Host $outputMsg -ForegroundColor Green
        return 0
    }
    catch {
        $outputMsg = "[-] Error checking Windows Store licensing: $($_.Exception.Message)"
        Write-Host $outputMsg -ForegroundColor Red
        return 1
    }
}

#endregion

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
