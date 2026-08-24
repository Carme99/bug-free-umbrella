<#
.SYNOPSIS
    Detects whether the insecure SMBv1 protocol is enabled on the local device.
.DESCRIPTION
    Runs three complementary checks: the SMB1Protocol optional feature state via
    Get-WindowsOptionalFeature, the EnableSMB1Protocol flag on the SMB server configuration, and
    the LanmanServer SMB1 registry value as a backup. SMBv1 is vulnerable to attacks such as
    WannaCry and must stay disabled for security compliance. This is a read-only detection
    script: it never disables anything itself, so re-running it on a converged system is safe
    (idempotent).
    Exit codes:
    - 0: compliant - SMBv1 is properly disabled across feature, server configuration and registry.
    - 1: non-compliant - SMBv1 is enabled in one or more locations, or the check failed.
.EXAMPLE
    PS C:\> .\Test-RemediationFixSMBv1Protocol.ps1
    Checks feature, SMB server configuration and registry, exiting 1 if SMBv1 is enabled anywhere.
.EXAMPLE
    PS C:\> & 'C:\Program Files\Intune\ProactiveRemediations\Test-RemediationFixSMBv1Protocol.ps1'
    Runs the same check from the Intune Management Extension under the SYSTEM context.
.NOTES
    File Name: Test-RemediationFixSMBv1Protocol.ps1
    Author: Intune Admin
    Prerequisite: PowerShell 7.0
    Version: 1.0.0
    Date: 2026-08-23
#>

[CmdletBinding()]

$ErrorActionPreference = 'Stop'

function Main {
    try {
        Write-Host "[*] Checking whether SMBv1 is enabled..." -ForegroundColor Cyan

        $issues = @()

        # Check if SMBv1 is enabled using Get-WindowsOptionalFeature.
        $smbv1Feature = Get-WindowsOptionalFeature -Online -FeatureName 'SMB1Protocol' -ErrorAction Stop

        if ($smbv1Feature) {
            if ($smbv1Feature.State -eq 'Enabled') {
                $issues += 'SMBv1 Protocol is enabled (security risk)'
            }
        }

        # Check SMB server configuration.
        $smbServerConfig = Get-SmbServerConfiguration -ErrorAction Stop
        if ($smbServerConfig) {
            if ($smbServerConfig.EnableSMB1Protocol -eq $true) {
                $issues += 'SMBv1 is enabled in SMB server configuration'
            }
        }

        # Check registry key as backup; tolerated reads so a missing key is not an issue.
        $regPath = 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters'
        if (Test-Path -Path $regPath -ErrorAction SilentlyContinue) {
            $smb1 = Get-ItemProperty -Path $regPath -Name 'SMB1' -ErrorAction SilentlyContinue
            if ($smb1 -and $smb1.SMB1 -ne 0) {
                $issues += 'SMBv1 is enabled in registry'
            }
        }

        if ($issues.Count -gt 0) {
            Write-Host "[!] SMBv1 security issues detected:" -ForegroundColor Yellow
            foreach ($issue in $issues) {
                Write-Host "[!]   - $issue" -ForegroundColor Yellow
            }
            return 1
        }

        Write-Host "[+] SMBv1 is properly disabled (secure configuration)" -ForegroundColor Green
        return 0
    }
    catch {
        Write-Host "[-] Error checking SMBv1 status: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
