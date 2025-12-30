<#
.SYNOPSIS
    Backup BitLocker recovery keys to Azure AD

.DESCRIPTION
    Remediates BitLocker volumes by backing up recovery keys to Azure AD.
    Attempts to escrow all recovery keys for encrypted volumes.

.NOTES
    For Intune Proactive Remediations
    Exit 0 = Successfully escrowed keys
    Exit 1 = Failed to escrow keys
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

try {
    # Check if BitLocker module is available
    if (-not (Get-Module -ListAvailable -Name BitLocker)) {
        Write-Host "BitLocker module not available on this system"
        exit 1
    }

    # Get BitLocker volumes
    $bitlockerVolumes = Get-BitLockerVolume -ErrorAction Stop

    if (-not $bitlockerVolumes) {
        Write-Host "No BitLocker volumes found"
        exit 0
    }

    $escrowed = @()
    $failed = @()

    foreach ($vol in $bitlockerVolumes) {
        if ($vol.VolumeStatus -eq 'FullyEncrypted' -or $vol.VolumeStatus -eq 'EncryptionInProgress') {
            $recoveryKeys = $vol.KeyProtector | Where-Object { $_.KeyProtectorType -eq 'RecoveryPassword' }

            foreach ($key in $recoveryKeys) {
                try {
                    # Backup to Azure AD
                    BackupToAAD-BitLockerKeyProtector -MountPoint $vol.MountPoint -KeyProtectorId $key.KeyProtectorId -ErrorAction Stop
                    $escrowed += "$($vol.MountPoint)"
                    Write-Host "Escrowed recovery key for $($vol.MountPoint)"
                } catch {
                    $errorMsg = "Failed to escrow $($vol.MountPoint): $($_.Exception.Message)"
                    Write-Host $errorMsg
                    $failed += $errorMsg
                }
            }
        }
    }

    if ($escrowed.Count -gt 0) {
        Write-Host "Successfully escrowed $($escrowed.Count) BitLocker key(s)"
    }

    if ($failed.Count -gt 0) {
        Write-Host "Failed to escrow $($failed.Count) BitLocker key(s)"
        exit 1
    }

    if ($escrowed.Count -eq 0) {
        Write-Host "No keys needed escrow"
    }

    exit 0

} catch {
    Write-Error "Failed to remediate BitLocker keys: $($_.Exception.Message)"
    Write-Error $_.ScriptStackTrace
    exit 1
}
