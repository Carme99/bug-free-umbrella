# Remediate by removing unnecessary language packs
# Exit 0 if successful, Exit 1 if failed

$ErrorActionPreference = 'Stop'

# Allowed/Required language packs
$allowedLanguages = @('en-GB', 'en-US')

try {
    # Get current language list
    $currentLanguages = Get-WinUserLanguageList

    # Create new list with only allowed languages
    $newLanguageList = New-Object System.Collections.Generic.List[Microsoft.InternationalSettings.Commands.WinUserLanguage]

    # Ensure en-GB is first
    $ukLanguage = $currentLanguages | Where-Object { $_.LanguageTag -eq 'en-GB' }
    if ($ukLanguage) {
        $newLanguageList.Add($ukLanguage)
    }
    else {
        # Add en-GB if it doesn't exist
        Write-Host "Adding en-GB..."
        $lang = New-WinUserLanguageList -Language 'en-GB'
        $newLanguageList.Add($lang[0])
    }

    # Add en-US if it exists (often required for Windows)
    $usLanguage = $currentLanguages | Where-Object { $_.LanguageTag -eq 'en-US' }
    if ($usLanguage) {
        $newLanguageList.Add($usLanguage)
    }

    # Count removed languages
    $removedCount = $currentLanguages.Count - $newLanguageList.Count
    $removed = @()

    foreach ($lang in $currentLanguages) {
        if ($lang.LanguageTag -notin $allowedLanguages) {
            $removed += $lang.LanguageTag
        }
    }

    if ($removedCount -gt 0) {
        Write-Host "Removing unnecessary language packs: $($removed -join ', ')"
        Set-WinUserLanguageList -LanguageList $newLanguageList -Force
        Write-Host "Removed $removedCount language pack(s). Sign out required for full effect."
        exit 0
    }
    else {
        Write-Host "No unnecessary language packs to remove"
        exit 0
    }
}
catch {
    Write-Host "Error removing language packs: $($_.Exception.Message)"
    exit 1
}
