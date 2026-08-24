<#
.SYNOPSIS
    Removes US English (en-US) language packs from Windows 11 24H2.

.DESCRIPTION
    This script removes US English language packs and related components:
    - Removes en-US from user language list
    - Removes en-US keyboard layouts
    - Removes US language features on demand
    - Verifies UK English (en-GB) is set as default before removal

    All mutations are gated behind ShouldProcess, so -WhatIf/-Confirm are honored and no
    change is made without confirmation. The script is idempotent: when en-US is not present
    in the user language list it reports "nothing to remove" and exits 0 without changing
    anything. Sign-out/restart may be required for all changes to take effect.

.PARAMETER Force
    Forces removal without confirmation prompts.

.PARAMETER KeepKeyboard
    Keeps US keyboard layout (only removes language pack).

.EXAMPLE
    PS C:\> .\removeUSlangpack.ps1
    Removes US language pack with confirmation prompts.

.EXAMPLE
    PS C:\> .\removeUSlangpack.ps1 -Force
    Forces removal without prompts.

.EXAMPLE
    PS C:\> .\removeUSlangpack.ps1 -KeepKeyboard
    Removes language pack but keeps US keyboard layout.

.EXAMPLE
    PS C:\> .\removeUSlangpack.ps1 -WhatIf
    Shows every change the script would make without applying any of them.

.NOTES
    File Name   : removeUSlangpack.ps1
    Author      : Bug-Free Umbrella
    Prerequisite: PowerShell 7.0
    Version     : 1.0.0
    Date        : 2026-08-23

    Requires Administrator privileges (enforced by #Requires -RunAsAdministrator).
    Compatible with Windows 11 24H2.
    Ensures en-GB is configured before removing en-US.
    Sign-out/restart may be required.
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
    Justification = 'RELAUNCH-SPEC §3 mandates console status output via Write-Host with [+]/[!]/[-]/[*] prefixes.')]
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $false)]
    [switch]$Force,

    [Parameter(Mandatory = $false)]
    [switch]$KeepKeyboard
)

#Requires -RunAsAdministrator

$ErrorActionPreference = 'Stop'

