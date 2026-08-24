<#
.SYNOPSIS
    Detects TPM (Trusted Platform Module) issues.

.DESCRIPTION
    Checks if TPM is present, enabled, activated, and ready, which is critical for
    BitLocker encryption and Windows security features. TPM ownership is intentionally not
    checked: since Windows 10 version 1607 Windows automatically initializes the TPM, so a
    TpmOwned value of $false is not a failure. This is a read-only detection script: it
    never modifies anything, so re-running it on a healthy device converges to exit 0
    (idempotent).
    Exit codes:
    - 0: compliant - TPM is present, enabled, activated and ready.
    - 1: non-compliant - TPM issues detected or the check failed.

.EXAMPLE
    PS C:\> .\Test-RemediationCheckTPMStatus.ps1
    Runs the TPM check and exits 0 when TPM is healthy, 1 when issues are found.

.EXAMPLE
    PS C:\> & 'C:\Program Files\Intune\ProactiveRemediations\Test-RemediationCheckTPMStatus.ps1'
    Runs the same check from the Intune Management Extension under the SYSTEM context.

.NOTES
    File Name: Test-RemediationCheckTPMStatus.ps1
    Author: Intune Admin
    Prerequisite: PowerShell 7.0
    Version: 1.0.0
    Date: 2026-08-23

    TPM version reference: https://learn.microsoft.com/en-us/windows/security/hardware-security/
    tpm/initialize-and-configure-ownership-of-the-tpm
#>

[CmdletBinding()]

$ErrorActionPreference = 'Stop'

function Main {
    try {
        Write-Host "[*] Checking TPM status..." -ForegroundColor Cyan

        $issues = @()

        # Check if TPM is present
        $tpm = Get-Tpm -ErrorAction SilentlyContinue
        if (-not $tpm) {
            Write-Host "[!] TPM is not present on this device" -ForegroundColor Yellow
            return 1
        }

        # Check if TPM is enabled
        if ($tpm.TpmPresent -eq $false) {
            $issues += "TPM is not present"
        }

        if ($tpm.TpmEnabled -eq $false) {
            $issues += "TPM is not enabled (may require BIOS/UEFI configuration)"
        }

        if ($tpm.TpmActivated -eq $false) {
            $issues += "TPM is not activated"
        }

        # Check if TPM is ready for use
        if ($tpm.TpmReady -eq $false) {
            $issues += "TPM is not ready for use"
        }

        # Check TPM version (TPM 2.0 is preferred)
        $tpmWmi = Get-WmiObject -Namespace "root\cimv2\Security\MicrosoftTpm" -Class Win32_Tpm `
            -ErrorAction SilentlyContinue
        $tpmVersion = $tpmWmi.SpecVersion
        if ($tpmVersion) {
            $majorVersion = $tpmVersion.Split(",")[0]
            if ([int]$majorVersion -lt 2) {
                $issues += "TPM version is $tpmVersion (TPM 2.0 is recommended)"
            }
        }

        if ($issues.Count -gt 0) {
            Write-Host "[!] TPM issues detected:" -ForegroundColor Yellow
            foreach ($issue in $issues) {
                Write-Host "  - $issue" -ForegroundColor Yellow
            }
            return 1
        }

        Write-Host "[+] TPM is healthy and ready (Version: $tpmVersion)" -ForegroundColor Green
        return 0
    }
    catch {
        Write-Host "[-] Error checking TPM status: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
