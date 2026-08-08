<#
.SYNOPSIS
    Detects improper PowerShell execution policy settings.

.DESCRIPTION
    Checks if the EFFECTIVE PowerShell execution policy is set appropriately for
    enterprise environments (should be RemoteSigned, not Unrestricted or
    Restricted). The effective policy is the highest-precedence non-Undefined
    scope per MS Learn, so Group Policy (MachinePolicy/UserPolicy), LocalMachine
    and CurrentUser overrides are all taken into account.

.NOTES
    Author: Intune Admin
    Version: 1.1
    Intune Context: SYSTEM
    Exit 0: Execution policy is properly configured
    Exit 1: Issues detected - remediation needed

    The Process scope is deliberately excluded from the effective-policy
    calculation: Intune launches remediation scripts with -ExecutionPolicy Bypass
    (unless signature enforcement is enabled), which would otherwise report every
    device as non-compliant regardless of actual configuration. The Process scope
    reflects the runner, not the device configuration, and cannot be remediated.

.CONFIGURATION
    $desiredPolicy: Desired execution policy (default: RemoteSigned)
#>

try {
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
        Write-Host "PowerShell execution policy issues detected:"
        foreach ($issue in $issues) {
            Write-Host "  - $issue"
        }
        exit 1
    }

    Write-Host "PowerShell execution policy is properly configured: $effectivePolicy"
    exit 0

}
catch {
    Write-Host "Error checking PowerShell execution policy: $_"
    exit 1
}
