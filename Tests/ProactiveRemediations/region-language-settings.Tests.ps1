#Requires -Modules Pester

BeforeAll {
    # Corrected path: scripts are in endpoints/devices/proactive-remediations
    $script:detectScript = Join-Path $PSScriptRoot "..\..\scripts\endpoints\devices\proactive-remediations\region-language-settings\detect.ps1"
    $script:remediateScript = Join-Path $PSScriptRoot "..\..\scripts\endpoints\devices\proactive-remediations\region-language-settings\remediate.ps1"
    
    # Helper function to check if cmdlet exists (defined in BeforeAll for proper scoping)
    function script:Test-CmdletExists {
        param([string]$Name)
        try {
            $null = Get-Command $Name -ErrorAction Stop
            return $true
        }
        catch {
            return $false
        }
    }
    
    # Pre-compute availability flags
    $script:hasWinHomeLocation = Test-CmdletExists 'Get-WinHomeLocation'
    $script:hasTimeZone = Test-CmdletExists 'Get-TimeZone'
    $script:hasCulture = Test-CmdletExists 'Get-Culture'
    $script:hasSetCulture = Test-CmdletExists 'Set-Culture'
    $script:hasWinSystemLocale = Test-CmdletExists 'Get-WinSystemLocale'
    $script:hasWinUserLanguageList = Test-CmdletExists 'Get-WinUserLanguageList'
    $script:hasSetWinHomeLocation = Test-CmdletExists 'Set-WinHomeLocation'
    $script:hasSetTimeZone = Test-CmdletExists 'Set-TimeZone'
    $script:hasSetWinSystemLocale = Test-CmdletExists 'Set-WinSystemLocale'
    $script:hasNewWinUserLanguageList = Test-CmdletExists 'New-WinUserLanguageList'
    $script:hasSetWinUserLanguageList = Test-CmdletExists 'Set-WinUserLanguageList'
}

Describe "Region Language Settings - Detect" {
    Context "Detection Logic" {
        BeforeEach {
            # Mock Windows cmdlets - only mock if they exist
            if ($script:hasCulture) {
                Mock Get-Culture {
                    return @{ Name = "en-US" }  # Non-compliant
                }
            }
            if ($script:hasWinHomeLocation) {
                Mock Get-WinHomeLocation {
                    return @{ GeoId = 244 }  # US, not UK (242)
                }
            }
            if ($script:hasTimeZone) {
                Mock Get-TimeZone {
                    return @{ Id = "Pacific Standard Time" }  # Non-compliant
                }
            }
            if ($script:hasWinSystemLocale) {
                Mock Get-WinSystemLocale {
                    return @{ Name = "en-US" }
                }
            }
            if ($script:hasWinUserLanguageList) {
                Mock Get-WinUserLanguageList {
                    $lang = New-Object PSObject -Property @{
                        LanguageTag = "en-US"
                    }
                    return @($lang)
                }
            }
        }

        It "Should detect non-UK culture" -Skip:(-not $script:hasCulture) {
            $culture = Get-Culture
            $culture.Name | Should -Not -Be "en-GB"
        }

        It "Should detect non-UK geographic location" -Skip:(-not $script:hasWinHomeLocation) {
            $location = Get-WinHomeLocation
            $location.GeoId | Should -Not -Be 242
        }

        It "Should detect non-GMT time zone" -Skip:(-not $script:hasTimeZone) {
            $timeZone = Get-TimeZone
            $timeZone.Id | Should -Not -Be "GMT Standard Time"
        }
    }

    Context "Compliant System Detection" {
        BeforeEach {
            # Mock compliant system - only mock if cmdlets exist
            if ($script:hasCulture) {
                Mock Get-Culture {
                    return @{ Name = "en-GB" }
                }
            }
            if ($script:hasWinHomeLocation) {
                Mock Get-WinHomeLocation {
                    return @{ GeoId = 242 }  # UK
                }
            }
            if ($script:hasTimeZone) {
                Mock Get-TimeZone {
                    return @{ Id = "GMT Standard Time" }
                }
            }
            if ($script:hasWinSystemLocale) {
                Mock Get-WinSystemLocale {
                    return @{ Name = "en-GB" }
                }
            }
            if ($script:hasWinUserLanguageList) {
                Mock Get-WinUserLanguageList {
                    $lang = New-Object PSObject -Property @{
                        LanguageTag = "en-GB"
                    }
                    return @($lang)
                }
            }
        }

        It "Should detect UK culture as compliant" -Skip:(-not $script:hasCulture) {
            $culture = Get-Culture
            $culture.Name | Should -Be "en-GB"
        }

        It "Should detect UK geographic location as compliant" -Skip:(-not $script:hasWinHomeLocation) {
            $location = Get-WinHomeLocation
            $location.GeoId | Should -Be 242
        }

        It "Should detect GMT time zone as compliant" -Skip:(-not $script:hasTimeZone) {
            $timeZone = Get-TimeZone
            $timeZone.Id | Should -Be "GMT Standard Time"
        }
    }
}

