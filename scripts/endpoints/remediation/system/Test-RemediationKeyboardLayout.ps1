<#
.SYNOPSIS
    Detects whether a UK keyboard layout is the primary input method.

.DESCRIPTION
    Checks the user's Windows language list and exits 1 (non-compliant) when the primary
    keyboard layout is not UK English (00000809) or UK Extended (00000452), or when the primary
    language tag is not en-GB. Exits 0 when compliant.
    Exit codes:
    - 0: compliant - a UK keyboard layout with the en-GB language tag is primary.
    - 1: non-compliant or failure - the primary layout or language deviates, or the check failed.

.EXAMPLE
    PS C:\> .\Test-RemediationKeyboardLayout.ps1
    Runs the detection check and exits 0 when UK English is the primary input method.

.EXAMPLE
    PS C:\> & 'C:\Program Files\Intune\Test-RemediationKeyboardLayout.ps1'
    Runs the same check from the Intune Management Extension in the user context.

.NOTES
    File Name: Test-RemediationKeyboardLayout.ps1
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
        $outputMsg = "[*] Checking primary keyboard layout..."
        Write-Host $outputMsg -ForegroundColor Cyan

        # Required keyboard layouts (either standard UK or UK Extended is compliant).
        # Keyboard layout identifiers (Microsoft keyboard reference):
        #   00000809 = United Kingdom standard   https://learn.microsoft.com/en-us/globalization/keyboards/kbduk
        #   00000452 = United Kingdom Extended   https://learn.microsoft.com/en-us/globalization/keyboards/kbdukx
        $requiredLayouts = @('00000809', '00000452')
        $layoutPattern = $requiredLayouts -join '|'

        # Get current input language list
        $languageList = Get-WinUserLanguageList -ErrorAction Stop

        # Check primary language's input methods
        $primaryLanguage = $languageList[0]
        $primaryInputMethod = $primaryLanguage.InputMethodTips[0]

        # Expected formats: "0809:00000809" for standard UK, "0809:00000452" for UK Extended
        if ($primaryInputMethod -notmatch $layoutPattern) {
            $outputMsg = "[!] Non-compliant: Primary keyboard is $primaryInputMethod"
            Write-Host $outputMsg -ForegroundColor Yellow
            $outputMsg = "[!]   Expected UK (00000809) or UK Extended (00000452)"
            Write-Host $outputMsg -ForegroundColor Yellow
            return 1
        }

        # Check if UK English is the primary language
        if ($primaryLanguage.LanguageTag -ne 'en-GB') {
            $outputMsg = "[!] Non-compliant: Primary language is $($primaryLanguage.LanguageTag)"
            Write-Host $outputMsg -ForegroundColor Yellow
            $outputMsg = "[!]   Expected en-GB"
            Write-Host $outputMsg -ForegroundColor Yellow
            return 1
        }

        $outputMsg = "[+] Compliant: UK keyboard layout (en-GB) is primary"

        Write-Host $outputMsg -ForegroundColor Green
        return 0
    }
    catch {
        $outputMsg = "[-] Error checking keyboard layout: $($_.Exception.Message)"
        Write-Host $outputMsg -ForegroundColor Red
        return 1
    }
}

#endregion

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
