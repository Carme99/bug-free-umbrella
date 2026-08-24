<#
.SYNOPSIS
    Detects improper PowerShell execution policy settings.

.DESCRIPTION
    Checks if the EFFECTIVE PowerShell execution policy is set appropriately for
    enterprise environments (should be RemoteSigned, not Unrestricted or
    Restricted). The effective policy is the highest-precedence non-Undefined
    scope per MS Learn, so Group Policy (MachinePolicy/UserPolicy), LocalMachine
    and CurrentUser overrides are all taken into account.
    Exit codes: 0 = compliant (execution policy is properly configured),
    1 = non-compliant (issues detected - remediation needed). This is a
    read-only detection script: it never modifies anything, so re-running it on
    a converged device converges to exit 0 (idempotent).

.EXAMPLE
    PS C:\> .\Test-RemediationFixPowerShellExecutionPolicy.ps1
    Evaluates the effective execution policy and exits 0 when it is RemoteSigned,
    1 when it is misconfigured (too permissive or too restrictive).

.EXAMPLE
    PS C:\> & 'C:\Program Files\Intune\ProactiveRemediations\Test-RemediationFixPowerShellExecutionPolicy.ps1'
    Runs the same check from the Intune Management Extension under the SYSTEM context.

.NOTES
    File Name: Test-RemediationFixPowerShellExecutionPolicy.ps1
    Author: Intune Admin
    Prerequisite: PowerShell 7.0
    Version: 1.0.0
    Date: 2026-08-23

    The Process scope is deliberately excluded from the effective-policy
    calculation: Intune launches remediation scripts with -ExecutionPolicy Bypass
    (unless signature enforcement is enabled), which would otherwise report every
    device as non-compliant regardless of actual configuration. The Process scope
    reflects the runner, not the device configuration, and cannot be remediated.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

function Main {
    try {
        Write-Host "[*] Checking PowerShell execution policy..." -ForegroundColor Cyan

        # Configuration
        $desiredPolicy = "RemoteSigned"

        $issues = @()

        # Effective policy: Get-ExecutionPolicy -List output is already in precedence
        # order (MachinePolicy, UserPolicy, LocalMachine, CurrentUser per MS Learn);
        # the first scope whose policy is not 'Undefined' wins. Process scope is
        # excluded - see the NOTES section.
        $effectivePolicy = (Get-ExecutionPolicy -List |
                Where-Object { $_.Scope -ne 'Process' -and $_.ExecutionPolicy -ne 'Undefined' } |
                Select-Object -First 1).ExecutionPolicy

        if ([string]::IsNullOrEmpty($effectivePolicy)) {
            $issues += "No effective execution policy could be determined"
        }
        else {
            if ($effectivePolicy -ne $desiredPolicy) {
                $issues += "Effective execution policy is '$effectivePolicy' (should be '$desiredPolicy')"
            }

            # Check for overly permissive policy
            if ($effectivePolicy -eq "Unrestricted" -or $effectivePolicy -eq "Bypass") {
                $issues += "Execution policy is too permissive: $effectivePolicy (security risk)"
            }

            # Check for overly restrictive policy
            if ($effectivePolicy -eq "Restricted" -or $effectivePolicy -eq "AllSigned") {
                $issues += "Execution policy may be too restrictive: $effectivePolicy"
            }
        }

        if ($issues.Count -gt 0) {
            Write-Host "[!] PowerShell execution policy issues detected:" -ForegroundColor Yellow
            foreach ($issue in $issues) {
                Write-Host "  - $issue" -ForegroundColor Yellow
            }
            return 1
        }

        Write-Host "[+] PowerShell execution policy is properly configured: $effectivePolicy" -ForegroundColor Green
        return 0
    }
    catch {
        Write-Host "[-] Error checking PowerShell execution policy: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
