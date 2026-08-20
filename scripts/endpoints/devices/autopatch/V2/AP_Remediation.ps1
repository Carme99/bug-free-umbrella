<#
.SYNOPSIS
    Remediate Windows Update policy drift (Autopatch V2)

.DESCRIPTION
    Removes the Windows Update policies DoNotConnectToWindowsUpdateInternetLocations and NoAutoUpdate from the registry so devices return to the default Windows Update behaviour. Logs via Start-Transcript.

.EXAMPLE
    ./AP_Remediation.ps1

.NOTES
    File Name  : AP_Remediation.ps1
    Author     : Intune / Proactive Remediations
    Prerequisite: PowerShell 5.1 or later, run in the Intune Proactive Remediation context
    Version    : 1.0.0
    Date       : 2026-08-08
#>

$TranscriptPath = "C:\ProgramData\Microsoft\IntuneManagementExtension\Logs"
$TranscriptName = "AutoPatchRemediation.log"
New-Item $TranscriptPath -ItemType Directory -Force

# stopping orphaned transcripts
try {
    Stop-Transcript | Out-Null
}
catch [System.InvalidOperationException] {
    Write-Verbose "No active transcript to stop: $($_.Exception.Message)" -Verbose:$false
}

Start-Transcript -Path $TranscriptPath\$TranscriptName -Append


# initialize the array
[PsObject[]]$regkeys = @()
# populate the array with each object
# NOTE: "DisableWindowsUpdateAccess" ("Remove access to use all Windows Update features")
# is not supported on Windows 10+ / Server 2016+; the supported WUaaS control is
# NoAutoUpdate under ...\WindowsUpdate\AU (see waas-wu-settings).
$regkeys += [PsObject]@{ Name = "DoNotConnectToWindowsUpdateInternetLocations"; path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\" }
$regkeys += [PsObject]@{ Name = "NoAutoUpdate"; path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU\" }

foreach ($setting in $regkeys) {
    Write-Host "checking $($setting.name)"
    if ((Get-Item $setting.path -ErrorAction Ignore).Property -contains $setting.name) {
        Write-Host "remediating $($setting.name)"
        Remove-ItemProperty -Path $setting.path -Name $($setting.name)
    }
    else {
        Write-Host "$($setting.name) was not found"
    }
}
Stop-Transcript