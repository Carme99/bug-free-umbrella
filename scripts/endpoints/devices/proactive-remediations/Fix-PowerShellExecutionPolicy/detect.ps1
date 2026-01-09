<#
.SYNOPSIS
    Detects improper PowerShell execution policy settings.

.DESCRIPTION
    Checks if PowerShell execution policy is set appropriately for enterprise
    environments (should be RemoteSigned, not Unrestricted or Restricted).

.NOTES
    Author: Intune Admin
    Version: 1.0
    Intune Context: SYSTEM
    Exit 0: Execution policy is properly configured
    Exit 1: Issues detected - remediation needed

.CONFIGURATION
    $desiredPolicy: Desired execution policy (default: RemoteSigned)
#>

try {
    # Configuration
    $desiredPolicy = "RemoteSigned"

    $issues = @()

    # Check execution policy for all scopes
    $currentPolicy = Get-ExecutionPolicy -Scope LocalMachine -ErrorAction SilentlyContinue

    if ($currentPolicy -ne $desiredPolicy) {
        $issues += "LocalMachine execution policy is '$currentPolicy' (should be '$desiredPolicy')"
    }

    # Check for overly permissive policy
    if ($currentPolicy -eq "Unrestricted" -or $currentPolicy -eq "Bypass") {
        $issues += "Execution policy is too permissive: $currentPolicy (security risk)"
    }

    # Check for overly restrictive policy
    if ($currentPolicy -eq "Restricted" -or $currentPolicy -eq "AllSigned") {
        $issues += "Execution policy may be too restrictive: $currentPolicy"
    }

    if ($issues.Count -gt 0) {
        Write-Host "PowerShell execution policy issues detected:"
        foreach ($issue in $issues) {
            Write-Host "  - $issue"
        }
        exit 1
    }

    Write-Host "PowerShell execution policy is properly configured: $currentPolicy"
    exit 0

} catch {
    Write-Host "Error checking PowerShell execution policy: $_"
    exit 1
}
