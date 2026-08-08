<#
.SYNOPSIS
    Removes unauthorized network shares.

.DESCRIPTION
    Removes network shares that are not in the approved list to prevent
    unauthorized data exposure.

.NOTES
    Author: Intune Admin
    Version: 1.0
    Intune Context: SYSTEM
    Exit 0: Remediation successful

.CONFIGURATION
    $approvedShares: List of approved share names (default: system shares)
#>

try {
    # Configuration - Add your approved share names here
    $approvedShares = @(
        "ADMIN$",
        "C$",
        "D$",
        "IPC$",
        "print$"
    )

    $remediationActions = @()

    # Get all network shares
    $shares = Get-SmbShare -ErrorAction SilentlyContinue

    foreach ($share in $shares) {
        $isApproved = $false

        foreach ($approved in $approvedShares) {
            if ($share.Name -like $approved) {
                $isApproved = $true
                break
            }
        }

        if (-not $isApproved) {
            try {
                Remove-SmbShare -Name $share.Name -Force -ErrorAction Stop
                $remediationActions += "Removed unauthorized share: $($share.Name) ($($share.Path))"
            }
            catch {
                Write-Host "Warning: Could not remove share $($share.Name): $_"
            }
        }
    }

    if ($remediationActions.Count -gt 0) {
        Write-Host "Network share remediation completed:"
        foreach ($action in $remediationActions) {
            Write-Host "  - $action"
        }
    }
    else {
        Write-Host "No unauthorized shares found to remove"
    }

    exit 0

}
catch {
    Write-Host "Error during network share remediation: $_"
    exit 1
}
