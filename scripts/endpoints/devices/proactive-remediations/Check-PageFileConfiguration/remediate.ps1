<#
.SYNOPSIS
    Configures page file to system-managed.

.DESCRIPTION
    Sets page file to system-managed configuration if it's disabled or
    improperly sized.

.NOTES
    Author: Intune Admin
    Version: 1.0
    Intune Context: SYSTEM
    Exit 0: Remediation successful
    Note: Requires restart to apply changes
#>

try {
    $remediationActions = @()

    # Enable system-managed page file
    $compSys = Get-WmiObject -Class Win32_ComputerSystem

    if ($compSys.AutomaticManagedPagefile -eq $false) {
        $compSys.AutomaticManagedPagefile = $true
        $compSys.Put() | Out-Null
        $remediationActions += "Enabled system-managed page file"
    }

    # Remove custom page file settings if any
    $pageFiles = Get-WmiObject -Class Win32_PageFileSetting
    foreach ($pf in $pageFiles) {
        $pf.Delete() | Out-Null
        $remediationActions += "Removed custom page file setting for $($pf.Name)"
    }

    if ($remediationActions.Count -gt 0) {
        Write-Host "Page file remediation completed:"
        foreach ($action in $remediationActions) {
            Write-Host "  - $action"
        }
        Write-Host ""
        Write-Host "IMPORTANT: A system restart is required for changes to take effect"
    } else {
        Write-Host "Page file was already properly configured"
    }

    exit 0

} catch {
    Write-Host "Error during page file remediation: $_"
    exit 1
}
