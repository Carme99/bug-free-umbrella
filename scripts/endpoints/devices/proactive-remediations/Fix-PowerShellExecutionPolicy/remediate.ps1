<#
.SYNOPSIS
    Sets PowerShell execution policy to RemoteSigned.

.DESCRIPTION
    Configures PowerShell execution policy to RemoteSigned for the LocalMachine scope,
    which is the recommended setting for enterprise environments.

.NOTES
    Author: Intune Admin
    Version: 1.0
    Intune Context: SYSTEM
    Exit 0: Remediation successful

.CONFIGURATION
    $desiredPolicy: Desired execution policy (default: RemoteSigned)
#>

try {
    # Configuration
    $desiredPolicy = "RemoteSigned"

    $remediationActions = @()

    # Set execution policy for LocalMachine scope
    $currentPolicy = Get-ExecutionPolicy -Scope LocalMachine -ErrorAction SilentlyContinue

    if ($currentPolicy -ne $desiredPolicy) {
        try {
            Set-ExecutionPolicy -ExecutionPolicy $desiredPolicy -Scope LocalMachine -Force -ErrorAction Stop
            $remediationActions += "Set LocalMachine execution policy to $desiredPolicy (was: $currentPolicy)"
        } catch {
            Write-Host "Error setting execution policy: $_"
            exit 1
        }
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
