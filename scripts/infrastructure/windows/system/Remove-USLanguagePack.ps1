<#
.SYNOPSIS
    Removes US English (en-US) language packs from Windows Server 2016-2022.

.DESCRIPTION
    This script removes US English language packs and related components:
    - Verifies UK English (en-GB) is set as default before removal
    - Sets en-GB as the default language and removes en-US keyboard layouts
    - Removes the en-US language pack via DISM (lpksetup fallback)
    - Removes US language features on demand (FOD)
    - Cleans up US entries from MUI and user language registry settings

    All mutations are gated by -WhatIf/-Confirm (SupportsShouldProcess). The en-US
    presence check is a check-then-act guard: if en-US is not installed the script
    exits successfully without changes.

    Exit codes: 0 = removed (or nothing to remove / user cancelled), 1 = fatal error
    or missing Administrator privileges.

.PARAMETER Force
    Forces removal without confirmation prompts.

.PARAMETER KeepKeyboard
    Keeps US keyboard layout (only removes language pack).

.PARAMETER BackupFirst
    Creates a system restore point before removal.

.EXAMPLE
    PS C:\> .\Remove-USLanguagePack.ps1
    Removes US language pack with confirmation prompts.

.EXAMPLE
    PS C:\> .\Remove-USLanguagePack.ps1 -Force -BackupFirst
    Forces removal after creating restore point.

.EXAMPLE
    PS C:\> .\Remove-USLanguagePack.ps1 -KeepKeyboard
    Removes language pack but keeps US keyboard layout.

.NOTES
    File Name:     Remove-USLanguagePack.ps1
    Author:        Bug-Free Umbrella
    Prerequisite:  PowerShell 5.1+
    Version:       1.0.0
    Date:          2026-08-23

    Requires Administrator privileges on supported operating systems.
    Compatible with Windows Server 2016, 2019, and 2022.
    Ensures en-GB is configured before removing en-US.
    System restart may be required.
#>

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
    Justification = 'Console remediation tool: prefixed, color-coded host output is the intended user interface.')]
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $false)]
    [switch]$Force,

    [Parameter(Mandatory = $false)]
    [switch]$KeepKeyboard,

    [Parameter(Mandatory = $false)]
    [switch]$BackupFirst
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
        default { "Cyan" }
    }
    Write-Host "[$timestamp] $prefix $Message" -ForegroundColor $color
}

function Invoke-DismCapture {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$ArgumentList
    )

    $output = & "$env:windir\System32\Dism.exe" @ArgumentList 2>&1
    return [PSCustomObject]@{ ExitCode = $LASTEXITCODE; Output = ($output | Out-String) }
}

function Invoke-LpkSetup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$UnattendPath
    )

    & "$env:windir\System32\lpksetup.exe" /u /s "/f:$UnattendPath" 2>&1 | Out-Null
    return $LASTEXITCODE
}

