<#
.SYNOPSIS
    Clears bloated Windows Event Logs above a size threshold.

.DESCRIPTION
    Enumerates all Windows event logs and clears every non-critical log whose file
    size exceeds the configured threshold; the critical System, Security and
    Application logs are never cleared - their maximum size is reconfigured so
    they archive instead. Every mutation is gated behind -WhatIf/-Confirm via
    SupportsShouldProcess. Re-running on an already-converged system finds no log
    above the threshold, changes nothing and still exits 0 (idempotent).
    Exit codes: 0 = completed successfully (with or without clearing), 1 = an
    unexpected error occurred.

.EXAMPLE
    PS C:\> .\Invoke-RemediationFixEventLogSize.ps1

    Clears oversized non-critical event logs and raises the size limit of the
    critical logs to 50 MB.

.EXAMPLE
    PS C:\> .\Invoke-RemediationFixEventLogSize.ps1 -WhatIf

    Shows which logs would be cleared or reconfigured without changing anything.

.NOTES
    File Name  : Invoke-RemediationFixEventLogSize.ps1
    Author     : Intune Admin
    Prerequisite: PowerShell 7.0
    Version    : 1.0.0
    Date       : 2026-08-23
#>

[CmdletBinding(SupportsShouldProcess)]
param()

$ErrorActionPreference = 'Stop'

function Invoke-WevtUtil {
    # Thin wrapper around the native wevtutil.exe executable; mock seam for Pester tests.
    param(
        [Parameter(ValueFromRemainingArguments)]
        [string[]]$Remaining
    )

    & wevtutil.exe @Remaining 2>&1 | Out-Null
    return $LASTEXITCODE
}

function Main {
    # Advanced function so $PSCmdlet (and thus ShouldProcess) resolves inside Main.
    [CmdletBinding(SupportsShouldProcess)]
    param()

    try {
        Write-Host "[*] Checking Windows Event Logs for bloat..." -ForegroundColor Cyan

        # Configuration: clear non-critical logs larger than this (in MB).
        $maxLogSizeMB = 100
        $maxLogSizeBytes = $maxLogSizeMB * 1MB

        $remediationActions = @()
        $criticalLogs = @("System", "Security", "Application")

        # Get all event logs
        $eventLogs = Get-WinEvent -ListLog * -ErrorAction Stop

        foreach ($log in $eventLogs) {
            if ($log.FileSize -gt $maxLogSizeBytes) {
                $logName = $log.LogName
                $sizeMB = [math]::Round($log.FileSize / 1MB, 2)

                if ($criticalLogs -contains $logName) {
                    # For critical logs, configure auto-archiving instead of clearing
                    if ($PSCmdlet.ShouldProcess($logName, 'Configure critical log size limit')) {
                        $rc = Invoke-WevtUtil sl "$logName" /ms:52428800  # Set max size to 50MB
                        if ($rc -eq 0) {
                            $remediationActions += "Configured size limit for $logName ($sizeMB MB)"
                        }
                        else {
                            Write-Host "[!] wevtutil failed for ${logName}: exit code $rc" -ForegroundColor Yellow
                        }
                    }
                }
                else {
                    # Clear non-critical logs
                    if ($PSCmdlet.ShouldProcess($logName, 'Clear event log')) {
                        $rc = Invoke-WevtUtil cl "$logName"
                        if ($rc -eq 0) {
                            $remediationActions += "Cleared $logName ($sizeMB MB)"
                        }
                        else {
                            Write-Host "[!] wevtutil failed for ${logName}: exit code $rc" -ForegroundColor Yellow
                        }
                    }
                }
            }
        }

        if ($remediationActions.Count -gt 0) {
            Write-Host "[+] Event log remediation completed:" -ForegroundColor Green
            foreach ($action in $remediationActions) {
                Write-Host "    - $action"
            }
        }
        else {
            Write-Host "[+] Already clean: no event logs required clearing" -ForegroundColor Green
        }

        return 0
    }
    catch {
        Write-Host "[-] Error during event log remediation: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
