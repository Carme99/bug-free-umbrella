# Detect unnecessary language packs installed on the system
# Exit 0 if only essential language packs are installed, Exit 1 if unnecessary packs found
#
# NOTE: installed OS language packs are system components managed via DISM
# (Get-WindowsPackage / Dism /Online /Get-Packages). Get-WinUserLanguageList
# manages the per-user language list and is NOT used here.
# See https://learn.microsoft.com/en-us/previous-versions/windows/it-pro/windows-8.1-and-8/hh825679(v=win.10)

$ErrorActionPreference = 'Stop'

# Allowed/Required language packs for UK environment
$allowedLanguages = @('en-GB', 'en-US')  # en-US is Windows default, often required

try {
    # Enumerate installed OS language packs via DISM (requires elevation; Intune runs as SYSTEM)
    $languagePacks = Get-WindowsPackage -Online -ErrorAction Stop |
        Where-Object { $_.PackageName -match 'LanguagePack' }

    if (-not $languagePacks) {
        Write-Host "No installed language packs found via DISM"
        exit 0
    }

    # Extract the language tag from each package name, e.g.
    # Microsoft-Windows-Client-LanguagePack-Package~31bf3856ad364e35~amd64~~en-GB~10.0.19041.1
    $installedLanguages = @($languagePacks | ForEach-Object {
        if ($_.PackageName -match '~([a-zA-Z]{2}-[a-zA-Z]{2})~') {
            $Matches[1]
        }
    } | Sort-Object -Unique)

    Write-Host "Installed language packs: $($installedLanguages -join ', ')"

    # Check for non-allowed languages
    $unnecessaryLanguages = @($installedLanguages | Where-Object { $_ -notin $allowedLanguages })

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
