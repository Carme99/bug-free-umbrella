<#
.SYNOPSIS
    Detects OneDrive Known Folder Move (KFM) configuration issues.

.DESCRIPTION
    Checks that OneDrive is installed and running and that Known Folder Move protects the
    Desktop, Documents, and Pictures folders of the current user (registry protection status 2),
    plus the presence of the OneDrive Business1 sync settings folder.
    Exit codes:
    - 0: healthy - OneDrive installed, running, and all known folders are protected.
    - 1: non-compliant - KFM issues detected, or the check failed.

.NOTES
    File Name: Test-RemediationFixOneDriveKnownFolderMove.ps1
    Author: Intune Admin
    Prerequisite: PowerShell 7.0
    Version: 1.0.0
    Date: 2026-08-23

.EXAMPLE
    PS C:\> .\Test-RemediationFixOneDriveKnownFolderMove.ps1
    Reports each KFM issue found and returns 0 when healthy, 1 when remediation is needed.

.EXAMPLE
    PS C:\> pwsh -NoProfile -File .\Test-RemediationFixOneDriveKnownFolderMove.ps1
    Runs the same detection under the Intune Management Extension SYSTEM context.
#>

[CmdletBinding()]

$ErrorActionPreference = 'Stop'

#region Functions

function Resolve-CurrentUserSid {
    <#
    .SYNOPSIS
        Translates a DOMAIN\user account name into its security identifier (SID).
    #>
    param([ValidateNotNullOrEmpty()][string]$UserName)

    $ntAccount = New-Object System.Security.Principal.NTAccount($UserName)
    return $ntAccount.Translate([System.Security.Principal.SecurityIdentifier]).Value
}

function Main {
    try {
        $outputMsg = "[*] Checking OneDrive Known Folder Move status..."
        Write-Host $outputMsg -ForegroundColor Cyan

        $issues = @()

        # Check if OneDrive is installed
        $oneDrivePath = "$env:ProgramFiles\Microsoft OneDrive\OneDrive.exe"
        if (-not (Test-Path $oneDrivePath)) {
            $oneDrivePath = "${env:ProgramFiles(x86)}\Microsoft OneDrive\OneDrive.exe"
            if (-not (Test-Path $oneDrivePath)) {
                $outputMsg = "[!] OneDrive is not installed."
                Write-Host $outputMsg -ForegroundColor Yellow
                return 1
            }
        }

        # Check if OneDrive process is running
        $oneDriveProcess = Get-Process -Name "OneDrive" -ErrorAction SilentlyContinue
        if (-not $oneDriveProcess) {
            $issues += "OneDrive is not running"
        }

        # Get the current user SID (need to check per-user settings)
        # PSAvoidUsingWMICmdlet justified: Get-WmiObject kept deliberately to preserve this
        # detection's original runtime behavior on Windows PowerShell-based Intune hosts.
        $currentUser = (Get-WmiObject -Class Win32_ComputerSystem -ErrorAction SilentlyContinue).UserName
        if ($currentUser) {
            $userSid = Resolve-CurrentUserSid -UserName $currentUser

            # Check KFM registry settings
            $kfmRegPath = "Registry::HKEY_USERS\$userSid\Software\Microsoft\OneDrive\Accounts\Business1"
            if (Test-Path $kfmRegPath) {
                # Check if folders are protected (moved to OneDrive)
                $desktopProtectedStatus = Get-ItemProperty -Path $kfmRegPath `
                    -Name "DesktopFolderProtectedStatus" `
                    -ErrorAction SilentlyContinue
                $desktopProtected = $desktopProtectedStatus.DesktopFolderProtectedStatus
                $documentsProtectedStatus = Get-ItemProperty -Path $kfmRegPath `
                    -Name "DocumentsFolderProtectedStatus" `
                    -ErrorAction SilentlyContinue
                $documentsProtected = $documentsProtectedStatus.DocumentsFolderProtectedStatus
                $picturesProtectedStatus = Get-ItemProperty -Path $kfmRegPath `
                    -Name "PicturesFolderProtectedStatus" `
                    -ErrorAction SilentlyContinue
                $picturesProtected = $picturesProtectedStatus.PicturesFolderProtectedStatus

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
            }
            else {
                $issues += "OneDrive Business account not configured"
            }
        }

        # Check OneDrive sync status
        $oneDriveSettingsPath = "$env:LOCALAPPDATA\Microsoft\OneDrive\settings\Business1"
        if (-not (Test-Path $oneDriveSettingsPath)) {
            $issues += "OneDrive sync folder not found - may not be configured"
        }

        if ($issues.Count -gt 0) {
            $outputMsg = "[!] OneDrive KFM issues detected:"
            Write-Host $outputMsg -ForegroundColor Yellow
            foreach ($issue in $issues) {
                Write-Host "- $issue"
            }
            return 1
        }

        $outputMsg = "[+] OneDrive Known Folder Move is healthy and active."

        Write-Host $outputMsg -ForegroundColor Green
        return 0
    }
    catch {
        $outputMsg = "[-] Error checking OneDrive KFM status: $($_.Exception.Message)"
        Write-Host $outputMsg -ForegroundColor Red
        return 1
    }
}
#endregion

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
