<#
.SYNOPSIS
    Detects Windows system file corruption for Intune Proactive Remediations.

.DESCRIPTION
    Checks component store health via the DISM ScanHealth operation (invoked only through
    the Invoke-Dism wrapper) and scans the tail of the CBS log for recent SFC corruption
    findings. This is a read-only detection script; it makes no changes to the system.
    Exit codes:
    - 0: no corruption detected.
    - 1: corruption was found (repairable or confirmed), the DISM scan failed, or the check
      itself failed; triggers remediation.
    Re-running against an unchanged system yields the same result (idempotent).

.NOTES
    File Name: Test-RemediationFixSystemFileCorruption.ps1
    Author: Intune Admin
    Prerequisite: PowerShell 7.0
    Version: 1.0.0
    Date: 2026-08-23

.EXAMPLE
    PS C:\> .\Test-RemediationFixSystemFileCorruption.ps1
    Runs DISM ScanHealth and CBS log checks; exits 0 when clean, 1 on corruption.

.EXAMPLE
    PS C:\> .\Test-RemediationFixSystemFileCorruption.ps1; $LASTEXITCODE
    Runs the checks and prints the resulting exit code for pipeline consumption.
#>

[CmdletBinding()]

$ErrorActionPreference = 'Stop'

function Invoke-Dism {
    <#
    .SYNOPSIS
        Thin wrapper around the native dism.exe CLI (the mock seam for Pester).
    .DESCRIPTION
        Runs dism.exe with the given arguments, captures combined output, and returns both
        the output text and the native exit code so callers can translate non-zero exits
        into failure handling.
    #>
    param([Parameter(Mandatory)][string[]]$Arguments)

    $output = & "$env:SystemRoot\System32\Dism.exe" @Arguments 2>&1
    $exitCode = $LASTEXITCODE
    [pscustomobject] @{
        ExitCode = $exitCode
        Output   = ($output | Out-String)
    }
}

function Main {
    try {
        $issues = @()

        # Check component store health using DISM (via the wrapper - never call dism.exe directly)
        $outputMsg = "[*] Checking component store health (this may take a few minutes)..."
        Write-Host $outputMsg -ForegroundColor Cyan
        $dismResult = Invoke-Dism -Arguments @('/Online', '/Cleanup-Image', '/ScanHealth')

        if ($dismResult.Output -match 'The component store is repairable') {
            $issues += "Component store corruption detected (repairable)"
        }
        elseif ($dismResult.Output -match 'The component store corruption was detected') {
            $issues += "Component store corruption detected"
        }
        elseif ($dismResult.ExitCode -ne 0) {
            # Translate a non-zero native exit into failure handling
            $issues += "Component store scan failed (dism.exe exit code $($dismResult.ExitCode))"
        }

        # Check for recent SFC scan results in CBS log
        $cbsLog = "$env:SystemRoot\Logs\CBS\CBS.log"
        if (Test-Path $cbsLog) {
            $recentLog = Get-Content $cbsLog -Tail 500 -ErrorAction SilentlyContinue
            if ($recentLog -match 'found corrupt files' -or $recentLog -match 'verification failed') {
                $issues += "SFC detected corrupted files in recent scan"
            }
        }

        if ($issues.Count -gt 0) {
            $outputMsg = "[!] System file corruption detected:"
            Write-Host $outputMsg -ForegroundColor Yellow
            foreach ($issue in $issues) {
                $outputMsg = "  - $issue"
                Write-Host $outputMsg -ForegroundColor Yellow
            }
            return 1
        }

        $outputMsg = "[+] No system file corruption detected"

        Write-Host $outputMsg -ForegroundColor Green
        return 0
    }
    catch {
        $outputMsg = "[-] Error checking system file integrity: $($_.Exception.Message)"
        Write-Host $outputMsg -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
