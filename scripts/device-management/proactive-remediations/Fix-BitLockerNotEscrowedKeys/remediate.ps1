# Backup BitLocker recovery keys to Azure AD
$bitlockerVolumes = Get-BitLockerVolume -ErrorAction SilentlyContinue
$escrowed = @()

foreach($vol in $bitlockerVolumes) {
    if($vol.VolumeStatus -eq 'FullyEncrypted' -or $vol.VolumeStatus -eq 'EncryptionInProgress') {
        $recoveryKeys = $vol.KeyProtector | Where-Object {$_.KeyProtectorType -eq 'RecoveryPassword'}
        
        foreach($key in $recoveryKeys) {
            try {
                # Backup to Azure AD
                BackupToAAD-BitLockerKeyProtector -MountPoint $vol.MountPoint -KeyProtectorId $key.KeyProtectorId
                $escrowed += "$($vol.MountPoint)"
                Write-Host "Escrowed recovery key for $($vol.MountPoint)"
            }
            catch {
                Write-Host "Failed to escrow $($vol.MountPoint): $($_.Exception.Message)"
            }
        }
    }
}

if($escrowed.Count -gt 0) {
    Write-Host "Successfully escrowed $($escrowed.Count) BitLocker keys"
} else {
    Write-Host "No keys escrowed"
}
exit 0
