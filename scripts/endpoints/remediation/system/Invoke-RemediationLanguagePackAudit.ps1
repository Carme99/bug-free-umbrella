<#
.SYNOPSIS
    Audit and remove unnecessary OS language packs.

.DESCRIPTION
    Enumerates the installed OS language packs (via Get-WindowsPackage -Online,
    the DISM /Online surface) and removes every pack outside the allowed en-GB /
    en-US set with Remove-WindowsPackage. This is a destructive operation:
    removed packages may require a restart to fully leave the image, and every
    removal is gated behind -WhatIf/-Confirm via SupportsShouldProcess.
    Get-WinUserLanguageList / Set-WinUserLanguageList manage the per-user language
    list and are NOT touched by this script. Requires an elevated context (Intune
    Proactive Remediations run as SYSTEM). Re-running against an already-compliant
    device finds no unnecessary packs and still exits 0 (idempotent).

.EXAMPLE
    PS C:\> .\Invoke-RemediationLanguagePackAudit.ps1

    Removes every installed OS language pack that is not en-GB or en-US.

.EXAMPLE
    PS C:\> .\Invoke-RemediationLanguagePackAudit.ps1 -WhatIf

    Lists which language packs would be removed without removing anything.

.NOTES
    File Name  : Invoke-RemediationLanguagePackAudit.ps1
    Author     : Intune / Proactive Remediations
    Prerequisite: PowerShell 7.0, elevated (SYSTEM) context
    Version    : 1.0.0
    Date       : 2026-08-23

    See https://learn.microsoft.com/en-us/previous-versions/windows/it-pro/windows-8.1-and-8/hh825679(v=win.10)
#>

[CmdletBinding(SupportsShouldProcess)]
param()

$ErrorActionPreference = 'Stop'

function Test-ElevatedPrivilege {
    # Belt-and-braces elevation probe; mock seam for Pester tests on Linux CI.
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Main {
    # Advanced function so $PSCmdlet (and thus ShouldProcess) resolves inside Main.
    [CmdletBinding(SupportsShouldProcess)]
    param()

    try {
        Write-Host "[*] Auditing installed OS language packs..." -ForegroundColor Cyan

        # Allowed/Required language packs
        $allowedLanguages = @('en-GB', 'en-US')

        if (-not (Test-ElevatedPrivilege)) {
            throw "Administrator privileges are required to remove OS language packs"
        }

        # Enumerate installed OS language packs via DISM (Get-WindowsPackage -Online).
        $languagePacks = Get-WindowsPackage -Online -ErrorAction Stop |
            Where-Object { $_.PackageName -match 'LanguagePack' }

        $removed = @()

        foreach ($package in $languagePacks) {
            if ($package.PackageName -match '~([a-zA-Z]{2}-[a-zA-Z]{2})~') {
                $lang = $Matches[1]
                if ($lang -notin $allowedLanguages) {
                    if ($PSCmdlet.ShouldProcess($package.PackageName, "Remove unnecessary language pack ($lang)")) {
                        Remove-WindowsPackage -Online -PackageName $package.PackageName -NoRestart -ErrorAction Stop | Out-Null
                        $removed += $lang
                    }
                }
            }
        }

        if ($removed.Count -gt 0) {
            Write-Host "[+] Removed $($removed.Count) unnecessary language pack(s): $($removed -join ', ')" -ForegroundColor Green
        }
        else {
            Write-Host "[+] Already compliant: no unnecessary OS language packs found" -ForegroundColor Green
        }
        return 0
    }
    catch {
        Write-Host "[-] Error auditing/removing language packs: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
