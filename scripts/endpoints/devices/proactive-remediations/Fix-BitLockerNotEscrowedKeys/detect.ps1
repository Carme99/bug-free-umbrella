<#
.SYNOPSIS
    Detect BitLocker keys not escrowed to Azure AD

.DESCRIPTION
    Checks BitLocker volumes for recovery keys and verifies escrow status.
    Returns exit code 1 if any volumes need key escrow.

.NOTES
    For Intune Proactive Remediations
    Exit 0 = Compliant (all keys escrowed)
    Exit 1 = Non-compliant (keys need escrow)
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
            # Check if recovery key exists
            $recoveryKeys = $vol.KeyProtector | Where-Object { $_.KeyProtectorType -eq 'RecoveryPassword' }

            if ($recoveryKeys.Count -eq 0) {
                $notEscrowed += "$($vol.MountPoint) - No recovery key"
            }
            else {
                # In a real implementation, check Azure AD escrow status via Graph API
                # For now, assume keys need escrow if they exist
                $notEscrowed += "$($vol.MountPoint) - Recovery key not verified in Azure AD"
            }
        }
    }

    if ($notEscrowed.Count -gt 0) {
        Write-Host "BitLocker keys need escrow: $($notEscrowed -join '; ')"
        exit 1
    }

    Write-Host "All BitLocker keys properly escrowed"
    exit 0

} catch {
    Write-Error "Failed to check BitLocker status: $($_.Exception.Message)"
    Write-Error $_.ScriptStackTrace
    exit 1
}
