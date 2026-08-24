#Requires -Modules Pester

Describe "Get-PerformanceTrends" {
    BeforeAll {
        $scriptPath = Join-Path $PSScriptRoot "../../../scripts/security/monitoring/Get-PerformanceTrends.ps1"
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
        function Get-CimInstance {
            param([Parameter(Position = 0)][string]$ClassName, [string]$Filter)
        }

        function Initialize-CounterMocks {
            # Fresh per-test mocks so exact call counts are scoped to the calling It.
            Mock Get-Counter {
                [pscustomobject]@{ CounterSamples = [pscustomobject]@{ CookedValue = 42.5 } }
            }
            Mock Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_OperatingSystem' } {
                [pscustomobject]@{ TotalVisibleMemorySize = 8000000; FreePhysicalMemory = 2000000 }
            }
            Mock Start-Sleep { }
        }

        Mock Get-Counter {
            [pscustomobject]@{ CounterSamples = [pscustomobject]@{ CookedValue = 42.5 } }
        }
        Mock Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_OperatingSystem' } {
            [pscustomobject]@{ TotalVisibleMemorySize = 8000000; FreePhysicalMemory = 2000000 }
        }
        Mock Start-Sleep { }
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
        It "Collects the expected number of samples, exports CSV data, and returns 0 without real delays" {
            Initialize-CounterMocks
            $outDir = Join-Path $TestDrive 'perf-ok'
            $out = Main -DurationMinutes 1 -SampleInterval 30 -OutputPath $outDir 6>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            Should -Invoke Get-Counter -Times 6 -Exactly   # 3 counter queries x 2 samples
            Should -Invoke Start-Sleep -Times 2 -Exactly
            Get-ChildItem -Path $outDir -Filter 'PerformanceData_*.csv' | Should -Not -BeNullOrEmpty
        }

        It "Raises [!] alerts and writes an alerts CSV when thresholds are exceeded" {
            Initialize-CounterMocks
            $outDir = Join-Path $TestDrive 'perf-alert'
            $out = Main -DurationMinutes 1 -SampleInterval 60 -OutputPath $outDir `
                -AlertThresholds @{ CPU = 10; Memory = 85; Disk = 95 } 6>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            ($out | Out-String) | Should -Match '\[!\]'
            Get-ChildItem -Path $outDir -Filter 'Alerts_*.csv' | Should -Not -BeNullOrEmpty
        }

        It "Records top processes when -MonitorProcesses is supplied" {
            Initialize-CounterMocks
            Mock Get-Process {
                [pscustomobject]@{ ProcessName = 'mockproc'; Id = 4242; CPU = 12.3; WorkingSet64 = 100MB }
            }
            $outDir = Join-Path $TestDrive 'perf-proc'
            Main -DurationMinutes 1 -SampleInterval 60 -OutputPath $outDir -MonitorProcesses | Should -Be 0
            Get-ChildItem -Path $outDir -Filter 'ProcessData_*.csv' | Should -Not -BeNullOrEmpty
        }

        It "Rejects unsafe OutputPath with return 1 and [-] prefixed output" {
            $out = Main -DurationMinutes 1 -SampleInterval 60 -OutputPath '//unc-server/reports' 6>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
            ($out | Out-String) | Should -Match '\[-\]'
        }

        It "Returns 1 and writes [-] prefixed output when memory probing fails" {
            Initialize-CounterMocks
            Mock Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_OperatingSystem' } { throw 'WMI broken' }
            $out = Main -DurationMinutes 1 -SampleInterval 60 -OutputPath (Join-Path $TestDrive 'perf-err') 6>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
            ($out | Out-String) | Should -Match '\[-\]'
        }

        It "Is repeatable: a second monitoring run on the same output directory also returns 0" {
            Initialize-CounterMocks
            $outDir = Join-Path $TestDrive 'perf-rerun'
            Main -DurationMinutes 1 -SampleInterval 60 -OutputPath $outDir | Should -Be 0
            Main -DurationMinutes 1 -SampleInterval 60 -OutputPath $outDir | Should -Be 0
        }
    }
}
