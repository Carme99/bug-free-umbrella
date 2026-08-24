#Requires -Modules Pester

Describe "Get-USBDeviceAudit" {
    BeforeAll {
        $scriptPath = Join-Path $PSScriptRoot `
            "../../../../scripts/security/compliance/frameworks/Get-USBDeviceAudit.ps1"

        # Stub Windows-only cmdlets so Pester can attach mocks on Linux.
        function Get-CimInstance { }

        # Safe: the script's top-level guard skips Main when dot-sourced.
        . $scriptPath
        $rawText = Get-Content -LiteralPath $scriptPath -Raw

        $script:usbDevices = @(
            [pscustomobject]@{
                Name = 'Microsoft USB Basic Optical Mouse'
                Status = 'OK'
                Manufacturer = 'Microsoft'
                DeviceID = 'USB\VID_045E&PID_00CB\5&21ab34cd&0&1'
            },
            [pscustomobject]@{
                Name = 'Generic Flash Drive'
                Status = 'OK'
                Manufacturer = 'Generic'
                DeviceID = 'USB\VID_ABCD&PID_1234\0700000000000001'
            }
        )

        Mock Get-CimInstance { $script:usbDevices }
        Mock Test-Path { $false }
        Mock Out-File { }
        Mock Export-Csv { }
    }

    Context "Help & Metadata" {
        It "Declares required NOTES fields with Version 1.0.0 and Date 2026-08-23" {
            $rawText | Should -Match '(?m)^\.NOTES\r?$'
            $rawText | Should -Match 'Version\s*:\s*1\.0\.0'
            $rawText | Should -Match 'Date\s*:\s*2026-08-23'
            $rawText | Should -Match 'Prerequisite\s*:\s*PowerShell'
            $rawText | Should -Match 'Author\s*:\s*\S'
        }

        It "Matches the disk filename in File Name" {
            $fileName = Split-Path $scriptPath -Leaf
            $rawText | Should -Match ("File Name\s*:\s*" + [regex]::Escape($fileName))
        }

        It "Documents one .PARAMETER block per declared parameter" {
            $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$null, [ref]$errors)
            $declared = @($ast.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath })
            $helped = [regex]::Matches($rawText, '(?m)^\.PARAMETER\s+(\S+)') | ForEach-Object { $_.Groups[1].Value }

            $declared.Count | Should -BeGreaterThan 0
            $helped.Count | Should -Be $declared.Count
            foreach ($name in $declared) {
                $helped | Should -Contain $name
            }
        }

        It "Provides at least two EXAMPLES with PS C:\> prompts" {
            $promptCount = ([regex]::Matches($rawText, 'PS C:\\>')).Count
            $promptCount | Should -BeGreaterOrEqual 2
        }
    }

    Context "Syntax & Static" {
        It "Parses with zero syntax errors" {
            $parseErrors = $null
            $null = [System.Management.Automation.Language.Parser]::ParseFile(
                $scriptPath, [ref]$null, [ref]$parseErrors)
            @($parseErrors).Count | Should -Be 0
        }

        It "Contains no PS7-only operators without a 7.0 opt-out" {
            ($rawText -match '#Requires -Version 7\.0') | Should -BeFalse
            ($rawText -match '\?\?|\?\?=|&&|\|\|') | Should -BeFalse
        }
    }

    Context "Behavior" {
        It "Audits connected devices and returns 0" {
            $out = Main *>&1

            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            ($out -join "`n") | Should -Match 'Total devices found: 2'
            ($out -join "`n") | Should -Match 'Currently connected: 2'
        }

        It "Flags unauthorized vendors against the authorized list" {
            $out = Main -AuthorizedVendors '045E' *>&1

            ($out -join "`n") | Should -Match 'Unauthorized devices: 1'
            Should -Invoke Get-CimInstance -Times 1 -Exactly
        }

        It "Merges historical USBSTOR devices without dropping currently connected ones" {
            Mock Test-Path { $true }
            Mock Get-ChildItem -ParameterFilter { $Path -like '*USBSTOR' } {
                @(
                    [pscustomobject]@{
                        PSChildName = 'Disk&Ven_Kingston&Prod_DataTraveler'
                        PSPath = 'HKLM:\SYSTEM\CurrentControlSet\Enum\USBSTOR\Disk&Ven_Kingston'
                    }
                )
            }
            Mock Get-ChildItem {
                @(
                    [pscustomobject]@{
                        PSChildName = '0700000000000002&0'
                        PSPath = 'HKLM:\SYSTEM\CurrentControlSet\Enum\USBSTOR\...\0700000000000002&0'
                    }
                )
            }
            Mock Get-ItemProperty {
                [pscustomobject]@{ FriendlyName = 'Kingston DataTraveler USB Device' }
            }

            $out = Main *>&1
            ($out -join "`n") | Should -Match 'Total devices found: 3'
            ($out -join "`n") | Should -Match 'Historical devices: 1'
        }

        It "Is idempotent: repeated audit runs return 0" {
            (Main *>&1 | Where-Object { $_ -is [int] }) | Should -Be 0
            (Main *>&1 | Where-Object { $_ -is [int] }) | Should -Be 0
        }

        It "Returns 1 with [-]-prefixed output when CSV report writing fails" {
            Mock Export-Csv { throw "disk full" }

            $out = Main -OutputFormat CSV *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
            ($out -join "`n") | Should -Match '\[-\]'
        }
    }
}
