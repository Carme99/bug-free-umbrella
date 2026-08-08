<#
.SYNOPSIS
    Detect BitLocker volumes missing a recovery password protector

.DESCRIPTION
    Checks BitLocker volumes for a RecoveryPassword key protector. Escrow
    (BackupToAAD-BitLockerKeyProtector) can only back up an existing protector,
    so the actionable non-compliant state is a volume with NO recovery password
    protector. Returns exit code 1 if any volumes need a recovery key.

.NOTES
    For Intune Proactive Remediations
    Exit 0 = Compliant (all volumes have a recovery password protector)
    Exit 1 = Non-compliant (volumes missing a recovery password protector)

    Documented limitation: actual Azure AD escrow status is NOT verified here
    (that requires Graph API access to informationProtection/bitlocker/recoveryKeys).
    A volume whose recovery password exists but was never escrowed to Azure AD
    is not flagged by this script.
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

try {
    # Check if BitLocker module is available
    if (-not (Get-Module -ListAvailable -Name BitLocker)) {
        Write-Host "BitLocker module not available on this system"
        exit 0
    }

    # Get BitLocker volumes
    $bitlockerVolumes = Get-BitLockerVolume -ErrorAction Stop

    if (-not $bitlockerVolumes) {
        Write-Host "No BitLocker volumes found"
        exit 0
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
        Write-Host "BitLocker volumes missing a recovery key: $($notEscrowed -join '; ')"
        exit 1
    }

    Write-Host "All BitLocker volumes have a recovery password protector"
    exit 0

} catch {
    Write-Error "Failed to check BitLocker status: $($_.Exception.Message)"
    Write-Error $_.ScriptStackTrace
    exit 1
}
