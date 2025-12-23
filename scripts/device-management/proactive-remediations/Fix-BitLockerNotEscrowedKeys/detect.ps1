# Detect BitLocker keys not escrowed to Azure AD
$bitlockerVolumes = Get-BitLockerVolume -ErrorAction SilentlyContinue

if(-not $bitlockerVolumes) {
    Write-Host "No BitLocker volumes found"
    exit 0
}

$notEscrowed = @()

foreach($vol in $bitlockerVolumes) {
    if($vol.VolumeStatus -eq 'FullyEncrypted' -or $vol.VolumeStatus -eq 'EncryptionInProgress') {
        # Check if recovery key exists
        $recoveryKeys = $vol.KeyProtector | Where-Object {$_.KeyProtectorType -eq 'RecoveryPassword'}
        
        if($recoveryKeys.Count -eq 0) {
            $notEscrowed += "$($vol.MountPoint) - No recovery key"
        }
        else {
            # In a real implementation, check Azure AD escrow status via Graph API
            # For now, assume keys need escrow if they exist
            $notEscrowed += "$($vol.MountPoint) - Recovery key not verified in Azure AD"
        }
    }
}

if($notEscrowed.Count -gt 0) {
    Write-Host "BitLocker keys need escrow: $($notEscrowed -join '; ')"
    exit 1
}

Write-Host "All BitLocker keys properly escrowed"
exit 0
