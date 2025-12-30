# Detect unnecessary language packs installed on the system
# Exit 0 if only essential language packs are installed, Exit 1 if unnecessary packs found

$ErrorActionPreference = 'Stop'

# Allowed/Required language packs for UK environment
$allowedLanguages = @('en-GB', 'en-US')  # en-US is Windows default, often required

try {
    # Get installed language packs
    $installedLanguages = Get-WinUserLanguageList

    # Check for non-allowed languages
    $unnecessaryLanguages = @()

    foreach ($lang in $installedLanguages) {
        if ($lang.LanguageTag -notin $allowedLanguages) {
            $unnecessaryLanguages += $lang.LanguageTag
        }
    }

    if ($unnecessaryLanguages.Count -gt 0) {
        Write-Host "Unnecessary language packs found: $($unnecessaryLanguages -join ', ')"
        Write-Host "Allowed: $($allowedLanguages -join ', ')"
        exit 1
    }

    # Check system locale
    $systemLocale = (Get-WinSystemLocale).Name
    if ($systemLocale -ne 'en-GB' -and $systemLocale -ne 'en-US') {
        Write-Host "System locale is $systemLocale (expected en-GB or en-US)"
        exit 1
    }

    Write-Host "Compliant: Only essential language packs installed"
    exit 0
}
catch {
    Write-Host "Error checking language packs: $($_.Exception.Message)"
    exit 1
}
