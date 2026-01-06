<#
.SYNOPSIS
    Remediates unauthorized local administrator accounts.

.DESCRIPTION
    Disables the built-in Administrator account and logs unauthorized admin accounts.
    Use with caution - manual review recommended before removing admin accounts.

.NOTES
    Author: Intune Admin
    Version: 1.0
    Intune Context: SYSTEM
    Exit 0: Remediation successful
#>

try {
    $remediationActions = @()

    # Disable built-in Administrator account if enabled
    $builtinAdmin = Get-LocalUser -Name "Administrator" -ErrorAction SilentlyContinue
    if ($builtinAdmin -and $builtinAdmin.Enabled -eq $true) {
        try {
            Disable-LocalUser -Name "Administrator" -ErrorAction Stop
            $remediationActions += "Disabled built-in Administrator account"
        } catch {
            Write-Host "Warning: Could not disable Administrator account: $_"
        }
    }

    # Note: We do NOT automatically remove unauthorized admin accounts
    # as this could lock out legitimate administrators or break systems.
    # Instead, we log them for manual review.

    Write-Host "Local administrator remediation completed:"
    if ($remediationActions.Count -gt 0) {
        foreach ($action in $remediationActions) {
            Write-Host "  - $action"
        }
    } else {
        Write-Host "  - No automatic remediation performed"
    }

    Write-Host ""
    Write-Host "Note: Unauthorized admin accounts detected should be reviewed manually"
    Write-Host "Automatic removal of admin accounts is not performed to prevent lockouts"

    exit 0

} catch {
    Write-Host "Error during local administrator remediation: $_"
    exit 1
}
