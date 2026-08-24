<#
.SYNOPSIS
    Detects bloated Windows Event Logs.

.DESCRIPTION
    Enumerates all event logs and flags every log whose on-disk file has grown beyond the
    configured size threshold (default 100 MB), which consumes excessive disk space.
    Exit codes:
    - 0: healthy - all event logs are within the configured size threshold.
    - 1: non-compliant - bloated logs detected, or the check failed.

.NOTES
    File Name: Test-RemediationFixEventLogSize.ps1
    Author: Intune Admin
    Prerequisite: PowerShell 7.0
    Version: 1.0.0
    Date: 2026-08-23

.EXAMPLE
    PS C:\> .\Test-RemediationFixEventLogSize.ps1
    Lists any event logs over the size threshold and returns 0 when healthy, 1 when bloated.

.EXAMPLE
    PS C:\> pwsh -NoProfile -File .\Test-RemediationFixEventLogSize.ps1
    Runs the same detection under the Intune Management Extension SYSTEM context.
#>

[CmdletBinding()]

$ErrorActionPreference = 'Stop'

#region Configuration
$MaxLogSizeMb = 100   # Maximum log size in MB before remediation
#endregion

#region Functions

function Main {
    try {
        $outputMsg = "[*] Checking Windows Event Log sizes..."
        Write-Host $outputMsg -ForegroundColor Cyan

        $maxLogSizeBytes = $MaxLogSizeMb * 1MB
        $bloatedLogs = @()

        # Get all event logs
        $eventLogs = Get-WinEvent -ListLog * -ErrorAction SilentlyContinue

        foreach ($log in $eventLogs) {
            if ($log.FileSize -gt $maxLogSizeBytes) {
                $bloatedLogs += [PSCustomObject]@{
                    LogName = $log.LogName
                    SizeMb  = [math]::Round($log.FileSize / 1MB, 2)
                }
            }
        }

        if ($bloatedLogs.Count -gt 0) {
            $outputMsg = "[!] Bloated event logs detected (over $MaxLogSizeMb MB):"
            Write-Host $outputMsg -ForegroundColor Yellow
            foreach ($log in $bloatedLogs) {
                Write-Host "- $($log.LogName): $($log.SizeMb) MB"
            }
            return 1
        }

        $outputMsg = "[+] Event log sizes are within normal limits."

        Write-Host $outputMsg -ForegroundColor Green
        return 0
    }
    catch {
        $outputMsg = "[-] Error checking event log sizes: $($_.Exception.Message)"
        Write-Host $outputMsg -ForegroundColor Red
        return 1
    }
}
#endregion

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
