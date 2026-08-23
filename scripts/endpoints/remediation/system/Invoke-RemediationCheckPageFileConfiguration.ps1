<#
.SYNOPSIS
    Configures page file to system-managed.

.DESCRIPTION
    Sets page file to system-managed configuration ONLY if it's completely disabled.
    Does NOT modify custom page file configurations as they may be intentional
    (SQL Server, crash dump requirements, performance tuning).

.NOTES
    Author: Intune Admin
    Version: 1.1
    Intune Context: SYSTEM
    Exit 0: Remediation successful
    Note: Requires restart to apply changes
#>

try {
    $remediationActions = @()

    # Get current configuration
    $compSys = Get-WmiObject -Class Win32_ComputerSystem
    $pageFiles = Get-WmiObject -Class Win32_PageFileSetting -ErrorAction SilentlyContinue

    # SAFETY CHECK: Only remediate if page file is COMPLETELY DISABLED
    # Do NOT touch custom page file configurations - they may be intentional
    # (e.g., SQL Server, crash dump requirements, performance tuning)

    if ($compSys.AutomaticManagedPagefile -eq $false -and (-not $pageFiles -or $pageFiles.Count -eq 0)) {
        # Page file is completely disabled - safe to enable system-managed
        Write-Host "Page file is completely disabled. Enabling system-managed page file..."

        $compSys.AutomaticManagedPagefile = $true
        $compSys.Put() | Out-Null
        $remediationActions += "Enabled system-managed page file"

        Write-Host "Page file remediation completed:"
        foreach ($action in $remediationActions) {
            Write-Host "  - $action"
        }
        Write-Host ""
        Write-Host "IMPORTANT: A system restart is required for changes to take effect"
    }
    elseif ($pageFiles -and $pageFiles.Count -gt 0) {
        # Custom page file exists - don't touch it even if undersized
        Write-Host "Custom page file configuration detected:"
        foreach ($pf in $pageFiles) {
            Write-Host "  - $($pf.Name): Initial=$($pf.InitialSize)MB, Maximum=$($pf.MaximumSize)MB"
        }
        Write-Host ""
        Write-Host "NOTICE: Custom page file configurations are not automatically changed."
        Write-Host "If this configuration is unintentional, manually review and adjust."
        Write-Host "Custom configurations may be required for:"
        Write-Host "  - SQL Server performance"
        Write-Host "  - Complete memory dump collection"
        Write-Host "  - Application-specific requirements"
    }
    else {
        Write-Host "Page file is already properly configured (system-managed)"
    }

    exit 0

}
catch {
    Write-Host "Error during page file remediation: $_"
    exit 1
}
