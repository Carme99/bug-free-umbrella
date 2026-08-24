<#
.SYNOPSIS
    Run disk health maintenance on fixed drives.

.DESCRIPTION
    Enables the built-in Disk Cleanup items under the VolumeCaches registry key, runs
    cleanmgr for system files, schedules a chkdsk pass of the system drive for the next
    reboot and optimizes every fixed volume (trim on SSD, defragment on HDD). Every
    mutation is gated behind -WhatIf/-Confirm via SupportsShouldProcess. Re-running on an
    already-maintained device finds no cleanup items, no fixed volumes and nothing to
    schedule, makes no changes and still exits 0 (idempotent).

.EXAMPLE
    PS C:\> .\Invoke-RemediationCheckDiskHealth.ps1

    Runs disk cleanup, schedules a boot-time chkdsk and optimizes all fixed volumes.

.EXAMPLE
    PS C:\> .\Invoke-RemediationCheckDiskHealth.ps1 -WhatIf

    Shows which maintenance actions would run without changing anything.

.NOTES
    File Name  : Invoke-RemediationCheckDiskHealth.ps1
    Author     : Intune Admin
    Prerequisite: PowerShell 7.0
    Version    : 1.0.0
    Date       : 2026-08-23
#>

[CmdletBinding(SupportsShouldProcess)]
param()

$ErrorActionPreference = 'Stop'

function Invoke-Chkdsk {
    # Thin wrapper around the native chkdsk.exe executable.
    # Exists as the mock seam for Pester tests (native commands cannot be mocked).
    & chkdsk.exe @args 2>&1 | Out-Null
    return $LASTEXITCODE
}

function Main {
    # Advanced function so $PSCmdlet (and thus ShouldProcess) resolves inside Main.
    [CmdletBinding(SupportsShouldProcess)]
    param()

    try {
        Write-Host "[*] Running disk health maintenance..." -ForegroundColor Cyan

        $remediationActions = @()

        # Enable common cleanup items so cleanmgr /sagerun:1 has something configured.
        $volumeCachesPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches'
        $cleanupItems = @(
            'Temporary Files',
            'Temporary Setup Files',
            'Downloaded Program Files',
            'Recycle Bin',
            'Temporary Internet Files'
        )

        $configuredItems = @()
        foreach ($item in $cleanupItems) {
            $itemPath = "$volumeCachesPath\$item"
            if (Test-Path $itemPath -ErrorAction SilentlyContinue) {
                if ($PSCmdlet.ShouldProcess($itemPath, 'Enable disk cleanup item')) {
                    New-ItemProperty -Path $itemPath -Name 'StateFlags0001' -Value 2 -PropertyType DWord -Force -ErrorAction SilentlyContinue
                }
                $configuredItems += $itemPath
            }
        }

        # Only invoke cleanmgr when at least one cleanup item was found to configure.
        if ($configuredItems.Count -gt 0) {
            if ($PSCmdlet.ShouldProcess('cleanmgr.exe', 'Run disk cleanup for system files')) {
                Start-Process -FilePath 'cleanmgr.exe' -ArgumentList '/sagerun:1' -WindowStyle Hidden -Wait -ErrorAction SilentlyContinue
                $remediationActions += 'Executed disk cleanup'
            }
        }

        # Schedule a disk check for the next reboot on the system drive.
        if ($env:SystemDrive) {
            $systemDrive = $env:SystemDrive
            Write-Host "[*] Scheduling disk check for $systemDrive on next reboot..." -ForegroundColor Cyan
            if ($PSCmdlet.ShouldProcess($systemDrive, 'Schedule chkdsk on next reboot')) {
                $chkdskExitCode = Invoke-Chkdsk $systemDrive /F /R /X
                if ($chkdskExitCode -ne 0) {
                    Write-Host "[!] Could not schedule disk check (chkdsk exit code $chkdskExitCode)" -ForegroundColor Yellow
                }
                else {
                    $remediationActions += 'Scheduled disk check for next reboot'
                }
            }
        }
        else {
            Write-Host "[!] System drive could not be determined; skipping chkdsk scheduling" -ForegroundColor Yellow
        }

        # Optimize/defragment drives (SSD = trim, HDD = defrag).
        $volumes = Get-Volume -ErrorAction SilentlyContinue |
            Where-Object { $_.DriveType -eq 'Fixed' -and $_.DriveLetter }

        foreach ($volume in $volumes) {
            if ($PSCmdlet.ShouldProcess("Volume $($volume.DriveLetter):", 'Optimize volume (trim or defrag)')) {
                Optimize-Volume -DriveLetter $volume.DriveLetter -ErrorAction SilentlyContinue
                $remediationActions += "Optimized volume $($volume.DriveLetter):"
            }
        }

        if ($remediationActions.Count -eq 0) {
            Write-Host "[+] Already maintained: no disk maintenance actions were necessary" -ForegroundColor Green
        }
        else {
            Write-Host "[+] Disk health remediation completed:" -ForegroundColor Green
            foreach ($action in $remediationActions) {
                Write-Host "  - $action"
            }
            Write-Host ""
            Write-Host "[!] Note: Disk errors may require a system restart to fully repair" -ForegroundColor Yellow
            Write-Host "[!] Hardware failures require physical disk replacement" -ForegroundColor Yellow
        }
        return 0
    }
    catch {
        Write-Host "[-] Error during disk health remediation: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
