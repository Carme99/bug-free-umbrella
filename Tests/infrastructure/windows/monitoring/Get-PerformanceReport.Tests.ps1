#Requires -Modules Pester

Describe "Get-PerformanceReport" {
    BeforeAll {
        $scriptPath = Join-Path $PSScriptRoot `
            ""../../../../scripts/infrastructure/windows/monitoring/Get-PerformanceReport.ps1""

        # Safe: the script's top-level guard skips Main when dot-sourced.
        . $scriptPath

        # Stub Windows-only commands so Pester can attach mocks on Linux.
        function Get-CimInstance { }
        function Get-Counter { }

        # Mock ALL externals so nothing touches the machine or network.
        Mock Test-AdminPrivilege { $true }
        Mock Start-Sleep { }
        Mock Get-CimInstance {
            [pscustomobject]@{
                TotalVisibleMemorySize = 8388608   # KB -> 8192 MB
                FreePhysicalMemory     = 4194304   # KB -> 4096 MB free
            }
        }
        Mock Get-Counter {
            [pscustomobject]@{
                CounterSamples = @(
                    [pscustomobject]@{
                        Path = '\\host\processor(_total)\% processor time'
                        InstanceName = ''; CookedValue = 12.5
                    },
                    [pscustomobject]@{
                        Path = '\\host\memory\available mbytes'
                        InstanceName = ''; CookedValue = 4096.0
                    }
                )
            }
        }
        Mock Get-Process { @() }
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
        It "Collects the configured samples, analyzes them, and returns 0" {
            $DurationMinutes = 1     # single sample: no sleeps, exactly one Get-Counter call
            $SampleInterval = 60
            $out = Main *>&1
            $rc = $out | Where-Object { $_ -is [int] } | Select-Object -First 1
            $rc | Should -Be 0
            ($out | Out-String) | Should -Match '\[\+\]'
            Should -Invoke Get-Counter -Times 1 -Exactly
            $script:report.TotalSamples | Should -Be 1
            $script:report.CPU.Samples | Should -Contain 12.5
        }

        It "Returns 1 with [-] output when counter collection fails upstream" {
            $DurationMinutes = 1
            $SampleInterval = 60
            Mock Get-CimInstance { throw "WMI unavailable" }
            $out = Main *>&1
            $rc = $out | Where-Object { $_ -is [int] } | Select-Object -First 1
            $rc | Should -Be 1
            ($out | Out-String) | Should -Match '\[-\]'
        }

        It "Returns 1 with [-] output when administrator privileges are missing" {
            Mock Test-AdminPrivilege { $false }
            $out = Main *>&1
            $rc = $out | Where-Object { $_ -is [int] } | Select-Object -First 1
            $rc | Should -Be 1
            ($out | Out-String) | Should -Match '\[-\]'
        }
    }
}
