<#
.SYNOPSIS
    Remediates OneDrive Known Folder Move issues.

.DESCRIPTION
    Attempts to start OneDrive and trigger Known Folder Move configuration.
    Note: Full KFM setup typically requires user interaction or Intune policy.

.NOTES
    Author: Intune Admin
    Version: 1.0
    Intune Context: SYSTEM
    Exit 0: Remediation successful
#>

try {
    $remediationActions = @()

    # Find OneDrive executable
    $oneDrivePath = "$env:ProgramFiles\Microsoft OneDrive\OneDrive.exe"
    if (-not (Test-Path $oneDrivePath)) {
        $oneDrivePath = "${env:ProgramFiles(x86)}\Microsoft OneDrive\OneDrive.exe"
    }

    # Start OneDrive if not running
    $oneDriveProcess = Get-Process -Name "OneDrive" -ErrorAction SilentlyContinue
    if (-not $oneDriveProcess) {
        Start-Process -FilePath $oneDrivePath -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 5
        $remediationActions += "Started OneDrive application"
    }

    # Set registry keys to enable KFM silently (requires Intune policy for full automation)
    # These settings will be picked up by OneDrive on next sync
    $currentUser = (Get-WmiObject -Class Win32_ComputerSystem).UserName
    if ($currentUser) {
        $userSID = (New-Object System.Security.Principal.NTAccount($currentUser)).Translate([System.Security.Principal.SecurityIdentifier]).Value

        # Enable silent KFM migration (this works in conjunction with Intune policies)
        $odRegPath = "Registry::HKEY_USERS\$userSID\Software\Microsoft\OneDrive"
        if (-not (Test-Path $odRegPath)) {
            New-Item -Path $odRegPath -Force | Out-Null
        }

        # Set KFM opt-in registry keys
        Set-ItemProperty -Path $odRegPath -Name "KFMSilentOptIn" -Value "1" -Type String -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $odRegPath -Name "KFMSilentOptInWithNotification" -Value "1" -Type DWord -ErrorAction SilentlyContinue
        $remediationActions += "Configured OneDrive KFM registry settings"

        # Restart OneDrive to apply settings
        Stop-Process -Name "OneDrive" -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        Start-Process -FilePath $oneDrivePath -ErrorAction SilentlyContinue
        $remediationActions += "Restarted OneDrive to apply changes"
    }

    Write-Host "OneDrive KFM remediation completed:"
    foreach ($action in $remediationActions) {
        Write-Host "  - $action"
    }
    Write-Host ""
    Write-Host "Note: Full KFM activation requires Intune policy configuration:"
    Write-Host "  - Set 'Silently move Windows known folders to OneDrive' policy"
    Write-Host "  - Configure Tenant ID in the policy"
    Write-Host "  - User may need to sign in to OneDrive"

    exit 0

}
catch {
    Write-Host "Error during OneDrive KFM remediation: $_"
    exit 1
}
