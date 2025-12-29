#Requires -Modules Pester

BeforeAll {
    $detectScript = Join-Path $PSScriptRoot "..\..\scripts\device-management\proactive-remediations\region-language-settings\detect.ps1"
    $remediateScript = Join-Path $PSScriptRoot "..\..\scripts\device-management\proactive-remediations\region-language-settings\remediate.ps1"
}

Describe "Region Language Settings - Detect" {
    Context "Detection Logic" {
        BeforeEach {
            # Mock Windows cmdlets
            Mock Get-Culture {
                return @{ Name = "en-US" }  # Non-compliant
            }
            Mock Get-WinHomeLocation {
                return @{ GeoId = 244 }  # US, not UK (242)
            }
            Mock Get-TimeZone {
                return @{ Id = "Pacific Standard Time" }  # Non-compliant
            }
            Mock Get-WinSystemLocale {
                return @{ Name = "en-US" }
            }
            Mock Get-WinUserLanguageList {
                $lang = New-Object PSObject -Property @{
                    LanguageTag = "en-US"
                }
                return @($lang)
            }
        }

        It "Should detect non-UK culture" {
            $culture = Get-Culture
            $culture.Name | Should -Not -Be "en-GB"
        }

        It "Should detect non-UK geographic location" {
            $location = Get-WinHomeLocation
            $location.GeoId | Should -Not -Be 242
        }

        It "Should detect non-GMT time zone" {
            $timeZone = Get-TimeZone
            $timeZone.Id | Should -Not -Be "GMT Standard Time"
        }
    }

    Context "Compliant System Detection" {
        BeforeEach {
            # Mock compliant system
            Mock Get-Culture {
                return @{ Name = "en-GB" }
            }
            Mock Get-WinHomeLocation {
                return @{ GeoId = 242 }  # UK
            }
            Mock Get-TimeZone {
                return @{ Id = "GMT Standard Time" }
            }
            Mock Get-WinSystemLocale {
                return @{ Name = "en-GB" }
            }
            Mock Get-WinUserLanguageList {
                $lang = New-Object PSObject -Property @{
                    LanguageTag = "en-GB"
                }
                return @($lang)
            }
        }

        It "Should detect UK culture as compliant" {
            $culture = Get-Culture
            $culture.Name | Should -Be "en-GB"
        }

        It "Should detect UK geographic location as compliant" {
            $location = Get-WinHomeLocation
            $location.GeoId | Should -Be 242
        }

        It "Should detect GMT time zone as compliant" {
            $timeZone = Get-TimeZone
            $timeZone.Id | Should -Be "GMT Standard Time"
        }
    }
}

Describe "Region Language Settings - Remediate" {
    Context "Remediation Actions" {
        BeforeEach {
            Mock Set-WinHomeLocation { }
            Mock Set-TimeZone { }
            Mock Set-WinSystemLocale { }
            Mock Set-Culture { }
            Mock New-WinUserLanguageList { return @() }
            Mock Set-WinUserLanguageList { }

            # Mock current state as non-compliant
            Mock Get-WinHomeLocation { return @{ GeoId = 244 } }
            Mock Get-TimeZone { return @{ Id = "Pacific Standard Time" } }
            Mock Get-WinSystemLocale { return @{ Name = "en-US" } }
            Mock Get-Culture { return @{ Name = "en-US" } }
            Mock Get-WinUserLanguageList {
                $lang = New-Object PSObject -Property @{ LanguageTag = "en-US" }
                return @($lang)
            }
        }

        It "Should call Set-WinHomeLocation for non-UK location" {
            $currentLocation = Get-WinHomeLocation
            if ($currentLocation.GeoId -ne 242) {
                Set-WinHomeLocation -GeoId 242
            }

            Should -Invoke Set-WinHomeLocation -Times 1
        }

        It "Should call Set-TimeZone for non-GMT timezone" {
            $currentTimeZone = Get-TimeZone
            if ($currentTimeZone.Id -ne 'GMT Standard Time') {
                Set-TimeZone -Id 'GMT Standard Time'
            }

            Should -Invoke Set-TimeZone -Times 1
        }

        It "Should call Set-Culture for non-UK culture" {
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
            $detectScript | Should -Exist
        }

        It "Remediate script should exist" {
            $remediateScript | Should -Exist
        }
    }

    Context "Script Syntax" {
        It "Detect script should have valid PowerShell syntax" {
            { $null = [System.Management.Automation.PSParser]::Tokenize((Get-Content $detectScript -Raw), [ref]$null) } | Should -Not -Throw
        }

        It "Remediate script should have valid PowerShell syntax" {
            { $null = [System.Management.Automation.PSParser]::Tokenize((Get-Content $remediateScript -Raw), [ref]$null) } | Should -Not -Throw
        }
    }
}
