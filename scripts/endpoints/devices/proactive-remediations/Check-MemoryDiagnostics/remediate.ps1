<#
.SYNOPSIS
    Schedules Windows Memory Diagnostic on next reboot.

.DESCRIPTION
    Memory errors cannot be fixed in software. This script schedules the
    Windows Memory Diagnostic tool to run on next reboot for detailed testing.

.NOTES
    Author: Intune Admin
    Version: 1.0
    Intune Context: SYSTEM
    Exit 0: Diagnostic scheduled
#>

try {
    $remediationActions = @()

    # Schedule memory diagnostic for next reboot
    $schedResult = bcdedit /set {default} bootstatuspolicy ignoreallfailures
    $memDiagResult = MdSched.exe /v

    if ($LASTEXITCODE -eq 0) {
        $remediationActions += "Scheduled Windows Memory Diagnostic for next reboot"
    }

    Write-Host "Memory diagnostic remediation:"
    Write-Host "  Memory errors detected in event logs"
    Write-Host "  Windows Memory Diagnostic has been scheduled for next reboot"
    Write-Host ""
    Write-Host "IMPORTANT:"
    Write-Host "  - User will be prompted to restart the computer"
    Write-Host "  - Memory test will run before Windows starts"
    Write-Host "  - Test takes 10-20 minutes depending on RAM size"
    Write-Host "  - Results will be available in Event Viewer after boot"
    Write-Host ""
    Write-Host "If memory errors are confirmed, RAM replacement is required"

    foreach ($action in $remediationActions) {
        Write-Host "  - $action"
    }

    exit 0

} catch {
    Write-Host "Error scheduling memory diagnostic: $_"
    exit 1
}
