<#
.SYNOPSIS
    Detect Windows Update policy drift (Autopatch V2)

.DESCRIPTION
    Checks the registry for the Windows Update policies DoNotConnectToWindowsUpdateInternetLocations and NoAutoUpdate (the supported WUaaS controls; DisableWindowsUpdateAccess is unsupported on Windows 10+ / Server 2016+). Exits 1 when drift is found so the paired remediation can remove the values. Logs via Start-Transcript.

.EXAMPLE
    ./AP_Detection.ps1

.NOTES
    File Name  : AP_Detection.ps1
    Author     : Intune / Proactive Remediations
    Prerequisite: PowerShell 5.1 or later, run in the Intune Proactive Remediation context
    Version    : 1.0.0
    Date       : 2026-08-08
#>

$TranscriptPath = "C:\ProgramData\Microsoft\IntuneManagementExtension\Logs"
$TranscriptName = "AutoPatchDetection.log"
New-Item $TranscriptPath -ItemType Directory -Force

# stopping orphaned transcripts
try {
    Stop-Transcript | Out-Null
}
catch [System.InvalidOperationException]
{}

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
        Write-Host "$($setting.name) is not correct"
        $RemediationNeeded = $true
    }
}


if ($RemediationNeeded -eq $true) {
    Write-Host "registry settings are incorrect"
    Stop-Transcript
    exit 1
}
else {
    Write-Host "registry settings are correct"
    Stop-Transcript
    exit 0
}