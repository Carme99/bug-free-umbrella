<#
.SYNOPSIS
    Remediate Windows Update policy drift (Autopatch V5)

.DESCRIPTION
    Removes the Windows Update policies DoNotConnectToWindowsUpdateInternetLocations, NoAutoUpdate, WUServer and UseWUServer from the registry so devices return to the default Windows Update behaviour. Logs via Start-Transcript.

.EXAMPLE
    ./remediate.ps1

.NOTES
    File Name  : remediate.ps1
    Author     : Intune / Proactive Remediations
    Prerequisite: PowerShell 5.1 or later, run in the Intune Proactive Remediation context
    Version    : 1.0.0
    Date       : 2026-08-08
#>

$TranscriptPath = "C:\ProgramData\Microsoft\IntuneManagementExtension\Logs"
$TranscriptName = "AutoPatchRemediation.log"
New-Item $TranscriptPath -ItemType Directory -Force | Out-Null

# Stop any orphaned transcripts
try { Stop-Transcript | Out-Null } catch [System.InvalidOperationException] {}

Start-Transcript -Path "$TranscriptPath\$TranscriptName" -Append

# Initialize the array
# NOTE: "DisableWindowsUpdateAccess" ("Remove access to use all Windows Update features")
# is not supported on Windows 10+ / Server 2016+; the supported WUaaS control is
# NoAutoUpdate under ...\WindowsUpdate\AU (see waas-wu-settings).
[PsObject[]]$regkeys = @(
    @{ Name = "DoNotConnectToWindowsUpdateInternetLocations"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\" },
    @{ Name = "NoAutoUpdate"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU\" },
    @{ Name = "WUServer"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\" },
    @{ Name = "UseWUServer"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU\" }
)

foreach ($setting in $regkeys) {
    Write-Host "Checking $($setting.Name)"
    if ((Get-Item $setting.Path -ErrorAction Ignore).Property -contains $setting.Name) {
        Write-Host "Removing $($setting.Name)"
        Remove-ItemProperty -Path $setting.Path -Name $setting.Name -ErrorAction SilentlyContinue
    }
    else {
        Write-Host "$($setting.Name) not found"
    }
}

Stop-Transcript