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
    } else {
        Write-Host "Not present: $($setting.Name)"
    }
}

Stop-Transcript
exit ($RemediationNeeded -eq $true) ? 1 : 0