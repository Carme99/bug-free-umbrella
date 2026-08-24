<#
.SYNOPSIS
    Remediate the user keyboard layout to UK English.

.DESCRIPTION
    Ensures the en-GB language is present in the user language list, sets the UK
    standard (0809:00000809) and UK Extended (0809:00000452) input method tips,
    and moves en-GB to the first position so UK English becomes the primary
    keyboard layout. The script persists its changes via Set-WinUserLanguageList;
    every persisted mutation is gated behind -WhatIf/-Confirm via
    SupportsShouldProcess. Re-running against an already-converged profile makes
    no changes and still exits 0 (idempotent). The user may need to sign out for
    the new layout to fully apply.

.EXAMPLE
    PS C:\> .\Invoke-RemediationKeyboardLayout.ps1

    Applies the UK English keyboard layout as the primary user layout.

.EXAMPLE
    PS C:\> .\Invoke-RemediationKeyboardLayout.ps1 -WhatIf

    Shows which language-list changes would be applied without changing anything.

.NOTES
    File Name  : Invoke-RemediationKeyboardLayout.ps1
    Author     : Intune / Proactive Remediations
    Prerequisite: PowerShell 7.0
    Version    : 1.0.0
    Date       : 2026-08-23

    Keyboard layout identifiers (Microsoft keyboard reference):
      00000809 = United Kingdom (standard) https://learn.microsoft.com/en-us/globalization/keyboards/kbduk
      00000452 = United Kingdom Extended   https://learn.microsoft.com/en-us/globalization/keyboards/kbdukx
#>

[CmdletBinding(SupportsShouldProcess)]
param()

$ErrorActionPreference = 'Stop'

function Main {
    # Advanced function so $PSCmdlet (and thus ShouldProcess) resolves inside Main.
    [CmdletBinding(SupportsShouldProcess)]
    param()

    try {
        Write-Host "[*] Remediating keyboard layout to UK English..." -ForegroundColor Cyan

        # Required input method tips (Microsoft keyboard reference):
        #   0809:00000809 = United Kingdom (standard)
        #   0809:00000452 = United Kingdom Extended
        $requiredTips = @('0809:00000809', '0809:00000452')

        $languageList = @(Get-WinUserLanguageList -ErrorAction Stop)
        $ukLanguage = $languageList |
            Where-Object { $_.LanguageTag -eq 'en-GB' } |
            Select-Object -First 1

        # Converged profile: en-GB sits first and carries exactly the required tips.
        $isConverged = $false
        if ($ukLanguage -and $languageList.Count -gt 0) {
            $tipsMatched = @(Compare-Object -ReferenceObject $requiredTips -DifferenceObject @($ukLanguage.InputMethodTips)).Count -eq 0
            $isConverged = ($languageList[0].LanguageTag -eq 'en-GB') -and $tipsMatched
        }

        if ($isConverged) {
            Write-Host "[+] Already configured: UK English is the primary keyboard layout" -ForegroundColor Green
            return 0
        }

        if (-not $ukLanguage) {
            Write-Host "[*] Adding en-GB language..." -ForegroundColor Cyan
            $ukLanguage = (New-WinUserLanguageList -Language 'en-GB' -ErrorAction Stop)[0]
        }
        else {
            $ukLanguage.InputMethodTips.Clear()
        }
        foreach ($tip in $requiredTips) {
            $ukLanguage.InputMethodTips.Add($tip)
        }

        # Rebuild the list with en-GB first, preserving every remaining language.
        $newLanguageList = @($ukLanguage)
        foreach ($lang in $languageList) {
            if ($lang.LanguageTag -ne 'en-GB') {
                $newLanguageList += $lang
            }
        }

        if ($PSCmdlet.ShouldProcess('user language list', 'Set en-GB as the primary UK keyboard layout')) {
            Set-WinUserLanguageList -LanguageList $newLanguageList -Force -ErrorAction Stop
            Write-Host "[+] UK keyboard layout set as primary. User may need to sign out for changes to fully apply." -ForegroundColor Green
        }
        return 0
    }
    catch {
        Write-Host "[-] Error setting keyboard layout: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
