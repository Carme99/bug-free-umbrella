#Requires -Modules Pester

Describe "Get-FailedLoginReport" {
    BeforeAll {
        $scriptName = "Get-FailedLoginReport.ps1"
        $scriptPath = Join-Path $PSScriptRoot "../../../../scripts/security/compliance/frameworks/$scriptName"
        . $scriptPath

        # Get-WinEvent (Microsoft.PowerShell.Diagnostics) is absent on Linux; declare a
        # function seam first so Pester has a local command to mock.
        function Get-WinEvent { param([hashtable]$FilterHashtable) $null }

        function New-TestFailedLogonEvent {
            param(
                [string]$UserName = 'svc_test',
                [string]$IpAddress = '10.0.0.5',
                [string]$LogonType = '10',
                [string]$Status = '0xC000006A'
            )
            $xmlPayload = '<Event><EventData>' +
                "<Data Name=`"TargetUserName`">$UserName</Data>" +
                "<Data Name=`"TargetDomainName`">CONTOSO</Data>" +
                "<Data Name=`"WorkstationName`">WS-01</Data>" +
                "<Data Name=`"IpAddress`">$IpAddress</Data>" +
                "<Data Name=`"LogonType`">$LogonType</Data>" +
                "<Data Name=`"Status`">$Status</Data>" +
                "<Data Name=`"SubStatus`">$Status</Data>" +
                '</EventData></Event>'
            $evt = [pscustomobject]@{
                TimeCreated = (Get-Date)
                Id          = 4625
                XmlPayload  = $xmlPayload
            }
            Add-Member -InputObject $evt -MemberType ScriptMethod -Name ToXml -Value { $this.XmlPayload }
            $evt
        }

        Mock Get-WinEvent -ParameterFilter { $FilterHashtable.ID -eq 4625 } { @() }
        Mock Get-WinEvent -ParameterFilter { $FilterHashtable.ID -eq 4740 } { @() }

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

        It "Contains no RunAsAdministrator requirement that would break dot-sourcing offline" {
            $raw | Should -Not -Match '#Requires\s+-RunAsAdministrator'
        }
    }

    Context "Behavior" {
        It "Detects a brute-force pattern from repeated failures and returns 1" {
            Mock Get-WinEvent -ParameterFilter { $FilterHashtable.ID -eq 4625 } {
                @(1..6 | ForEach-Object { New-TestFailedLogonEvent -UserName 'svc_backup' -IpAddress '203.0.113.9' })
            }
            Mock Get-WinEvent -ParameterFilter { $FilterHashtable.ID -eq 4740 } { @() }

            $out = Main *>&1
            $out | Where-Object { $_ -is [int] } | Should -Be 1
            ($out | Out-String) | Should -Match 'Brute Force Attack Detected'
            ($out | Out-String) | Should -Match 'Incorrect password'
        }

        It "Returns 0 when no failed logon or lockout events exist and queries both event IDs" {
            Mock Get-WinEvent -ParameterFilter { $FilterHashtable.ID -eq 4625 } { @() }
            Mock Get-WinEvent -ParameterFilter { $FilterHashtable.ID -eq 4740 } { @() }

            $out = Main *>&1
            $out | Where-Object { $_ -is [int] } | Should -Be 0
            ($out | Out-String) | Should -Match '\[\+\]'
            Should -Invoke Get-WinEvent -Exactly 2
        }

        It "Is idempotent: repeated runs against an unchanged quiet log still return 0" {
            Mock Get-WinEvent -ParameterFilter { $FilterHashtable.ID -eq 4625 } { @() }
            Mock Get-WinEvent -ParameterFilter { $FilterHashtable.ID -eq 4740 } { @() }
            Main | Should -Be 0
            Main | Should -Be 0
        }

        It "Returns 1 and writes [-] output when the Security log cannot be queried" {
            Mock Get-WinEvent -ParameterFilter { $FilterHashtable.ID -eq 4625 } {
                throw 'Attempted to perform an unauthorized operation.'
            }
            Mock Get-WinEvent -ParameterFilter { $FilterHashtable.ID -eq 4740 } {
                throw 'Attempted to perform an unauthorized operation.'
            }
            $out = Main *>&1
            $out | Where-Object { $_ -is [int] } | Should -Be 1
            ($out | Out-String) | Should -Match '\[-\]'
            ($out | Out-String) | Should -Match 'Unable to query event log'
        }
    }
}