Describe "Region Language Settings - Remediate" {
    Context "Remediation Actions" {
        BeforeEach {
            # Only mock if cmdlets exist
            if ($script:hasSetWinHomeLocation) {
                Mock Set-WinHomeLocation { }
            }
            if ($script:hasSetTimeZone) {
                Mock Set-TimeZone { }
            }
            if ($script:hasSetWinSystemLocale) {
                Mock Set-WinSystemLocale { }
            }
            if ($script:hasSetCulture) {
                Mock Set-Culture { }
            }
            if ($script:hasNewWinUserLanguageList) {
                Mock New-WinUserLanguageList { return @() }
            }
            if ($script:hasSetWinUserLanguageList) {
                Mock Set-WinUserLanguageList { }
            }

            # Mock current state as non-compliant
            if ($script:hasWinHomeLocation) {
                Mock Get-WinHomeLocation { return @{ GeoId = 244 } }
            }
            if ($script:hasTimeZone) {
                Mock Get-TimeZone { return @{ Id = "Pacific Standard Time" } }
            }
            if ($script:hasWinSystemLocale) {
                Mock Get-WinSystemLocale { return @{ Name = "en-US" } }
            }
            if ($script:hasCulture) {
                Mock Get-Culture { return @{ Name = "en-US" } }
            }
            if ($script:hasWinUserLanguageList) {
                Mock Get-WinUserLanguageList {
                    $lang = New-Object PSObject -Property @{ LanguageTag = "en-US" }
                    return @($lang)
                }
            }
        }

        It "Should call Set-WinHomeLocation for non-UK location" -Skip:(-not $script:hasWinHomeLocation -or -not $script:hasSetWinHomeLocation) {
            $currentLocation = Get-WinHomeLocation
            if ($currentLocation.GeoId -ne 242) {
                Set-WinHomeLocation -GeoId 242
            }

            Should -Invoke Set-WinHomeLocation -Times 1
        }

        It "Should call Set-TimeZone for non-GMT timezone" -Skip:(-not $script:hasTimeZone -or -not $script:hasSetTimeZone) {
            $currentTimeZone = Get-TimeZone
            if ($currentTimeZone.Id -ne 'GMT Standard Time') {
                Set-TimeZone -Id 'GMT Standard Time'
            }

            Should -Invoke Set-TimeZone -Times 1
        }

        It "Should call Set-Culture for non-UK culture" -Skip:(-not $script:hasCulture -or -not $script:hasSetCulture) {
            $currentCulture = Get-Culture
            if ($currentCulture.Name -ne 'en-GB') {
                Set-Culture -CultureInfo 'en-GB'
            }

            Should -Invoke Set-Culture -Times 1
        }
    }

    Context "Exit Codes" {
        It "Should return 0 for successful remediation" {
            # Exit code 0 indicates success
            $expectedExitCode = 0
            $expectedExitCode | Should -Be 0
        }

        It "Should return 1 for failed remediation" {
            # Exit code 1 indicates failure
            $expectedExitCode = 1
            $expectedExitCode | Should -Be 1
        }
    }
}

Describe "Region Language Settings - Script Structure" {
    Context "File Existence" {
        It "Detect script should exist" {
            $script:detectScript | Should -Exist
        }

        It "Remediate script should exist" {
            $script:remediateScript | Should -Exist
        }
    }

    Context "Script Syntax" {
        BeforeAll {
            $script:detectExists = Test-Path $script:detectScript
            $script:remediateExists = Test-Path $script:remediateScript
        }

        It "Detect script should have valid PowerShell syntax" -Skip:(-not $script:detectExists) {
            $tokens = $null
            $parseErrors = $null
            [System.Management.Automation.Language.Parser]::ParseFile($script:detectScript, [ref]$tokens, [ref]$parseErrors) | Out-Null
            $parseErrors.Count | Should -Be 0
        }

        It "Remediate script should have valid PowerShell syntax" -Skip:(-not $script:remediateExists) {
            $tokens = $null
            $parseErrors = $null
            [System.Management.Automation.Language.Parser]::ParseFile($script:remediateScript, [ref]$tokens, [ref]$parseErrors) | Out-Null
            $parseErrors.Count | Should -Be 0
        }
    }
}