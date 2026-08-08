<#
.SYNOPSIS
    Detects TPM (Trusted Platform Module) issues.

.DESCRIPTION
    Checks if TPM is present, enabled, activated, and owned. TPM is critical
    for BitLocker encryption and Windows security features.

.NOTES
    Author: Intune Admin
    Version: 1.0
    Intune Context: SYSTEM
    Exit 0: TPM is healthy
    Exit 1: Issues detected - remediation needed
#>

try {
    $issues = @()

    # Check if TPM is present
    $tpm = Get-Tpm -ErrorAction SilentlyContinue
    if (-not $tpm) {
        Write-Host "TPM is not present on this device"
        exit 1
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

    # TPM ownership is intentionally NOT checked: since Windows 10 version 1607, Windows
    # automatically initializes and takes ownership of the TPM, so TpmOwned=$false is not a
    # failure. See https://learn.microsoft.com/en-us/windows/security/hardware-security/tpm/initialize-and-configure-ownership-of-the-tpm

    # Check TPM version (TPM 2.0 is preferred)
    $tpmVersion = (Get-WmiObject -Namespace "root\cimv2\Security\MicrosoftTpm" -Class Win32_Tpm -ErrorAction SilentlyContinue).SpecVersion
    if ($tpmVersion) {
        $majorVersion = $tpmVersion.Split(",")[0]
        if ([int]$majorVersion -lt 2) {
            $issues += "TPM version is $tpmVersion (TPM 2.0 is recommended)"
        }
    }

    if ($issues.Count -gt 0) {
        Write-Host "TPM issues detected:"
        foreach ($issue in $issues) {
            Write-Host "  - $issue"
        }
        exit 1
    }

    Write-Host "TPM is healthy and ready (Version: $tpmVersion)"
    exit 0

} catch {
    Write-Host "Error checking TPM status: $_"
    exit 1
}
