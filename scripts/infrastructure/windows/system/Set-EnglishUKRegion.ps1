<#
.SYNOPSIS
    Configures Windows Server to use English (UK) regional settings system-wide.

.DESCRIPTION
    Sets English (United Kingdom) as the system-wide language and regional configuration: system locale,
    UI language, culture, home location, time zone, UK date/time/currency/number formats, keyboard layout,
    and copies international settings to the default user profile (and optionally to every existing user
    profile) by loading each NTUSER.DAT hive with reg.exe. System account and welcome screen settings are
    applied via an unattend XML processed by control.exe.

    This is a configuration-changing operation: all mutations are gated by -WhatIf/-Confirm
    (SupportsShouldProcess). A check-then-act guard makes the script idempotent: on an already-converged
    system it reports success without making further changes. Administrator privileges are enforced by a
    runtime guard (Test-AdminPrivilege) instead of '#Requires -RunAsAdministrator', which would prevent
    offline test dot-sourcing.

    Exit codes: 0 = configured (or already converged / WhatIf dry-run), 1 = fatal error such as missing
    Administrator privileges or an unavailable International module.

.PARAMETER TimeZone
    Timezone to set (default: 'GMT Standard Time' for UK).
    Use 'Get-TimeZone -ListAvailable' to see all options.

.PARAMETER ApplyToExistingUsers
    Applies settings to all existing user profiles.

.PARAMETER SkipTimeZone
    Skips timezone configuration.

.PARAMETER SkipKeyboard
    Skips keyboard layout configuration.

.PARAMETER Restart
    Restarts the server automatically 30 seconds after configuration completes
    instead of only recommending a manual restart.

.EXAMPLE
    PS C:\> .\Set-EnglishUKRegion.ps1
    Sets English UK regional settings with the default timezone.

.EXAMPLE
    PS C:\> .\Set-EnglishUKRegion.ps1 -ApplyToExistingUsers
    Sets English UK settings and applies them to all existing users.

.EXAMPLE
    PS C:\> .\Set-EnglishUKRegion.ps1 -TimeZone "GMT Standard Time" -WhatIf
    Shows which changes would be applied without modifying the system.

.NOTES
    File Name:     Set-EnglishUKRegion.ps1
    Author:        Bug-Free Umbrella
    Prerequisite:  PowerShell 5.1+
    Version:       1.0.0
    Date:          2026-08-23

    Requires Administrator privileges on supported operating systems (enforced at runtime).
    Compatible with Windows Server 2016, 2019, and 2022.
    A system restart is recommended after running this script.
#>

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
    Justification = 'Console remediation tool: prefixed, color-coded host output is the intended user interface.')]
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$TimeZone = "GMT Standard Time",

    [Parameter(Mandatory = $false)]
    [switch]$ApplyToExistingUsers,

    [Parameter(Mandatory = $false)]
    [switch]$SkipTimeZone,

    [Parameter(Mandatory = $false)]
    [switch]$SkipKeyboard,

    [Parameter(Mandatory = $false)]
    [switch]$Restart
)

$ErrorActionPreference = 'Stop'

function Test-AdminPrivilege {
    [CmdletBinding()]
    param()

    try {
        $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = [System.Security.Principal.WindowsPrincipal]$identity
        return $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch {
        # Non-Windows platform or unavailable identity APIs.
        return $false
    }
}

function Write-LogEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [ValidateSet("INFO", "SUCCESS", "WARNING", "ERROR", "HEADER")]
        [string]$Type = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $prefix = switch ($Type) {
        "ERROR" { "[-]" }
        "SUCCESS" { "[+]" }
        "WARNING" { "[!]" }
        default { "[*]" }
    }
    $color = switch ($Type) {
        "ERROR" { "Red" }
        "SUCCESS" { "Green" }
        "WARNING" { "Yellow" }
        "HEADER" { "Cyan" }
        default { "White" }
    }
    Write-Host "[$timestamp] $prefix $Message" -ForegroundColor $color
}

