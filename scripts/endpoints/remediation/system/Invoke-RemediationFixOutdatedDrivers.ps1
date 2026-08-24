<#
.SYNOPSIS
    Installs available driver updates from Windows Update.

.DESCRIPTION
    Searches Windows Update for pending driver updates and installs them via the
    Windows Update COM API, then triggers a Plug and Play hardware rescan when
    devices report driver problems. Every mutation (installing updates, rescanning
    devices) is gated behind -WhatIf/-Confirm via SupportsShouldProcess. Re-running
    on an already-converged system finds no pending updates and no problem devices,
    changes nothing and still exits 0 (idempotent). A restart may be required to
    complete installation.
    Exit codes: 0 = remediation completed successfully (with or without changes),
    1 = an unexpected error occurred.

.EXAMPLE
    PS C:\> .\Invoke-RemediationFixOutdatedDrivers.ps1

    Installs any pending driver updates and rescans devices with driver problems.

.EXAMPLE
    PS C:\> .\Invoke-RemediationFixOutdatedDrivers.ps1 -WhatIf

    Shows which driver actions would run without changing anything.

.NOTES
    File Name  : Invoke-RemediationFixOutdatedDrivers.ps1
    Author     : Intune Admin
    Prerequisite: PowerShell 7.0
    Version    : 1.0.0
    Date       : 2026-08-23
#>

[CmdletBinding(SupportsShouldProcess)]
param()

$ErrorActionPreference = 'Stop'

function Invoke-PnpUtil {
    # Thin wrapper around the native pnputil.exe executable; mock seam for Pester tests.
    param(
        [Parameter(ValueFromRemainingArguments)]
        [string[]]$Remaining
    )

    & pnputil.exe @Remaining 2>&1 | Out-Null
    return $LASTEXITCODE
}

function Install-DriverUpdates {
    # Searches Windows Update for pending driver updates and installs them via the
    # Windows Update COM API. Exists as the mock seam for Pester tests (the COM
    # pipeline cannot be exercised off-Windows). Returns a status string, or $null
    # when no driver updates were pending.
    $updateSession = New-Object -ComObject Microsoft.Update.Session
    $updateSearcher = $updateSession.CreateUpdateSearcher()

    Write-Host "[*] Searching for driver updates..." -ForegroundColor Cyan
    $searchResult = $updateSearcher.Search("IsInstalled=0 and Type='Driver'")

    if ($searchResult.Updates.Count -eq 0) {
        return $null
    }

    $updatesToInstall = New-Object -ComObject Microsoft.Update.UpdateColl

    foreach ($update in $searchResult.Updates) {
        if ($update.IsDownloaded -eq $false) {
            Write-Host "[*] Driver update available: $($update.Title)" -ForegroundColor Cyan
            $updatesToInstall.Add($update) | Out-Null
        }
    }

    if ($updatesToInstall.Count -eq 0) {
        return $null
    }

    # Download updates
    $downloader = $updateSession.CreateUpdateDownloader()
    $downloader.Updates = $updatesToInstall
    Write-Host "[*] Downloading $($updatesToInstall.Count) driver update(s)..." -ForegroundColor Cyan
    $null = $downloader.Download()

    # Install updates
    $installer = $updateSession.CreateUpdateInstaller()
    $installer.Updates = $updatesToInstall
    Write-Host "[*] Installing driver updates..." -ForegroundColor Cyan
    $installResult = $installer.Install()

    if ($installResult.ResultCode -eq 2) {
        return "Successfully installed $($updatesToInstall.Count) driver update(s)"
    }
    else {
        return "Driver installation completed with result code: $($installResult.ResultCode)"
    }
}

function Main {
    # Advanced function so $PSCmdlet (and thus ShouldProcess) resolves inside Main.
    [CmdletBinding(SupportsShouldProcess)]
    param()

    try {
        Write-Host "[*] Checking for outdated drivers..." -ForegroundColor Cyan

        $remediationActions = @()

        # Install driver updates using the Windows Update COM API.
        if ($PSCmdlet.ShouldProcess('Windows Update', 'Download and install pending driver updates')) {
            try {
                $action = Install-DriverUpdates
                if ($action) {
                    $remediationActions += $action
                }
            }
            catch {
                Write-Host "[!] Error installing driver updates: $($_.Exception.Message)" -ForegroundColor Yellow
                $remediationActions += "Could not install drivers automatically - may require manual intervention"
            }
        }

        # Try to fix devices with driver issues by scanning for hardware changes
        $problemDevices = Get-CimInstance -ClassName Win32_PnPEntity -ErrorAction Stop |
            Where-Object { $_.ConfigManagerErrorCode -ne 0 }

        if ($problemDevices) {
            if ($PSCmdlet.ShouldProcess('Plug and Play devices', 'Trigger hardware rescan')) {
                $rc = Invoke-PnpUtil /scan-devices
                if ($rc -ne 0) {
                    Write-Host "[!] pnputil hardware rescan failed with exit code $rc" -ForegroundColor Yellow
                }
                $remediationActions += "Triggered hardware rescan for problem devices"
            }
        }

        if ($remediationActions.Count -gt 0) {
            Write-Host "[+] Driver remediation completed:" -ForegroundColor Green
            foreach ($action in $remediationActions) {
                Write-Host "    - $action"
            }
            Write-Host ""
            Write-Host "Note: A restart may be required to complete driver installation"
        }
        else {
            Write-Host "[+] Already clean: no driver updates were necessary" -ForegroundColor Green
        }

        return 0
    }
    catch {
        Write-Host "[-] Error during driver remediation: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
