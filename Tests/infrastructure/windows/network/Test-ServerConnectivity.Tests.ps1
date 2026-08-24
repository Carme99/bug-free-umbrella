#Requires -Modules Pester

Describe "Test-ServerConnectivity" {
    BeforeAll {
        $scriptPath = Join-Path $PSScriptRoot `
            ""../../../../scripts/infrastructure/windows/network/Test-ServerConnectivity.ps1""

        # Safe: the script's top-level guard skips Main when dot-sourced.
. $scriptPath -ComputerName @('placeholder-target')

        # Mock ALL externals so nothing touches the machine or network.
        Mock Test-Connection {
            @(
                [pscustomobject]@{ ResponseTime = 10 },
                [pscustomobject]@{ ResponseTime = 12 }
            )
        }
        Mock Test-Path { $true }
        Mock New-Item { }
        Mock Out-File { }
        Mock Export-Csv { }

        $scriptText = Get-Content -Raw $scriptPath
    }

    Context "Help & Metadata" {
        It "Declares Version 1.0.0" {
            $scriptText | Should -Match '(?m)^\s*Version\s*:\s*1\.0\.0\s*$'
        }

        It "Declares relaunch Date 2026-08-23" {
            $scriptText | Should -Match '(?m)^\s*Date\s*:\s*2026-08-23\s*$'
        }

        It "Declares File Name matching the disk filename" {
            $expected = Split-Path -Leaf $scriptPath
            $scriptText | Should -Match "(?m)^\s*File Name\s*:\s*$([regex]::Escape($expected))\s*$"
        }

        It "Declares an Author and Prerequisite" {
            $scriptText | Should -Match '(?m)^\s*Author\s*:\s*\S'
            $scriptText | Should -Match '(?m)^\s*Prerequisite\s*:\s*PowerShell'
        }

        It "Has at least two EXAMPLE blocks with PS C:\> prompts" {
            ([regex]::Matches($scriptText, '(?m)^\.EXAMPLE')).Count | Should -BeGreaterOrEqual 2
            ([regex]::Matches($scriptText, 'PS C:\\>')).Count | Should -BeGreaterOrEqual 2
        }

        It "Has one .PARAMETER per declared parameter, in order" {
            $tokens = $null; $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseInput($scriptText, [ref]$tokens, [ref]$errors)
            $declared = @($ast.ParamBlock.Parameters.Name.VariablePath.UserPath)
            $documented = @([regex]::Matches($scriptText, '(?m)^\.PARAMETER\s+(\w+)') |
                ForEach-Object { $_.Groups[1].Value })
            $documented.Count | Should -Be $declared.Count
            for ($i = 0; $i -lt $declared.Count; $i++) {
                $documented[$i] | Should -Be $declared[$i]
            }
        }
    }

    Context "Syntax & Static" {
        It "Parses cleanly via the PowerShell parser" {
            $tokens = $null; $errors = $null
            [System.Management.Automation.Language.Parser]::ParseFile(
                $scriptPath, [ref]$tokens, [ref]$errors) | Out-Null
            $errors | Should -BeNullOrEmpty
        }

        It "Contains no PS7-only syntax (no #Requires -Version 7.0 present)" {
            $scriptText | Should -Not -Match '#Requires\s+-Version\s+7'
            $scriptText | Should -Not -Match '\?\?'
            $scriptText | Should -Not -Match '&&'
            $scriptText | Should -Not -Match '\|\|'
            $scriptText | Should -Not -Match '-Parallel\b'
        }

        It "Wraps execution in Main and exits only via the top-level guard" {
            $scriptText | Should -Match '(?m)^function Main \{'
            $guardLine = [regex]::Escape("if (`$MyInvocation.InvocationName -ne '.') { exit (Main) }")
            $scriptText | Should -Match $guardLine
            ([regex]::Matches($scriptText, '\bexit\b')).Count | Should -Be 1
        }

        It "Uses UTF-8 BOM and CRLF line endings" {
            $raw = [System.IO.File]::ReadAllBytes($scriptPath)
            ($raw[0], $raw[1], $raw[2]) | Should -Be (0xEF, 0xBB, 0xBF)
            [System.Text.Encoding]::UTF8.GetString($raw) | Should -Not -Match "(?<!`r)`n"
        }
    }

    Context "Behavior" {
        It "Pings a reachable IP target and returns 0 (ports skipped when none supplied)" {
            $ComputerName = @('192.0.2.10')
            $Port = @()

            $out = Main *>&1
            $rc = $out | Where-Object { $_ -is [int] } | Select-Object -First 1
            $rc | Should -Be 0
            ($out | Out-String) | Should -Match '\[\+\]'
            $script:report.Summary.SuccessfulPings | Should -Be 1
            $script:report.Summary.PortTestsRun | Should -Be 0
            Should -Invoke Test-Connection -Times 1 -Exactly
        }

        It "Counts failed pings but still exits 0 (detect-style reporting)" {
            $ComputerName = @('192.0.2.99')
            $Port = @()
            Mock Test-Connection { throw "request timed out" }

            $out = Main *>&1
            $rc = $out | Where-Object { $_ -is [int] } | Select-Object -First 1
            $rc | Should -Be 0
            ($out | Out-String) | Should -Match '\[FAIL\]'
            $script:report.Summary.FailedPings | Should -Be 1
        }

        It "Returns 1 with [-] output when no targets are supplied" {
            $ComputerName = @()
            $out = Main *>&1
            $rc = $out | Where-Object { $_ -is [int] } | Select-Object -First 1
            $rc | Should -Be 1
            ($out | Out-String) | Should -Match '\[-\]'
            Should -Invoke Test-Connection -Times 0 -Exactly
        }
    }
}
