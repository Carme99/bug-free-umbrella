<#
.SYNOPSIS
    Remove unnecessary OS language packs

.DESCRIPTION
    Removes installed OS language packs that are not in the allowed en-GB/en-US set using Remove-WindowsPackage (DISM /Online). Requires an elevated context (Intune Proactive Remediations run as SYSTEM). Exits 0 on success and 1 on failure.

.EXAMPLE
    ./remediate.ps1

.NOTES
    File Name  : remediate.ps1
    Author     : Intune / Proactive Remediations
    Prerequisite: PowerShell 5.1 or later, run in the Intune Proactive Remediation context
    Version    : 1.0.0
    Date       : 2026-08-08
#>

# Remediate by removing unnecessary language packs via DISM
# Exit 0 if successful, Exit 1 if failed
#
# NOTE: installed OS language packs are system components removed with
# Remove-WindowsPackage / Dism /Online /Remove-Package. Get/Set-WinUserLanguageList
# manage the per-user language list and are NOT touched by this script.
# See https://learn.microsoft.com/en-us/previous-versions/windows/it-pro/windows-8.1-and-8/hh825679(v=win.10)

#Requires -RunAsAdministrator

[CmdletBinding(SupportsShouldProcess = $true)]
param()

$ErrorActionPreference = 'Stop'

# Allowed/Required language packs
$allowedLanguages = @('en-GB', 'en-US')

try {
    # Admin check (belt-and-braces; #Requires also enforces it)
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Host "Administrator privileges are required to remove language packs"
        exit 1
    }

    # Enumerate installed OS language packs via DISM
    $languagePacks = Get-WindowsPackage -Online -ErrorAction Stop |
        Where-Object { $_.PackageName -match 'LanguagePack' }

    $removedCount = 0
    $removed = @()

    foreach ($package in $languagePacks) {
        if ($package.PackageName -match '~([a-zA-Z]{2}-[a-zA-Z]{2})~') {
            $lang = $Matches[1]
            if ($lang -notin $allowedLanguages) {
                Write-Host "Removing language pack $lang ($($package.PackageName))..."
                # -WhatIf-safe: Remove-WindowsPackage honours -WhatIf from SupportsShouldProcess
                Remove-WindowsPackage -Online -PackageName $package.PackageName -NoRestart -WhatIf:$WhatIfPreference -ErrorAction Stop
                if (-not $WhatIfPreference) {
                    $removed += $lang
                    $removedCount++
                }
            }
        }
    }

    if ($WhatIfPreference) {
        Write-Host "WhatIf: $removedCount language pack(s) would be removed ($($removed -join ', '))"
        exit 0
    }

    if ($removedCount -gt 0) {
        Write-Host "Removed $removedCount unnecessary language pack(s): $($removed -join ', ')"
        exit 0
    }
    else {
        Write-Host "No unnecessary language packs to remove"
        exit 0
    }
}
catch {
    Write-Host "Error removing language packs: $($_.Exception.Message)"
    exit 1
}
