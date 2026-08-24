#Requires -Modules Pester

Describe "Get-SystemHealthCheck" {
    BeforeAll {
        $scriptPath = Join-Path $PSScriptRoot "../../../scripts/security/monitoring/Get-SystemHealthCheck.ps1"
        $scriptName = Split-Path $scriptPath -Leaf
        $rawScript = Get-Content -Raw -LiteralPath $scriptPath

        # Safe: the script's top-level guard skips Main when dot-sourced.
        . $scriptPath

        # Stub Windows-only cmdlets so Pester can mock them on Linux pwsh.
        function Get-CimInstance {
            param([Parameter(Position = 0)][string]$ClassName, [string]$Filter)
        }
        function Get-Counter {
            param(
                [Parameter(Position = 0)][string]$Counter,
                [int]$SampleInterval,
                [int]$MaxSamples
            )
        }
        function Get-Service {
            param([Parameter(Position = 0)][string]$Name)
        }
        function Get-WinEvent {
            param([hashtable]$FilterHashtable, [int]$MaxEvents)
        }

        function Initialize-HealthMocks {
            # Fresh per-test mocks so exact behavior is scoped to the calling It.
            Mock Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_Processor' } {
                [pscustomobject]@{
                    Name = 'Mock CPU'
                    NumberOfCores = 4
                    NumberOfLogicalProcessors = 8
                    MaxClockSpeed = 3000
                }
            }
            Mock Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_OperatingSystem' } {
                [pscustomobject]@{
                    TotalVisibleMemorySize = 16000000
                    FreePhysicalMemory = 8000000
                    LastBootUpTime = (Get-Date).AddHours(-5)
                }
            }
            Mock Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_LogicalDisk' } {
                [pscustomobject]@{ DeviceID = 'C:'; Size = 100GB; FreeSpace = 50GB; VolumeName = 'OS' }
            }
            Mock Get-Counter {
                [pscustomobject]@{
                    CounterSamples = @(
                        [pscustomobject]@{ CookedValue = 12.5 }
                        [pscustomobject]@{ CookedValue = 17.5 }
                    )
                }
            }
            Mock Get-Service {
                [pscustomobject]@{
                    Name = 'wuauserv'
                    DisplayName = 'Windows Update'
                    Status = 'Running'
                    StartType = 'Automatic'
                }
            }
            Mock Get-WinEvent { @() }

            $mockSearcher = New-Object -TypeName PSObject
            $mockSearcher | Add-Member -MemberType ScriptMethod -Name Search -Value {
                param($query)
                [pscustomobject]@{ Updates = @([pscustomobject]@{}, [pscustomobject]@{}) }
            }
            $mockSession = New-Object -TypeName PSObject
            $mockSession | Add-Member -MemberType ScriptMethod -Name CreateUpdateSearcher -Value { $mockSearcher }
            Mock New-Object -ParameterFilter { $ComObject -eq 'Microsoft.Update.Session' } { $mockSession }
        }

        Initialize-HealthMocks
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
        It "Completes a healthy check: return 0 with [+] and an Overall Health: Healthy summary" {
            Initialize-HealthMocks
            $out = Main 6>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            $text = $out | Out-String
            $text | Should -Match '\[\+\]'
            $text | Should -Match 'Overall Health: Healthy'
        }

        It "Downgrades to Warning and lists the issue when memory pressure is extreme" {
            Initialize-HealthMocks
            Mock Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_OperatingSystem' } {
                [pscustomobject]@{
                    TotalVisibleMemorySize = 16000000
                    FreePhysicalMemory = 800000   # ~95% used > default 90% threshold
                    LastBootUpTime = (Get-Date).AddHours(-5)
                }
            }
            $out = Main 6>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            $text = $out | Out-String
            $text | Should -Match 'Memory usage is very high'
            $text | Should -Match 'Overall Health: Warning'
        }

        It "Flags a stopped automatic critical service as a critical issue" {
            Initialize-HealthMocks
            Mock Get-Service {
                [pscustomobject]@{
                    Name = 'BITS'
                    DisplayName = 'Background Intelligent Transfer'
                    Status = 'Stopped'
                    StartType = 'Automatic'
                }
            }
            $out = Main 6>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            ($out | Out-String) | Should -Match 'Critical service not running'
        }

        It "Returns 1 with [-] output for an unsafe OutputPath when export is requested" {
            $out = Main -OutputFormat HTML -OutputPath '\\unc-server\reports' 6>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
            ($out | Out-String) | Should -Match '\[-\]'
        }

        It "Warns that HTML export is not implemented yet still returns 0 on a valid path" {
            Initialize-HealthMocks
            $outDir = Join-Path $TestDrive 'hc-out'
            $out = Main -OutputFormat HTML -OutputPath $outDir 6>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            ($out | Out-String) | Should -Match '\[!\]'
            ($out | Out-String) | Should -Match 'not implemented'
        }

        It "Is idempotent: consecutive runs against the same mocked system both return 0" {
            Initialize-HealthMocks
            Main | Should -Be 0
            Main | Should -Be 0
        }
    }
}
