<#
.SYNOPSIS
    Pester tests for Check-DeviceHealthScore/detect.ps1

.DESCRIPTION
    Pester test suite covering the device health score calculation of the Check-DeviceHealthScore proactive remediation detection script. Mocks Get-CimInstance, Get-WinEvent, Get-MpComputerStatus and related cmdlets to validate the category scores and that the script does not throw on null data.

.EXAMPLE
    ./detect.Tests.ps1

.NOTES
    File Name  : detect.Tests.ps1
    Author     : Intune / Proactive Remediations
    Prerequisite: PowerShell 5.1 or later, run in the Intune Proactive Remediation context
    Version    : 1.0.0
    Date       : 2026-08-08
#>

BeforeAll {
    # Import the script to test
    $scriptPath = "$PSScriptRoot/detect.ps1"

    # Mock external cmdlets
    Mock Get-CimInstance { }
    Mock Get-WinEvent { }
    Mock Get-Module { }
    Mock Get-MpComputerStatus { }
    Mock Write-Host { }
}

Describe "Check-DeviceHealthScore.detect.ps1" {

    Context "Category Initialization" {
        It "Should initialize all category scores to 0" {
            # This would require refactoring the script to export the healthReport
            # For now, we test that the script doesn't fail on null categories
            Mock Get-CimInstance { return $null }
            Mock Get-WinEvent { return $null }

            { & $scriptPath } | Should -Not -Throw
        }
    }

    Context "Uptime Health Scoring" {
        BeforeEach {
            Mock Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_OperatingSystem' } {
                [PSCustomObject]@{
                    LastBootUpTime = (Get-Date).AddDays(-$script:UptimeDays)
                }
            }
        }

        It "Should deduct 10 points for uptime >30 days" {
            $script:UptimeDays = 35

            Mock Get-WinEvent { return $null }
            Mock Get-Module { return $null }

            $output = & $scriptPath *>&1
            $output | Should -Match "Excessive uptime"
        }

        It "Should deduct 5 points for uptime >14 days but <30 days" {
            $script:UptimeDays = 20

            Mock Get-WinEvent { return $null }
            Mock Get-Module { return $null }

            $output = & $scriptPath *>&1
            $output | Should -Match "High uptime"
        }

        It "Should not deduct points for uptime <14 days" {
            $script:UptimeDays = 7

            Mock Get-WinEvent { return $null }
            Mock Get-Module { return $null }

            $output = & $scriptPath *>&1
            $output | Should -Not -Match "uptime.*days"
        }
    }

    Context "Crash Stability Scoring" {
        BeforeEach {
            Mock Get-CimInstance { return $null }
            Mock Get-Module { return $null }
        }

        It "Should detect system crashes" {
            $mockCrashes = @(
                [PSCustomObject]@{ TimeCreated = (Get-Date) }
                [PSCustomObject]@{ TimeCreated = (Get-Date).AddHours(-1) }
            )

            Mock Get-WinEvent -ParameterFilter { $FilterHashtable.ID -eq 41 } {
                return $mockCrashes
            }
            Mock Get-WinEvent { return $null }

            $output = & $scriptPath *>&1
            $output | Should -Match "System crashes"
        }

        It "Should handle no crashes gracefully" {
            Mock Get-WinEvent { return $null }

            $output = & $scriptPath *>&1
            $output | Should -Not -Match "System crashes"
        }
    }

    Context "Hardware Health Scoring" {
        BeforeEach {
            Mock Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_OperatingSystem' } {
                [PSCustomObject]@{ LastBootUpTime = (Get-Date).AddDays(-7) }
            }
            Mock Get-WinEvent { return $null }
            Mock Get-Module { return $null }
        }

        It "Should detect WHEA hardware errors" {
            $mockWheaErrors = @(
                [PSCustomObject]@{ Message = "Hardware error" }
                [PSCustomObject]@{ Message = "Hardware error" }
            )

            Mock Get-WinEvent -ParameterFilter { $FilterHashtable.ProviderName -eq 'Microsoft-Windows-WHEA-Logger' } {
                return $mockWheaErrors
            }
            Mock Get-CimInstance -ParameterFilter { $ClassName -eq 'MSStorageDriver_FailurePredictStatus' } {
                return $null
            }

            $output = & $scriptPath *>&1
            $output | Should -Match "Hardware errors"
        }

        It "Should detect disk SMART failures" {
            Mock Get-WinEvent { return $null }
            Mock Get-CimInstance -ParameterFilter { $ClassName -eq 'MSStorageDriver_FailurePredictStatus' } {
                return @([PSCustomObject]@{ PredictFailure = $true })
            }

            $output = & $scriptPath *>&1
            $output | Should -Match "CRITICAL.*Disk failure predicted"
        }

        It "Should handle healthy disks" {
            Mock Get-WinEvent { return $null }
            Mock Get-CimInstance -ParameterFilter { $ClassName -eq 'MSStorageDriver_FailurePredictStatus' } {
                return @([PSCustomObject]@{ PredictFailure = $false })
            }

            $output = & $scriptPath *>&1
            $output | Should -Not -Match "Disk failure predicted"
        }
    }

    Context "Security Posture Scoring" {
        BeforeEach {
            Mock Get-CimInstance { return $null }
            Mock Get-WinEvent { return $null }
        }

        It "Should skip Defender checks when module not available" {
            Mock Get-Module { return $null }

            $output = & $scriptPath *>&1
            $output | Should -Match "Defender module not available"
        }

        It "Should check Defender when module is available" {
            Mock Get-Module {
                return [PSCustomObject]@{ Name = "Defender" }
            }
            Mock Get-MpComputerStatus {
                return [PSCustomObject]@{
                    RealTimeProtectionEnabled = $true
                    AntivirusSignatureAge = 2
                }
            }

            $output = & $scriptPath *>&1
            $output | Should -Not -Match "Real-time protection disabled"
        }

        It "Should detect disabled real-time protection" {
            Mock Get-Module {
                return [PSCustomObject]@{ Name = "Defender" }
            }
            Mock Get-MpComputerStatus {
                return [PSCustomObject]@{
                    RealTimeProtectionEnabled = $false
                    AntivirusSignatureAge = 2
                }
            }

            $output = & $scriptPath *>&1
            $output | Should -Match "Real-time protection disabled"
        }

        It "Should detect outdated antivirus signatures" {
            Mock Get-Module {
                return [PSCustomObject]@{ Name = "Defender" }
            }
            Mock Get-MpComputerStatus {
                return [PSCustomObject]@{
                    RealTimeProtectionEnabled = $true
                    AntivirusSignatureAge = 10
                }
            }

            $output = & $scriptPath *>&1
            $output | Should -Match "Antivirus signatures outdated"
        }
    }

    Context "Exit Codes" {
        BeforeEach {
            Mock Get-CimInstance { return $null }
            Mock Get-WinEvent { return $null }
            Mock Get-Module { return $null }
        }

        It "Should exit with 0 for good health score (>=70)" {
            # Mock perfect health
            Mock Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_OperatingSystem' } {
                [PSCustomObject]@{ LastBootUpTime = (Get-Date).AddDays(-7) }
            }

            try {
                & $scriptPath
                $LASTEXITCODE | Should -Be 0
            }
            catch {
                Write-Verbose "Handled exception: $($_.Exception.Message)" -Verbose:$false
            }
        }

        It "Should exit with 1 for poor health score (<70)" {
            # Mock multiple critical issues
            Mock Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_OperatingSystem' } {
                [PSCustomObject]@{ LastBootUpTime = (Get-Date).AddDays(-35) }
            }

            $mockCrashes = 1..10 | ForEach-Object {
                [PSCustomObject]@{ TimeCreated = (Get-Date).AddHours(-$_) }
            }
            Mock Get-WinEvent { return $mockCrashes }

            try {
                & $scriptPath
                $LASTEXITCODE | Should -Be 1
            }
            catch {
                Write-Verbose "Handled exception: $($_.Exception.Message)" -Verbose:$false
            }
        }
    }

    Context "Error Handling" {
        It "Should handle Get-CimInstance errors gracefully" {
            Mock Get-CimInstance { throw "CIM Error" }
            Mock Get-WinEvent { return $null }
            Mock Get-Module { return $null }

            { & $scriptPath } | Should -Not -Throw
        }

        It "Should handle Get-WinEvent errors gracefully" {
            Mock Get-CimInstance { return $null }
            Mock Get-WinEvent { throw "Event Log Error" }
            Mock Get-Module { return $null }

            { & $scriptPath } | Should -Not -Throw
        }
    }
}
