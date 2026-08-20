<#
.SYNOPSIS
    Detect if a UK keyboard layout is the primary input method

.DESCRIPTION
    Checks the user's language list and exits 1 (non-compliant) when the primary keyboard layout is not UK English (00000809) or UK Extended (00000452), or when the primary language tag is not en-GB. Exits 0 when compliant.

.EXAMPLE
    ./detect.ps1

.NOTES
    File Name  : detect.ps1
    Author     : Intune / Proactive Remediations
    Prerequisite: PowerShell 5.1 or later, run in the Intune Proactive Remediation context
    Version    : 1.0.0
    Date       : 2026-08-08
#>

# Detect if a UK keyboard layout is the primary input method
# Exit 0 if compliant, Exit 1 if non-compliant
#
# Keyboard layout identifiers (Microsoft keyboard reference):
#   00000809 = United Kingdom (standard)   https://learn.microsoft.com/en-us/globalization/keyboards/kbduk
#   00000452 = United Kingdom Extended     https://learn.microsoft.com/en-us/globalization/keyboards/kbdukx

$ErrorActionPreference = 'Stop'

# Required keyboard layouts (either standard UK or UK Extended is compliant)
$requiredLayouts = @('00000809', '00000452')

try {
    # Get current input language list
    $languageList = Get-WinUserLanguageList

    # Check primary language's input methods
    $primaryLanguage = $languageList[0]
    $primaryInputMethod = $primaryLanguage.InputMethodTips[0]

    # Expected formats: "0809:00000809" for standard UK, "0809:00000452" for UK Extended
    if ($primaryInputMethod -notmatch '00000809|00000452') {
        Write-Host "Non-compliant: Primary keyboard is $primaryInputMethod (expected UK: 00000809 or UK Extended: 00000452)"
        exit 1
    }

    # Check if UK English is the primary language
    if ($primaryLanguage.LanguageTag -ne 'en-GB') {
        Write-Host "Non-compliant: Primary language is $($primaryLanguage.LanguageTag) (expected en-GB)"
        exit 1
    }

    Write-Host "Compliant: UK keyboard layout (en-GB) is primary"
    exit 0
}
catch {
    Write-Host "Error checking keyboard layout: $($_.Exception.Message)"
    exit 1
}
