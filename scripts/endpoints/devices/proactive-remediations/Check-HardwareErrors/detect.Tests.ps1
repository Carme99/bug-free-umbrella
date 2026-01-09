BeforeAll {
    # Import the script to test
    $scriptPath = "$PSScriptRoot/detect.ps1"

    # Mock external cmdlets
    Mock Get-WinEvent { }
    Mock Get-CimInstance { }
    Mock Test-Path { }
    Mock Get-ChildItem { }
    Mock Get-Item { }
    Mock Write-Host { }
}

Describe "Check-HardwareErrors.detect.ps1" {

    Context "WHEA Hardware Error Detection" {
        It "Should detect WHEA errors" {
            $mockWheaErrors = @(
                [PSCustomObject]@{
                    Id = 17
                    TimeCreated = (Get-Date)
                    Message = "Hardware error occurred"
                }
                [PSCustomObject]@{
                    Id = 18
                    TimeCreated = (Get-Date).AddHours(-1)
                    Message = "Another hardware error"
                }
            )

            Mock Get-WinEvent -ParameterFilter { $FilterHashtable.ProviderName -eq 'Microsoft-Windows-WHEA-Logger' } {
                return $mockWheaErrors
            }
            Mock Get-CimInstance { return $null }

            $output = & $scriptPath *>&1
            $output | Should -Match "WHEA hardware errors"
            $LASTEXITCODE | Should -Be 1
        }

        It "Should handle no WHEA errors" {
            Mock Get-WinEvent { return $null }
            Mock Get-CimInstance { return $null }

            $output = & $scriptPath *>&1
            $output | Should -Match "No hardware errors detected"
            $LASTEXITCODE | Should -Be 0
        }
    }

    Context "Disk SMART Status Check" {
        It "Should detect disk failure prediction" {
            Mock Get-WinEvent { return $null }
            Mock Get-CimInstance -ParameterFilter { $ClassName -eq 'MSStorageDriver_FailurePredictStatus' } {
                return @(
                    [PSCustomObject]@{
                        InstanceName = "PHYSICALDRIVE0"
                        PredictFailure = $true
                    }
                )
            }
            Mock Get-CimInstance -ParameterFilter { $ClassName -eq 'MSStorageDriver_FailurePredictData' } {
                return @(
                    [PSCustomObject]@{
                        InstanceName = "PHYSICALDRIVE0"
                        PredictFailure = $true
                    }
                )
            }

            $output = & $scriptPath *>&1
            $output | Should -Match "SMART failure prediction"
            $output | Should -Match "WARNING.*Disk failure predicted"
            $LASTEXITCODE | Should -Be 1
        }

        It "Should handle healthy disks" {
            Mock Get-WinEvent { return $null }
            Mock Get-CimInstance -ParameterFilter { $ClassName -eq 'MSStorageDriver_FailurePredictStatus' } {
                return @(
                    [PSCustomObject]@{
                        InstanceName = "PHYSICALDRIVE0"
                        PredictFailure = $false
                    }
                )
            }
            Mock Get-CimInstance -ParameterFilter { $ClassName -eq 'MSStorageDriver_FailurePredictData' } {
                return @(
                    [PSCustomObject]@{
                        InstanceName = "PHYSICALDRIVE0"
                        PredictFailure = $false
                    }
                )
            }

            $output = & $scriptPath *>&1
            $output | Should -Match "Status.*OK"
            $LASTEXITCODE | Should -Be 0
        }

        It "Should handle null SMART data gracefully" {
            Mock Get-WinEvent { return $null }
            Mock Get-CimInstance -ParameterFilter { $ClassName -eq 'MSStorageDriver_FailurePredictStatus' } {
                return @([PSCustomObject]@{ PredictFailure = $false })
            }
            Mock Get-CimInstance -ParameterFilter { $ClassName -eq 'MSStorageDriver_FailurePredictData' } {
                return $null
            }

            { & $scriptPath } | Should -Not -Throw
        }
    }

    Context "Physical Disk Errors" {
        BeforeEach {
            Mock Get-CimInstance { return $null }
        }

        It "Should detect disk errors" {
            $mockDiskErrors = @(
                [PSCustomObject]@{ Message = "Disk error 1" }
                [PSCustomObject]@{ Message = "Disk error 2" }
                [PSCustomObject]@{ Message = "Disk error 3" }
                [PSCustomObject]@{ Message = "Disk error 4" }
            )

            Mock Get-WinEvent -ParameterFilter { $FilterHashtable.ProviderName -eq 'disk' } {
                return $mockDiskErrors
            }
            Mock Get-WinEvent { return $null }

            $output = & $scriptPath *>&1
            $output | Should -Match "Physical disk errors"
            $LASTEXITCODE | Should -Be 1
        }

        It "Should handle few disk errors as acceptable" {
            $mockDiskErrors = @(
                [PSCustomObject]@{ Message = "Disk error 1" }
            )

            Mock Get-WinEvent -ParameterFilter { $FilterHashtable.ProviderName -eq 'disk' } {
                return $mockDiskErrors
            }
            Mock Get-WinEvent { return $null }

            $output = & $scriptPath *>&1
            $output | Should -Not -Match "Frequent disk errors"
        }
    }

    Context "CPU/Processor Errors" {
        BeforeEach {
            Mock Get-CimInstance { return $null }
        }

        It "Should detect processor errors" {
            $mockCpuErrors = @(
                [PSCustomObject]@{ Message = "Processor error" }
            )

            Mock Get-WinEvent -ParameterFilter { $FilterHashtable.ProviderName -eq 'Microsoft-Windows-Kernel-Processor-Power' } {
                return $mockCpuErrors
            }
            Mock Get-WinEvent { return $null }

            $output = & $scriptPath *>&1
            $output | Should -Match "Processor errors"
            $LASTEXITCODE | Should -Be 1
        }
    }

    Context "USB Controller Errors" {
        BeforeEach {
            Mock Get-CimInstance { return $null }
        }

        It "Should detect USB controller errors" {
            $mockUsbErrors = 1..6 | ForEach-Object {
                [PSCustomObject]@{ Message = "USB error $_" }
            }

            Mock Get-WinEvent -ParameterFilter { $FilterHashtable.ProviderName -eq @('USBHUB3', 'USBXHCI') } {
                return $mockUsbErrors
            }
            Mock Get-WinEvent { return $null }

            $output = & $scriptPath *>&1
            $output | Should -Match "USB controller"
            $LASTEXITCODE | Should -Be 1
        }

        It "Should tolerate minor USB errors" {
            $mockUsbErrors = @(
                [PSCustomObject]@{ Message = "Minor USB error" }
            )

            Mock Get-WinEvent -ParameterFilter { $FilterHashtable.ProviderName -eq @('USBHUB3', 'USBXHCI') } {
                return $mockUsbErrors
            }
            Mock Get-WinEvent { return $null }

            $output = & $scriptPath *>&1
            $output | Should -Not -Match "USB controller issues detected"
        }
    }

    Context "Battery Hardware Errors" {
        BeforeEach {
            Mock Get-CimInstance { return $null }
        }

        It "Should detect battery hardware errors" {
            $mockBatteryErrors = @(
                [PSCustomObject]@{ Message = "Battery error" }
            )

            Mock Get-WinEvent -ParameterFilter { $FilterHashtable.ProviderName -match 'Battery' } {
                return $mockBatteryErrors
            }
            Mock Get-WinEvent { return $null }

            $output = & $scriptPath *>&1
            $output | Should -Match "Battery hardware"
            $LASTEXITCODE | Should -Be 1
        }
    }

    Context "Thermal/Overheating Events" {
        BeforeEach {
            Mock Get-CimInstance { return $null }
        }

        It "Should detect thermal events" {
            $mockThermalEvents = @(
                [PSCustomObject]@{ Message = "System overheating" }
            )

            Mock Get-WinEvent -ParameterFilter { $FilterHashtable.ID -eq 37 } {
                return $mockThermalEvents
            }
            Mock Get-WinEvent { return $null }

            $output = & $scriptPath *>&1
            $output | Should -Match "overheating"
            $LASTEXITCODE | Should -Be 1
        }
    }

    Context "PCI/PCIe Errors" {
        BeforeEach {
            Mock Get-CimInstance { return $null }
        }

        It "Should detect PCI/PCIe errors" {
            $mockPciErrors = @(
                [PSCustomObject]@{ Message = "PCI bus error" }
            )

            Mock Get-WinEvent -ParameterFilter { $FilterHashtable.ProviderName -eq 'pci' } {
                return $mockPciErrors
            }
            Mock Get-WinEvent { return $null }

            $output = & $scriptPath *>&1
            $output | Should -Match "PCI/PCIe"
            $LASTEXITCODE | Should -Be 1
        }
    }

    Context "Exit Codes" {
        It "Should exit with 0 when no errors detected" {
            Mock Get-WinEvent { return $null }
            Mock Get-CimInstance { return $null }

            & $scriptPath
            $LASTEXITCODE | Should -Be 0
        }

        It "Should exit with 1 when hardware errors detected" {
            Mock Get-WinEvent {
                return @([PSCustomObject]@{ Message = "Error" })
            }
            Mock Get-CimInstance { return $null }

            & $scriptPath
            $LASTEXITCODE | Should -Be 1
        }
    }

    Context "Error Handling" {
        It "Should handle Get-WinEvent errors gracefully" {
            Mock Get-WinEvent { throw "Event log access denied" }
            Mock Get-CimInstance { return $null }

            { & $scriptPath } | Should -Not -Throw
        }

        It "Should handle Get-CimInstance errors gracefully" {
            Mock Get-WinEvent { return $null }
            Mock Get-CimInstance { throw "CIM access error" }

            { & $scriptPath } | Should -Not -Throw
        }
    }
}
