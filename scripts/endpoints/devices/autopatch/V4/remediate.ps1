<#
.SYNOPSIS
    Remediate Windows Update policy drift (Autopatch V4)

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
New-Item -Path $TranscriptPath -ItemType Directory -Force | Out-Null

try { Stop-Transcript | Out-Null } catch {}

Start-Transcript -Path "$TranscriptPath\$TranscriptName" -Append

$regkeys = @(
    @{ Name = "DoNotConnectToWindowsUpdateInternetLocations"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" },
    @{ Name = "NoAutoUpdate"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" },
    @{ Name = "UseWUServer"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" },
    @{ Name = "WUServer"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" }
)

foreach ($setting in $regkeys) {
    Write-Host "Checking for $($setting.Name) at $($setting.Path)"
    try {
        if ((Get-ItemProperty -Path $setting.Path -ErrorAction SilentlyContinue).PSObject.Properties.Name -contains $setting.Name) {
            Remove-ItemProperty -Path $setting.Path -Name $setting.Name -Force
            Write-Host "🧹 Removed: $($setting.Name)"
        }
        else {
            Write-Host "Already clean: $($setting.Name)"
        }
    }
    catch {
        Write-Warning "Could not remove $($setting.Name): $_"
    }
}

Stop-Transcript