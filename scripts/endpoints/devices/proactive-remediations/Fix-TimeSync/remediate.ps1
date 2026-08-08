<#
.SYNOPSIS
    Remediates time synchronization issues.

.DESCRIPTION
    Fixes Windows Time service issues by ensuring the service is running and
    configured properly, then forces a time sync.
      - Domain-joined workstations/servers: uses NT5DS (sync from the domain
        hierarchy, w32tm /syncfromflags:domhier) - the documented configuration
        for domain members; manual NTP is NOT forced on them.
      - Domain controllers: NT5DS plus /reliable:yes (only meaningful on DCs).
      - Workgroup devices: manual sync from time.windows.com (no /reliable -
        only domain controllers may be reliable time sources).

.NOTES
    Author: Intune Admin
    Version: 1.1
    Intune Context: SYSTEM
    Exit 0: Remediation successful
#>

try {
    $remediationActions = @()

    # Determine domain membership / domain controller role
    $computerSystem = Get-CimInstance Win32_ComputerSystem
    $isDomainJoined = $computerSystem.PartOfDomain -eq $true
    # DomainRole: 0=standalone workstation, 1=member workstation,
    # 2=standalone server, 3=member server, 4=backup DC, 5=primary DC
    $isDomainController = $computerSystem.DomainRole -in @(4, 5)

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

    # Configure time source based on domain membership
    if ($isDomainController) {
        # Domain controllers sync from the domain hierarchy and are reliable
        $configResult = w32tm /config /syncfromflags:domhier /reliable:yes /update 2>&1
        if ($LASTEXITCODE -eq 0) {
            $remediationActions += "Configured NT5DS time sync (domain controller, reliable)"
        }
    } elseif ($isDomainJoined) {
        # Domain members use NT5DS - do NOT override with manual NTP, which
        # would break the documented domain time topology
        $configResult = w32tm /config /syncfromflags:domhier /update 2>&1
        if ($LASTEXITCODE -eq 0) {
            $remediationActions += "Configured NT5DS time sync from the domain hierarchy"
        }
    } else {
        # Workgroup device - manual sync from time.windows.com. /reliable is
        # only meaningful on domain controllers, so it is never set here.
        $configResult = w32tm /config /manualpeerlist:"time.windows.com" /syncfromflags:manual /update 2>&1
        if ($LASTEXITCODE -eq 0) {
            $remediationActions += "Configured time server to time.windows.com"
        }
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
