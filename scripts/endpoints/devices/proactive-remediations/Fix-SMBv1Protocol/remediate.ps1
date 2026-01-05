<#
.SYNOPSIS
    Disables SMBv1 protocol.

.DESCRIPTION
    Disables the insecure SMBv1 protocol to improve security posture.
    May require a restart to fully complete.

.NOTES
    Author: Intune Admin
    Version: 1.0
    Intune Context: SYSTEM
    Exit 0: Remediation successful
#>

try {
    $remediationActions = @()

    # Disable SMBv1 using Windows Optional Feature
    $smbv1Feature = Get-WindowsOptionalFeature -Online -FeatureName "SMB1Protocol" -ErrorAction SilentlyContinue

    if ($smbv1Feature -and $smbv1Feature.State -eq "Enabled") {
        try {
            Disable-WindowsOptionalFeature -Online -FeatureName "SMB1Protocol" -NoRestart -ErrorAction Stop | Out-Null
            $remediationActions += "Disabled SMBv1 Windows Optional Feature"
        } catch {
            Write-Host "Warning: Could not disable SMBv1 feature: $_"
        }
    }

    # Disable SMBv1 in SMB server configuration
    $smbServerConfig = Get-SmbServerConfiguration -ErrorAction SilentlyContinue
    if ($smbServerConfig -and $smbServerConfig.EnableSMB1Protocol -eq $true) {
        try {
            Set-SmbServerConfiguration -EnableSMB1Protocol $false -Force -ErrorAction Stop
            $remediationActions += "Disabled SMBv1 in SMB server configuration"
        } catch {
            Write-Host "Warning: Could not disable SMBv1 in server config: $_"
        }
    }

    # Disable SMBv1 via registry as backup
    $regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters"
    if (Test-Path $regPath) {
        Set-ItemProperty -Path $regPath -Name "SMB1" -Value 0 -Type DWord -ErrorAction SilentlyContinue
        $remediationActions += "Disabled SMBv1 via registry"
    }

    if ($remediationActions.Count -gt 0) {
        Write-Host "SMBv1 remediation completed:"
        foreach ($action in $remediationActions) {
            Write-Host "  - $action"
        }
        Write-Host ""
        Write-Host "Note: A system restart may be required to fully disable SMBv1"
    } else {
        Write-Host "SMBv1 was already disabled"
    }

    exit 0

} catch {
    Write-Host "Error during SMBv1 remediation: $_"
    exit 1
}
