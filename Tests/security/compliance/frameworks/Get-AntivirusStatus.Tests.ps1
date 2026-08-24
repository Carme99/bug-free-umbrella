#Requires -Modules Pester

Describe "Get-AntivirusStatus" {
    BeforeAll {
        $scriptName = "Get-AntivirusStatus.ps1"
        $scriptPath = Join-Path $PSScriptRoot "../../../../scripts/security/compliance/frameworks/$scriptName"
        . $scriptPath

        # Defender module and other Windows-only cmdlets do not exist on Linux; declare
        # function seams first so Pester has local commands to mock.
        function Get-MpComputerStatus { $null }
        function Get-MpThreatDetection { $null }
        function Get-MpThreat { $null }
        function Get-CimInstance { $null }
        function Get-Service { $null }
        function Get-NetFirewallProfile { $null }

        Mock Get-MpComputerStatus {
            [pscustomobject]@{
                AntivirusEnabled              = $true
                RealTimeProtectionEnabled     = $true
                BehaviorMonitorEnabled        = $true
                IoavProtectionEnabled         = $true
                OnAccessProtectionEnabled     = $true
                AntivirusSignatureVersion     = '1.405.1234.0'
                AntivirusSignatureAge         = 1
                AntivirusSignatureLastUpdated = (Get-Date).AddHours(-6)
                QuickScanAge                  = 1
                FullScanAge                   = 4
                QuickScanEndTime              = (Get-Date).AddHours(-20)
                FullScanEndTime               = (Get-Date).AddDays(-4)
            }
        }
        Mock Get-MpThreatDetection { @() }
        Mock Get-MpThreat { @() }
        Mock Get-CimInstance { @() }
        Mock Get-Service { $null }
        Mock Get-NetFirewallProfile {
            @(
                [pscustomobject]@{ Name = 'Domain'; Enabled = $true }
                [pscustomobject]@{ Name = 'Private'; Enabled = $true }
                [pscustomobject]@{ Name = 'Public'; Enabled = $true }
            )
        }

        $tokens = $null
        $parseErrors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
        $raw = Get-Content -LiteralPath $scriptPath -Raw
    }

    Context "Help & Metadata" {
        It "Declares a File Name matching the disk filename" {
            $raw | Should -Match ([regex]::Escape("File Name   : $scriptName"))
        }

        It "Pins Version 1.0.0 and relaunch Date 2026-08-23" {
            $raw | Should -Match 'Version\s*:\s*1\.0\.0'
            $raw | Should -Match 'Date\s*:\s*2026-08-23'
        }

        It "Documents every declared parameter in declaration order" {
            $declared = @($ast.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath })
            $documented = @([regex]::Matches($raw, '(?m)^\.PARAMETER\s+(\S+)') | ForEach-Object { $_.Groups[1].Value })
            $documented | Should -Be $declared
        }

        It "Provides at least two EXAMPLES with PS C:\> prompts" {
            ([regex]::Matches($raw, '(?m)^\.EXAMPLE\s*$')).Count | Should -BeGreaterOrEqual 2
            ([regex]::Matches($raw, 'PS C:\\>')).Count | Should -BeGreaterOrEqual 2
        }
    }

    Context "Syntax & Static" {
        It "Parses with zero errors" {
            $parseErrors | Should -BeNullOrEmpty
        }

        It "Avoids PS7-only operators (targets 5.1-compatible syntax)" {
            $offenders = @($raw -split "`n" | Where-Object { $_ -match '\?\?|\?\?=|&&|\|\|' })
            $offenders | Should -BeNullOrEmpty
        }

        It "Wraps execution in Main with a dot-source guard and exit only in the guard line" {
            $raw | Should -Match 'function Main \{'
            $raw | Should -Match ([regex]::Escape("if (`$MyInvocation.InvocationName -ne '.') { exit (Main) }"))
            ($raw -split "`n" | Where-Object { $_ -match '(?m)^\s*exit\b' }).Count | Should -Be 1
        }
    }

    Context "Behavior" {
        It "Returns 0 on a fully protected system with no issues" {
            $out = Main *>&1
            $out | Where-Object { $_ -is [int] } | Should -Be 0
            ($out | Out-String) | Should -Match '\[\+\]'
            Should -Invoke Get-MpComputerStatus -Exactly 1
        }

        It "Is idempotent: a second run on a converged system still returns 0" {
            Main | Should -Be 0
            Main | Should -Be 0
        }

        It "Returns 1 when Defender real-time protection is disabled" {
            Mock Get-MpComputerStatus {
                [pscustomobject]@{
                    AntivirusEnabled          = $true
                    RealTimeProtectionEnabled = $false
                    AntivirusSignatureVersion = '1.405.1234.0'
                    AntivirusSignatureAge     = 1
                    QuickScanAge              = 1
                }
            }
            $out = Main *>&1
            $out | Where-Object { $_ -is [int] } | Should -Be 1
            ($out | Out-String) | Should -Match 'Real-Time Protection is DISABLED'
        }

        It "Returns 1 and writes [-] output when Defender status cannot be retrieved" {
            Mock Get-MpComputerStatus { $null }
            $out = Main *>&1
            $out | Where-Object { $_ -is [int] } | Should -Be 1
            ($out | Out-String) | Should -Match '\[-\]'
            ($out | Out-String) | Should -Match 'Could not retrieve Windows Defender status'
        }
    }
}
