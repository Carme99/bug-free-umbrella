<#
.SYNOPSIS
    Check the Windows activation grace period and license status.

.DESCRIPTION
    Queries the SoftwareLicensingProduct WMI class for the installed Windows edition
    and flags devices that are unlicensed, in a grace or notification mode, whose
    grace period expires within 30 days, or whose evaluation end date is due within
    30 days. Intended to run in SYSTEM context via Intune Proactive Remediations so
    activation problems are caught before devices lose compliance.
    Exit codes: 0 = compliant/healthy (activation is valid), 1 = issue detected
    (grace period or expiration warning, or an unexpected error occurred). The script
    changes no system state, so it is idempotent.

.EXAMPLE
    PS C:\> .\Test-RemediationCheckWindowsActivationGracePeriod.ps1

    Exits 0 when Windows activation is valid; exits 1 when a grace period or
    expiration warning is detected.

.EXAMPLE
    PS C:\> .\Test-RemediationCheckWindowsActivationGracePeriod.ps1 -Verbose

    Runs the same read-only analysis with verbose pipeline output for troubleshooting.

.NOTES
    File Name  : Test-RemediationCheckWindowsActivationGracePeriod.ps1
    Author     : Intune Admin
    Prerequisite: PowerShell 7.0
    Version    : 1.0.0
    Date       : 2026-08-23
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

function Main {
    param()

    try {
        $issues = @()

        Write-Host "[*] Checking Windows activation status..." -ForegroundColor Cyan

        # Get licensing information for the Windows operating system class
        $licensingStatus = Get-CimInstance -ClassName SoftwareLicensingProduct `
            -Filter "ApplicationID='55c92734-d682-4d71-983e-d6ec3f16059f' AND PartialProductKey <> null" `
            -ErrorAction SilentlyContinue |
            Select-Object -First 1

        if ($licensingStatus) {
            $licenseStatus = $licensingStatus.LicenseStatus
            $gracePeriodRemaining = $licensingStatus.GracePeriodRemaining

            # License Status: 0=Unlicensed, 1=Licensed, 2=OOBGrace, 3=OOTGrace, 4=NonGenuineGrace, 5=Notification, 6=ExtendedGrace
            switch ($licenseStatus) {
                0 { $issues += "Windows is unlicensed" }
                2 { $issues += "Windows is in Out-of-Box grace period" }
                3 { $issues += "Windows is in Out-of-Tolerance grace period" }
                4 { $issues += "Windows is in non-genuine grace period" }
                5 { $issues += "Windows is in notification mode" }
                6 { $issues += "Windows is in extended grace period" }
            }

            # Check grace period remaining (in minutes)
            if ($gracePeriodRemaining -gt 0) {
                $daysRemaining = [math]::Round($gracePeriodRemaining / 1440, 1)
                if ($daysRemaining -le 30) {
                    $issues += "Grace period expires in $daysRemaining days"
                }
            }

            # Check evaluation end date (Get-CimInstance converts DMTF datetimes to DateTime)
            if ($licensingStatus.EvaluationEndDate) {
                $evalEndDate = $licensingStatus.EvaluationEndDate
                if ($evalEndDate -isnot [datetime]) {
                    $evalEndDate = [Management.ManagementDateTimeConverter]::ToDateTime($evalEndDate)
                }

                $daysUntilExpiry = ($evalEndDate - (Get-Date)).Days

                if ($daysUntilExpiry -le 30 -and $daysUntilExpiry -gt 0) {
                    $issues += "Evaluation expires in $daysUntilExpiry days"
                }
            }
        }
        else {
            Write-Host "[!] No activated Windows licensing product found" -ForegroundColor Yellow
        }

        if ($issues.Count -gt 0) {
            Write-Host "[!] Windows activation grace period warnings:" -ForegroundColor Yellow
            foreach ($issue in $issues) {
                Write-Host "[!]   - $issue" -ForegroundColor Yellow
            }
            return 1
        }

        Write-Host "[+] Windows activation is valid" -ForegroundColor Green
        return 0
    }
    catch {
        Write-Host "[-] Error checking activation grace period: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
