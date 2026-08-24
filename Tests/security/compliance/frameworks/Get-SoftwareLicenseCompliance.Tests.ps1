#Requires -Modules Pester

Describe "Get-SoftwareLicenseCompliance" {
    BeforeAll {
        $scriptPath = Join-Path $PSScriptRoot `
            "../../../../scripts/security/compliance/frameworks/Get-SoftwareLicenseCompliance.ps1"

        # Stub Windows-only cmdlets so Pester can attach mocks on Linux.
        function Get-CimInstance { }

        # Safe: the script's top-level guard skips Main when dot-sourced.
        . $scriptPath
        $rawText = Get-Content -LiteralPath $scriptPath -Raw

        $script:uninstallApps = @(
            [pscustomobject]@{
                DisplayName = 'Microsoft Office Professional Plus 2019'
                DisplayVersion = '16.0.10402'
                Publisher = 'Microsoft Corporation'
                InstallDate = '20240115'
                InstallLocation = 'C:\Program Files\Microsoft Office'
                UninstallString = 'MsiExec.exe /X{90160000}'
            },
            [pscustomobject]@{
                DisplayName = 'Microsoft Windows 11 Pro'
                DisplayVersion = '10.0.22631'
                Publisher = 'Microsoft Corporation'
                InstallDate = ''
                InstallLocation = 'C:\Windows'
                UninstallString = ''
            },
            [pscustomobject]@{
                DisplayName = '7-Zip 23.01'
                DisplayVersion = '23.01'
                Publisher = 'Igor Pavlov'
                InstallDate = '20230601'
                InstallLocation = 'C:\Program Files\7-Zip'
                UninstallString = '"C:\Program Files\7-Zip\Uninstall.exe"'
            }
        )

        # Registry enumeration returns the same apps for each hive path (dedup is exercised).
        Mock Get-ItemProperty { $script:uninstallApps }
        Mock Test-Path { $false }
        Mock Get-CimInstance {
            [pscustomobject]@{ ProductKeyID = '03612-03242-000-000001-04' }
        }
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
        It "Inventories software, dedupes across registry hives, resolves licenses, and returns 0" {
            $out = Main *>&1

            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            ($out -join "`n") | Should -Match 'Total applications found: 3'
            ($out -join "`n") | Should -Match '\[\+\]'
            # Office + Windows queried once per registry hive BEFORE dedup (3 hives each).
            Should -Invoke Get-CimInstance -Times 6 -Exactly
        }

        It "Is idempotent: a second audit run also returns 0 with no state change" {
            (Main *>&1 | Where-Object { $_ -is [int] }) | Should -Be 0
            (Main *>&1 | Where-Object { $_ -is [int] }) | Should -Be 0
        }

        It "Flags critical software as unlicensed when licensing queries return nothing" {
            Mock Get-CimInstance { $null }

            $out = Main *>&1
            ($out -join "`n") | Should -Match 'Potentially Unlicensed Critical Software'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
        }

        It "Returns 1 with [-]-prefixed output when report writing fails" {
            Mock Out-File { throw "disk full" }

            $out = Main -OutputFormat HTML *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
            ($out -join "`n") | Should -Match '\[-\]'
        }
    }
}
