<#
.SYNOPSIS
    Sets the LocalMachine PowerShell execution policy to RemoteSigned and verifies it sticks.

.DESCRIPTION
    Configures the PowerShell execution policy to RemoteSigned for the LocalMachine scope,
    which is the recommended setting for enterprise environments, then VERIFIES the change
    actually stuck (Set-ExecutionPolicy can silently fail or be overridden by Group Policy
    re-apply). If a higher-priority scope (Group Policy MachinePolicy/UserPolicy or
    CurrentUser) still overrides the LocalMachine setting, remediation reports failure
    honestly instead of claiming success. This script changes machine configuration; the
    Set-ExecutionPolicy mutation is gated behind ShouldProcess, so -WhatIf performs a dry
    run and re-running on a compliant device exits 0 without changes (idempotent).
    Exit codes:
    - 0: remediation successful (policy already correct or changed and verified).
    - 1: remediation failed (LocalMachine change did not stick, or a higher-priority scope
      overrides it and cannot be changed here).

.EXAMPLE
    PS C:\> .\Invoke-RemediationFixPowerShellExecutionPolicy.ps1
    Sets LocalMachine execution policy to RemoteSigned and verifies the effective policy.

.EXAMPLE
    PS C:\> .\Invoke-RemediationFixPowerShellExecutionPolicy.ps1 -WhatIf
    Reports whether the execution policy would be changed, without modifying anything.

.NOTES
    File Name: Invoke-RemediationFixPowerShellExecutionPolicy.ps1
    Author: Intune Admin
    Prerequisite: PowerShell 7.0
    Version: 1.0.0
    Date: 2026-08-23

    The Process scope is deliberately excluded from the effective-policy
    calculation - see the companion detection script's notes.
#>

[CmdletBinding(SupportsShouldProcess)]

$ErrorActionPreference = 'Stop'

function Main {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    try {
        Write-Host "[*] Checking PowerShell execution policy..." -ForegroundColor Cyan

        # Configuration
        $desiredPolicy = "RemoteSigned"

        $remediationActions = @()

        # Effective policy (Process scope excluded - see detection script notes)
        $effectivePolicy = (Get-ExecutionPolicy -List |
                Where-Object { $_.Scope -ne 'Process' -and $_.ExecutionPolicy -ne 'Undefined' } |
                Select-Object -First 1).ExecutionPolicy

        if ($effectivePolicy -eq $desiredPolicy) {
            $msg = "[+] PowerShell execution policy is already correctly configured (effective: $effectivePolicy)"
            Write-Host $msg -ForegroundColor Green
            return 0
        }

        # Set execution policy for LocalMachine scope
        $currentPolicy = Get-ExecutionPolicy -Scope LocalMachine -ErrorAction SilentlyContinue

        if ($currentPolicy -ne $desiredPolicy) {
            try {
                if ($PSCmdlet.ShouldProcess('LocalMachine scope',
                        "Set PowerShell execution policy to $desiredPolicy")) {
                    Set-ExecutionPolicy -ExecutionPolicy $desiredPolicy -Scope LocalMachine -Force -ErrorAction Stop

                    # Verify the change actually stuck - Group Policy re-apply, UAC
                    # virtualization or registry redirection can silently drop it.
                    $verifiedPolicy = Get-ExecutionPolicy -Scope LocalMachine -ErrorAction SilentlyContinue
                    if ($verifiedPolicy -ne $desiredPolicy) {
                        $msg = "[-] Remediation failed: LocalMachine execution policy is still '$verifiedPolicy' " +
                            "(expected '$desiredPolicy') after Set-ExecutionPolicy."
                        Write-Host $msg -ForegroundColor Red
                        return 1
                    }
                    $remediationActions += "Set LocalMachine execution policy to $desiredPolicy (was: $currentPolicy)"
                }
            }
            catch {
                Write-Host "[-] Error setting execution policy: $_" -ForegroundColor Red
                return 1
            }
        }

        # Re-check the effective policy (same logic as the detection script). If a
        # higher-priority scope still overrides LocalMachine, the device remains
        # non-compliant and LocalMachine changes cannot fix it - report it honestly.
        $effectiveAfter = (Get-ExecutionPolicy -List |
                Where-Object { $_.Scope -ne 'Process' -and $_.ExecutionPolicy -ne 'Undefined' } |
                Select-Object -First 1).ExecutionPolicy

        if ($effectiveAfter -ne $desiredPolicy) {
            $msg = "[-] Remediation incomplete: effective execution policy is still '$effectiveAfter'. " +
                "It is controlled by a higher-priority scope (Group Policy MachinePolicy/UserPolicy or " +
                "CurrentUser) that LocalMachine changes cannot override."
            Write-Host $msg -ForegroundColor Red
            return 1
        }

        if ($remediationActions.Count -gt 0) {
            Write-Host "[+] PowerShell execution policy remediation completed:" -ForegroundColor Green
            foreach ($action in $remediationActions) {
                Write-Host "  - $action" -ForegroundColor Green
            }
        }
        else {
            Write-Host "[+] PowerShell execution policy was already set correctly" -ForegroundColor Green
        }

        return 0
    }
    catch {
        $msg = "[-] Error during PowerShell execution policy remediation: $($_.Exception.Message)"
        Write-Host $msg -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
