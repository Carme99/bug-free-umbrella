<#
.SYNOPSIS
    Stop stuck Windows Performance Recorder trace sessions.

.DESCRIPTION
    Detects orphaned WPR-initiated ETW tracing sessions via logman and stops them,
    then terminates a hung wpr.exe process if one is still running, restoring system
    performance. Side effects: stops ETW trace sessions and kills the WPR process;
    every stop operation is gated behind -WhatIf/-Confirm via SupportsShouldProcess.
    On a system with no stuck recorder sessions the script makes no changes and still
    exits 0 (idempotent).
    Exit codes: 0 = remediation complete or nothing to do; 1 = an unexpected error
    occurred. Intune Context: SYSTEM.

.EXAMPLE
    PS C:\> .\Invoke-RemediationFixWindowsPerformanceRecorder.ps1

    Stops every orphaned WPR ETW session and the WPR process if present.

.EXAMPLE
    PS C:\> .\Invoke-RemediationFixWindowsPerformanceRecorder.ps1 -WhatIf

    Lists the sessions and processes that would be stopped without stopping them.

.NOTES
    File Name  : Invoke-RemediationFixWindowsPerformanceRecorder.ps1
    Author     : Intune Admin
    Prerequisite: PowerShell 7.0
    Version    : 1.0.0
    Date       : 2026-08-23
#>

[CmdletBinding(SupportsShouldProcess)]
param()

$ErrorActionPreference = 'Stop'

function Get-WprSessionName {
    # Thin wrapper around native logman.exe query; mock seam for Pester tests.
    # Returns the names of currently running WPR-initiated ETW sessions.
    $queryOutput = & logman.exe query -ets 2>&1
    return @(
        $queryOutput | Where-Object { $_ -match 'WPR_initiated_' } |
            ForEach-Object { ([string]$_).Trim() -replace '\s.*$', '' }
    )
}

function Stop-WprSession {
    # Thin wrapper around native logman.exe stop; mock seam for Pester tests.
    param([string]$Name)

    & logman.exe stop $Name -ets 2>&1 | Out-Null
    return $LASTEXITCODE
}

function Main {
    # Advanced function so $PSCmdlet (and thus ShouldProcess) resolves inside Main.
    [CmdletBinding(SupportsShouldProcess)]
    param()

    try {
        Write-Host "[*] Stopping stuck Windows Performance Recorder sessions..." -ForegroundColor Cyan

        $stoppedCount = 0

        # Stop all WPR-initiated ETW trace sessions.
        foreach ($sessionName in (Get-WprSessionName)) {
            if ($PSCmdlet.ShouldProcess($sessionName, 'Stop orphaned WPR ETW trace session')) {
                $stopExitCode = Stop-WprSession -Name $sessionName
                if ($stopExitCode -ne 0) {
                    Write-Host "[!] Could not stop WPR session $sessionName (exit code $stopExitCode)" -ForegroundColor Yellow
                    continue
                }
                Write-Host "[+] Stopped WPR session: $sessionName" -ForegroundColor Green
                $stoppedCount++
            }
        }

        # Stop the WPR process if it is still running.
        $wprProcess = Get-Process -Name 'wpr' -ErrorAction SilentlyContinue
        if ($wprProcess) {
            if ($PSCmdlet.ShouldProcess('wpr', 'Stop stuck Windows Performance Recorder process')) {
                Stop-Process -Name 'wpr' -Force -ErrorAction Stop
                Write-Host "[+] Stopped WPR process" -ForegroundColor Green
                $stoppedCount++
            }
        }

        if ($stoppedCount -eq 0) {
            Write-Host "[+] Already clean: no stuck performance recorder sessions found" -ForegroundColor Green
        }
        else {
            Write-Host "[+] Performance recorder remediation completed ($stoppedCount action(s))" -ForegroundColor Green
        }
        return 0
    }
    catch {
        Write-Host "[-] Error during performance recorder remediation: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
