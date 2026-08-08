<#
.SYNOPSIS
    Detect if regional settings match UK standards

.DESCRIPTION
    Checks the system culture (en-GB), geographic location (GeoId 242, United Kingdom), time zone (GMT Standard Time), system locale and primary user language and exits 1 when any setting deviates from the required UK values.

.EXAMPLE
    ./detect.ps1

.NOTES
    File Name  : detect.ps1
    Author     : Intune / Proactive Remediations
    Prerequisite: PowerShell 5.1 or later, run in the Intune Proactive Remediation context
    Version    : 1.0.0
    Date       : 2026-08-08
#>

# Detect if Windows client device regional settings match UK standards
# Exit 0 if compliant, Exit 1 if non-compliant

$ErrorActionPreference = 'Stop'

# Required settings
$requiredCulture = 'en-GB'
$requiredGeoId = 242  # United Kingdom
$requiredTimeZone = 'GMT Standard Time'

try {
    # Get current settings
    $currentCulture = (Get-Culture).Name
    $currentGeoId = (Get-WinHomeLocation).GeoId
    $currentTimeZone = (Get-TimeZone).Id

    # Get system locale
    $systemLocale = (Get-WinSystemLocale).Name

    # Get user language list
    $userLanguageList = Get-WinUserLanguageList
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
        Write-Host "Non-compliant regional settings: $($issues -join '; ')"
        exit 1
    }

    Write-Host "Regional settings compliant: en-GB, UK location, GMT timezone"
    exit 0
}
catch {
    Write-Host "Error checking regional settings: $($_.Exception.Message)"
    exit 1
}
