<#
.SYNOPSIS
    Detects regional settings that deviate from UK standards.

.DESCRIPTION
    Checks the system culture (en-GB), geographic location (GeoId 242, United Kingdom), time
    zone (GMT Standard Time), system locale and primary user language, and exits 1 when any
    setting deviates from the required UK values. Every deviation found is listed in the output.
    Exit codes:
    - 0: compliant - all regional settings match the required UK values.
    - 1: non-compliant or failure - one or more settings deviate, or the check failed.

.EXAMPLE
    PS C:\> .\Test-RemediationRegionLanguageSettings.ps1
    Runs the detection check and exits 0 when all regional settings match UK standards.

.EXAMPLE
    PS C:\> & 'C:\Program Files\Intune\Test-RemediationRegionLanguageSettings.ps1'
    Runs the same check from the Intune Management Extension in the user context.

.NOTES
    File Name: Test-RemediationRegionLanguageSettings.ps1
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
        $outputMsg = "[*] Checking regional settings against UK standards..."
        Write-Host $outputMsg -ForegroundColor Cyan

        # Required settings
        $requiredCulture = 'en-GB'
        $requiredGeoId = 242  # United Kingdom
        $requiredTimeZone = 'GMT Standard Time'

        # Get current settings
        $currentCulture = (Get-Culture).Name
        $currentGeoId = (Get-WinHomeLocation -ErrorAction Stop).GeoId
        $currentTimeZone = (Get-TimeZone).Id

        # Get system locale
        $systemLocale = (Get-WinSystemLocale -ErrorAction Stop).Name

        # Get user language list
        $userLanguageList = Get-WinUserLanguageList -ErrorAction Stop
        $primaryLanguage = $userLanguageList[0].LanguageTag

        $issues = @()

        # Check culture
        if ($currentCulture -ne $requiredCulture) {
            $issues += "Culture: $currentCulture (expected: $requiredCulture)"
        }

        # Check geographic location
        if ($currentGeoId -ne $requiredGeoId) {
            $issues += "Geographic Location: $currentGeoId (expected: $requiredGeoId)"
        }

        # Check time zone
        if ($currentTimeZone -ne $requiredTimeZone) {
            $issues += "Time Zone: $currentTimeZone (expected: $requiredTimeZone)"
        }

        # Check system locale
        if ($systemLocale -ne $requiredCulture) {
            $issues += "System Locale: $systemLocale (expected: $requiredCulture)"
        }

        # Check primary language
        if ($primaryLanguage -ne $requiredCulture) {
            $issues += "Primary Language: $primaryLanguage (expected: $requiredCulture)"
        }

        if ($issues.Count -gt 0) {
            $outputMsg = "[!] Non-compliant regional settings: $($issues -join '; ')"
            Write-Host $outputMsg -ForegroundColor Yellow
            return 1
        }

        $outputMsg = "[+] Regional settings compliant: en-GB, UK location, GMT timezone"

        Write-Host $outputMsg -ForegroundColor Green
        return 0
    }
    catch {
        $outputMsg = "[-] Error checking regional settings: $($_.Exception.Message)"
        Write-Host $outputMsg -ForegroundColor Red
        return 1
    }
}

#endregion

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
