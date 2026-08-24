#Requires -Modules Pester

Describe "New-WingetSourceConfig" {
    BeforeAll {
        # Mirrored layout: this file lives at Tests/endpoints/intune/deployment/ -> script sits four levels up + across.
        $relative = "../../../../scripts/endpoints/intune/deployment/New-WingetSourceConfig.ps1"
        $scriptPath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot $relative))
        $raw = Get-Content -LiteralPath $scriptPath -Raw

        # Safe: the top-level guard skips Main when dot-sourced; mandatory Add-set params
        # are bound explicitly so the dot-source never prompts.
        . $scriptPath -SourceName 'DotSourceRepo' -SourceURL 'https://dotsource.local'

        # Mock externals: elevation check, winget locator, and the native winget wrapper.
        # winget.exe itself is never invoked by name - only through Invoke-WingetCommand.
        Mock Test-AdministratorPrivilege { return $true }
        Mock Get-WingetPath { return "C:\Program Files\WindowsApps\fake\winget.exe" }
        Mock Invoke-WingetCommand {
            return [pscustomobject]@{ Output = @('winget', 'msstore'); ExitCode = 0 }
        }
    }

    Context "Help & Metadata" {
        It "Contains all required .NOTES metadata fields" {
            $start = $raw.IndexOf('<#')
            $end = $raw.IndexOf('#>')
            $help = $raw.Substring($start, $end - $start)

            $help | Should -Match 'File Name\s*:\s*New-WingetSourceConfig\.ps1'
            $help | Should -Match 'Author\s*:'
            $help | Should -Match 'Prerequisite\s*:\s*PowerShell 7\.0'
            $help | Should -Match 'Version\s*:\s*1\.0\.0'
            $help | Should -Match 'Date\s*:\s*2026-08-23'
        }

        It "Declares a .PARAMETER entry for every param() variable" {
            $tokens = $null
            $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errors)
            $paramNames = @($ast.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath })

            $start = $raw.IndexOf('<#')
            $end = $raw.IndexOf('#>')
            $help = $raw.Substring($start, $end - $start)

            $helpParams = @([regex]::Matches($help, '(?m)^\s*\.PARAMETER\s+(\S+)') |
                ForEach-Object { $_.Groups[1].Value })
            $helpParams.Count | Should -Be $paramNames.Count
            foreach ($name in $paramNames) {
                $helpParams | Should -Contain $name
            }
        }

        It "Is saved as UTF-8 with BOM" {
            $bytes = [System.IO.File]::ReadAllBytes($scriptPath)
            (($bytes[0..2] | ForEach-Object { $_.ToString('X2') }) -join '') | Should -Be 'EFBBBF'
        }
    }

    Context "Syntax & Static" {
        BeforeAll {
            $tokens = $null
            $parseErrors = $null
            $scriptAst = [System.Management.Automation.Language.Parser]::ParseFile(
                $scriptPath, [ref]$tokens, [ref]$parseErrors)
        }

        It "Parses with zero errors" {
            $parseErrors | Should -BeNullOrEmpty
        }

        It "Avoids PS7-only syntax without a 7.0 requirement" {
            $raw | Should -Not -Match '#Requires\s+-Version\s+7\.0'
            $raw | Should -Not -Match '\|\||&&|\?\?'
        }

        It "Defines a Main function with a dot-source guard as final line" {
            $mainFn = @($scriptAst.FindAll(
                { $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
                  $args[0].Name -eq 'Main' },
                $true))
            $mainFn.Count | Should -Be 1

            $lastLine = (Get-Content -LiteralPath $scriptPath | Where-Object { $_.Trim() })[-1]
            $lastLine | Should -Match 'InvocationName'
        }

        It "Enforces elevation at runtime instead of a RunAsAdministrator directive" {
            $raw | Should -Not -Match '(?m)^#Requires\s+-RunAsAdministrator'
            $raw | Should -Match 'Test-AdministratorPrivilege'
        }
    }

    Context "Behavior" {
        It "Returns 1 with [-] output when not running elevated" {
            Mock Test-AdministratorPrivilege { return $false }

            $out = (Main *>&1)

            ($out | Out-String) | Should -Match '\[-\]'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
            Should -Invoke Invoke-WingetCommand -Times 0 -Exactly
        }

        It "Adds a custom source and returns 0 when elevated" {
            $SourceName = "CompanyRepo"
            $SourceURL = "https://packages.company.com"

            $out = (Main *>&1)

            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            ($out | Out-String) | Should -Match '\[\+\]'
            Should -Invoke Invoke-WingetCommand -ParameterFilter {
                $ArgumentList -contains 'add' -and $ArgumentList -contains 'CompanyRepo'
            } -Times 1 -Exactly
        }

        It "Honors -WhatIf: add flow applies no source changes but succeeds" {
            $SourceName = "WhatIfRepo"
            $SourceURL = "https://packages.whatif.com"

            $out = (Main -WhatIf *>&1)

            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            Should -Invoke Invoke-WingetCommand -ParameterFilter { $ArgumentList -contains 'add' } -Times 0 -Exactly
        }

        It "Removes default sources when -RemoveDefaultSources is set" {
            $SourceName = "RepoWithDefaults"
            $SourceURL = "https://packages.defaults.com"
            $RemoveDefaultSources = $true

            (Main *>&1 | Where-Object { $_ -is [int] }) | Should -Be 0

            Should -Invoke Invoke-WingetCommand -ParameterFilter {
                $ArgumentList -contains 'remove' -and $ArgumentList -contains 'winget'
            } -Times 1 -Exactly
            Should -Invoke Invoke-WingetCommand -ParameterFilter {
                $ArgumentList -contains 'remove' -and $ArgumentList -contains 'msstore'
            } -Times 1 -Exactly
        }

        It "Resets sources with -ResetSources and returns 0" {
            $ResetSources = $true

            $out = (Main *>&1)

            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            Should -Invoke Invoke-WingetCommand -ParameterFilter {
                $ArgumentList -contains 'reset' -and $ArgumentList -contains '--force'
            } -Times 1 -Exactly
        }

        It "Exports source configuration to JSON and returns 0" {
            $ExportConfig = $true
            $OutputPath = $TestDrive

            (Main *>&1 | Where-Object { $_ -is [int] }) | Should -Be 0

            $exports = @(Get-ChildItem -LiteralPath $OutputPath -Filter 'winget-sources_*.json')
            $exports.Count | Should -BeGreaterOrEqual 1
            Get-Content -LiteralPath $exports[0].FullName -Raw | Should -Match 'ExportDate'
        }

        It "Imports source configuration from a JSON fixture and returns 0" {
            $configPath = Join-Path $TestDrive "sources.json"
            $jsonFixture = '{"Sources":[{"Name":"ImportedRepo",' +
                '"Arg":"https://imported.company.com","Type":"Microsoft.Rest"}]}'
            Set-Content -LiteralPath $configPath -Value $jsonFixture

            $ImportConfig = $configPath

            $out = (Main *>&1)

            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            Should -Invoke Invoke-WingetCommand -ParameterFilter {
                $ArgumentList -contains 'add' -and $ArgumentList -contains 'ImportedRepo'
            } -Times 1 -Exactly
        }
    }
}
