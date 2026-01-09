<#
.SYNOPSIS
    Remediates time synchronization issues.

.DESCRIPTION
    Fixes Windows Time service issues by ensuring service is running,
    configured properly, and forces a time sync.

.NOTES
    Author: Intune Admin
    Version: 1.0
    Intune Context: SYSTEM
    Exit 0: Remediation successful
#>

try {
    $remediationActions = @()

    # Set service to Automatic startup
    $w32timeService = Get-Service -Name "W32Time" -ErrorAction SilentlyContinue
    if ($w32timeService.StartType -ne "Automatic") {
        Set-Service -Name "W32Time" -StartupType Automatic -ErrorAction SilentlyContinue
        $remediationActions += "Set Windows Time service to Automatic startup"
    }

    # Start the service if not running
    if ($w32timeService.Status -ne "Running") {
        Start-Service -Name "W32Time" -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        $remediationActions += "Started Windows Time service"
    }

    # Configure time service to use time.windows.com
    $configResult = w32tm /config /manualpeerlist:"time.windows.com" /syncfromflags:manual /reliable:yes /update 2>&1
    if ($LASTEXITCODE -eq 0) {
        $remediationActions += "Configured time server to time.windows.com"
    }

    # Restart the service to apply changes
    Restart-Service -Name "W32Time" -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    $remediationActions += "Restarted Windows Time service"

    # Force immediate time sync
    $syncResult = w32tm /resync /force 2>&1
    if ($LASTEXITCODE -eq 0) {
        $remediationActions += "Forced time synchronization"
    } else {
        $remediationActions += "Attempted time sync (may take a few minutes to complete)"
    }

    Write-Host "Time sync remediation completed:"
    foreach ($action in $remediationActions) {
        Write-Host "  - $action"
    }

    exit 0

} catch {
    Write-Host "Error during time sync remediation: $_"
    exit 1
}
