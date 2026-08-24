#Requires -Modules Pester

Describe "Get-BatteryHealth" {
    BeforeAll {
        $scriptPath = Join-Path $PSScriptRoot "../../../scripts/security/monitoring/Get-BatteryHealth.ps1"
        $scriptName = Split-Path $scriptPath -Leaf
        $rawScript = Get-Content -Raw -LiteralPath $scriptPath

        # Safe: the script's top-level guard skips Main when dot-sourced.
        . $scriptPath

        # Stub Windows-only cmdlets so Pester can mock them on Linux pwsh.
        function Get-CimInstance {
            param([Parameter(Position = 0)][string]$ClassName, [string]$Filter)
        }

        function New-MockBattery {
            [pscustomobject]@{
                Name = 'Test Battery'
                BatteryStatus = 2
                Chemistry = 6
                DesignCapacity = 50000
                FullChargeCapacity = 50000
                EstimatedChargeRemaining = 88
                EstimatedRunTime = 0
            }
        }

        Mock Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_Battery' } { New-MockBattery }
        Mock Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_PortableBattery' } { $null }
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
        It "Reports battery health, writes the HTML summary report, and returns 0" {
            $outDir = Join-Path $TestDrive 'batt-ok'
            $out = Main -OutputPath $outDir 6>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            ($out | Out-String) | Should -Match '\[\+\]'
            Get-ChildItem -Path $outDir -Filter 'BatteryHealthReport_*.html' | Should -Not -BeNullOrEmpty
        }

        It "Warns when battery health is below the alert threshold but still returns 0 (detector)" {
            Mock Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_Battery' } {
                $weak = New-MockBattery
                $weak.FullChargeCapacity = 30000   # 60% health < default 80% threshold
                $weak
            }
            $outDir = Join-Path $TestDrive 'batt-warn'
            $out = Main -OutputPath $outDir 6>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            ($out | Out-String) | Should -Match '\[!\]'
            ($out | Out-String) | Should -Match 'WARNING'
        }

        It "Returns 0 with a warning on desktop systems without a battery" {
            Mock Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_Battery' } { $null }
            $out = Main -OutputPath (Join-Path $TestDrive 'batt-none') 6>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            ($out | Out-String) | Should -Match 'No battery detected'
        }

        It "Rejects unsafe OutputPath with return 1 and [-] prefixed output" {
            $out = Main -OutputPath 'C:\..\evil' 6>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
            ($out | Out-String) | Should -Match '\[-\]'
        }

        It "Exports CSV records when -ExportToCSV is supplied and reruns cleanly on a converged system" {
            $outDir = Join-Path $TestDrive 'batt-csv'
            Main -OutputPath $outDir -ExportToCSV | Should -Be 0
            Get-ChildItem -Path $outDir -Filter 'BatteryHealth_*.csv' | Should -Not -BeNullOrEmpty
            Main -OutputPath $outDir -ExportToCSV | Should -Be 0
        }

        It "Returns 1 and writes [-] prefixed output when battery enumeration fails" {
            Mock Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_Battery' } { throw 'CIM unavailable' }
            $out = Main -OutputPath (Join-Path $TestDrive 'batt-err') 6>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
            ($out | Out-String) | Should -Match '\[-\]'
        }
    }
}
