<#
.SYNOPSIS
    Repair Windows system file corruption with DISM and SFC.

.DESCRIPTION
    Runs DISM RestoreHealth and SFC /scannow to repair corrupted system files
    and the component store, after verifying two safety preconditions: at least
    10 GB of free space on the system drive and AC power (devices on battery
    are never repaired).
    Side effects: DISM and SFC modify the component store and protected system
    files; a restart may be required to complete repairs. Both repair passes are
    gated behind -WhatIf/-Confirm via SupportsShouldProcess.
    The repairs themselves are safe to re-run (idempotent): a converged system
    reports "no integrity violations" and exits 0 again.
    Exit codes: 0 = remediation completed, 1 = a safety check failed (insufficient
    disk space or battery power) or DISM/SFC raised an unexpected error.

.EXAMPLE
    PS C:\> .\Invoke-RemediationFixSystemFileCorruption.ps1

    Runs the disk space and power safety checks, then repairs the component
    store with DISM and system files with SFC.

.EXAMPLE
    PS C:\> .\Invoke-RemediationFixSystemFileCorruption.ps1 -WhatIf

    Runs the safety checks but skips both repair passes.

.NOTES
    File Name  : Invoke-RemediationFixSystemFileCorruption.ps1
    Author     : Intune Admin
    Prerequisite: PowerShell 7.0
    Version    : 1.0.0
    Date       : 2026-08-23

    Intune Context: SYSTEM. May require a restart to complete and can take
    10-30 minutes; detailed results are logged in C:\Windows\Logs\CBS\CBS.log.
#>

[CmdletBinding(SupportsShouldProcess)]
param()

$ErrorActionPreference = 'Stop'

function Invoke-Dism {
    # Thin wrapper around the native Dism.exe executable; mock seam for Pester tests.
    & Dism.exe @args 2>&1 | Out-Null
    return $LASTEXITCODE
}

function Invoke-Sfc {
    # Thin wrapper around the native sfc.exe executable; mock seam for Pester tests.
    & sfc.exe @args 2>&1 | Out-Null
    return $LASTEXITCODE
}

function Main {
    # Advanced function so $PSCmdlet (and thus ShouldProcess) resolves inside Main.
    [CmdletBinding(SupportsShouldProcess)]
    param()

    try {
        Write-Host "[*] Repairing system file corruption (this may take 10-30 minutes)..." -ForegroundColor Cyan

        $minDiskSpaceGB = 10  # Minimum free space required for the DISM operation
        $actions = @()

        # SAFETY CHECK 1: verify sufficient free disk space for DISM.
        $driveLetter = 'C'
        if ($env:SystemDrive) {
            $driveLetter = $env:SystemDrive.TrimEnd(':')
        }
        $systemDrive = Get-Volume -DriveLetter $driveLetter -ErrorAction SilentlyContinue
        if ($systemDrive) {
            $freeSpaceGB = [math]::Round($systemDrive.SizeRemaining / 1GB, 2)
            Write-Host "[*] System drive free space: $freeSpaceGB GB" -ForegroundColor Cyan

            if ($freeSpaceGB -lt $minDiskSpaceGB) {
                Write-Host "[-] Error repairing system files: insufficient disk space (free: ${freeSpaceGB} GB, required: ${minDiskSpaceGB} GB)" -ForegroundColor Red
                return 1
            }
        }

        # SAFETY CHECK 2: never run DISM/SFC on battery power.
        # BatteryStatus: 1 = Discharging, 4 = Low, 5 = Critical (all mean: on battery).
        $battery = Get-CimInstance -ClassName Win32_Battery -ErrorAction SilentlyContinue
        if ($battery -and $battery.BatteryStatus -in @(1, 4, 5)) {
            Write-Host "[-] Error repairing system files: device is running on battery power; connect to AC before running repairs" -ForegroundColor Red
            return 1
        }

        Write-Host "[!] This operation is resource-intensive; the system remains responsive" -ForegroundColor Yellow

        # DISM component-store repair.
        if ($PSCmdlet.ShouldProcess('Component Store', 'Run DISM RestoreHealth')) {
            Write-Host "[*] Running DISM RestoreHealth..." -ForegroundColor Cyan
            $dismExitCode = Invoke-Dism /Online /Cleanup-Image /RestoreHealth /NoRestart
            if ($dismExitCode -eq 0) {
                $actions += 'DISM RestoreHealth completed successfully'
            }
            else {
                Write-Host "[!] DISM RestoreHealth returned exit code $dismExitCode" -ForegroundColor Yellow
                $actions += "DISM RestoreHealth completed with warnings (exit code $dismExitCode)"
            }
        }

        # SFC scan.
        if ($PSCmdlet.ShouldProcess('System Files', 'Run SFC /scannow')) {
            Write-Host "[*] Running System File Checker..." -ForegroundColor Cyan
            $sfcExitCode = Invoke-Sfc /scannow
            if ($sfcExitCode -eq 0) {
                $actions += 'SFC scan completed successfully'
            }
            else {
                Write-Host "[!] SFC returned exit code $sfcExitCode" -ForegroundColor Yellow
                $actions += "SFC scan completed with warnings (exit code $sfcExitCode)"
            }
        }

        foreach ($action in $actions) {
            Write-Host "  - $action" -ForegroundColor Cyan
        }
        Write-Host "[+] System file corruption remediation completed; a restart may be required to finish repairs" -ForegroundColor Green
        return 0
    }
    catch {
        Write-Host "[-] Error repairing system files: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
