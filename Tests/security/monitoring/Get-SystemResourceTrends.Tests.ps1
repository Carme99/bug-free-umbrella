#Requires -Modules Pester

Describe "Get-SystemResourceTrends" {
    BeforeAll {
        $scriptPath = Join-Path $PSScriptRoot "../../../scripts/security/monitoring/Get-SystemResourceTrends.ps1"
        $scriptName = Split-Path $scriptPath -Leaf
        $rawScript = Get-Content -Raw -LiteralPath $scriptPath

        # Safe: the script's top-level guard skips Main when dot-sourced.
        . $scriptPath

        # Stub Windows-only cmdlets so Pester can mock them on Linux pwsh.
        function Get-Counter {
            param(
                [Parameter(Position = 0)][string]$Counter,
                [int]$SampleInterval,
                [int]$MaxSamples
            )
        }

        function Initialize-CounterMocks {
            # Fresh per-test mock so exact call counts are scoped to the calling It.
            Mock Get-Counter {
                [pscustomobject]@{ CounterSamples = [pscustomobject]@{ CookedValue = 33.3 } }
            }
        }

        Mock Get-Counter {
            [pscustomobject]@{ CounterSamples = [pscustomobject]@{ CookedValue = 33.3 } }
        }
    }

    Context "Help & Metadata" {
        It "Declares Version 1.0.0 and the relaunch Date in NOTES" {
            $rawScript | Should -Match '(?m)^\s*Version\s*:\s*1\.0\.0\s*$'
            $rawScript | Should -Match '(?m)^\s*Date\s*:\s*2026-08-23\s*$'
        }

        It "Matches File Name to the disk filename and declares all five NOTES fields" {
            $rawScript | Should -Match "(?m)^\s*File Name\s*:\s*$([regex]::Escape($scriptName))\s*$"
            foreach ($field in 'Author', 'Prerequisite', 'Version', 'Date') {
                $rawScript | Should -Match "(?m)^\s*$field\s*:\s*\S"
            }
        }

        It "Documents one .PARAMETER block per declared parameter, in order" {
            $tokens = $null
            $parseErrors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile(
                $scriptPath, [ref]$tokens, [ref]$parseErrors)
            $declared = @($ast.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath })
            $helpParams = @([regex]::Matches($rawScript, '(?m)^\s*\.PARAMETER\s+(\w+)') |
                ForEach-Object { $_.Groups[1].Value })
            $helpParams | Should -Be $declared
        }

        It "Provides at least two EXAMPLES with PS C:\> prompts" {
            ([regex]::Matches($rawScript, 'PS C:\\>')).Count | Should -BeGreaterOrEqual 2
        }
    }

    Context "Syntax & Static" {
        It "Parses with zero errors" {
            $tokens = $null
            $parseErrors = $null
            [System.Management.Automation.Language.Parser]::ParseFile(
                $scriptPath, [ref]$tokens, [ref]$parseErrors) | Out-Null
            $parseErrors | Should -BeNullOrEmpty
        }

        It "Contains no PS7-only operators and uses the mandatory Main + dot-source guard shape" {
            $codeLines = ($rawScript -split "`r?`n") | Where-Object { $_ -notmatch '^\s*#' }
            ($codeLines -join "`n") | Should -Not -Match '\?\?=|\?\?|\|\||&&'
            $eapPattern = [regex]::Escape('$ErrorActionPreference = ''Stop''')
            $guardPattern = [regex]::Escape(
                'if ($MyInvocation.InvocationName -ne ''.'') { exit (Main @PSBoundParameters) }')
            $rawScript | Should -Match $eapPattern
            $rawScript | Should -Match $guardPattern
        }
    }

    Context "Behavior" {
        It "Samples CPU, memory, and disk counters (mocked, instant) and returns 0" {
            Initialize-CounterMocks
            $out = Main 6>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            $text = $out | Out-String
            $text | Should -Match '\[\+\] Average CPU: 33\.3%'
            $text | Should -Match '\[\+\] Average Memory: 33\.3%'
            $text | Should -Match '\[\+\] Average Disk Idle: 33\.3%'
            Should -Invoke Get-Counter -Times 3 -Exactly
        }

        It "Returns 1 and writes [-] prefixed output when counter collection fails" {
            Initialize-CounterMocks
            Mock Get-Counter { throw 'counter service unavailable' }
            $out = Main 6>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
            ($out | Out-String) | Should -Match '\[-\]'
        }

        It "Is idempotent: repeated sampling runs both return 0" {
            Initialize-CounterMocks
            Main | Should -Be 0
            Main | Should -Be 0
        }
    }
}