function Invoke-Reg {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string[]]$ArgumentList
    )

    $output = & reg.exe @ArgumentList 2>&1
    return [PSCustomObject]@{ ExitCode = $LASTEXITCODE; Output = ($output | Out-String) }
}

function Invoke-ControlIntlCpl {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$XmlPath
    )

    return Start-Process -FilePath "$env:SystemRoot\System32\control.exe" `
        -ArgumentList "intl.cpl,,/f:`"$XmlPath`"" -Wait -PassThru -WindowStyle Hidden -ErrorAction Stop
}

function Test-RegistryHiveLoaded {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$HiveName
    )
    $result = Invoke-Reg -ArgumentList @('query', 'HKU')
    return ($result.Output -match [regex]::Escape($HiveName))
}

function Import-RegistryHive {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$HiveName,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$HivePath
    )

    if (-not (Test-Path -LiteralPath $HivePath)) {
        Write-LogEntry "Registry hive file not found: $HivePath" "WARNING"
        return $null
    }

    if (Test-RegistryHiveLoaded -HiveName $HiveName) {
        Write-LogEntry "Registry hive '$HiveName' is already loaded" "INFO"
        return $null  # Already loaded; we did not load it ourselves.
    }

    try {
        $result = Invoke-Reg -ArgumentList @('load', $HiveName, $HivePath)
        if ($result.ExitCode -eq 0) {
            Write-LogEntry "Successfully loaded registry hive: $HiveName" "SUCCESS"
            return $true  # We loaded it; caller must unload.
        }
        Write-LogEntry "Failed to load registry hive: $($result.Output.Trim())" "ERROR"
        return $false
    }
    catch {
        Write-LogEntry "Error loading registry hive: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

function Dismount-RegistryHive {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$HiveName,

        [Parameter(Mandatory = $false)]
        [object]$WeLoadedIt
    )

    if ($WeLoadedIt -ne $true) {
        Write-LogEntry "Skipping unload of '$HiveName' (not loaded by this session)" "INFO"
        return
    }

    try {
        # Force garbage collection to release any handles.
        [System.GC]::Collect()
        [System.GC]::WaitForPendingFinalizers()
        Start-Sleep -Milliseconds 500

        $result = Invoke-Reg -ArgumentList @('unload', $HiveName)
        if ($result.ExitCode -eq 0) {
            Write-LogEntry "Successfully unloaded registry hive: $HiveName" "SUCCESS"
        }
        else {
            Write-LogEntry "Warning: Could not unload registry hive: $($result.Output.Trim())" "WARNING"
        }
    }
    catch {
        Write-LogEntry "Error unloading registry hive: $($_.Exception.Message)" "WARNING"
    }
}

