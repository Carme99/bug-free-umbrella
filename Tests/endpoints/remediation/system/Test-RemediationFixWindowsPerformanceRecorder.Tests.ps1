#Requires -Modules Pester

Describe "Test-RemediationFixWindowsPerformanceRecorder" {
    BeforeAll {
        # Mirrored layout: walk up from Tests/... to the repo root, then across to scripts/.
        $repoRoot = $PSScriptRoot
        while (-not (Test-Path (Join-Path $repoRoot '.git'))) { $repoRoot = Split-Path $repoRoot -Parent }
        $scriptRelPath = 'scripts/endpoints/remediation/system/Test-RemediationFixWindowsPerformanceRecorder.ps1'
        $scriptPath = Join-Path $repoRoot $scriptRelPath

        # Safe: the script's top-level guard skips Main when dot-sourced.
        . $scriptPath

        # Default mocks so nothing touches the real registry; individual Its override as needed.
        Mock Get-ItemProperty { @() }
    }

    Context "Help & Metadata" {
        It "Declares required .NOTES fields with Version 1.0.0 and Date 2026-08-23" {
            $raw = Get-Content -Path $scriptPath -Raw
            $raw | Should -Match 'File Name:\s*Test-RemediationFixWindowsPerformanceRecorder\.ps1'
            $raw | Should -Match 'Version:\s*1\.0\.0'
            $raw | Should -Match 'Date:\s*2026-08-23'
            $raw | Should -Match 'Author:'
            $raw | Should -Match 'Prerequisite:\s*PowerShell 7\.0'
        }

        It "Has SYNOPSIS, DESCRIPTION and at least two EXAMPLES" {
            $help = Get-Help $scriptPath
            $help.Synopsis | Should -Not -BeNullOrEmpty
            $help.Description | Should -Not -BeNullOrEmpty
            @($help.Examples.Example).Count | Should -BeGreaterOrEqual 2
        }

        It "Declares one .PARAMETER per param() parameter" {
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$null, [ref]$null)
            if ($null -eq $ast.ParamBlock) { $declared = @() }
            else { $declared = @($ast.ParamBlock.Parameters.Name.VariableText) }
            $raw = Get-Content -Path $scriptPath -Raw
            $paramHelpMatches = [regex]::Matches($raw, '(?m)^\s*\.PARAMETER\s+(\S+)')
            $documented = @($paramHelpMatches | ForEach-Object { $_.Groups[1].Value })
            @($documented).Count | Should -Be @($declared).Count
            foreach ($p in $declared) { $documented | Should -Contain $p }
        }
    }

    Context "Syntax & Static" {
        BeforeAll {
            $tokens = $null
            $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errors)
        }
        It "Parses with zero errors" {
            $errors | Should -BeNullOrEmpty
        }
        It "Contains no PS7-only operators (no #Requires -Version 7.0 opt-out present)" {
            $raw = Get-Content -Path $scriptPath -Raw
            $raw | Should -Not -Match '(?m)&&|\|\||\?\?|\?\?='
            $raw | Should -Not -Match '\$\w+\s*\?\s*[^:]'
        }
    }

    Context "Behavior" {
        It "Returns 0 when session counts and autologgers are within thresholds" {
            Mock Invoke-LogmanQuery {
                [pscustomobject]@{ ExitCode = 0; Output = @('Status', '------', 'WPR_initiated_WPR_A', 'AudioSes') }
            }
            Main *>&1 | Where-Object { $_ -is [int] } | Should -Be 0
        }

        It "Returns 1 with [!] output when more than two WPR sessions are active" {
            Mock Invoke-LogmanQuery {
                [pscustomobject]@{
                    ExitCode = 0
                    Output   = @('WPR_initiated_WPR_A', 'WPR_initiated_WPR_B', 'WPR_initiated_WPR_C')
                }
            }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[!\]'
            ($out | Out-String) | Should -Match 'Multiple active WPR tracing sessions'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }

        It "Returns 1 with [!] output when a non-eventlog autologger is enabled" {
            Mock Invoke-LogmanQuery { [pscustomobject]@{ ExitCode = 0; Output = @('SomeSession') } }
            Mock Get-ItemProperty {
                @(
                    [pscustomobject]@{ Start = 1; PSChildName = 'EventLog-System' },
                    [pscustomobject]@{ Start = 1; PSChildName = 'StuckAutoLogger' }
                )
            }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[!\]'
            ($out | Out-String) | Should -Match 'stuck AutoLogger'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }

        It "Returns 1 with [!] output when ETW session count exceeds the threshold" {
            $manySessions = @(1..60 | ForEach-Object { "Session$_" })
            Mock Invoke-LogmanQuery { [pscustomobject]@{ ExitCode = 0; Output = $manySessions } }
            $out = Main *>&1
            ($out | Out-String) | Should -Match 'Excessive ETW sessions'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }

        It "Returns 1 and writes [-] prefixed output when the logman query fails" {
            Mock Invoke-LogmanQuery { throw "logman not found" }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[-\]'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }
    }
}
