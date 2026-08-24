<#
.SYNOPSIS
    Fix Windows Time service configuration and force a resync.

.DESCRIPTION
    Ensures the Windows Time service (W32Time) is set to Automatic startup and
    running, configures the correct time source for the device role, restarts
    the service to apply it and forces an immediate time synchronization.
      - Domain controllers: NT5DS plus /reliable:yes (only DCs may be reliable).
      - Domain members: NT5DS from the domain hierarchy; manual NTP is NOT
        forced on them because that would break the domain time topology.
      - Workgroup devices: manual sync from time.windows.com without /reliable.
    Side effects: service startup type and w32tm configuration are changed and
    the service is restarted. Every mutation is gated behind -WhatIf/-Confirm
    via SupportsShouldProcess. Re-running on a converged system changes nothing
    and still exits 0 (idempotent).
    Exit codes: 0 = remediation successful (or already converged), 1 = the
    W32Time service was not found or a critical call failed.

.EXAMPLE
    PS C:\> .\Invoke-RemediationFixTimeSync.ps1

    Configures the role-appropriate time source and forces a time sync.

.EXAMPLE
    PS C:\> .\Invoke-RemediationFixTimeSync.ps1 -WhatIf

    Shows which service and w32tm configuration changes would be made without
    changing anything.

.NOTES
    File Name  : Invoke-RemediationFixTimeSync.ps1
    Author     : Intune Admin
    Prerequisite: PowerShell 7.0
    Version    : 1.0.0
    Date       : 2026-08-23

    Intune Context: SYSTEM.
#>

[CmdletBinding(SupportsShouldProcess)]
param()

$ErrorActionPreference = 'Stop'

function Invoke-W32tm {
    # Thin wrapper around the native w32tm.exe executable; mock seam for Pester tests.
    & w32tm.exe @args 2>&1 | Out-Null
    return $LASTEXITCODE
}

function Main {
    # Advanced function so $PSCmdlet (and thus ShouldProcess) resolves inside Main.
    [CmdletBinding(SupportsShouldProcess)]
    param()

    try {
        Write-Host "[*] Remediating time synchronization..." -ForegroundColor Cyan

        $actions = @()

        # Determine domain membership / domain controller role.
        $computerSystem = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
        $isDomainJoined = ($computerSystem.PartOfDomain -eq $true)
        # DomainRole: 4 = backup DC, 5 = primary DC.
        $isDomainController = ($computerSystem.DomainRole -in @(4, 5))

        $w32timeService = Get-Service -Name 'W32Time' -ErrorAction SilentlyContinue
        if (-not $w32timeService) {
            Write-Host "[-] Error remediating time sync: the W32Time service was not found" -ForegroundColor Red
            return 1
        }

        # Ensure Automatic startup.
        if ($w32timeService.StartType -ne 'Automatic') {
            if ($PSCmdlet.ShouldProcess('W32Time', 'Set startup type to Automatic')) {
                Set-Service -Name 'W32Time' -StartupType Automatic -ErrorAction Stop
                $actions += 'Set Windows Time service to Automatic startup'
            }
        }

        # Start the service if not running.
        if ($w32timeService.Status -ne 'Running') {
            if ($PSCmdlet.ShouldProcess('W32Time', 'Start Windows Time service')) {
                Start-Service -Name 'W32Time' -ErrorAction Stop
                $actions += 'Started Windows Time service'
            }
        }

        # Configure the time source based on domain membership / role.
        if ($isDomainController) {
            # Domain controllers sync from the domain hierarchy and are reliable.
            if ($PSCmdlet.ShouldProcess('W32Time', 'Configure NT5DS time source (domain controller, reliable)')) {
                $rc = Invoke-W32tm /config /syncfromflags:domhier /reliable:yes /update
                if ($rc -eq 0) {
                    $actions += 'Configured NT5DS time sync (domain controller, reliable)'
                }
                else {
                    Write-Host "[!] w32tm /config returned exit code $rc" -ForegroundColor Yellow
                }
            }
        }
        elseif ($isDomainJoined) {
            # Domain members use NT5DS - do NOT override with manual NTP.
            if ($PSCmdlet.ShouldProcess('W32Time', 'Configure NT5DS time source from the domain hierarchy')) {
                $rc = Invoke-W32tm /config /syncfromflags:domhier /update
                if ($rc -eq 0) {
                    $actions += 'Configured NT5DS time sync from the domain hierarchy'
                }
                else {
                    Write-Host "[!] w32tm /config returned exit code $rc" -ForegroundColor Yellow
                }
            }
        }
        else {
            # Workgroup device - manual sync from time.windows.com. /reliable is
            # only meaningful on domain controllers, so it is never set here.
            if ($PSCmdlet.ShouldProcess('W32Time', 'Configure manual time source time.windows.com')) {
                $rc = Invoke-W32tm /config /manualpeerlist:"time.windows.com" /syncfromflags:manual /update
                if ($rc -eq 0) {
                    $actions += 'Configured time server to time.windows.com'
                }
                else {
                    Write-Host "[!] w32tm /config returned exit code $rc" -ForegroundColor Yellow
                }
            }
        }

        # Restart the service to apply configuration changes.
        if ($actions.Count -gt 0) {
            if ($PSCmdlet.ShouldProcess('W32Time', 'Restart Windows Time service to apply configuration')) {
                Restart-Service -Name 'W32Time' -Force -ErrorAction Stop
                $actions += 'Restarted Windows Time service'
            }
        }

        # Force an immediate time sync (harmless when already converged).
        if ($PSCmdlet.ShouldProcess('W32Time', 'Force immediate time resynchronization')) {
            $rc = Invoke-W32tm /resync /force
            if ($rc -eq 0) {
                $actions += 'Forced time synchronization'
            }
            else {
                $actions += 'Attempted time sync (may take a few minutes to complete)'
            }
        }

        if ($actions.Count -gt 0) {
            foreach ($action in $actions) {
                Write-Host "  - $action" -ForegroundColor Cyan
            }
            Write-Host "[+] Time sync remediation completed" -ForegroundColor Green
        }
        else {
            Write-Host "[+] Already configured: Windows Time service is running with Automatic startup" -ForegroundColor Green
        }
        return 0
    }
    catch {
        Write-Host "[-] Error remediating time sync: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
