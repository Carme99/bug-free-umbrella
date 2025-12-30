# Remediate security baseline issues
$remediated = @()

# Enable Windows Firewall
$firewallProfiles = Get-NetFirewallProfile
foreach($profile in $firewallProfiles) {
    if(-not $profile.Enabled) {
        Set-NetFirewallProfile -Profile $profile.Name -Enabled True
        $remediated += "Enabled $($profile.Name) firewall profile"
    }
}

# Enable Windows Defender Real-Time Protection
$defenderStatus = Get-MpComputerStatus -ErrorAction SilentlyContinue
if($defenderStatus -and -not $defenderStatus.RealTimeProtectionEnabled) {
    Set-MpPreference -DisableRealtimeMonitoring $false
    $remediated += "Enabled real-time protection"
}

# Update Defender signatures
Update-MpSignature -ErrorAction SilentlyContinue
$remediated += "Updated antivirus signatures"

# Enable UAC
$uacKey = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -ErrorAction SilentlyContinue
if($uacKey.EnableLUA -ne 1) {
    Set-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "EnableLUA" -Value 1
    $remediated += "Enabled UAC"
}

if($remediated.Count -gt 0) {
    Write-Host "Remediated $($remediated.Count) issues: $($remediated -join '; ')"
} else {
    Write-Host "No remediation needed"
}
exit 0
