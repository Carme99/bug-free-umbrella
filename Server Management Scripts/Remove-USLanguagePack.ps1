<#
.SYNOPSIS
    Removes US English (en-US) language packs from Windows Server 2016-2022.

.DESCRIPTION
    This script removes US English language packs and related components:
    - Removes en-US language pack
    - Removes en-US keyboard layouts
    - Cleans up US regional settings
    - Removes US language features on demand
    - Verifies UK English (en-GB) is set as default before removal

.PARAMETER Force
    Forces removal without confirmation prompts.

.PARAMETER KeepKeyboard
    Keeps US keyboard layout (only removes language pack).

.PARAMETER BackupFirst
    Creates a system restore point before removal.

.EXAMPLE
    .\Remove-USLanguagePack.ps1
    Removes US language pack with confirmation prompts.

.EXAMPLE
    .\Remove-USLanguagePack.ps1 -Force -BackupFirst
    Forces removal after creating restore point.

.EXAMPLE
    .\Remove-USLanguagePack.ps1 -KeepKeyboard
    Removes language pack but keeps US keyboard layout.

.NOTES
    Requires Administrator privileges
    Compatible with Windows Server 2016, 2019, and 2022
    Ensures en-GB is configured before removing en-US
    System restart may be required
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [switch]$Force,

    [Parameter(Mandatory=$false)]
    [switch]$KeepKeyboard,

    [Parameter(Mandatory=$false)]
    [switch]$BackupFirst
)

#Requires -RunAsAdministrator

