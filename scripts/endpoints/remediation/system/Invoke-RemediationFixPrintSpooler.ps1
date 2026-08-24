<#
.SYNOPSIS
    Repair a stuck or broken Print Spooler service.

.DESCRIPTION
    Stops the Print Spooler service when it is running, clears stuck print jobs
    (*.shd/*.spl) from the spool directory, restores the service to Automatic
    startup and starts it again, verifying that it ends up Running.
    Side effects: the Spooler service is stopped/started, its startup type may be
    changed and stuck print job files are permanently deleted. Every mutating
    step is gated behind -WhatIf/-Confirm via SupportsShouldProcess.
    Re-running on an already-converged system makes no changes and still exits 0
    (idempotent).
    Exit codes: 0 = remediation successful (or already converged), 1 = the
    Spooler service was not found or did not return to Running.

.EXAMPLE
    PS C:\> .\Invoke-RemediationFixPrintSpooler.ps1

    Clears stuck print jobs and restores the Print Spooler service to Running.

.EXAMPLE
    PS C:\> .\Invoke-RemediationFixPrintSpooler.ps1 -WhatIf

    Shows which service actions and spool file deletions would occur without
    changing anything.

.NOTES
    File Name  : Invoke-RemediationFixPrintSpooler.ps1
    Author     : Intune / Proactive Remediations
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
        Write-Host "[*] Remediating Print Spooler..." -ForegroundColor Cyan

        $spoolPath = Join-Path $env:SystemRoot 'System32\spool\PRINTERS'
        $changeCount = 0

        $spoolerService = Get-Service -Name 'Spooler' -ErrorAction SilentlyContinue
        if (-not $spoolerService) {
            Write-Host "[-] Error remediating Print Spooler: the Spooler service was not found" -ForegroundColor Red
            return 1
        }

        # Clear stuck print jobs (*.shd/*.spl) from the spool directory.
        $staleJobs = @()
        if (Test-Path -LiteralPath $spoolPath) {
            $staleJobs = @(Get-ChildItem -LiteralPath $spoolPath -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Extension -in '.shd', '.spl' })
        }
        else {
            # Recreate a missing spool directory so the service can queue again.
            if ($PSCmdlet.ShouldProcess($spoolPath, 'Create missing spool directory')) {
                New-Item -Path $spoolPath -ItemType Directory -Force -ErrorAction Stop | Out-Null
                $changeCount++
            }
        }

        # Stop the service only when there are stuck jobs to remove, so a
        # converged system (clean spool, running service) is left untouched.
        if ($staleJobs.Count -gt 0 -and $spoolerService.Status -eq 'Running') {
            if ($PSCmdlet.ShouldProcess('Spooler', 'Stop Print Spooler service')) {
                Stop-Service -Name 'Spooler' -Force -ErrorAction Stop
                $changeCount++
            }
        }

        foreach ($job in $staleJobs) {
            if ($PSCmdlet.ShouldProcess($job.FullName, 'Delete stuck print job')) {
                Remove-Item -LiteralPath $job.FullName -Force -ErrorAction Stop
                $changeCount++
            }
        }

        # Restore Automatic startup.
        if ($spoolerService.StartType -ne 'Automatic') {
            if ($PSCmdlet.ShouldProcess('Spooler', 'Set startup type to Automatic')) {
                Set-Service -Name 'Spooler' -StartupType Automatic -ErrorAction Stop
                $changeCount++
            }
        }

        # Start the service again.
        if ($spoolerService.Status -ne 'Running') {
            if ($PSCmdlet.ShouldProcess('Spooler', 'Start Print Spooler service')) {
                Start-Service -Name 'Spooler' -ErrorAction Stop
                $changeCount++
            }
        }

        # Verify the service ended up Running.
        $spoolerService = Get-Service -Name 'Spooler' -ErrorAction SilentlyContinue
        if (-not $spoolerService -or $spoolerService.Status -ne 'Running') {
            $finalStatus = 'Missing'
            if ($spoolerService) {
                $finalStatus = $spoolerService.Status
            }
            Write-Host "[-] Error remediating Print Spooler: service did not return to Running (status: $finalStatus)" -ForegroundColor Red
            return 1
        }

        if ($changeCount -eq 0) {
            Write-Host "[+] Already healthy: Print Spooler is running with Automatic startup and a clean spool directory" -ForegroundColor Green
        }
        else {
            Write-Host "[+] Print Spooler remediation completed ($changeCount change(s))" -ForegroundColor Green
        }
        return 0
    }
    catch {
        Write-Host "[-] Error remediating Print Spooler: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
