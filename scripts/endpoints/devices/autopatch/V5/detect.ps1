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
} else {
    exit 0
}