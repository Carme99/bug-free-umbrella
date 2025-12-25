<#
.SYNOPSIS
    Configures Windows Server to use English (UK) regional settings system-wide.

.DESCRIPTION
    This script sets English (UK) as the system-wide language and regional settings including:
    - System locale to English (United Kingdom)
    - Timezone to GMT/BST
    - Date/time formats to UK standard (DD/MM/YYYY)
    - Currency to GBP (£)
    - First day of week to Monday
    - Measurement system to Metric
    - Keyboard layout to UK English
    - Applies settings to system, new users, and welcome screen

.PARAMETER TimeZone
    Timezone to set (default: 'GMT Standard Time' for UK).
    Use 'Get-TimeZone -ListAvailable' to see all options.

.PARAMETER ApplyToExistingUsers
    Applies settings to all existing user profiles.

.PARAMETER SkipTimeZone
    Skips timezone configuration.

.PARAMETER SkipKeyboard
    Skips keyboard layout configuration.

.EXAMPLE
    .\Set-EnglishUKRegion.ps1
    Sets English UK regional settings with default timezone.

.EXAMPLE
    .\Set-EnglishUKRegion.ps1 -ApplyToExistingUsers
    Sets English UK settings and applies to all existing users.

.EXAMPLE
    .\Set-EnglishUKRegion.ps1 -TimeZone "GMT Standard Time"
    Sets English UK with GMT timezone explicitly.

.NOTES
    Requires Administrator privileges
    Compatible with Windows Server 2016, 2019, and 2022
    A system restart is recommended after running this script
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$TimeZone = "GMT Standard Time",

    [Parameter(Mandatory=$false)]
    [switch]$ApplyToExistingUsers,

    [Parameter(Mandatory=$false)]
    [switch]$SkipTimeZone,

    [Parameter(Mandatory=$false)]
    [switch]$SkipKeyboard
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

Write-Log "=== Configuring English (UK) Regional Settings ===" "HEADER"
Write-Log "Server: $env:COMPUTERNAME" "INFO"

# Check if International module is available
if (-not (Get-Module -ListAvailable -Name International)) {
    Write-Log "International PowerShell module not found. Installing..." "WARNING"
    try {
        Import-Module International -ErrorAction Stop
        Write-Log "International module imported successfully" "SUCCESS"
    }
    catch {
        Write-Log "Failed to import International module: $($_.Exception.Message)" "ERROR"
        exit 1
    }
}

# 1. Set System Locale and Culture to English (UK)
Write-Log "Setting system locale to English (United Kingdom)..." "INFO"
try {
    # Set system locale (en-GB)
    Set-WinSystemLocale -SystemLocale en-GB
    Write-Log "System locale set to en-GB" "SUCCESS"

    # Set user language list
    Set-WinUILanguageOverride -Language en-GB
    Write-Log "UI Language override set to en-GB" "SUCCESS"

    # Set culture (regional format)
    Set-Culture -CultureInfo en-GB
    Write-Log "Culture set to en-GB" "SUCCESS"

    # Set home location to United Kingdom
    Set-WinHomeLocation -GeoId 242  # 242 = United Kingdom
    Write-Log "Home location set to United Kingdom" "SUCCESS"
}
catch {
    Write-Log "Error setting locale: $($_.Exception.Message)" "ERROR"
}

# 2. Set Timezone
if (-not $SkipTimeZone) {
    Write-Log "Setting timezone to $TimeZone..." "INFO"
    try {
        # Verify timezone exists
        $availableTimeZones = Get-TimeZone -ListAvailable
        $selectedTimeZone = $availableTimeZones | Where-Object { $_.Id -eq $TimeZone }

        if ($selectedTimeZone) {
            Set-TimeZone -Id $TimeZone
            Write-Log "Timezone set to $TimeZone" "SUCCESS"
        }
        else {
            Write-Log "Timezone '$TimeZone' not found. Available UK timezones:" "WARNING"
            $availableTimeZones | Where-Object { $_.Id -match "GMT|GMT Standard Time" } | ForEach-Object {
                Write-Log "  - $($_.Id)" "INFO"
            }
        }
    }
    catch {
        Write-Log "Error setting timezone: $($_.Exception.Message)" "ERROR"
    }
}

# 3. Configure Regional Format Settings
Write-Log "Configuring regional format settings..." "INFO"
try {
    # Set date/time formats to UK standard
    $registryPath = "HKCU:\Control Panel\International"

    # UK date format: DD/MM/YYYY
    Set-ItemProperty -Path $registryPath -Name "sShortDate" -Value "dd/MM/yyyy" -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $registryPath -Name "sLongDate" -Value "dd MMMM yyyy" -ErrorAction SilentlyContinue

    # UK time format: 24-hour
    Set-ItemProperty -Path $registryPath -Name "sTimeFormat" -Value "HH:mm:ss" -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $registryPath -Name "sShortTime" -Value "HH:mm" -ErrorAction SilentlyContinue

    # First day of week: Monday (1)
    Set-ItemProperty -Path $registryPath -Name "iFirstDayOfWeek" -Value "0" -ErrorAction SilentlyContinue  # 0 = Monday

    # Currency format: GBP
    Set-ItemProperty -Path $registryPath -Name "sCurrency" -Value "£" -ErrorAction SilentlyContinue

    # Number format: Decimal separator = . , Thousands separator = ,
    Set-ItemProperty -Path $registryPath -Name "sDecimal" -Value "." -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $registryPath -Name "sThousand" -Value "," -ErrorAction SilentlyContinue

    # Measurement system: Metric
    Set-ItemProperty -Path $registryPath -Name "iMeasure" -Value "0" -ErrorAction SilentlyContinue  # 0 = Metric

    Write-Log "Regional format settings configured" "SUCCESS"
}
catch {
    Write-Log "Error configuring regional formats: $($_.Exception.Message)" "ERROR"
}

