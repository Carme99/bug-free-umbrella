<#
.SYNOPSIS
    Detect Windows Update policy drift (Autopatch V2)

.DESCRIPTION
    Checks the registry for the Windows Update policies DoNotConnectToWindowsUpdateInternetLocations and
    NoAutoUpdate. DisableWindowsUpdateAccess is unsupported on Windows 10+ / Server 2016+, so this pair manages
    the supported WUaaS controls instead.
    Intune Proactive Remediation detection script: exits 1 when any managed value is present (drift, remediation
    needed) and 0 when the device is compliant. Logs to the Intune Management Extension log directory via
    Start-Transcript.
    See https://learn.microsoft.com/en-us/windows/deployment/update/waas-wu-settings

.EXAMPLE
    PS C:\> .\AP_Detection.ps1

    Runs the detection; exit 0 means compliant, exit 1 means drift was found.

.EXAMPLE
    PS C:\> .\AP_Detection.ps1 -Verbose

    Runs the detection with verbose preference enabled.

.NOTES
    File Name  : AP_Detection.ps1
    Author     : Intune / Proactive Remediations
    Prerequisite: PowerShell 5.1+
    Version    : 1.0.0
    Date       : 2026-08-23
#>

[CmdletBinding()]
param()

# PSScriptAnalyzer: Write-Host with prefix/color output is mandated by docs/RELAUNCH-SPEC.md section 3.

$ErrorActionPreference = 'Stop'

$TranscriptPath = 'C:\ProgramData\Microsoft\IntuneManagementExtension\Logs'
$TranscriptName = 'AutoPatchDetection.log'

$regkeys = @(
    @{ Name = 'DoNotConnectToWindowsUpdateInternetLocations'
       Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' },
    @{ Name = 'NoAutoUpdate'
       Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' }
)

function Start-DetectionLog {
# Opens the Intune transcript, stopping any orphaned session first.
    # PSSA justification: New-Item only creates the Intune log directory; non-destructive and idempotent.
    New-Item -Path $TranscriptPath -ItemType Directory -Force -ErrorAction Stop | Out-Null
    try { Stop-Transcript | Out-Null } catch { Write-Verbose 'No active transcript to stop' }
    Start-Transcript -Path "$TranscriptPath\$TranscriptName" -Append -ErrorAction Stop
}

function Main {
    try {
        Start-DetectionLog
        $remediationNeeded = $false
        foreach ($setting in $regkeys) {
            Write-Host "[*] Checking $($setting.Name)" -ForegroundColor Cyan
            if ((Get-Item -Path $setting.Path -ErrorAction Ignore).Property -contains $setting.Name) {
                Write-Host "[!] $($setting.Name) is present and should be removed." -ForegroundColor Yellow
                $remediationNeeded = $true
            }
        }
        Stop-Transcript
        if ($remediationNeeded) {
            return 1
        }
        Write-Host '[+] Registry settings are correct.' -ForegroundColor Green
        return 0
    }
    catch {
        Write-Host "[-] Error: $($_.Exception.Message)" -ForegroundColor Red
        try { Stop-Transcript | Out-Null } catch { Write-Verbose 'No active transcript to stop' }
        return 1
    }
}

if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
