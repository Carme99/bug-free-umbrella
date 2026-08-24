<#
.SYNOPSIS
    Detects BitLocker volumes missing a recovery password protector.

.DESCRIPTION
    Checks BitLocker volumes for a RecoveryPassword key protector. Escrow
    (BackupToAAD-BitLockerKeyProtector) can only back up an existing protector,
    so the actionable non-compliant state is a volume with NO recovery password
    protector. The companion remediation script adds the missing protector and
    escrows it to Azure AD.
    Exit codes: 0 = compliant (every encrypted volume has a recovery password
    protector, or BitLocker is not available on this system), 1 = non-compliant
    (volumes are missing a recovery password protector, or the check failed).
    This is a read-only detection script: it never modifies anything, so
    re-running it on a converged device converges to exit 0 (idempotent).

    Documented limitation: actual Azure AD escrow status is NOT verified here
    (that requires Graph API access to informationProtection/bitlocker/recoveryKeys).
    A volume whose recovery password exists but was never escrowed to Azure AD
    is not flagged by this script.

.EXAMPLE
    PS C:\> .\Test-RemediationFixBitLockerNotEscrowedKeys.ps1
    Runs the BitLocker check and exits 0 when every encrypted volume has a
    recovery password protector, 1 when any volume is missing one.

.EXAMPLE
    PS C:\> & 'C:\Program Files\Intune\ProactiveRemediations\Test-RemediationFixBitLockerNotEscrowedKeys.ps1'
    Runs the same check from the Intune Management Extension under the SYSTEM context.

.NOTES
    File Name: Test-RemediationFixBitLockerNotEscrowedKeys.ps1
    Author: Bug-Free Umbrella
    Prerequisite: PowerShell 7.0
    Version: 1.0.0
    Date: 2026-08-23

    For Intune Proactive Remediations:
    Exit 0 = Compliant (all volumes have a recovery password protector)
    Exit 1 = Non-compliant (volumes missing a recovery password protector)
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

Set-StrictMode -Version Latest

function Main {
    try {
        Write-Host "[*] Checking BitLocker volumes for recovery password protectors..." -ForegroundColor Cyan

        # Check if BitLocker module is available
        if (-not (Get-Module -ListAvailable -Name BitLocker)) {
            Write-Host "[!] BitLocker module not available on this system" -ForegroundColor Yellow
            return 0
        }

        # Get BitLocker volumes
        $bitlockerVolumes = Get-BitLockerVolume -ErrorAction Stop

        if (-not $bitlockerVolumes) {
            Write-Host "[+] No BitLocker volumes found" -ForegroundColor Green
            return 0
        }

        $notEscrowed = @()

        foreach ($vol in $bitlockerVolumes) {
            if ($vol.VolumeStatus -eq 'FullyEncrypted' -or $vol.VolumeStatus -eq 'EncryptionInProgress') {
                # Check if a RecoveryPassword key protector exists
                $recoveryKeys = @($vol.KeyProtector | Where-Object { $_.KeyProtectorType -eq 'RecoveryPassword' })

                if ($recoveryKeys.Count -eq 0) {
                    # No recovery password protector - remediate.ps1 will add one and
                    # escrow it (escrow can only back up an existing protector)
                    $notEscrowed += "$($vol.MountPoint) - No recovery password protector"
                }
            }
        }

        if ($notEscrowed.Count -gt 0) {
            Write-Host "[!] BitLocker volumes missing a recovery key: $($notEscrowed -join '; ')" `
                -ForegroundColor Yellow
            return 1
        }

        Write-Host "[+] All BitLocker volumes have a recovery password protector" -ForegroundColor Green
        return 0
    }
    catch {
        Write-Host "[-] Error checking BitLocker status: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
