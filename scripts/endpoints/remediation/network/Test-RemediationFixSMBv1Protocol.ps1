<#
.SYNOPSIS
    Detects if SMBv1 protocol is enabled.

.DESCRIPTION
    Checks if the insecure SMBv1 protocol is enabled. SMBv1 should be disabled
    for security compliance as it's vulnerable to attacks like WannaCry.

.NOTES
    Author: Intune Admin
    Version: 1.0
    Intune Context: SYSTEM
    Exit 0: SMBv1 is properly disabled
    Exit 1: SMBv1 is enabled - remediation needed
#>

try {
    $issues = @()

    # Check if SMBv1 is enabled using Get-WindowsOptionalFeature
    $smbv1Feature = Get-WindowsOptionalFeature -Online -FeatureName "SMB1Protocol" -ErrorAction SilentlyContinue

    if ($smbv1Feature) {
        if ($smbv1Feature.State -eq "Enabled") {
            $issues += "SMBv1 Protocol is enabled (security risk)"
        }
    }

    # Check SMB server configuration
    $smbServerConfig = Get-SmbServerConfiguration -ErrorAction SilentlyContinue
    if ($smbServerConfig) {
        if ($smbServerConfig.EnableSMB1Protocol -eq $true) {
            $issues += "SMBv1 is enabled in SMB server configuration"
        }
    }

    # Check registry key as backup
    $regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters"
    if (Test-Path $regPath) {
        $smb1 = Get-ItemProperty -Path $regPath -Name "SMB1" -ErrorAction SilentlyContinue
        if ($smb1 -and $smb1.SMB1 -ne 0) {
            $issues += "SMBv1 is enabled in registry"
        }
    }

    if ($issues.Count -gt 0) {
        Write-Host "SMBv1 security issues detected:"
        foreach ($issue in $issues) {
            Write-Host "  - $issue"
        }
        exit 1
    }

    Write-Host "SMBv1 is properly disabled (secure configuration)"
    exit 0

}
catch {
    Write-Host "Error checking SMBv1 status: $_"
    exit 1
}
