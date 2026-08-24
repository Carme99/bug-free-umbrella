<#
.SYNOPSIS
    Detects low free disk space on fixed drives.

.DESCRIPTION
    Checks all fixed disk volumes for low disk space conditions and reports every volume that has
    less than 10 percent free space or less than 10 GB free space remaining.
    Intended for Intune Proactive Remediations.
    Exit codes:
    - 0: compliant - every fixed volume meets both free-space thresholds.
    - 1: non-compliant - at least one fixed volume is below a threshold, or the check failed.

.NOTES
    File Name: Test-RemediationFixDiskSpace.ps1
    Author: Bug-Free Umbrella
    Prerequisite: PowerShell 7.0
    Version: 1.0.0
    Date: 2026-08-23

.EXAMPLE
    PS C:\> .\Test-RemediationFixDiskSpace.ps1
    Lists any low-space volumes and returns 0 when healthy, 1 when remediation is needed.

.EXAMPLE
    PS C:\> pwsh -NoProfile -File .\Test-RemediationFixDiskSpace.ps1
    Runs the same detection under the Intune Management Extension SYSTEM context.
#>

[CmdletBinding()]

$ErrorActionPreference = 'Stop'

#region Configuration
$MinFreePercent = 10   # Minimum acceptable free space percentage
$MinFreeGb = 10        # Minimum acceptable free space in GB
#endregion

#region Functions

function Main {
    try {
        $outputMsg = "[*] Checking fixed drive free space..."
        Write-Host $outputMsg -ForegroundColor Cyan

        $volumes = Get-Volume -ErrorAction Stop | Where-Object { $_.DriveLetter -and $_.DriveType -eq 'Fixed' }
        $issues = @()

        foreach ($vol in $volumes) {
            $freePercent = ($vol.SizeRemaining / $vol.Size) * 100
            $freeGb = [math]::Round($vol.SizeRemaining / 1GB, 2)

            if ($freePercent -lt $MinFreePercent -or $freeGb -lt $MinFreeGb) {
                $issues += "$($vol.DriveLetter): $freeGb GB free ($([math]::Round($freePercent, 1))%)"
            }
        }

        if ($issues.Count -gt 0) {
            $outputMsg = "[!] Low disk space detected: $($issues -join ', ')"
            Write-Host $outputMsg -ForegroundColor Yellow
            return 1
        }

        $outputMsg = "[+] Disk space healthy."

        Write-Host $outputMsg -ForegroundColor Green
        return 0
    }
    catch {
        $outputMsg = "[-] Error checking disk space: $($_.Exception.Message)"
        Write-Host $outputMsg -ForegroundColor Red
        return 1
    }
}
#endregion

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
