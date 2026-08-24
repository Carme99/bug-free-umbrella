<#
.SYNOPSIS
    Back up BitLocker recovery keys to Azure AD

.DESCRIPTION
    Intune Proactive Remediation remediation script for BitLocker key escrow. Enumerates all BitLocker volumes,
    backs up
    every RecoveryPassword key protector to Azure AD, and reports per-volume status.

    Idempotent check-then-act: re-running on a converged system simply re-confirms escrow without changing
    state. Exits
    0 when every key protector is escrowed successfully and 1 when any key fails to escrow so Intune reports the
    remediation as failed.

.EXAMPLE
    PS C:\> .\Fix_BitLockerKeyBackup.ps1

    Backs up all BitLocker recovery keys to Azure AD; exits 0 on success or 1 on any escrow failure.

.EXAMPLE
    PS C:\> .\Fix_BitLockerKeyBackup.ps1 -WhatIf

    Shows which BitLocker recovery keys would be backed up without backing them up.

.NOTES
    File Name  : Fix_BitLockerKeyBackup.ps1
    Author     : Intune / Proactive Remediations
    Prerequisite: PowerShell 5.1+
    Version    : 1.0.0
    Date       : 2026-08-23

    Run as administrator/SYSTEM on Windows with the BitLocker management cmdlets available.
    The Azure AD escrow call is gated behind ShouldProcess, so -WhatIf previews every backup without performing it.
#>

[CmdletBinding(SupportsShouldProcess)]
param()

$ErrorActionPreference = 'Stop'

# PSScriptAnalyzer: Write-Host with prefix/color output is mandated by docs/RELAUNCH-SPEC.md section 3.

function Backup-BitLockerKeyToAAD {
    <#
    .SYNOPSIS
        Backs up BitLocker recovery keys to Azure Active Directory (AAD).

    .DESCRIPTION
        Retrieves the BitLocker volumes of the local computer and attempts to back up each RecoveryPassword key
        protector to
        Azure AD. Returns 0 when every key protector is escrowed and 1 when any key fails so Intune reports the
        remediation
        as failed.

    .EXAMPLE
        PS C:\> Backup-BitLockerKeyToAAD

    .NOTES
        Run this script as an administrator.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param ()

    begin {
        Write-Host "[*] Starting BitLocker Key Backup process to Azure AD." -ForegroundColor Cyan
        $script:BackupFailed = $false
    }

    process {
        try {
# Get BitLocker volumes.
            $BitLockerVolumes = Get-BitLockerVolume -ErrorAction Stop

            $volumeInfoArray = @()

            foreach ($BitLockerVolume in $BitLockerVolumes) {
# Construct a single string per volume with type, mount point, status, percentage, and protector type.
                $v = $BitLockerVolume
                $volumeInfo = "Volume Type: $($v.VolumeType), Mount Point: $($v.MountPoint), " +
                    "Volume Status: $($v.VolumeStatus), Encryption Percentage: $($v.EncryptionPercentage), " +
                    "KeyProtector Type: $($v.KeyProtector[0].KeyProtectorType)"

                $volumeInfoArray += $volumeInfo

# Get KeyProtector IDs for the BitLocker volume.
                $KeyProtectorIds = $BitLockerVolume.KeyProtector |
                    Where-Object { $_.KeyProtectorType -eq 'RecoveryPassword' } |
                    Select-Object -ExpandProperty KeyProtectorID

                foreach ($KeyProtectorId in $KeyProtectorIds) {
# Back up the BitLocker key to Azure AD.
                    try {
                        $target = "volume $($BitLockerVolume.MountPoint) key protector $($KeyProtectorId)"
                        if ($PSCmdlet.ShouldProcess($target, 'Back up BitLocker recovery key to Azure AD')) {
                            BackupToAAD-BitLockerKeyProtector -MountPoint $BitLockerVolume.MountPoint `
                                -KeyProtectorId $KeyProtectorId -ErrorAction Stop
                            Write-Host "[+] Backed up BitLocker Key for volume $($v.MountPoint)." -ForegroundColor Green
                        }
                    }
                    catch {
                        Write-Host "[-] Failed to backup key for volume $($v.MountPoint): $_" -ForegroundColor Red
                        $script:BackupFailed = $true
                    }
                }
            }

# Output all drive info as a single string, with each drive separated by a dot.
            $driveInfoString = $volumeInfoArray -join '. '
        }
        catch {
            Write-Host "[-] Failed to backup BitLocker Key to Azure AD: $_" -ForegroundColor Red
            $script:BackupFailed = $true
            $driveInfoString = ""
        }
    }

    end {
        Write-Host "[*] BitLocker Key Backup process to Azure AD completed." -ForegroundColor Cyan
        Write-Host $driveInfoString

# Escrow failure must yield a non-zero result so Intune does not report success.
        if ($script:BackupFailed) {
            return 1
        }
        return 0
    }
}

function Main {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    try {
        return (Backup-BitLockerKeyToAAD)
    }
    catch {
        Write-Host "[-] Error: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
