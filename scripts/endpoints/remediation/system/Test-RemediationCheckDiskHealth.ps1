<#
.SYNOPSIS
    Check disk health via SMART status, reliability counters and free space.

.DESCRIPTION
    Inspects the health and operational status of every physical disk via the
    Storage module, reads storage reliability counters (read/write errors) for
    SSD and HDD media and checks every fixed volume for critically low free
    space (<5%) so failing or full disks are caught before data loss occurs.
    Exit codes: 0 = disks are healthy, 1 = disk health issues detected (or an
    unexpected error occurred). The script is read-only, changes no system state
    and is therefore idempotent.

.EXAMPLE
    PS C:\> .\Test-RemediationCheckDiskHealth.ps1

    Exits 0 when all disks are healthy; exits 1 when disk health issues are detected.

.EXAMPLE
    PS C:\> .\Test-RemediationCheckDiskHealth.ps1 -Verbose

    Runs the same analysis with verbose progress information.

.NOTES
    File Name  : Test-RemediationCheckDiskHealth.ps1
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

        Write-Host "[*] Checking disk health..." -ForegroundColor Cyan

        # Get all physical disks
        $physicalDisks = Get-PhysicalDisk -ErrorAction SilentlyContinue

        foreach ($disk in $physicalDisks) {
            # Check health status
            if ($disk.HealthStatus -ne "Healthy") {
                $issues += "Disk $($disk.FriendlyName): Health status is $($disk.HealthStatus)"
            }

            # Check operational status
            if ($disk.OperationalStatus -ne "OK") {
                $issues += "Disk $($disk.FriendlyName): Operational status is $($disk.OperationalStatus)"
            }

            # Check for predictive failure
            if ($disk.MediaType -eq "SSD" -or $disk.MediaType -eq "HDD") {
                $reliability = Get-StorageReliabilityCounter -PhysicalDisk $disk -ErrorAction SilentlyContinue
                if ($reliability) {
                    if ($reliability.ReadErrorsTotal -gt 0) {
                        $issues += "Disk $($disk.FriendlyName): $($reliability.ReadErrorsTotal) read errors detected"
                    }
                    if ($reliability.WriteErrorsTotal -gt 0) {
                        $issues += "Disk $($disk.FriendlyName): $($reliability.WriteErrorsTotal) write errors detected"
                    }
                }
            }
        }

        # Check disk usage and fragmentation
        $volumes = Get-Volume -ErrorAction SilentlyContinue | Where-Object { $_.DriveType -eq "Fixed" }

        foreach ($volume in $volumes) {
            # Check for critically low disk space (less than 5%)
            if ($volume.Size -gt 0) {
                $freePercentage = ($volume.SizeRemaining / $volume.Size) * 100
                if ($freePercentage -lt 5) {
                    $issues += "Volume $($volume.DriveLetter): Critically low disk space ($([math]::Round($freePercentage, 2))% free)"
                }
            }
        }

        if ($issues.Count -gt 0) {
            Write-Host "[!] Disk health issues detected:" -ForegroundColor Yellow
            foreach ($issue in $issues) {
                Write-Host "[!]   - $issue" -ForegroundColor Yellow
            }
            return 1
        }

        Write-Host "[+] All disks are healthy" -ForegroundColor Green
        return 0
    }
    catch {
        Write-Host "[-] Error checking disk health: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