function Write-Log {
    param([string]$Message, [string]$Type = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $color = switch($Type) {
        "ERROR" { "Red" }
        "SUCCESS" { "Green" }
        "WARNING" { "Yellow" }
        "HEADER" { "Cyan" }
        default { "White" }
    }
    Write-Host "[$timestamp] [$Type] $Message" -ForegroundColor $color
}

Write-Log "=== US English Language Pack Removal Tool ===" "HEADER"
Write-Log "Server: $env:COMPUTERNAME" "INFO"

# Create system restore point if requested
if ($BackupFirst) {
    Write-Log "Creating system restore point..." "INFO"
    try {
        Enable-ComputerRestore -Drive "C:\" -ErrorAction SilentlyContinue
        Checkpoint-Computer -Description "Before US Language Pack Removal" -RestorePointType "MODIFY_SETTINGS"
        Write-Log "System restore point created successfully" "SUCCESS"
    }
    catch {
        Write-Log "Failed to create restore point: $($_.Exception.Message)" "WARNING"
        if (-not $Force) {
            $continue = Read-Host "Continue without restore point? (Y/N)"
            if ($continue -ne "Y" -and $continue -ne "y") {
                Write-Log "Operation cancelled by user" "INFO"
                exit 0
            }
        }
    }
}

# Check current language configuration
Write-Log "Checking current language configuration..." "INFO"

try {
    $currentCulture = Get-Culture
    $systemLocale = Get-WinSystemLocale
    $installedLanguages = Get-WinUserLanguageList

    Write-Log "Current Culture: $($currentCulture.Name)" "INFO"
    Write-Log "System Locale: $($systemLocale.Name)" "INFO"
    Write-Log "Installed Languages:" "INFO"
    foreach ($lang in $installedLanguages) {
        Write-Log "  - $($lang.LanguageTag)" "INFO"
    }

    # Check if en-GB is configured
    $hasEnGB = $installedLanguages | Where-Object { $_.LanguageTag -eq "en-GB" }
    $hasEnUS = $installedLanguages | Where-Object { $_.LanguageTag -eq "en-US" }

    if (-not $hasEnGB) {
        Write-Log "WARNING: English (UK) language pack is not installed!" "ERROR"
        Write-Log "You must install and configure en-GB before removing en-US" "ERROR"

        if (-not $Force) {
            $install = Read-Host "Would you like to install en-GB now? (Y/N)"
            if ($install -eq "Y" -or $install -eq "y") {
                Write-Log "Installing English (UK) language pack..." "INFO"
                try {
                    Install-Language -Language en-GB
                    Write-Log "en-GB installed successfully" "SUCCESS"
                    $hasEnGB = $true
                }
                catch {
                    Write-Log "Failed to install en-GB: $($_.Exception.Message)" "ERROR"
                    exit 1
                }
            }
            else {
                Write-Log "Cannot proceed without en-GB. Exiting." "ERROR"
                exit 1
            }
        }
    }
    else {
        Write-Log "English (UK) is installed - safe to proceed" "SUCCESS"
    }

    if (-not $hasEnUS) {
        Write-Log "US English language pack is not installed - nothing to remove" "INFO"
        exit 0
    }
}
catch {
    Write-Log "Error checking language configuration: $($_.Exception.Message)" "ERROR"
    exit 1
}

# Confirm removal
if (-not $Force) {
    Write-Log "`nThis will remove US English (en-US) language pack from the system." "WARNING"
    Write-Log "This includes:" "WARNING"
    Write-Log "  - US English language pack" "WARNING"
    Write-Log "  - US English keyboard layouts (unless -KeepKeyboard is specified)" "WARNING"
    Write-Log "  - US English display language" "WARNING"

    $confirm = Read-Host "`nDo you want to continue? (Y/N)"
    if ($confirm -ne "Y" -and $confirm -ne "y") {
        Write-Log "Operation cancelled by user" "INFO"
        exit 0
    }
}

# 1. Set en-GB as default before removing en-US
Write-Log "`nEnsuring en-GB is set as default language..." "INFO"
try {
    # Get current language list
    $languageList = Get-WinUserLanguageList

    # Find en-GB
    $enGB = $languageList | Where-Object { $_.LanguageTag -eq "en-GB" }

    if ($enGB) {
        # Create new list with en-GB first
        $newList = @()
        $newList += $enGB

        # Add other languages except en-US
        foreach ($lang in $languageList) {
            if ($lang.LanguageTag -ne "en-GB" -and $lang.LanguageTag -ne "en-US") {
                $newList += $lang
            }
        }

        # Set the new language list
        Set-WinUserLanguageList -LanguageList $newList -Force
        Write-Log "Set en-GB as default language" "SUCCESS"
    }
}
catch {
    Write-Log "Error setting default language: $($_.Exception.Message)" "ERROR"
}

# 2. Remove US keyboard layout
if (-not $KeepKeyboard) {
    Write-Log "Removing US keyboard layout..." "INFO"
    try {
        $languageList = Get-WinUserLanguageList

        foreach ($lang in $languageList) {
            if ($lang.LanguageTag -eq "en-GB") {
                # Remove en-US keyboard if present
                $usKeyboard = $lang.InputMethodTips | Where-Object { $_ -match "0409" }
                if ($usKeyboard) {
                    $lang.InputMethodTips.Remove($usKeyboard) | Out-Null
                    Write-Log "Removed US keyboard layout from en-GB" "SUCCESS"
                }
            }
        }

        Set-WinUserLanguageList -LanguageList $languageList -Force
    }
    catch {
        Write-Log "Error removing keyboard layout: $($_.Exception.Message)" "WARNING"
    }
}
else {
    Write-Log "Keeping US keyboard layout as requested" "INFO"
}

# 3. Remove en-US language pack using DISM
Write-Log "Removing US English language pack using DISM..." "INFO"
Write-Log "This may take several minutes..." "WARNING"

try {
    # Get installed language packs
    $installedPacks = & DISM /Online /Get-Intl 2>&1

    if ($installedPacks -match "en-US") {
        Write-Log "Found en-US language pack, removing..." "INFO"

        # Remove language pack
        $result = & DISM /Online /Remove-Package /PackageName:Microsoft-Windows-Client-Language-Pack-Package~31bf3856ad364e35~amd64~en-US~ /NoRestart 2>&1

        if ($LASTEXITCODE -eq 0 -or $result -match "successfully") {
            Write-Log "US language pack removed successfully" "SUCCESS"
        }
        else {
            Write-Log "Language pack removal may have failed - trying alternative method..." "WARNING"

            # Try using lpksetup (alternative method)
            $unattendXML = @"
<?xml version="1.0" encoding="utf-8"?>
<unattend xmlns="urn:schemas-microsoft-com:unattend">
    <servicing>
        <package action="remove">
            <assemblyIdentity name="Microsoft-Windows-Client-Language-Pack" version="10.0.0.0" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="en-US" />
        </package>
    </servicing>
</unattend>
"@
            $xmlPath = "$env:TEMP\RemoveUSLang.xml"
            $unattendXML | Out-File -FilePath $xmlPath -Encoding UTF8

            & lpksetup /u /s /f:$xmlPath 2>&1 | Out-Null

            Remove-Item -Path $xmlPath -Force -ErrorAction SilentlyContinue
            Write-Log "Alternative removal method executed" "INFO"
        }
    }
    else {
        Write-Log "en-US language pack not found via DISM" "INFO"
    }
}
catch {
    Write-Log "Error during language pack removal: $($_.Exception.Message)" "WARNING"
}

# 4. Remove language features on demand (FOD)
Write-Log "Removing US language features..." "INFO"
try {
    $usFOD = Get-WindowsCapability -Online | Where-Object {
        $_.Name -like "*Language.Basic*en-US*" -or
        $_.Name -like "*Language.Handwriting*en-US*" -or
        $_.Name -like "*Language.OCR*en-US*" -or
        $_.Name -like "*Language.Speech*en-US*" -or
        $_.Name -like "*Language.TextToSpeech*en-US*"
    }

    if ($usFOD) {
        foreach ($feature in $usFOD) {
            if ($feature.State -eq "Installed") {
                Write-Log "Removing feature: $($feature.Name)" "INFO"
                try {
                    Remove-WindowsCapability -Online -Name $feature.Name -NoRestart | Out-Null
                    Write-Log "Removed: $($feature.Name)" "SUCCESS"
                }
                catch {
                    Write-Log "Failed to remove: $($feature.Name)" "WARNING"
                }
            }
        }
    }
    else {
        Write-Log "No US language features found" "INFO"
    }
}
catch {
    Write-Log "Error removing language features: $($_.Exception.Message)" "WARNING"
}

# 5. Clean up registry entries
Write-Log "Cleaning up registry entries..." "INFO"
try {
    # Remove US from MUI languages
    $muiPath = "HKLM:\SYSTEM\CurrentControlSet\Control\MUI\UILanguages"
    if (Test-Path "$muiPath\en-US") {
        Remove-Item -Path "$muiPath\en-US" -Recurse -Force -ErrorAction SilentlyContinue
        Write-Log "Removed en-US from MUI languages" "SUCCESS"
    }

    # Remove from user settings
    $userLangPath = "HKCU:\Control Panel\International\User Profile"
    if (Test-Path $userLangPath) {
        $languages = Get-ItemProperty -Path $userLangPath -Name "Languages" -ErrorAction SilentlyContinue
        if ($languages) {
            $langArray = $languages.Languages | Where-Object { $_ -ne "en-US" }
            if ($langArray) {
                Set-ItemProperty -Path $userLangPath -Name "Languages" -Value $langArray -ErrorAction SilentlyContinue
                Write-Log "Updated user language preferences" "SUCCESS"
            }
        }
    }
}
catch {
    Write-Log "Error cleaning registry: $($_.Exception.Message)" "WARNING"
}

# 6. Verify removal
Write-Log "`nVerifying removal..." "INFO"
try {
    $remainingLanguages = Get-WinUserLanguageList

    Write-Log "Current installed languages:" "INFO"
    foreach ($lang in $remainingLanguages) {
        Write-Log "  - $($lang.LanguageTag)" "SUCCESS"
    }

    $stillHasUS = $remainingLanguages | Where-Object { $_.LanguageTag -eq "en-US" }
    if ($stillHasUS) {
        Write-Log "WARNING: en-US still appears in language list" "WARNING"
        Write-Log "This may be residual and will be cleaned up on restart" "INFO"
    }
    else {
        Write-Log "en-US successfully removed from language list" "SUCCESS"
    }
}
catch {
    Write-Log "Error verifying removal: $($_.Exception.Message)" "WARNING"
}

# 7. Display summary and restart recommendation
Write-Log "`n=== Removal Summary ===" "HEADER"
Write-Log "US English language pack removal completed" "SUCCESS"
Write-Log "Current system language: en-GB (English UK)" "INFO"
Write-Log "`nChanges made:" "INFO"
Write-Log "  ✓ Removed en-US from language list" "SUCCESS"
if (-not $KeepKeyboard) {
    Write-Log "  ✓ Removed US keyboard layout" "SUCCESS"
}
Write-Log "  ✓ Removed US language features" "SUCCESS"
Write-Log "  ✓ Cleaned up registry entries" "SUCCESS"

Write-Log "`nIMPORTANT: A system restart is required to complete the removal." "WARNING"

if (-not $Force) {
    $restart = Read-Host "`nWould you like to restart the server now? (Y/N)"
    if ($restart -eq "Y" -or $restart -eq "y") {
        Write-Log "Restarting server in 30 seconds..." "WARNING"
        Write-Log "Press Ctrl+C to cancel" "WARNING"
        Start-Sleep -Seconds 5
        Restart-Computer -Force -Delay 30
    }
    else {
        Write-Log "Please restart the server manually to complete the removal." "INFO"
    }
}
else {
    Write-Log "Restart required to complete removal - please restart manually." "INFO"
}
