# Detect security baseline drift
$issues = @()

# Check Windows Firewall
$firewallProfiles = Get-NetFirewallProfile
foreach($profile in $firewallProfiles) {
    if(-not $profile.Enabled) {
        $issues += "Firewall $($profile.Name) profile is disabled"
    }
}

# Check Windows Defender
$defenderStatus = Get-MpComputerStatus -ErrorAction SilentlyContinue
if($defenderStatus) {
    if(-not $defenderStatus.RealTimeProtectionEnabled) {
        $issues += "Real-time protection disabled"
    }
    if($defenderStatus.AntivirusSignatureAge -gt 7) {
        $issues += "Antivirus signatures outdated ($($defenderStatus.AntivirusSignatureAge) days)"
    }
}

# Check UAC
$uacKey = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -ErrorAction SilentlyContinue
if($uacKey.EnableLUA -ne 1) {
    $issues += "UAC is disabled"
}

# Check automatic updates
$wuKey = Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -ErrorAction SilentlyContinue
if($wuKey.NoAutoUpdate -eq 1) {
    $issues += "Automatic updates disabled"
}

if($issues.Count -gt 0) {
    Write-Host "Security baseline issues: $($issues -join '; ')"
    exit 1
}

Write-Host "Security baseline compliant"
exit 0