# 4. Set Keyboard Layout to UK English
if (-not $SkipKeyboard) {
    Write-Log "Setting keyboard layout to UK English..." "INFO"
    try {
        # UK English keyboard layout code: 0809:00000809
        Set-WinUserLanguageList -LanguageList en-GB -Force
        Write-Log "Keyboard layout set to UK English" "SUCCESS"
    }
    catch {
        Write-Log "Error setting keyboard layout: $($_.Exception.Message)" "ERROR"
    }
}

# 5. Apply settings to system-wide (default user profile and welcome screen)
Write-Log "Applying settings to system-wide defaults..." "INFO"
try {
    # Copy settings to default user profile
    $defaultUserHive = "HKU\DEFAULT_USER"
    $currentUserSettings = "HKCU:\Control Panel\International"

    # Load default user registry hive
    & reg load "HKU\DEFAULT_USER" "C:\Users\Default\NTUSER.DAT" 2>&1 | Out-Null

    # Copy international settings
    & reg copy "HKCU\Control Panel\International" "HKU\DEFAULT_USER\Control Panel\International" /s /f 2>&1 | Out-Null

    # Unload default user hive
    & reg unload "HKU\DEFAULT_USER" 2>&1 | Out-Null

    Write-Log "Settings applied to default user profile" "SUCCESS"

    # Set system-wide language settings
    $xmlContent = @"
<gs:GlobalizationServices xmlns:gs="urn:longhornGlobalizationUnattend">
    <gs:UserList>
        <gs:User UserID="Current" CopySettingsToDefaultUserAcct="true" CopySettingsToSystemAcct="true"/>
    </gs:UserList>
    <gs:InputPreferences>
        <gs:InputLanguageID Action="add" ID="0809:00000809"/>
    </gs:InputPreferences>
    <gs:MUILanguage Value="en-GB"/>
    <gs:SystemLocale Name="en-GB"/>
    <gs:UserLocale>
        <gs:Locale Name="en-GB" SetAsCurrent="true" ResetAllSettings="true"/>
    </gs:UserLocale>
</gs:GlobalizationServices>
"@

    $xmlPath = "$env:TEMP\EnglishUK_Settings.xml"
    $xmlContent | Out-File -FilePath $xmlPath -Encoding UTF8

    # Apply XML settings system-wide
    & control intl.cpl,,/f:"$xmlPath" 2>&1 | Out-Null

    Write-Log "System-wide settings applied" "SUCCESS"

    Remove-Item -Path $xmlPath -Force -ErrorAction SilentlyContinue
}
catch {
    Write-Log "Error applying system-wide settings: $($_.Exception.Message)" "WARNING"
}

# 6. Apply to existing user profiles (if specified)
if ($ApplyToExistingUsers) {
    Write-Log "Applying settings to existing user profiles..." "INFO"

    try {
        $userProfiles = Get-ChildItem -Path "C:\Users" -Directory -Exclude "Public", "Default*"

        foreach ($profile in $userProfiles) {
            $profilePath = $profile.FullName
            $userName = $profile.Name

            Write-Log "  Configuring profile: $userName" "INFO"

            # Load user registry hive
            $userHive = "HKU\$userName"
            $ntUserDat = "$profilePath\NTUSER.DAT"

            if (Test-Path $ntUserDat) {
                & reg load $userHive $ntUserDat 2>&1 | Out-Null

                # Copy settings
                & reg copy "HKCU\Control Panel\International" "$userHive\Control Panel\International" /s /f 2>&1 | Out-Null

                # Unload hive
                & reg unload $userHive 2>&1 | Out-Null

                Write-Log "  Profile '$userName' updated" "SUCCESS"
            }
        }
    }
    catch {
        Write-Log "Error applying to existing users: $($_.Exception.Message)" "WARNING"
    }
}

# 7. Display current settings
Write-Log "`n=== Current Regional Settings ===" "HEADER"
try {
    $culture = Get-Culture
    $timezone = Get-TimeZone
    $location = Get-WinHomeLocation

    Write-Log "Culture:              $($culture.Name) - $($culture.DisplayName)" "INFO"
    Write-Log "System Locale:        $(Get-WinSystemLocale)" "INFO"
    Write-Log "Timezone:             $($timezone.Id) ($($timezone.DisplayName))" "INFO"
    Write-Log "Home Location:        $($location.HomeLocation)" "INFO"
    Write-Log "Date Format:          $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')" "INFO"
    Write-Log "Currency:             £ (GBP)" "INFO"
    Write-Log "First Day of Week:    Monday" "INFO"
    Write-Log "Measurement System:   Metric" "INFO"
}
catch {
    Write-Log "Error displaying current settings: $($_.Exception.Message)" "WARNING"
}

Write-Log "`n=== Configuration Complete ===" "HEADER"
Write-Log "IMPORTANT: A system restart is recommended to apply all settings." "WARNING"
Write-Log "Some applications may require a restart to use new regional settings." "INFO"

# Ask for restart
$restart = Read-Host "`nWould you like to restart the server now? (Y/N)"
if ($restart -eq "Y" -or $restart -eq "y") {
    Write-Log "Restarting server in 30 seconds..." "WARNING"
    Write-Log "Press Ctrl+C to cancel" "WARNING"
    Start-Sleep -Seconds 5
    Restart-Computer -Force -Delay 30
}
else {
    Write-Log "Please restart the server manually when convenient." "INFO"
}
