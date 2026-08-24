<#
.SYNOPSIS
    Backs up BitLocker recovery keys to Azure AD so they are properly escrowed.

.DESCRIPTION
    Remediates BitLocker volumes by backing up recovery keys to Azure AD. Volumes that have
    no RecoveryPassword key protector first get one added (Add-BitLockerKeyProtector) so
    escrow becomes possible - this converges with the companion detection script, which flags
    exactly that state. This script mutates system state (adds key protectors and backs them
    up to Azure AD); every mutation is gated behind ShouldProcess, so -WhatIf performs a dry
    run and re-running on a fully escrowed device converges to exit 0 (idempotent).
    Exit codes:
    - 0: successfully escrowed keys, or no keys needed escrow.
    - 1: failed to escrow keys, or the BitLocker module is not available.

.EXAMPLE
    PS C:\> .\Invoke-RemediationFixBitLockerNotEscrowedKeys.ps1
    Adds any missing recovery password protectors and escrows all recovery keys to Azure AD.

.EXAMPLE
    PS C:\> .\Invoke-RemediationFixBitLockerNotEscrowedKeys.ps1 -WhatIf
    Shows which volumes would receive new protectors and which keys would be escrowed, without changing anything.

.NOTES
    File Name: Invoke-RemediationFixBitLockerNotEscrowedKeys.ps1
    Author: Intune / Proactive Remediations
    Prerequisite: PowerShell 7.0
    Version: 1.0.0
    Date: 2026-08-23
#>

[CmdletBinding(SupportsShouldProcess)]

$ErrorActionPreference = 'Stop'

function Main {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    try {
        Write-Host "[*] Checking BitLocker volumes for unescrowed recovery keys..." -ForegroundColor Cyan

        # Check if BitLocker module is available
        if (-not (Get-Module -ListAvailable -Name BitLocker)) {
            Write-Host "[!] BitLocker module not available on this system" -ForegroundColor Yellow
            return 1
        }

        # Get BitLocker volumes
        $bitlockerVolumes = Get-BitLockerVolume -ErrorAction Stop

        if (-not $bitlockerVolumes) {
            Write-Host "[+] No BitLocker volumes found - nothing to remediate" -ForegroundColor Green
            return 0
        }

        $escrowed = @()
        $failed = @()

        foreach ($vol in $bitlockerVolumes) {
            if ($vol.VolumeStatus -eq 'FullyEncrypted' -or $vol.VolumeStatus -eq 'EncryptionInProgress') {
                $recoveryKeys = @($vol.KeyProtector | Where-Object { $_.KeyProtectorType -eq 'RecoveryPassword' })

                # Escrow can only back up an existing RecoveryPassword protector.
                # If the volume has none (the state detection flags), create one
                # first so the pair converges.
                if ($recoveryKeys.Count -eq 0) {
                    try {
                        if ($PSCmdlet.ShouldProcess($vol.MountPoint, 'Add BitLocker recovery password protector')) {
                            $msg = "[*] Adding recovery password protector for $($vol.MountPoint)"
                            Write-Host $msg -ForegroundColor Cyan
                            $newProtector = Add-BitLockerKeyProtector -MountPoint $vol.MountPoint `
                                -RecoveryPassword -ErrorAction Stop
                            $recoveryKeys = @($newProtector)
                        }
                        else {
                            continue
                        }
                    }
                    catch {
                        $errorMsg = "Failed to add recovery key for $($vol.MountPoint): $($_.Exception.Message)"
                        Write-Host "[-] $errorMsg" -ForegroundColor Red
                        $failed += $errorMsg
                        continue
                    }
                }

                foreach ($key in $recoveryKeys) {
                    try {
                        $target = "$($vol.MountPoint) key $($key.KeyProtectorId)"
                        if ($PSCmdlet.ShouldProcess($target, 'Back up BitLocker recovery key to Azure AD')) {
                            # Backup to Azure AD
                            BackupToAAD-BitLockerKeyProtector -MountPoint $vol.MountPoint `
                                -KeyProtectorId $key.KeyProtectorId -ErrorAction Stop
                            $escrowed += "$($vol.MountPoint)"
                            Write-Host "[+] Escrowed recovery key for $($vol.MountPoint)" -ForegroundColor Green
                        }
                    }
                    catch {
                        $errorMsg = "Failed to escrow $($vol.MountPoint): $($_.Exception.Message)"
                        Write-Host "[-] $errorMsg" -ForegroundColor Red
                        $failed += $errorMsg
                    }
                }
            }
        }

        if ($escrowed.Count -gt 0) {
            Write-Host "[+] Successfully escrowed $($escrowed.Count) BitLocker key(s)" -ForegroundColor Green
        }

        if ($failed.Count -gt 0) {
            Write-Host "[-] Failed to escrow $($failed.Count) BitLocker key(s)" -ForegroundColor Red
            return 1
        }

        if ($escrowed.Count -eq 0) {
            Write-Host "[+] No keys needed escrow" -ForegroundColor Green
        }

        return 0
    }
    catch {
        Write-Host "[-] Failed to remediate BitLocker keys: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
