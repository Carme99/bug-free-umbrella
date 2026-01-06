<#
.SYNOPSIS
    Detects OneDrive Known Folder Move (KFM) issues.

.DESCRIPTION
    Checks if OneDrive is installed, running, and Known Folder Move is properly
    configured for Desktop, Documents, and Pictures folders.

.NOTES
    Author: Intune Admin
    Version: 1.0
    Intune Context: SYSTEM
    Exit 0: OneDrive KFM is healthy
    Exit 1: Issues detected - remediation needed
#>

try {
    $issues = @()

    # Check if OneDrive is installed
    $oneDrivePath = "$env:ProgramFiles\Microsoft OneDrive\OneDrive.exe"
    if (-not (Test-Path $oneDrivePath)) {
        $oneDrivePath = "${env:ProgramFiles(x86)}\Microsoft OneDrive\OneDrive.exe"
        if (-not (Test-Path $oneDrivePath)) {
            Write-Host "OneDrive is not installed"
            exit 1
        }
    }

    # Check if OneDrive process is running
    $oneDriveProcess = Get-Process -Name "OneDrive" -ErrorAction SilentlyContinue
    if (-not $oneDriveProcess) {
        $issues += "OneDrive is not running"
    }

    # Get the current user SID (need to check per-user settings)
    $currentUser = (Get-WmiObject -Class Win32_ComputerSystem).UserName
    if ($currentUser) {
        $userName = $currentUser.Split('\')[1]
        $userSID = (New-Object System.Security.Principal.NTAccount($currentUser)).Translate([System.Security.Principal.SecurityIdentifier]).Value

        # Check KFM registry settings
        $kfmRegPath = "Registry::HKEY_USERS\$userSID\Software\Microsoft\OneDrive\Accounts\Business1"
        if (Test-Path $kfmRegPath) {
            # Check if folders are protected (moved to OneDrive)
            $desktopProtected = (Get-ItemProperty -Path $kfmRegPath -Name "DesktopFolderProtectedStatus" -ErrorAction SilentlyContinue).DesktopFolderProtectedStatus
            $documentsProtected = (Get-ItemProperty -Path $kfmRegPath -Name "DocumentsFolderProtectedStatus" -ErrorAction SilentlyContinue).DocumentsFolderProtectedStatus
            $picturesProtected = (Get-ItemProperty -Path $kfmRegPath -Name "PicturesFolderProtectedStatus" -ErrorAction SilentlyContinue).PicturesFolderProtectedStatus

            # Status 2 = Protected, anything else is not protected
            if ($desktopProtected -ne 2) {
                $issues += "Desktop folder is not protected by OneDrive KFM"
            }
            if ($documentsProtected -ne 2) {
                $issues += "Documents folder is not protected by OneDrive KFM"
            }
            if ($picturesProtected -ne 2) {
                $issues += "Pictures folder is not protected by OneDrive KFM"
            }
        } else {
            $issues += "OneDrive Business account not configured"
        }
    }

    # Check OneDrive sync status
    $oneDriveSettingsPath = "$env:LOCALAPPDATA\Microsoft\OneDrive\settings\Business1"
    if (Test-Path $oneDriveSettingsPath) {
        # OneDrive is configured
    } else {
        $issues += "OneDrive sync folder not found - may not be configured"
    }

    if ($issues.Count -gt 0) {
        Write-Host "OneDrive KFM issues detected:"
        foreach ($issue in $issues) {
            Write-Host "  - $issue"
        }
        exit 1
    }

    Write-Host "OneDrive Known Folder Move is healthy and active"
    exit 0

} catch {
    Write-Host "Error checking OneDrive KFM status: $_"
    exit 1
}
