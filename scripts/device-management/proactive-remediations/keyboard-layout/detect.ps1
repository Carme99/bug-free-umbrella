# Detect if UK keyboard layout is the primary input method
# Exit 0 if compliant, Exit 1 if non-compliant

$ErrorActionPreference = 'Stop'

# Required keyboard layout
$requiredLayout = '00000809'  # United Kingdom Extended

try {
    # Get current input language list
    $languageList = Get-WinUserLanguageList

    # Check primary language's input methods
    $primaryLanguage = $languageList[0]
    $primaryInputMethod = $primaryLanguage.InputMethodTips[0]

    # Expected formats: "0809:00000809" for UK keyboard
    if ($primaryInputMethod -notlike "*00000809*") {
        Write-Host "Non-compliant: Primary keyboard is $primaryInputMethod (expected UK: 00000809)"
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
