<#
.SYNOPSIS
    Detects unnecessary OS language packs.

.DESCRIPTION
    Enumerates installed OS language packs via DISM (Get-WindowsPackage) and exits 1 when any
    language pack other than the allowed en-GB/en-US set is installed. Also verifies that the
    system locale is en-GB or en-US. Only OS language packs are considered; per-user language
    lists are not inspected.
    Exit codes:
    - 0: compliant - only essential language packs are installed and the system locale is allowed.
    - 1: non-compliant or failure - an unnecessary pack or disallowed system locale was found,
      or the DISM enumeration failed (it requires elevation; Intune runs as SYSTEM).

.EXAMPLE
    PS C:\> .\Test-RemediationLanguagePackAudit.ps1
    Runs the audit and exits 0 when only en-GB/en-US packs are installed, otherwise 1.

.EXAMPLE
    PS C:\> & 'C:\Program Files\Intune\Test-RemediationLanguagePackAudit.ps1'
    Runs the same audit from the Intune Management Extension under the SYSTEM context.

.NOTES
    File Name: Test-RemediationLanguagePackAudit.ps1
    Author: Intune / Proactive Remediations
    Prerequisite: PowerShell 7.0
    Version: 1.0.0
    Date: 2026-08-23
#>

[CmdletBinding()]

$ErrorActionPreference = 'Stop'

#region Functions

function Main {
    try {
        $outputMsg = "[*] Auditing installed OS language packs..."
        Write-Host $outputMsg -ForegroundColor Cyan

        # Allowed/Required language packs for UK environment.
        # Installed OS language packs are system components managed via DISM
        # (Get-WindowsPackage / Dism /Online /Get-Packages). Get-WinUserLanguageList
        # manages the per-user language list and is NOT used here.
        # See https://learn.microsoft.com/en-us/previous-versions/windows/it-pro/windows-8.1-and-8/hh825679(v=win.10)
        $allowedLanguages = @('en-GB', 'en-US')  # en-US is Windows default, often required

        # Enumerate installed OS language packs via DISM (requires elevation; Intune runs as SYSTEM)
        $languagePacks = Get-WindowsPackage -Online -ErrorAction Stop |
            Where-Object { $_.PackageName -match 'LanguagePack' }

        if (-not $languagePacks) {
            $outputMsg = "[*] No installed language packs found via DISM"
            Write-Host $outputMsg -ForegroundColor Cyan
            return 0
        }

        # Extract the language tag from each package name, e.g.
        # Microsoft-Windows-Client-LanguagePack-Package~31bf3856ad364e35~amd64~~en-GB~
        $installedLanguages = @($languagePacks | ForEach-Object {
                if ($_.PackageName -match '~([a-zA-Z]{2}-[a-zA-Z]{2})~') {
                    $Matches[1]
                }
            } | Sort-Object -Unique)

        $outputMsg = "[*] Installed language packs: $($installedLanguages -join ', ')"

        Write-Host $outputMsg -ForegroundColor Cyan

        # Check for non-allowed languages
        $unnecessaryLanguages = @($installedLanguages | Where-Object { $_ -notin $allowedLanguages })

        if ($unnecessaryLanguages.Count -gt 0) {
            $outputMsg = "[!] Unnecessary language packs found:"
            Write-Host $outputMsg -ForegroundColor Yellow
            $outputMsg = "[!]   $($unnecessaryLanguages -join ', ')"
            Write-Host $outputMsg -ForegroundColor Yellow
            $outputMsg = "[!] Allowed: $($allowedLanguages -join ', ')"
            Write-Host $outputMsg -ForegroundColor Yellow
            return 1
        }

        # Check system locale
        $systemLocale = (Get-WinSystemLocale -ErrorAction Stop).Name
        if ($systemLocale -ne 'en-GB' -and $systemLocale -ne 'en-US') {
            $outputMsg = "[!] System locale is $systemLocale (expected en-GB or en-US)"
            Write-Host $outputMsg -ForegroundColor Yellow
            return 1
        }

        $outputMsg = "[+] Compliant: Only essential language packs installed"

        Write-Host $outputMsg -ForegroundColor Green
        return 0
    }
    catch {
        $outputMsg = "[-] Error checking language packs: $($_.Exception.Message)"
        Write-Host $outputMsg -ForegroundColor Red
        return 1
    }
}

#endregion

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