function Main {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    try {
        if (-not (Test-AdminPrivilege)) {
            Write-LogEntry "Administrator privileges required. Run from an elevated PowerShell session." "ERROR"
            return 1
        }

        Write-LogEntry "=== Configuring English (UK) Regional Settings ===" "HEADER"
        Write-LogEntry "Server: $env:COMPUTERNAME" "INFO"

        # Check if International module is available.
        if (-not (Get-Module -ListAvailable -Name International)) {
            Write-LogEntry "International PowerShell module not found. Attempting import..." "WARNING"
            try {
                Import-Module International -ErrorAction Stop
                Write-LogEntry "International module imported successfully" "SUCCESS"
            }
            catch {
                throw "Failed to import International module: $($_.Exception.Message)"
            }
        }

        # Check-then-act: skip all mutations when the system has already converged.
        $converged = $false
        try {
            $systemLocale = Get-WinSystemLocale -ErrorAction Stop
            $culture = Get-Culture -ErrorAction Stop
            $homeLocation = Get-WinHomeLocation -ErrorAction Stop
            $uiOverride = Get-WinUILanguageOverride -ErrorAction Stop
            $converged = ($systemLocale.Name -eq 'en-GB') -and ($culture.Name -eq 'en-GB') -and
            ($homeLocation.GeoId -eq 242) -and ($uiOverride -eq 'en-GB')

            if ($converged -and -not $SkipTimeZone) {
                $currentTimeZone = Get-TimeZone -ErrorAction Stop
                $converged = ($currentTimeZone.Id -eq $TimeZone)
            }
        }
        catch {
            $converged = $false
        }

        if ($converged) {
            Write-LogEntry "System is already configured for English (United Kingdom). No changes required." "SUCCESS"
            return 0
        }

        if (-not $PSCmdlet.ShouldProcess("Computer '$env:COMPUTERNAME'", "Configure English (UK) regional settings")) {
            Write-LogEntry "WhatIf mode: no changes were applied." "INFO"
            return 0
        }

        # 1. Set System Locale and Culture to English (UK)
        Write-LogEntry "Setting system locale to English (United Kingdom)..." "INFO"
        try {
            Set-WinSystemLocale -SystemLocale en-GB -ErrorAction Stop
            Write-LogEntry "System locale set to en-GB" "SUCCESS"

            Set-WinUILanguageOverride -Language en-GB -ErrorAction Stop
            Write-LogEntry "UI Language override set to en-GB" "SUCCESS"

            Set-Culture -CultureInfo en-GB -ErrorAction Stop
            Write-LogEntry "Culture set to en-GB" "SUCCESS"

            # 242 = United Kingdom.
            Set-WinHomeLocation -GeoId 242 -ErrorAction Stop
            Write-LogEntry "Home location set to United Kingdom" "SUCCESS"
        }
        catch {
            Write-LogEntry "Error setting locale: $($_.Exception.Message)" "ERROR"
        }

        # 2. Set Timezone (check-then-act: skip when already correct)
        if (-not $SkipTimeZone) {
            Write-LogEntry "Setting timezone to $TimeZone..." "INFO"
            try {
                $currentId = (Get-TimeZone -ErrorAction Stop).Id
                if ($currentId -eq $TimeZone) {
                    Write-LogEntry "Timezone is already set to $TimeZone" "SUCCESS"
                }
                else {
                    $availableTimeZones = Get-TimeZone -ListAvailable -ErrorAction Stop
                    $selectedTimeZone = $availableTimeZones | Where-Object { $_.Id -eq $TimeZone }

                    if ($selectedTimeZone) {
                        Set-TimeZone -Id $TimeZone -ErrorAction Stop
                        Write-LogEntry "Timezone set to $TimeZone" "SUCCESS"
                    }
                    else {
                        Write-LogEntry "Timezone '$TimeZone' not found. Available UK timezones:" "WARNING"
                        $availableTimeZones | Where-Object { $_.Id -match "GMT|GMT Standard Time" } | ForEach-Object {
                            Write-LogEntry "  - $($_.Id)" "INFO"
                        }
                    }
                }
            }
            catch {
                Write-LogEntry "Error setting timezone: $($_.Exception.Message)" "ERROR"
            }
        }

        # 3. Configure Regional Format Settings
        Write-LogEntry "Configuring regional format settings..." "INFO"
        try {
            $registryPath = "HKCU:\Control Panel\International"

            # UK date format: DD/MM/YYYY
            Set-ItemProperty -Path $registryPath -Name "sShortDate" -Value "dd/MM/yyyy" -ErrorAction Stop
            Set-ItemProperty -Path $registryPath -Name "sLongDate" -Value "dd MMMM yyyy" -ErrorAction Stop

            # UK time format: 24-hour
            Set-ItemProperty -Path $registryPath -Name "sTimeFormat" -Value "HH:mm:ss" -ErrorAction Stop
            Set-ItemProperty -Path $registryPath -Name "sShortTime" -Value "HH:mm" -ErrorAction Stop

            # First day of week: Monday (0 = Monday)
            Set-ItemProperty -Path $registryPath -Name "iFirstDayOfWeek" -Value "0" -ErrorAction Stop

            # Currency format: GBP
            Set-ItemProperty -Path $registryPath -Name "sCurrency" -Value "£" -ErrorAction Stop

            # Number format: decimal separator '.', thousands separator ','
            Set-ItemProperty -Path $registryPath -Name "sDecimal" -Value "." -ErrorAction Stop
            Set-ItemProperty -Path $registryPath -Name "sThousand" -Value "," -ErrorAction Stop

            # Measurement system: Metric (0 = Metric)
            Set-ItemProperty -Path $registryPath -Name "iMeasure" -Value "0" -ErrorAction Stop

            Write-LogEntry "Regional format settings configured" "SUCCESS"
        }
        catch {
            Write-LogEntry "Error configuring regional formats: $($_.Exception.Message)" "ERROR"
        }

        # 4. Set Keyboard Layout to UK English
        if (-not $SkipKeyboard) {
            Write-LogEntry "Setting keyboard layout to UK English..." "INFO"
            try {
                # UK English keyboard layout code: 0809:00000809
                Set-WinUserLanguageList -LanguageList en-GB -Force -ErrorAction Stop
                Write-LogEntry "Keyboard layout set to UK English" "SUCCESS"
            }
            catch {
                Write-LogEntry "Error setting keyboard layout: $($_.Exception.Message)" "ERROR"
            }
        }

        # 5. Apply settings system-wide (default user profile and welcome screen)
        Write-LogEntry "Applying settings to system-wide defaults..." "INFO"
        try {
            $defaultUserHive = "HKU\DEFAULT_USER"
            $defaultUserPath = "C:\Users\Default\NTUSER.DAT"

            $hiveLoaded = Import-RegistryHive -HiveName $defaultUserHive -HivePath $defaultUserPath

            if ($hiveLoaded -ne $false) {
                # Copy international settings into the default profile.
                $copyResult = Invoke-Reg -ArgumentList @(
                    'copy', 'HKCU\Control Panel\International',
                    "$defaultUserHive\Control Panel\International", '/s', '/f'
                )
                if ($copyResult.ExitCode -eq 0) {
                    Write-LogEntry "Settings applied to default user profile" "SUCCESS"
                }
                else {
                    $copyOut = $copyResult.Output.Trim()
                    Write-LogEntry "Warning: Could not copy settings to default user profile: $copyOut" "WARNING"
                }

                Dismount-RegistryHive -HiveName $defaultUserHive -WeLoadedIt $hiveLoaded
            }

            Write-LogEntry "Applying system-wide language settings..." "INFO"
            try {
                # Unattend XML copies current user settings to the system and default user accounts.
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

                # Honour %TEMP%; fall back for environments where it is not set (e.g. Linux CI).
                $tempDir = if ($env:TEMP) { $env:TEMP } else { [System.IO.Path]::GetTempPath() }
                $xmlPath = Join-Path -Path $tempDir -ChildPath "EnglishUK_Settings.xml"
                # UTF-8 with BOM; .NET write avoids Out-File -Encoding binding differences between 5.1 and 7.x.
                $utf8Bom = New-Object System.Text.UTF8Encoding($true)
                [System.IO.File]::WriteAllText($xmlPath, $xmlContent, $utf8Bom)

                $process = Invoke-ControlIntlCpl -XmlPath $xmlPath

                if ($process.ExitCode -eq 0 -or $null -eq $process.ExitCode) {
                    Write-LogEntry "System-wide settings applied via XML" "SUCCESS"
                }
                else {
                    Write-LogEntry "XML application completed with exit code: $($process.ExitCode)" "WARNING"
                }

                Remove-Item -Path $xmlPath -Force -ErrorAction SilentlyContinue
            }
            catch {
                Write-LogEntry "Could not apply XML settings: $($_.Exception.Message)" "WARNING"
                Write-LogEntry "Settings have been applied to current user and default profile" "INFO"
            }
        }
        catch {
            Write-LogEntry "Error applying system-wide settings: $($_.Exception.Message)" "WARNING"
        }

        # 6. Apply to existing user profiles (if specified)
        if ($ApplyToExistingUsers) {
            Write-LogEntry "Applying settings to existing user profiles..." "INFO"

            try {
                $userProfiles = Get-ChildItem -Path "C:\Users" `
                    -Directory -Exclude "Public", "Default*" -ErrorAction Stop

                foreach ($userProfile in $userProfiles) {
                    $profilePath = $userProfile.FullName
                    $userName = $userProfile.Name

                    Write-LogEntry "  Configuring profile: $userName" "INFO"

                    $userHive = "HKU\TEMP_$userName"
                    $ntUserDat = Join-Path -Path $profilePath -ChildPath "NTUSER.DAT"

                    if (Test-Path -LiteralPath $ntUserDat) {
                        $userHiveLoaded = Import-RegistryHive -HiveName $userHive -HivePath $ntUserDat

                        if ($userHiveLoaded -ne $false) {
                            $copyResult = Invoke-Reg -ArgumentList @(
                                'copy', 'HKCU\Control Panel\International',
                                "$userHive\Control Panel\International", '/s', '/f'
                            )

                            if ($copyResult.ExitCode -eq 0) {
                                Write-LogEntry "  Profile '$userName' updated" "SUCCESS"
                            }
                            else {
                                $copyOut = $copyResult.Output.Trim()
                                Write-LogEntry "  Could not copy settings to '$userName': $copyOut" "WARNING"
                            }

                            Dismount-RegistryHive -HiveName $userHive -WeLoadedIt $userHiveLoaded
                        }
                        else {
                            Write-LogEntry "  Could not load registry for '$userName' (may be logged in)" "WARNING"
                        }
                    }
                    else {
                        Write-LogEntry "  NTUSER.DAT not found for '$userName'" "WARNING"
                    }
                }
            }
            catch {
                Write-LogEntry "Error applying to existing users: $($_.Exception.Message)" "WARNING"
            }
        }

        # 7. Display current settings
        Write-LogEntry "`n=== Current Regional Settings ===" "HEADER"
        try {
            $displayCulture = Get-Culture -ErrorAction Stop
            $displayTimeZone = Get-TimeZone -ErrorAction Stop
            $displayLocation = Get-WinHomeLocation -ErrorAction Stop
            $displayLocale = Get-WinSystemLocale -ErrorAction Stop

            Write-LogEntry "Culture:              $($displayCulture.Name) - $($displayCulture.DisplayName)" "INFO"
            Write-LogEntry "System Locale:        $($displayLocale.Name) - $($displayLocale.DisplayName)" "INFO"
            Write-LogEntry "Timezone:             $($displayTimeZone.Id) ($($displayTimeZone.DisplayName))" "INFO"
            Write-LogEntry "Home Location:        $($displayLocation.HomeLocation)" "INFO"
            Write-LogEntry "Date Format:          $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')" "INFO"
            Write-LogEntry "Currency:             £ (GBP)" "INFO"
            Write-LogEntry "First Day of Week:    Monday" "INFO"
            Write-LogEntry "Measurement System:   Metric" "INFO"
        }
        catch {
            Write-LogEntry "Error displaying current settings: $($_.Exception.Message)" "WARNING"
        }

        Write-LogEntry "`n=== Configuration Complete ===" "HEADER"

        if ($Restart) {
            Write-LogEntry "Restarting server in 30 seconds..." "WARNING"
            Write-LogEntry "Press Ctrl+C to cancel" "WARNING"
            Start-Sleep -Seconds 5
            Restart-Computer -Force -Delay 30 -ErrorAction Stop
        }
        else {
            Write-LogEntry "IMPORTANT: A system restart is recommended to apply all settings." "WARNING"
            Write-LogEntry "Please restart the server manually when convenient." "INFO"
            Write-LogEntry "Some applications may require a restart to use new regional settings." "INFO"
        }

        return 0
    }
    catch {
        Write-LogEntry "Error: $($_.Exception.Message)" "ERROR"
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main @PSBoundParameters) }
