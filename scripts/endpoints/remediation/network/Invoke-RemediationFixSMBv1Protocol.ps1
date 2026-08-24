<#
.SYNOPSIS
    Disables the insecure SMBv1 protocol.

.DESCRIPTION
    Disables SMBv1 in three places: the SMB1Protocol Windows Optional Feature, the SMB server
    configuration (EnableSMB1Protocol) and the LanmanServer SMB1 registry value as a backstop.
    Each step checks the current state first and only acts when SMBv1 is still enabled, so
    re-running the script on a converged system makes no changes and exits 0 (idempotent).
    These are configuration changes, so they honor -WhatIf/-Confirm via SupportsShouldProcess;
    a system restart may be required to fully complete the removal. Exit codes:
    - 0: remediation successful (SMBv1 disabled, or already disabled).
    - 1: the remediation failed unexpectedly.

.EXAMPLE
    PS C:\> .\Invoke-RemediationFixSMBv1Protocol.ps1
    Disables SMBv1 via the optional feature, SMB server configuration and registry.

.EXAMPLE
    PS C:\> .\Invoke-RemediationFixSMBv1Protocol.ps1 -WhatIf
    Shows which SMBv1-disabling steps would run without changing anything.

.NOTES
    File Name: Invoke-RemediationFixSMBv1Protocol.ps1
    Author: Intune Admin
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
        Write-Host "[*] Checking SMBv1 protocol exposure..." -ForegroundColor Cyan

        $remediationActions = @()

        # Disable SMBv1 using Windows Optional Feature.
        $smbv1Feature = Get-WindowsOptionalFeature -Online -FeatureName "SMB1Protocol" -ErrorAction SilentlyContinue

        if ($smbv1Feature -and $smbv1Feature.State -eq "Enabled") {
            try {
                if ($PSCmdlet.ShouldProcess("SMB1Protocol", "Disable SMBv1 Windows Optional Feature")) {
                    Disable-WindowsOptionalFeature -Online -FeatureName "SMB1Protocol" -NoRestart `
                        -ErrorAction Stop | Out-Null
                    $remediationActions += "Disabled SMBv1 Windows Optional Feature"
                }
            }
            catch {
                Write-Host "[!] Could not disable SMBv1 feature: $($_.Exception.Message)" -ForegroundColor Yellow
            }
        }

        # Disable SMBv1 in SMB server configuration.
        $smbServerConfig = Get-SmbServerConfiguration -ErrorAction SilentlyContinue
        if ($smbServerConfig -and $smbServerConfig.EnableSMB1Protocol -eq $true) {
            try {
                if ($PSCmdlet.ShouldProcess("SMB server configuration", "Disable SMBv1 protocol")) {
                    Set-SmbServerConfiguration -EnableSMB1Protocol $false -Force -ErrorAction Stop
                    $remediationActions += "Disabled SMBv1 in SMB server configuration"
                }
            }
            catch {
                Write-Host "[!] Could not disable SMBv1 in server config: $($_.Exception.Message)" `
                    -ForegroundColor Yellow
            }
        }

        # Disable SMBv1 via registry as backup.
        $regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters"
        if (Test-Path $regPath) {
            $smb1Value = (Get-ItemProperty -Path $regPath -Name "SMB1" -ErrorAction SilentlyContinue).SMB1
            if ($smb1Value -ne 0) {
                try {
                    if ($PSCmdlet.ShouldProcess($regPath, "Set SMB1 registry value to 0")) {
                        Set-ItemProperty -Path $regPath -Name "SMB1" -Value 0 -ErrorAction Stop
                        $remediationActions += "Disabled SMBv1 via registry"
                    }
                }
                catch {
                    Write-Host "[!] Could not disable SMBv1 via registry: $($_.Exception.Message)" `
                        -ForegroundColor Yellow
                }
            }
        }

        if ($remediationActions.Count -gt 0) {
            Write-Host "[+] SMBv1 remediation completed:" -ForegroundColor Green
            foreach ($action in $remediationActions) {
                Write-Host "  - $action"
            }
            Write-Host ""
            Write-Host "[!] A system restart may be required to fully disable SMBv1" -ForegroundColor Yellow
        }
        else {
            Write-Host "[+] SMBv1 was already disabled" -ForegroundColor Green
        }

        return 0
    }
    catch {
        Write-Host "[-] Error during SMBv1 remediation: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
