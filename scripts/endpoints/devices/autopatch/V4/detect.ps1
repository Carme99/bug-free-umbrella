<#
.SYNOPSIS
    Detect Windows Update policy drift (Autopatch V4)

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
New-Item -Path $TranscriptPath -ItemType Directory -Force | Out-Null

# Stop any orphaned transcript
try { Stop-Transcript | Out-Null } catch {}

Start-Transcript -Path "$TranscriptPath\$TranscriptName" -Append

# Define problematic registry values
# NOTE: "DisableWindowsUpdateAccess" ("Remove access to use all Windows Update features")
# is not supported on Windows 10+ / Server 2016+; the supported WUaaS control is
# NoAutoUpdate under ...\WindowsUpdate\AU (see waas-wu-settings).
$regkeys = @(
    @{ Name = "DoNotConnectToWindowsUpdateInternetLocations"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" },
    @{ Name = "NoAutoUpdate"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" },
    @{ Name = "UseWUServer"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" },
    @{ Name = "WUServer"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" }
)

$RemediationNeeded = $false

foreach ($setting in $regkeys) {
    Write-Host "Checking for $($setting.Name) at $($setting.Path)"
    if ((Get-ItemProperty -Path $setting.Path -ErrorAction SilentlyContinue).PSObject.Properties.Name -contains $setting.Name) {
        Write-Host "Found: $($setting.Name)"
        $RemediationNeeded = $true
    }
    else {
        Write-Host "Not present: $($setting.Name)"
    }
}

Stop-Transcript
exit ($RemediationNeeded -eq $true) ? 1 : 0