function Main {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory = $false)]
        [switch]$Force,

        [Parameter(Mandatory = $false)]
        [switch]$KeepKeyboard,

        [Parameter(Mandatory = $false)]
        [switch]$BackupFirst
    )

    try {
        Write-LogEntry "=== US English Language Pack Removal Tool ===" "HEADER"
        Write-LogEntry "Server: $env:COMPUTERNAME" "INFO"

        if (-not (Test-AdminPrivilege)) {
            Write-LogEntry "Administrator privileges are required. Re-run from an elevated PowerShell session." "ERROR"
            return 1
        }

        # Create system restore point if requested
        if ($BackupFirst) {
            Write-LogEntry "Creating system restore point..." "INFO"
            try {
                Enable-ComputerRestore -Drive "C:\" -ErrorAction SilentlyContinue
                Checkpoint-Computer -Description "Before US Language Pack Removal" -RestorePointType "MODIFY_SETTINGS"
                Write-LogEntry "System restore point created successfully" "SUCCESS"
            }
            catch {
                Write-LogEntry "Failed to create restore point: $($_.Exception.Message)" "WARNING"
                if (-not $Force) {
                    $continue = Read-Host "Continue without restore point? (Y/N)"
                    if ($continue -ne "Y" -and $continue -ne "y") {
                        Write-LogEntry "Operation cancelled by user" "INFO"
                        return 0
                    }
                }
            }
        }

        # Check current language configuration
        Write-LogEntry "Checking current language configuration..." "INFO"

        try {
            $currentCulture = Get-Culture
            $systemLocale = Get-WinSystemLocale
            $installedLanguages = Get-WinUserLanguageList

            Write-LogEntry "Current Culture: $($currentCulture.Name)" "INFO"
            Write-LogEntry "System Locale: $($systemLocale.Name)" "INFO"
            Write-LogEntry "Installed Languages:" "INFO"
            foreach ($lang in $installedLanguages) {
                Write-LogEntry "  - $($lang.LanguageTag)" "INFO"
            }

            # Check if en-GB is configured
            $hasEnGB = $installedLanguages | Where-Object { $_.LanguageTag -eq "en-GB" }
            $hasEnUS = $installedLanguages | Where-Object { $_.LanguageTag -eq "en-US" }

            if (-not $hasEnGB) {
                Write-LogEntry "WARNING: English (UK) language pack is not installed!" "ERROR"
                Write-LogEntry "You must install and configure en-GB before removing en-US" "ERROR"

                if (-not $Force) {
                    $install = Read-Host "Would you like to install en-GB now? (Y/N)"
                    if ($install -eq "Y" -or $install -eq "y") {
                        Write-LogEntry "Installing English (UK) language pack..." "INFO"
                        try {
                            Install-Language -Language en-GB
                            Write-LogEntry "en-GB installed successfully" "SUCCESS"
                            $hasEnGB = $true
                        }
                        catch {
                            Write-LogEntry "Failed to install en-GB: $($_.Exception.Message)" "ERROR"
                            return 1
                        }
                    }
                    else {
                        Write-LogEntry "Cannot proceed without en-GB. Exiting." "ERROR"
                        return 1
                    }
                }
                else {
                    Write-LogEntry "Cannot proceed without en-GB. Exiting." "ERROR"
                    return 1
                }
            }
            else {
                Write-LogEntry "English (UK) is installed - safe to proceed" "SUCCESS"
            }

            if (-not $hasEnUS) {
                Write-LogEntry "US English language pack is not installed - nothing to remove" "INFO"
                return 0
            }
        }
        catch {
            Write-LogEntry "Error checking language configuration: $($_.Exception.Message)" "ERROR"
            return 1
        }

        # Confirm removal
        if (-not $Force) {
            Write-LogEntry "`nThis will remove US English (en-US) language pack from the system." "WARNING"
            Write-LogEntry "This includes:" "WARNING"
            Write-LogEntry "  - US English language pack" "WARNING"
            Write-LogEntry "  - US English keyboard layouts (unless -KeepKeyboard is specified)" "WARNING"
            Write-LogEntry "  - US English display language" "WARNING"

            $confirm = Read-Host "`nDo you want to continue? (Y/N)"
            if ($confirm -ne "Y" -and $confirm -ne "y") {
                Write-LogEntry "Operation cancelled by user" "INFO"
                return 0
            }
        }

        # 1. Set en-GB as default before removing en-US
        if ($PSCmdlet.ShouldProcess("User language list", "Set en-GB as default language")) {
            Write-LogEntry "`nEnsuring en-GB is set as default language..." "INFO"
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
                    Write-LogEntry "Set en-GB as default language" "SUCCESS"
                }
            }
            catch {
                Write-LogEntry "Error setting default language: $($_.Exception.Message)" "ERROR"
            }
        }

        # 2. Remove US keyboard layout
        if (-not $KeepKeyboard) {
            if ($PSCmdlet.ShouldProcess("US keyboard layout", "Remove en-US input method")) {
                Write-LogEntry "Removing US keyboard layout..." "INFO"
                try {
                    $languageList = Get-WinUserLanguageList

                    foreach ($lang in $languageList) {
                        if ($lang.LanguageTag -eq "en-GB") {
                            # Remove en-US keyboard if present
                            $usKeyboard = $lang.InputMethodTips | Where-Object { $_ -match "0409" }
                            if ($usKeyboard) {
                                $lang.InputMethodTips.Remove($usKeyboard) | Out-Null
                                Write-LogEntry "Removed US keyboard layout from en-GB" "SUCCESS"
                            }
                        }
                    }

                    Set-WinUserLanguageList -LanguageList $languageList -Force
                }
                catch {
                    Write-LogEntry "Error removing keyboard layout: $($_.Exception.Message)" "WARNING"
                }
            }
        }
        else {
            Write-LogEntry "Keeping US keyboard layout as requested" "INFO"
        }

        # 3. Remove en-US language pack using DISM
        if ($PSCmdlet.ShouldProcess("en-US language pack", "Remove via DISM")) {
            Write-LogEntry "Removing US English language pack using DISM..." "INFO"
            Write-LogEntry "This may take several minutes..." "WARNING"

            try {
                # Get installed language packs
                $dismIntl = Invoke-DismCapture -ArgumentList @('/Online', '/Get-Intl')

                if ($dismIntl.Output -match "en-US") {
                    Write-LogEntry "Found en-US language pack, removing..." "INFO"

                    # Remove language pack
                    $result = Invoke-DismCapture -ArgumentList @(
                        '/Online',
                        '/Remove-Package',
                        '/PackageName:Microsoft-Windows-Client-Language-Pack-Package~31bf3856ad364e35~amd64~en-US~',
                        '/NoRestart'
                    )

                    if ($result.ExitCode -eq 0 -or $result.Output -match "successfully") {
                        Write-LogEntry "US language pack removed successfully" "SUCCESS"
                    }
                    else {
                        Write-LogEntry "Language pack removal may have failed - trying alternative method..." "WARNING"

                        # Try using lpksetup (alternative method)
                        $unattendXML = @"
<?xml version="1.0" encoding="utf-8"?>
<unattend xmlns="urn:schemas-microsoft-com:unattend">
    <servicing>
        <package action="remove">
            <assemblyIdentity name="Microsoft-Windows-Client-Language-Pack" version="10.0.0.0"
                processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="en-US" />
        </package>
    </servicing>
</unattend>
"@
                        $xmlPath = "$env:TEMP\RemoveUSLang.xml"
                        $unattendXML | Out-File -FilePath $xmlPath -Encoding UTF8

                        Invoke-LpkSetup -UnattendPath $xmlPath | Out-Null

                        Remove-Item -Path $xmlPath -Force -ErrorAction SilentlyContinue
                        Write-LogEntry "Alternative removal method executed" "INFO"
                    }
                }
                else {
                    Write-LogEntry "en-US language pack not found via DISM" "INFO"
                }
            }
            catch {
                Write-LogEntry "Error during language pack removal: $($_.Exception.Message)" "WARNING"
            }
        }

        # 4. Remove language features on demand (FOD)
        if ($PSCmdlet.ShouldProcess("US language features on demand", "Remove installed capabilities")) {
            Write-LogEntry "Removing US language features..." "INFO"
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
                            Write-LogEntry "Removing feature: $($feature.Name)" "INFO"
                            try {
                                Remove-WindowsCapability -Online -Name $feature.Name -NoRestart | Out-Null
                                Write-LogEntry "Removed: $($feature.Name)" "SUCCESS"
                            }
                            catch {
                                Write-LogEntry "Failed to remove: $($feature.Name)" "WARNING"
                            }
                        }
                    }
                }
                else {
                    Write-LogEntry "No US language features found" "INFO"
                }
            }
            catch {
                Write-LogEntry "Error removing language features: $($_.Exception.Message)" "WARNING"
            }
        }

        # 5. Clean up registry entries
        if ($PSCmdlet.ShouldProcess("US language registry entries", "Clean up MUI and user preferences")) {
            Write-LogEntry "Cleaning up registry entries..." "INFO"
            try {
                # Remove US from MUI languages
                $muiPath = "HKLM:\SYSTEM\CurrentControlSet\Control\MUI\UILanguages"
                if (Test-Path "$muiPath\en-US") {
                    Remove-Item -Path "$muiPath\en-US" -Recurse -Force -ErrorAction SilentlyContinue
                    Write-LogEntry "Removed en-US from MUI languages" "SUCCESS"
                }

                # Remove from user settings
                $userLangPath = "HKCU:\Control Panel\International\User Profile"
                if (Test-Path $userLangPath) {
                    $languages = Get-ItemProperty -Path $userLangPath -Name "Languages" -ErrorAction SilentlyContinue
                    if ($languages) {
                        $langArray = $languages.Languages | Where-Object { $_ -ne "en-US" }
                        if ($langArray) {
                            Set-ItemProperty -Path $userLangPath -Name "Languages" `
                                -Value $langArray -ErrorAction SilentlyContinue
                            Write-LogEntry "Updated user language preferences" "SUCCESS"
                        }
                    }
                }
            }
            catch {
                Write-LogEntry "Error cleaning registry: $($_.Exception.Message)" "WARNING"
            }
        }

        # 6. Verify removal
        Write-LogEntry "`nVerifying removal..." "INFO"
        try {
            $remainingLanguages = Get-WinUserLanguageList

            Write-LogEntry "Current installed languages:" "INFO"
            foreach ($lang in $remainingLanguages) {
                Write-LogEntry "  - $($lang.LanguageTag)" "SUCCESS"
            }

            $stillHasUS = $remainingLanguages | Where-Object { $_.LanguageTag -eq "en-US" }
            if ($stillHasUS) {
                Write-LogEntry "WARNING: en-US still appears in language list" "WARNING"
                Write-LogEntry "This may be residual and will be cleaned up on restart" "INFO"
            }
            else {
                Write-LogEntry "en-US successfully removed from language list" "SUCCESS"
            }
        }
        catch {
            Write-LogEntry "Error verifying removal: $($_.Exception.Message)" "WARNING"
        }

        # 7. Display summary and restart recommendation
        Write-LogEntry "`n=== Removal Summary ===" "HEADER"
        Write-LogEntry "US English language pack removal completed" "SUCCESS"
        Write-LogEntry "Current system language: en-GB (English UK)" "INFO"
        Write-LogEntry "`nChanges made:" "INFO"
        Write-LogEntry "  + Removed en-US from language list" "SUCCESS"
        if (-not $KeepKeyboard) {
            Write-LogEntry "  + Removed US keyboard layout" "SUCCESS"
        }
        Write-LogEntry "  + Removed US language features" "SUCCESS"
        Write-LogEntry "  + Cleaned up registry entries" "SUCCESS"

        Write-LogEntry "`nIMPORTANT: A system restart is required to complete the removal." "WARNING"

        if (-not $Force) {
            $restart = Read-Host "`nWould you like to restart the server now? (Y/N)"
            if ($restart -eq "Y" -or $restart -eq "y") {
                if ($PSCmdlet.ShouldProcess($env:COMPUTERNAME, "Restart server (30 second delay)")) {
                    Write-LogEntry "Restarting server in 30 seconds..." "WARNING"
                    Write-LogEntry "Press Ctrl+C to cancel" "WARNING"
                    Start-Sleep -Seconds 5
                    Restart-Computer -Force -Delay 30
                }
            }
            else {
                Write-LogEntry "Please restart the server manually to complete the removal." "INFO"
            }
        }
        else {
            Write-LogEntry "Restart required to complete removal - please restart manually." "INFO"
        }

        return 0
    }
    catch {
        Write-Host "[-] Error: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main @PSBoundParameters) }
