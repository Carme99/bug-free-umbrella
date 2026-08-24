<#
.SYNOPSIS
    Detects stuck Windows Performance Recorder (WPR) or ETW sessions.

.DESCRIPTION
    Checks for orphaned WPR/ETW tracing sessions that can cause high CPU usage and performance
    degradation: it queries active ETW sessions via logman.exe (invoked only through the
    Invoke-LogmanQuery wrapper), flags more than two WPR-initiated sessions and more than 50
    total sessions, and flags enabled Autologger sessions outside the event log ones via the
    registry. This is a read-only detection script: it changes nothing, so re-running it is
    safe (idempotent).
    Exit codes:
    - 0: healthy - no stuck WPR/ETW sessions detected.
    - 1: non-compliant - stuck sessions detected, or the check failed.

.EXAMPLE
    PS C:\> .\Test-RemediationFixWindowsPerformanceRecorder.ps1
    Queries WPR/ETW session state; exits 0 when clean, 1 when stuck sessions are detected.

.EXAMPLE
    PS C:\> & 'C:\Program Files\Intune\ProactiveRemediations\Test-RemediationFixWindowsPerformanceRecorder.ps1'
    Runs the same check from the Intune Management Extension under the SYSTEM context.

.NOTES
    File Name: Test-RemediationFixWindowsPerformanceRecorder.ps1
    Author: Intune Admin
    Prerequisite: PowerShell 7.0
    Version: 1.0.0
    Date: 2026-08-23
#>

[CmdletBinding()]

$ErrorActionPreference = 'Stop'

#region Functions

function Invoke-LogmanQuery {
    <#
    .SYNOPSIS
        Thin wrapper around the native logman.exe CLI; returns its output lines and exit code.
    #>

    $output = @(& logman.exe query -ets 2>&1 | ForEach-Object { $_.ToString() })
    [pscustomobject] @{
        ExitCode = $LASTEXITCODE
        Output   = $output
    }
}

function Main {
    try {
        $outputMsg = "[*] Checking for stuck WPR/ETW sessions..."
        Write-Host $outputMsg -ForegroundColor Cyan

        $issues = @()

        # Check for running WPR sessions.
        # NOTE: This check may produce false positives for legitimate active tracing.
        # WPR sessions are typically short-lived (<1 hour). Long-running sessions
        # may indicate orphaned traces consuming CPU/disk resources.
        $logmanResult = Invoke-LogmanQuery

        if ($logmanResult.ExitCode -ne 0) {
            $outputMsg = "[-] logman query failed with exit code $($logmanResult.ExitCode)"
            Write-Host $outputMsg -ForegroundColor Red
            return 1
        }

        $wprSessions = @($logmanResult.Output | Select-String -Pattern "WPR_initiated_")

        if ($wprSessions.Count -gt 0) {
            $sessionCount = $wprSessions.Count
            # Only flag if multiple WPR sessions (more likely to be orphaned)
            if ($sessionCount -gt 2) {
                                $issues += "Multiple active WPR tracing sessions detected: $sessionCount (may `
                    indicate orphaned sessions)"
            }
        }

        # Check for excessive ETW sessions (more reliable indicator of issues)
        $allSessions = @($logmanResult.Output | Select-String -Pattern "^[A-Za-z]")

        if ($allSessions.Count -gt 50) {
            $issues += "Excessive ETW sessions detected: $($allSessions.Count) (threshold: 50)"
        }

        # Check for autologger sessions that may be stuck
        $autoLoggers = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\WMI\Autologger\*" `
            -ErrorAction SilentlyContinue

        $stuckAutoLoggers = @($autoLoggers | Where-Object {
            $_.Start -eq 1 -and $_.PSChildName -notmatch "EventLog-System|EventLog-Application"
        })

        if ($stuckAutoLoggers.Count -gt 0) {
            $issues += "Potentially stuck AutoLogger sessions detected"
        }

        if ($issues.Count -gt 0) {
            $outputMsg = "[!] Performance recorder issues detected:"
            Write-Host $outputMsg -ForegroundColor Yellow
            foreach ($issue in $issues) {
                $outputMsg = "[!]   - $issue"
                Write-Host $outputMsg -ForegroundColor Yellow
            }
            return 1
        }

        $outputMsg = "[+] No stuck WPR/ETW sessions detected"

        Write-Host $outputMsg -ForegroundColor Green
        return 0
    }
    catch {
        $outputMsg = "[-] Error checking performance recorder status: $($_.Exception.Message)"
        Write-Host $outputMsg -ForegroundColor Red
        return 1
    }
}

#endregion

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
