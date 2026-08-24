<#
.SYNOPSIS
    Remediate Windows Update policy drift (Autopatch V4)

.DESCRIPTION
    Removes the Windows Update policies DoNotConnectToWindowsUpdateInternetLocations, NoAutoUpdate, UseWUServer
    and WUServer from the registry so devices return to default Windows Update behaviour.
    Idempotent check-then-act: values that are already absent are left untouched. Destructive registry removals
    are gated behind -WhatIf/-Confirm. Logs to the Intune Management Extension log directory via
    Start-Transcript.
    Intune Proactive Remediation remediation script; exits 0 on success (including already-compliant devices)
    and 1 on failure.

.EXAMPLE
    PS C:\> .\remediate.ps1

    Removes the managed policy values where present; exits 0.

.EXAMPLE
    PS C:\> .\remediate.ps1 -WhatIf

    Shows which registry values would be removed without changing anything.

.NOTES
    File Name  : remediate.ps1
    Author     : Intune / Proactive Remediations
    Prerequisite: PowerShell 5.1+
    Version    : 1.0.0
    Date       : 2026-08-23
#>

[CmdletBinding(SupportsShouldProcess)]
param()

# PSScriptAnalyzer: Write-Host with prefix/color output is mandated by docs/RELAUNCH-SPEC.md section 3.

$ErrorActionPreference = 'Stop'

$TranscriptPath = 'C:\ProgramData\Microsoft\IntuneManagementExtension\Logs'
$TranscriptName = 'AutoPatchRemediation.log'

$regkeys = @(
    @{ Name = 'DoNotConnectToWindowsUpdateInternetLocations'
       Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' },
    @{ Name = 'NoAutoUpdate'
       Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' },
    @{ Name = 'UseWUServer'
       Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' },
    @{ Name = 'WUServer'
       Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' }
)

function Start-RemediationLog {
# Opens the Intune transcript, stopping any orphaned session first.
    # PSSA justification: New-Item only creates the Intune log directory; non-destructive and idempotent.
    New-Item -Path $TranscriptPath -ItemType Directory -Force -ErrorAction Stop | Out-Null
    try { Stop-Transcript | Out-Null } catch { Write-Verbose 'No active transcript to stop' }
    Start-Transcript -Path "$TranscriptPath\$TranscriptName" -Append -ErrorAction Stop
}

function Main {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    try {
        Start-RemediationLog
        foreach ($setting in $regkeys) {
            Write-Host "[*] Checking $($setting.Name) at $($setting.Path)" -ForegroundColor Cyan
            $existing = Get-ItemProperty -Path $setting.Path -ErrorAction SilentlyContinue
            if ($existing.PSObject.Properties.Name -contains $setting.Name) {
                if ($PSCmdlet.ShouldProcess("$($setting.Path)::$($setting.Name)", 'Remove registry value')) {
                    Remove-ItemProperty -Path $setting.Path -Name $setting.Name -Force -ErrorAction Stop
                    Write-Host "[+] Removed: $($setting.Name)" -ForegroundColor Green
                }
            }
            else {
                Write-Host "[+] Already clean: $($setting.Name)" -ForegroundColor Green
            }
        }
        Stop-Transcript
        return 0
    }
    catch {
        Write-Host "[-] Error: $($_.Exception.Message)" -ForegroundColor Red
        try { Stop-Transcript | Out-Null } catch { Write-Verbose 'No active transcript to stop' }
        return 1
    }
}

if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
