<#
.SYNOPSIS
    Remediates OneDrive Known Folder Move configuration.

.DESCRIPTION
    Starts the OneDrive client if it is not running and sets the silent Known
    Folder Move (KFM) opt-in registry values for the current interactive user,
    restarting OneDrive so the settings are picked up on next sync. Every
    mutation (starting/stopping OneDrive, creating keys, setting registry values)
    is gated behind -WhatIf/-Confirm via SupportsShouldProcess. Re-running on an
    already-converged system finds the KFM values present, changes nothing and
    still exits 0 (idempotent). Note: full KFM activation typically requires user
    interaction or Intune policy.
    Exit codes: 0 = remediation completed successfully (with or without changes),
    1 = an unexpected error occurred.

.EXAMPLE
    PS C:\> .\Invoke-RemediationFixOneDriveKnownFolderMove.ps1

    Starts OneDrive if needed and configures silent KFM opt-in for the current user.

.EXAMPLE
    PS C:\> .\Invoke-RemediationFixOneDriveKnownFolderMove.ps1 -WhatIf

    Shows which actions would be taken without changing anything.

.NOTES
    File Name  : Invoke-RemediationFixOneDriveKnownFolderMove.ps1
    Author     : Intune Admin
    Prerequisite: PowerShell 7.0
    Version    : 1.0.0
    Date       : 2026-08-23
#>

[CmdletBinding(SupportsShouldProcess)]
param()

$ErrorActionPreference = 'Stop'

function Resolve-UserSid {
    # Translates a DOMAIN\user account to its Security Identifier.
    # Exists as the mock seam for Pester tests (NTAccount translation requires a real account).
    param(
        [Parameter(Mandatory)]
        [string]$UserName
    )

    $sid = New-Object System.Security.Principal.NTAccount($UserName)
    return $sid.Translate([System.Security.Principal.SecurityIdentifier]).Value
}

function Main {
    # Advanced function so $PSCmdlet (and thus ShouldProcess) resolves inside Main.
    [CmdletBinding(SupportsShouldProcess)]
    param()

    try {
        Write-Host "[*] Configuring OneDrive Known Folder Move..." -ForegroundColor Cyan

        # Find OneDrive executable
        $oneDrivePath = "$env:ProgramFiles\Microsoft OneDrive\OneDrive.exe"
        if (-not (Test-Path $oneDrivePath)) {
            $oneDrivePath = "${env:ProgramFiles(x86)}\Microsoft OneDrive\OneDrive.exe"
        }

        # Start OneDrive if not running
        $oneDriveProcess = Get-Process -Name "OneDrive" -ErrorAction SilentlyContinue
        if (-not $oneDriveProcess) {
            if ($PSCmdlet.ShouldProcess('OneDrive', 'Start OneDrive application')) {
                Start-Process -FilePath $oneDrivePath -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 5
                Write-Host "[+] Started OneDrive application" -ForegroundColor Green
            }
        }

        $computerSystem = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
        $currentUser = $computerSystem.UserName
        if (-not $currentUser) {
            Write-Host "[!] No interactive user session detected; skipping per-user KFM configuration" -ForegroundColor Yellow
            return 0
        }

        $userSid = Resolve-UserSid -UserName $currentUser

        $odRegPath = "Registry::HKEY_USERS\$userSid\Software\Microsoft\OneDrive"
        if (-not (Test-Path $odRegPath)) {
            if ($PSCmdlet.ShouldProcess($odRegPath, 'Create OneDrive registry key')) {
                New-Item -Path $odRegPath -Force -ErrorAction Stop | Out-Null
            }
        }

        # Set KFM opt-in registry keys unless they are already configured.
        # These settings will be picked up by OneDrive on next sync and work in
        # conjunction with Intune policies.
        $currentValues = Get-ItemProperty -Path $odRegPath -ErrorAction SilentlyContinue
        if ($currentValues -and $currentValues.KFMSilentOptIn -eq '1' -and $currentValues.KFMSilentOptInWithNotification -eq 1) {
            Write-Host "[+] Already configured: OneDrive KFM registry settings present" -ForegroundColor Green
        }
        else {
            if ($PSCmdlet.ShouldProcess($odRegPath, 'Set OneDrive KFM silent opt-in registry values')) {
                Set-ItemProperty -Path $odRegPath -Name "KFMSilentOptIn" -Value "1" -Type String -ErrorAction Stop
                Set-ItemProperty -Path $odRegPath -Name "KFMSilentOptInWithNotification" -Value "1" -Type DWord -ErrorAction Stop
                Write-Host "[+] Configured OneDrive KFM registry settings" -ForegroundColor Green

                # Restart OneDrive to apply settings
                if ($oneDrivePath -and (Test-Path $oneDrivePath)) {
                    Stop-Process -Name "OneDrive" -Force -ErrorAction SilentlyContinue
                    Start-Sleep -Seconds 2
                    Start-Process -FilePath $oneDrivePath -ErrorAction SilentlyContinue
                    Write-Host "[+] Restarted OneDrive to apply changes" -ForegroundColor Green
                }
            }
        }

        Write-Host ""
        Write-Host "Note: Full KFM activation requires Intune policy configuration:"
        Write-Host "  - Set 'Silently move Windows known folders to OneDrive' policy"
        Write-Host "  - Configure Tenant ID in the policy"
        Write-Host "  - User may need to sign in to OneDrive"

        Write-Host "[+] OneDrive Known Folder Move remediation completed" -ForegroundColor Green
        return 0
    }
    catch {
        Write-Host "[-] Error during OneDrive KFM remediation: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
