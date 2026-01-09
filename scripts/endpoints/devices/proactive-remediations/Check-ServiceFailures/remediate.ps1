<#
.SYNOPSIS
    Attempts to restart failed critical services.

.DESCRIPTION
    Restarts critical services that are stopped but should be running.
    Logs service failure patterns for IT investigation.

.NOTES
    Author: Intune Admin
    Version: 1.0
    Intune Context: SYSTEM
    Exit 0: Services restarted or logged for review
#>

try {
    $remediationActions = @()

    Write-Host "Service Failure Remediation:"
    Write-Host ""

    # Critical services that should be running
    $criticalServices = @(
        'wuauserv',      # Windows Update
        'BITS',          # Background Intelligent Transfer
        'Winmgmt',       # Windows Management Instrumentation
        'Dhcp',          # DHCP Client
        'Dnscache'       # DNS Client
    )

    foreach ($svcName in $criticalServices) {
        $service = Get-Service -Name $svcName -ErrorAction SilentlyContinue

        if ($service -and $service.Status -ne 'Running' -and $service.StartType -ne 'Disabled') {
            Write-Host "  Attempting to start $svcName..."

            try {
                Start-Service -Name $svcName -ErrorAction Stop
                $remediationActions += "Started service: $svcName"
                Write-Host "    ✓ Successfully started $svcName"
            } catch {
                $remediationActions += "Failed to start service: $svcName - $_"
                Write-Host "    ✗ Failed to start $svcName: $_"
            }
        }
    }

    if ($remediationActions.Count -eq 0) {
        Write-Host "Recurring service failures detected."
        Write-Host ""
        Write-Host "Common causes:"
        Write-Host "  - Application bugs or crashes"
        Write-Host "  - Insufficient system resources"
        Write-Host "  - Dependency service failures"
        Write-Host "  - Corrupted service configuration"
        Write-Host "  - Permission or security issues"
        Write-Host ""
        Write-Host "IT should investigate:"
        Write-Host "  1. Review service event logs"
        Write-Host "  2. Check application error logs"
        Write-Host "  3. Verify service dependencies"
        Write-Host "  4. Update or reinstall problematic software"
        Write-Host "  5. Check system resource availability"
        Write-Host ""
        Write-Host "Device flagged for service stability review."
    } else {
        Write-Host ""
        Write-Host "Remediation actions taken:"
        foreach ($action in $remediationActions) {
            Write-Host "  - $action"
        }
    }

    Write-Host ""
    Write-Host "Device: $env:COMPUTERNAME"

    exit 0

} catch {
    Write-Host "Error during service failure remediation: $_"
    exit 1
}
