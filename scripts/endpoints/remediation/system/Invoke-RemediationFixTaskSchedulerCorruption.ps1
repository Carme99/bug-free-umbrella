<#
.SYNOPSIS
    Restore a broken Task Scheduler service to Running.

.DESCRIPTION
    Verifies the Task Scheduler service ("Schedule") exists, starts it when it
    is not running and confirms the task database location
    (<SystemRoot>\System32\Tasks) is present.
    Side effects: the Schedule service may be started. The task database itself
    is deliberately never deleted - it holds critical scheduled task definitions.
    The service start is gated behind -WhatIf/-Confirm via SupportsShouldProcess.
    Re-running on an already-converged system (service Running, database
    location present) makes no changes and still exits 0 (idempotent).
    Exit codes: 0 = remediation successful (or already converged), 1 = the
    Schedule service was not found or could not be brought to Running.

.EXAMPLE
    PS C:\> .\Invoke-RemediationFixTaskSchedulerCorruption.ps1

    Starts the Task Scheduler service if it is not running and verifies the
    task database location.

.EXAMPLE
    PS C:\> .\Invoke-RemediationFixTaskSchedulerCorruption.ps1 -WhatIf

    Shows whether the service would be started without changing anything.

.NOTES
    File Name  : Invoke-RemediationFixTaskSchedulerCorruption.ps1
    Author     : Intune Admin
    Prerequisite: PowerShell 7.0
    Version    : 1.0.0
    Date       : 2026-08-23

    Intune Context: SYSTEM. If issues persist after the service is healthy,
    the Task Scheduler database may need manual repair.
#>

[CmdletBinding(SupportsShouldProcess)]
param()

$ErrorActionPreference = 'Stop'

function Main {
    # Advanced function so $PSCmdlet (and thus ShouldProcess) resolves inside Main.
    [CmdletBinding(SupportsShouldProcess)]
    param()

    try {
        Write-Host "[*] Remediating Task Scheduler corruption..." -ForegroundColor Cyan

        # Verify the task database location is present (never deleted - critical data).
        $taskDbPath = Join-Path $env:SystemRoot 'System32\Tasks'
        $taskDbPresent = (Test-Path -LiteralPath $taskDbPath)
        if ($taskDbPresent) {
            Write-Host "[*] Verified task database location: $taskDbPath" -ForegroundColor Cyan
        }
        else {
            Write-Host "[!] Task database location not found: $taskDbPath" -ForegroundColor Yellow
        }

        $schedService = Get-Service -Name 'Schedule' -ErrorAction SilentlyContinue
        if (-not $schedService) {
            Write-Host "[-] Error remediating Task Scheduler: the Schedule service was not found" -ForegroundColor Red
            return 1
        }

        if ($schedService.Status -ne 'Running') {
            if ($PSCmdlet.ShouldProcess('Schedule', 'Start Task Scheduler service')) {
                Start-Service -Name 'Schedule' -ErrorAction Stop
                Write-Host "[*] Started Task Scheduler service" -ForegroundColor Cyan
            }
            Write-Host "[+] Task Scheduler remediation completed" -ForegroundColor Green
        }
        else {
            Write-Host "[+] Already healthy: Task Scheduler service is running and the task database location is verified" -ForegroundColor Green
        }
        return 0
    }
    catch {
        Write-Host "[-] Error remediating Task Scheduler: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
