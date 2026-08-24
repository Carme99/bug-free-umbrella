<#
.SYNOPSIS
    Restart stopped critical services and log failures for IT review.

.DESCRIPTION
    Iterates a list of critical services (Windows Update, BITS, Winmgmt, DHCP Client,
    DNS Client) and attempts to start any service that is stopped but not disabled.
    Side effects: each start attempt is a system state change gated behind
    -WhatIf/-Confirm via SupportsShouldProcess. Services that cannot be started, as
    well as the underlying stability guidance, are logged for IT investigation.
    Re-running on an already-converged system finds every critical service running,
    makes no changes and exits 0 (idempotent).
    Exit codes: 0 = services running or remediated/logged for review, 1 = unexpected error.
    Intune Context: SYSTEM.

.EXAMPLE
    PS C:\> .\Invoke-RemediationCheckServiceFailures.ps1

    Starts every stopped critical service that is not disabled and prints the actions taken.

.EXAMPLE
    PS C:\> .\Invoke-RemediationCheckServiceFailures.ps1 -WhatIf

    Reports which services would be started without starting anything.

.NOTES
    File Name  : Invoke-RemediationCheckServiceFailures.ps1
    Author     : Intune Admin
    Prerequisite: PowerShell 7.0
    Version    : 1.0.0
    Date       : 2026-08-23
#>

[CmdletBinding(SupportsShouldProcess)]
param()

$ErrorActionPreference = 'Stop'

function Main {
    # Advanced function so $PSCmdlet (and thus ShouldProcess) resolves inside Main.
    [CmdletBinding(SupportsShouldProcess)]
    param()

    try {
        Write-Host "[*] Service failure remediation..." -ForegroundColor Cyan

        $remediationActions = @()
        $stoppedCount = 0

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
                $stoppedCount++
                Write-Host "[*] Attempting to start $svcName..." -ForegroundColor Cyan

                if ($PSCmdlet.ShouldProcess($svcName, "Start stopped critical service")) {
                    try {
                        Start-Service -Name $svcName -ErrorAction Stop
                        $remediationActions += "Started service: $svcName"
                        Write-Host "[+] Successfully started $svcName" -ForegroundColor Green
                    }
                    catch {
                        $remediationActions += "Failed to start service: $svcName - $($_.Exception.Message)"
                        Write-Host "[!] Failed to start ${svcName}: $($_.Exception.Message)" -ForegroundColor Yellow
                    }
                }
            }
        }

        if ($stoppedCount -eq 0) {
            Write-Host "[+] Already compliant: all critical services are running" -ForegroundColor Green
        }
        else {
            Write-Host "[*] Recurring service failures detected on this device." -ForegroundColor Cyan
            Write-Host ""
            Write-Host "[*] Common causes:" -ForegroundColor Cyan
            Write-Host "    - Application bugs or crashes"
            Write-Host "    - Insufficient system resources"
            Write-Host "    - Dependency service failures"
            Write-Host "    - Corrupted service configuration"
            Write-Host "    - Permission or security issues"
            Write-Host ""
            Write-Host "[*] IT should investigate:" -ForegroundColor Cyan
            Write-Host "    1. Review service event logs"
            Write-Host "    2. Check application error logs"
            Write-Host "    3. Verify service dependencies"
            Write-Host "    4. Update or reinstall problematic software"
            Write-Host "    5. Check system resource availability"
        }

        if ($remediationActions.Count -gt 0) {
            Write-Host ""
            Write-Host "[*] Remediation actions taken:" -ForegroundColor Cyan
            foreach ($action in $remediationActions) {
                Write-Host "    - $action"
            }
        }

        Write-Host ""
        Write-Host "[*] Device: $env:COMPUTERNAME" -ForegroundColor Cyan

        return 0
    }
    catch {
        Write-Host "[-] Error during service failure remediation: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
