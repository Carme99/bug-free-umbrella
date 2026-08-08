# Remediate keyboard layout to UK English
# Exit 0 if successful, Exit 1 if failed
#
# Keyboard layout identifiers (Microsoft keyboard reference):
#   00000809 = United Kingdom (standard)   https://learn.microsoft.com/en-us/globalization/keyboards/kbduk
#   00000452 = United Kingdom Extended     https://learn.microsoft.com/en-us/globalization/keyboards/kbdukx

$ErrorActionPreference = 'Stop'

try {
    # Get current language list
    $languageList = Get-WinUserLanguageList

    # Check if en-GB exists
    $ukLanguage = $languageList | Where-Object { $_.LanguageTag -eq 'en-GB' }

    if (-not $ukLanguage) {
        # Add en-GB if it doesn't exist
        Write-Host "Adding en-GB language..."
        $languageList.Add("en-GB")
        Set-WinUserLanguageList -LanguageList $languageList -Force

        # Refresh the list
        $languageList = Get-WinUserLanguageList
        $ukLanguage = $languageList | Where-Object { $_.LanguageTag -eq 'en-GB' }
    }

    # Ensure UK keyboard layouts are set:
    #   0809:00000809 = United Kingdom (standard) - kept as the standard-UK path
    #   0809:00000452 = United Kingdom Extended
    $ukLanguage.InputMethodTips.Clear()
    $ukLanguage.InputMethodTips.Add('0809:00000809')  # UK (standard) keyboard
    $ukLanguage.InputMethodTips.Add('0809:00000452')  # UK Extended keyboard

    # Move en-GB to the first position
    $newLanguageList = New-Object System.Collections.Generic.List[Microsoft.InternationalSettings.Commands.WinUserLanguage]
    $newLanguageList.Add($ukLanguage)

    # Add other languages
    foreach ($lang in $languageList) {
        if ($lang.LanguageTag -ne 'en-GB') {
            $newLanguageList.Add($lang)
        }
    }

    # Apply the new language list
    Set-WinUserLanguageList -LanguageList $newLanguageList -Force

    Write-Host "UK keyboard layout set as primary. User may need to sign out for changes to fully apply."
    exit 0
}
catch {
    Write-Host "Error setting keyboard layout: $($_.Exception.Message)"
    exit 1
}
