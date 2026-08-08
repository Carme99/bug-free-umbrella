$TranscriptPath = "C:\ProgramData\Microsoft\IntuneManagementExtension\Logs"
$TranscriptName = "AutoPatchDetection.log"
New-Item -Path $TranscriptPath -ItemType Directory -Force | Out-Null

try { Stop-Transcript | Out-Null } catch {}

Start-Transcript -Path "$TranscriptPath\$TranscriptName" -Append

$RemediationNeeded = $false

# Define registry keys to check
# NOTE: "DisableWindowsUpdateAccess" ("Remove access to use all Windows Update features")
# is not supported on Windows 10+ / Server 2016+; the supported WUaaS control is
# NoAutoUpdate under ...\WindowsUpdate\AU (see waas-wu-settings).
$regkeys = @(
    @{ Name = "DoNotConnectToWindowsUpdateInternetLocations"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\" },
    @{ Name = "NoAutoUpdate"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU\" }
)

foreach ($setting in $regkeys) {
    Write-Host "Checking $($setting.Name)"
    if ((Get-Item $setting.Path -ErrorAction Ignore).Property -contains $setting.Name) {
        Write-Host "$($setting.Name) exists and should not"
        $RemediationNeeded = $true
    }
}

Stop-Transcript

if ($RemediationNeeded) {
    exit 1  # Remediation needed
} else {
    exit 0  # All clear
}
