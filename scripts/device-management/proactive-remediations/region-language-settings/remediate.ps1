# Remediate Windows client device regional settings to UK standards
# Exit 0 if successful, Exit 1 if failed

$ErrorActionPreference = 'Stop'

# Required settings
$requiredCulture = 'en-GB'
$requiredGeoId = 242  # United Kingdom
$requiredTimeZone = 'GMT Standard Time'

try {
    $changes = @()

    # Set geographic location to United Kingdom
    $currentGeoId = (Get-WinHomeLocation).GeoId
    if ($currentGeoId -ne $requiredGeoId) {
        Set-WinHomeLocation -GeoId $requiredGeoId
        $changes += "Geographic location set to UK"
    }

    # Set time zone to GMT Standard Time
    $currentTimeZone = (Get-TimeZone).Id
    if ($currentTimeZone -ne $requiredTimeZone) {
        Set-TimeZone -Id $requiredTimeZone
        $changes += "Time zone set to GMT Standard Time"
    }

    # Set system locale
    $systemLocale = (Get-WinSystemLocale).Name
    if ($systemLocale -ne $requiredCulture) {
        Set-WinSystemLocale -SystemLocale $requiredCulture
        $changes += "System locale set to en-GB"
    }

    # Set culture
    $currentCulture = (Get-Culture).Name
    if ($currentCulture -ne $requiredCulture) {
        Set-Culture -CultureInfo $requiredCulture
        $changes += "Culture set to en-GB"
    }

    # Configure user language list
    $userLanguageList = Get-WinUserLanguageList
    $primaryLanguage = $userLanguageList[0].LanguageTag

    if ($primaryLanguage -ne $requiredCulture) {
        # Clear existing and set en-GB as primary
        $languageList = New-WinUserLanguageList -Language $requiredCulture
        Set-WinUserLanguageList -LanguageList $languageList -Force
        $changes += "Primary language set to en-GB"
    }

    if ($changes.Count -gt 0) {
        Write-Host "Regional settings remediated: $($changes -join '; '). Restart may be required for all changes to take effect."
        exit 0
    }
    else {
        Write-Host "No changes needed - already compliant"
        exit 0
    }
}
catch {
    Write-Host "Error remediating regional settings: $($_.Exception.Message)"
    exit 1
}