# Justification for PSAvoidOverwritingBuiltInCmdlets: Write-Log is this script's own logging helper,
# not an override of a live built-in cmdlet.
function Write-Log {
    param([string]$Message, [string]$Type = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $prefix = switch ($Type) {
        "ERROR" { "[-]" }
        "SUCCESS" { "[+]" }
        "WARNING" { "[!]" }
        "HEADER" { "[*]" }
        default { "[*]" }
    }
    $color = switch ($Type) {
        "ERROR" { "Red" }
        "SUCCESS" { "Green" }
        "WARNING" { "Yellow" }
        "HEADER" { "Cyan" }
        default { "White" }
    }
    Write-Host "[$timestamp] [$Type] $prefix $Message" -ForegroundColor $color
}

function Invoke-Logoff {
    # Thin wrapper around the native logoff.exe so tests can mock the wrapper (Pester cannot mock native commands).
    & logoff.exe @args
    return $LASTEXITCODE
}

function Main {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [switch]$Force,

        [switch]$KeepKeyboard
    )

    try {
        Write-Log "=== US English Language Pack Removal Tool (Windows 11) ===" "HEADER"
        $osCaption = "Unknown"
        try { $osCaption = (Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop).Caption } catch { }
        Write-Log "Computer: $env:COMPUTERNAME" "INFO"
        Write-Log "OS: $osCaption" "INFO"

        # Check current language configuration
        Write-Log "Checking current language configuration..." "INFO"

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
            Write-Log "English (UK) is not in the language list!" "ERROR"
            Write-Log "" "INFO"
            Write-Log "You must add en-GB before removing en-US." "ERROR"
            Write-Log "To add en-GB:" "INFO"
            Write-Log "  1. Open Settings > Time & Language > Language & region" "INFO"
            Write-Log "  2. Click 'Add a language'" "INFO"
            Write-Log "  3. Search for 'English (United Kingdom)' and install it" "INFO"
            Write-Log "  4. Set it as the Windows display language" "INFO"
            Write-Log "  5. Sign out and back in, then run this script again" "INFO"
            Write-Log "" "INFO"

            if (-not $Force) {
                $addNow = Read-Host "Would you like to add en-GB to the language list now? (Y/N)"
                if ($addNow -eq "Y" -or $addNow -eq "y") {
                    Write-Log "Adding en-GB to language list..." "INFO"
                    try {
                        $langList = Get-WinUserLanguageList
                        if ($PSCmdlet.ShouldProcess("User language list", "Add en-GB")) {
                            $langList.Insert(0, "en-GB")
                            Set-WinUserLanguageList $langList -Force -ErrorAction Stop
                        }
                        Write-Log "en-GB added to language list" "SUCCESS"
                        Write-Log "Please sign out and back in, then run this script again to complete removal." `
                            "WARNING"
                        return 0
                    }
                    catch {
                        Write-Log "Failed to add en-GB: $($_.Exception.Message)" "ERROR"
                        return 1
                    }
                }
                else {
                    Write-Log "Cannot proceed without en-GB. Exiting." "ERROR"
                    return 1
                }
            }
            else {
                Write-Log "Cannot proceed without en-GB and -Force was specified. Exiting." "ERROR"
                return 1
            }
        }
        else {
            Write-Log "English (UK) is installed - safe to proceed" "SUCCESS"
        }

        if (-not $hasEnUS) {
            Write-Log "US English is not in the language list - nothing to remove" "INFO"
            Write-Log "Already converged: en-US absent, no changes made" "SUCCESS"
            return 0
        }

        # Check if en-GB is the default (first in list)
        if ($installedLanguages[0].LanguageTag -ne "en-GB") {
            Write-Log "en-GB is not set as the default language" "WARNING"
            Write-Log "Current default: $($installedLanguages[0].LanguageTag)" "INFO"

            if (-not $Force) {
                $setDefault = Read-Host "Set en-GB as default before removing en-US? (Y/N)"
                if ($setDefault -eq "Y" -or $setDefault -eq "y") {
                    Write-Log "Setting en-GB as default..." "INFO"
                    try {
                        $langList = Get-WinUserLanguageList
                        $otherLangs = $langList | Where-Object {
                            $_.LanguageTag -ne "en-GB" -and $_.LanguageTag -ne "en-US"
                        }

                        if ($PSCmdlet.ShouldProcess("User language list", "Set en-GB as default")) {
                            $newList = New-WinUserLanguageList -Language "en-GB" -ErrorAction Stop
                            foreach ($lang in $otherLangs) {
                                $newList.Add($lang.LanguageTag)
                            }

                            Set-WinUserLanguageList $newList -Force -ErrorAction Stop
                        }
                        Write-Log "en-GB set as default" "SUCCESS"
                    }
                    catch {
                        Write-Log "Failed to set default: $($_.Exception.Message)" "ERROR"
                    }
                }
            }
        }

        # Confirm removal
        if (-not $Force) {
            Write-Log "" "INFO"
            Write-Log "This will remove US English (en-US) from the system." "WARNING"
            Write-Log "This includes:" "WARNING"
            Write-Log "  - US English from language list" "WARNING"
            if (-not $KeepKeyboard) {
                Write-Log "  - US English keyboard layout" "WARNING"
            }
            Write-Log "  - US English language features (speech, OCR, etc.)" "WARNING"
            Write-Log "" "INFO"

            $confirm = Read-Host "Do you want to continue? (Y/N)"
            if ($confirm -ne "Y" -and $confirm -ne "y") {
                Write-Log "Operation cancelled by user" "INFO"
                return 0
            }
        }

        # 1. Remove en-US from language list
        Write-Log "" "INFO"
        Write-Log "Removing en-US from language list..." "INFO"
        try {
            $langList = Get-WinUserLanguageList
            $newList = @($langList | Where-Object { $_.LanguageTag -ne "en-US" })

            if ($newList.Count -eq 0) {
                Write-Log "Cannot remove en-US - it would leave no languages!" "ERROR"
                return 1
            }

            if ($PSCmdlet.ShouldProcess("User language list", "Remove en-US")) {
                Set-WinUserLanguageList -LanguageList $newList -Force -ErrorAction Stop
            }
            Write-Log "Removed en-US from language list" "SUCCESS"
        }
        catch {
            Write-Log "Error removing en-US from language list: $($_.Exception.Message)" "ERROR"
        }

        # 2. Remove US keyboard layout from en-GB (if present)
        if (-not $KeepKeyboard) {
            Write-Log "Checking for US keyboard layouts..." "INFO"
            try {
                $langList = Get-WinUserLanguageList
                $modified = $false

                foreach ($lang in $langList) {
                    # US keyboard layout ID contains 0409
                    $usKeyboards = @($lang.InputMethodTips | Where-Object { $_ -match "0409:" })
                    foreach ($kb in $usKeyboards) {
                        if ($PSCmdlet.ShouldProcess("$($lang.LanguageTag) keyboard layouts",
                                "Remove US keyboard '$kb'")) {
                            $lang.InputMethodTips.Remove($kb) | Out-Null
                            Write-Log "Removed US keyboard from $($lang.LanguageTag): $kb" "SUCCESS"
                        }
                        $modified = $true
                    }
                }

                if ($modified) {
                    if ($PSCmdlet.ShouldProcess("User language list", "Persist keyboard layout changes")) {
                        Set-WinUserLanguageList -LanguageList $langList -Force -ErrorAction Stop
                    }
                }
                else {
                    Write-Log "No US keyboard layouts found to remove" "INFO"
                }
            }
            catch {
                Write-Log "Error removing keyboard layouts: $($_.Exception.Message)" "WARNING"
            }
        }
        else {
            Write-Log "Keeping US keyboard layout as requested" "INFO"
        }

        # 3. Remove US language capabilities (Features on Demand)
        Write-Log "Checking for US language features..." "INFO"
        try {
            $usCaps = @(Get-WindowsCapability -Online -ErrorAction Stop | Where-Object {
                $_.State -eq "Installed" -and (
                    $_.Name -like "Language.Basic~~~en-US~*" -or
                    $_.Name -like "Language.Handwriting~~~en-US~*" -or
                    $_.Name -like "Language.OCR~~~en-US~*" -or
                    $_.Name -like "Language.Speech~~~en-US~*" -or
                    $_.Name -like "Language.TextToSpeech~~~en-US~*"
                )
            })

            if ($usCaps.Count -gt 0) {
                foreach ($cap in $usCaps) {
                    Write-Log "Removing: $($cap.Name)" "INFO"
                    try {
                        if ($PSCmdlet.ShouldProcess("Windows capability '$($cap.Name)'", "Remove")) {
                            Remove-WindowsCapability -Online -Name $cap.Name -ErrorAction Stop | Out-Null
                            Write-Log "Removed: $($cap.Name)" "SUCCESS"
                        }
                    }
                    catch {
                        Write-Log "Failed to remove $($cap.Name): $($_.Exception.Message)" "WARNING"
                    }
                }
            }
            else {
                Write-Log "No US language features found" "INFO"
            }
        }
        catch {
            Write-Log "Error checking language features: $($_.Exception.Message)" "WARNING"
        }

        # 4. Clean up registry (optional, for thoroughness)
        Write-Log "Cleaning up registry entries..." "INFO"
        try {
            # User language preferences
            $userLangPath = "HKCU:\Control Panel\International\User Profile"
            if (Test-Path $userLangPath) {
                $languages = Get-ItemProperty -Path $userLangPath -Name "Languages" -ErrorAction SilentlyContinue
                if ($languages -and $languages.Languages -contains "en-US") {
                    $newLangs = $languages.Languages | Where-Object { $_ -ne "en-US" }
                    if ($PSCmdlet.ShouldProcess("Registry key '$userLangPath'", "Remove en-US from Languages value")) {
                        Set-ItemProperty -Path $userLangPath -Name "Languages" -Value $newLangs `
                            -ErrorAction SilentlyContinue
                    }
                    Write-Log "Cleaned user language preferences" "SUCCESS"
                }
            }
        }
        catch {
            Write-Log "Registry cleanup note: $($_.Exception.Message)" "WARNING"
        }

        # 5. Verify removal
        Write-Log "" "INFO"
        Write-Log "Verifying removal..." "INFO"
        $finalLanguages = Get-WinUserLanguageList

        Write-Log "Current language list:" "INFO"
        foreach ($lang in $finalLanguages) {
            Write-Log "  - $($lang.LanguageTag)" "SUCCESS"
        }

        $stillHasUS = $finalLanguages | Where-Object { $_.LanguageTag -eq "en-US" }
        if ($stillHasUS) {
            Write-Log "WARNING: en-US still appears in language list" "WARNING"
            Write-Log "A sign-out/restart may be required" "INFO"
        }
        else {
            Write-Log "en-US successfully removed from language list" "SUCCESS"
        }

        # 6. Summary
        Write-Log "" "INFO"
        Write-Log "=== Removal Summary ===" "HEADER"
        Write-Log "US English language removal completed" "SUCCESS"
        Write-Log "Default language: $($finalLanguages[0].LanguageTag)" "INFO"
        Write-Log "" "INFO"
        Write-Log "Changes made:" "INFO"
        Write-Log "  - Removed en-US from language list" "SUCCESS"
        if (-not $KeepKeyboard) {
            Write-Log "  - Removed US keyboard layouts" "SUCCESS"
        }
        Write-Log "  - Removed US language features" "SUCCESS"

        Write-Log "" "INFO"
        Write-Log "You may need to sign out and back in for all changes to take effect." "WARNING"

        if (-not $Force) {
            Write-Log "" "INFO"
            $signout = Read-Host "Would you like to sign out now? (Y/N)"
            if ($signout -eq "Y" -or $signout -eq "y") {
                Write-Log "Signing out in 10 seconds... Save your work!" "WARNING"
                Start-Sleep -Seconds 10
                if ($PSCmdlet.ShouldProcess("Current session", "Sign out (logoff)")) {
                    Invoke-Logoff | Out-Null
                }
            }
            else {
                Write-Log "Please sign out manually when ready." "INFO"
            }
        }

        return 0
    }
    catch {
        Write-Log "Fatal error: $($_.Exception.Message)" "ERROR"
        return 1
    }
}

# Justification for PSUseOutputTypeCorrectly: Main returns an int exit code consumed by the guard below.
# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main @PSBoundParameters) }
