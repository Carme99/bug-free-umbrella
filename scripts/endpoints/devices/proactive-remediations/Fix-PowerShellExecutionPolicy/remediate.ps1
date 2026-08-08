<#
.SYNOPSIS
    Sets PowerShell execution policy to RemoteSigned.

.DESCRIPTION
    Configures PowerShell execution policy to RemoteSigned for the LocalMachine
    scope, which is the recommended setting for enterprise environments, then
    VERIFIES the change actually stuck (Set-ExecutionPolicy can silently fail or
    be overridden by Group Policy re-apply). If a higher-priority scope
    (Group Policy MachinePolicy/UserPolicy or CurrentUser) still overrides the
    LocalMachine setting, remediation reports failure honestly instead of
    claiming success.

.NOTES
    Author: Intune Admin
    Version: 1.1
    Intune Context: SYSTEM
    Exit 0: Remediation successful
    Exit 1: Remediation failed (LocalMachine change did not stick, or a
            higher-priority scope overrides it and cannot be changed here)

    The Process scope is deliberately excluded from the effective-policy
    calculation - see Fix-PowerShellExecutionPolicy/detect.ps1 NOTES.

.CONFIGURATION
    $desiredPolicy: Desired execution policy (default: RemoteSigned)
#>

try {
    # Configuration
    $desiredPolicy = "RemoteSigned"

    $remediationActions = @()

    # Effective policy (Process scope excluded - see detect.ps1 NOTES)
    $effectivePolicy = (Get-ExecutionPolicy -List |
        Where-Object { $_.Scope -ne 'Process' -and $_.ExecutionPolicy -ne 'Undefined' } |
        Select-Object -First 1).ExecutionPolicy

    if ($effectivePolicy -eq $desiredPolicy) {
        Write-Host "PowerShell execution policy is already correctly configured (effective: $effectivePolicy)"
        exit 0
    }

    # Set execution policy for LocalMachine scope
    $currentPolicy = Get-ExecutionPolicy -Scope LocalMachine -ErrorAction SilentlyContinue

    if ($currentPolicy -ne $desiredPolicy) {
        try {
            Set-ExecutionPolicy -ExecutionPolicy $desiredPolicy -Scope LocalMachine -Force -ErrorAction Stop

            # Verify the change actually stuck - Group Policy re-apply, UAC
            # virtualization or registry redirection can silently drop it.
            $verifiedPolicy = Get-ExecutionPolicy -Scope LocalMachine -ErrorAction SilentlyContinue
            if ($verifiedPolicy -ne $desiredPolicy) {
                Write-Host "Remediation failed: LocalMachine execution policy is still '$verifiedPolicy' (expected '$desiredPolicy') after Set-ExecutionPolicy. A Group Policy refresh or access restriction may be blocking the change."
                exit 1
            }
            $remediationActions += "Set LocalMachine execution policy to $desiredPolicy (was: $currentPolicy)"
        } catch {
            Write-Host "Error setting execution policy: $_"
            exit 1
        }
    }

    # Re-check the effective policy (same logic as detect.ps1). If a
    # higher-priority scope (Group Policy MachinePolicy/UserPolicy, or the
    # CurrentUser scope) still overrides LocalMachine, the device remains
    # non-compliant and LocalMachine changes cannot fix it - report it honestly.
    $effectiveAfter = (Get-ExecutionPolicy -List |
        Where-Object { $_.Scope -ne 'Process' -and $_.ExecutionPolicy -ne 'Undefined' } |
        Select-Object -First 1).ExecutionPolicy

    if ($effectiveAfter -ne $desiredPolicy) {
        Write-Host "Remediation incomplete: effective execution policy is still '$effectiveAfter'. It is controlled by a higher-priority scope (Group Policy MachinePolicy/UserPolicy or the CurrentUser scope) that LocalMachine changes cannot override. Review Group Policy on this device."
        exit 1
    }

    if ($remediationActions.Count -gt 0) {
        Write-Host "PowerShell execution policy remediation completed:"
        foreach ($action in $remediationActions) {
            Write-Host "  - $action"
        }
    } else {
        Write-Host "PowerShell execution policy was already set correctly"
    }

    exit 0

} catch {
    Write-Host "Error during PowerShell execution policy remediation: $_"
    exit 1
}
