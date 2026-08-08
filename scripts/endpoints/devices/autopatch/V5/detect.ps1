<#
.SYNOPSIS
    Detect Windows Update policy drift (Autopatch V5)

.DESCRIPTION
    Checks the registry for the Windows Update policies DoNotConnectToWindowsUpdateInternetLocations, NoAutoUpdate, WUServer and UseWUServer (the supported WUaaS controls; DisableWindowsUpdateAccess is unsupported on Windows 10+ / Server 2016+). Exits 1 when drift is found so the paired remediation can remove the values. Logs via Start-Transcript.

.EXAMPLE
    ./detect.ps1

.NOTES
    File Name  : detect.ps1
    Author     : Intune / Proactive Remediations
    Prerequisite: PowerShell 5.1 or later, run in the Intune Proactive Remediation context
    Version    : 1.0.0
    Date       : 2026-08-08
#>

$TranscriptPath = "C:\ProgramData\Microsoft\IntuneManagementExtension\Logs"
$TranscriptName = "AutoPatchDetection.log"
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

$RemediationNeeded = $false

foreach ($setting in $regkeys) {
    Write-Host "Checking $($setting.Name)"
    if ((Get-Item $setting.Path -ErrorAction Ignore).Property -contains $setting.Name) {
        Write-Host "$($setting.Name) is present and should be removed"
        $RemediationNeeded = $true
    }
}

Stop-Transcript

if ($RemediationNeeded) {
    exit 1
}
else {
    exit 0
}