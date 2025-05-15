$TranscriptPath = "C:\ProgramData\Microsoft\IntuneManagementExtension\Logs"
$TranscriptName = "AutoPatchRemediation.log"
New-Item -Path $TranscriptPath -ItemType Directory -Force | Out-Null

try { Stop-Transcript | Out-Null } catch {}

Start-Transcript -Path "$TranscriptPath\$TranscriptName" -Append

$regkeys = @(
    @{ Name = "DoNotConnectToWindowsUpdateInternetLocations"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" },
    @{ Name = "DisableWindowsUpdateAccess"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" },
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
        } else {
            Write-Host "Already clean: $($setting.Name)"
        }
    } catch {
        Write-Warning "Could not remove $($setting.Name): $_"
    }
}

Stop-Transcript