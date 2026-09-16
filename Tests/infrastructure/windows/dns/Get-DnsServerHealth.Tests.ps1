#Requires -Modules Pester
<#
.SYNOPSIS
    Pester tests for scripts/infrastructure/windows/dns/Get-DnsServerHealth.ps1.
.DESCRIPTION
    Validates help/metadata conformance, static syntax rules, and observable behaviour of the
    DNS server health audit using fully mocked DnsServer cmdlets. Runs offline on Linux pwsh;
    no network, elevation, or installed product modules required.
.EXAMPLE
    PS C:\> Invoke-Pester -Path ./Tests/infrastructure/windows/dns/Get-DnsServerHealth.Tests.ps1
    Runs this test file.
.EXAMPLE
    PS C:\> Invoke-Pester -Path ./Tests/infrastructure/windows/dns/Get-DnsServerHealth.Tests.ps1 `
        -Output Detailed
    Runs this test file with per-test output.
.NOTES
    File Name   : Get-DnsServerHealth.Tests.ps1
    Author      : Bug-Free Umbrella
    Prerequisite: PowerShell 7.0
    Version     : 2.0.0
    Date        : 2026-09-16
#>

Describe 'Get-DnsServerHealth' {
    BeforeAll {
        $relativePath = '../../../../scripts/infrastructure/windows/dns/Get-DnsServerHealth.ps1'
        $scriptPath = Join-Path $PSScriptRoot $relativePath

        # Safe: the script's top-level guard skips Main when dot-sourced (RELAUNCH-SPEC section 3).
        . $scriptPath

        # The DnsServer module is not installed offline: declare its cmdlets as empty advanced
        # functions with their real parameter sets, then Mock each one.
        function Get-DnsServerZone {
            [CmdletBinding()]
            param(
                [Parameter()][string[]]$Name,
                [Parameter()][string]$ComputerName,
                [Parameter()][string]$VirtualizationInstance,
                [Parameter()][object[]]$CimSession,
                [Parameter()][int]$ThrottleLimit,
                [Parameter()][switch]$AsJob
            )
        }

        function Get-DnsServerZoneAging {
            [CmdletBinding()]
            param(
                [Parameter()][string[]]$Name,
                [Parameter()][string]$ComputerName,
                [Parameter()][object[]]$CimSession,
                [Parameter()][int]$ThrottleLimit,
                [Parameter()][switch]$AsJob
            )
        }

        function Get-DnsServerScavenging {
            [CmdletBinding()]
            param(
                [Parameter()][string]$ComputerName,
                [Parameter()][object[]]$CimSession,
                [Parameter()][int]$ThrottleLimit,
                [Parameter()][switch]$AsJob
            )
        }

        function Get-DnsServerForwarder {
            [CmdletBinding()]
            param(
                [Parameter()][string]$ComputerName,
                [Parameter()][object[]]$CimSession,
                [Parameter()][int]$ThrottleLimit,
                [Parameter()][switch]$AsJob
            )
        }

        function Get-DnsServerRecursion {
            [CmdletBinding()]
            param(
                [Parameter()][string]$ComputerName,
                [Parameter()][object[]]$CimSession,
                [Parameter()][int]$ThrottleLimit,
                [Parameter()][switch]$AsJob
            )
        }

        function Get-DnsServerResourceRecord {
            [CmdletBinding()]
            param(
                [Parameter()][string]$Name,
                [Parameter()][string]$ZoneName,
                [Parameter()][string]$RRType,
                [Parameter()][uint16]$Type,
                [Parameter()][string]$ComputerName,
                [Parameter()][switch]$Node,
                [Parameter()][string]$ZoneScope,
                [Parameter()][string]$VirtualizationInstance,
                [Parameter()][object[]]$CimSession,
                [Parameter()][int]$ThrottleLimit,
                [Parameter()][switch]$AsJob
            )
        }

        Mock Import-Module { }

        # Default inventory: one healthy AD-integrated primary zone, scavenging on, forwarders set.
        Mock Get-DnsServerScavenging {
            [pscustomobject]@{
                ScavengingState    = $true
                ScavengingInterval = [timespan]::FromDays(7)
            }
        }

        Mock Get-DnsServerZone {
            @(
                [pscustomobject]@{
                    ZoneName            = 'contoso.com'
                    ZoneType            = 'Primary'
                    IsDsIntegrated      = $true
                    IsReverseLookupZone = $false
                }
            )
        }

        Mock Get-DnsServerZoneAging {
            [pscustomobject]@{
                ZoneName            = 'contoso.com'
                AgingEnabled        = $true
                AvailForScavengeTime = [timespan]::FromDays(3)
            }
        }

        Mock Get-DnsServerForwarder {
            [pscustomobject]@{
                IPAddress   = @('10.0.0.10', '10.0.0.11')
                UseRootHint = $false
            }
        }

        Mock Get-DnsServerRecursion {
            [pscustomobject]@{ Enable = $true; Timeout = 8; RetryInterval = 15 }
        }

        Mock Get-DnsServerResourceRecord { @() }

        $raw = [IO.File]::ReadAllText($scriptPath)
        $tokens = $null
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens,
            [ref]$errors)
    }

    Context 'Help & Metadata' {
        It 'Declares all five NOTES fields with v2.0.0 values' {
            $raw | Should -Match '(?m)File Name\s*:\s*Get-DnsServerHealth\.ps1'
            $raw | Should -Match '(?m)Author\s*:\s*\S+'
            $raw | Should -Match '(?m)Prerequisite\s*:\s*PowerShell 7\.0'
            $raw | Should -Match '(?m)Version\s*:\s*2\.0\.0'
            $raw | Should -Match '(?m)Date\s*:\s*2026-09-16'
        }

        It 'Has one PARAMETER entry per declared parameter' {
            foreach ($name in @('ComputerName', 'ScavengingStaleDays', 'IncludeStaleRecords',
                    'OutputFormat', 'OutputPath')) {
                $raw | Should -Match "(?m)\.PARAMETER\s+$name"
            }
        }

        It 'Provides at least two examples with PS prompts' {
            ([regex]::Matches($raw, '(?m)^\.EXAMPLE')).Count | Should -BeGreaterOrEqual 2
            ([regex]::Matches($raw, '(?m)^\s*PS C:\\>')).Count | Should -BeGreaterOrEqual 2
        }

        It 'Documents the exit codes and cites Microsoft Learn' {
            $raw | Should -Match 'Exit codes: 0 = healthy'
            $raw | Should -Match '2 = findings present'
            $raw | Should -Match '1 = error'
            $raw | Should -Match 'learn\.microsoft\.com/powershell/module/dnsserver/'
        }
    }

    Context 'Syntax & Static' {
        It 'Parses with zero syntax errors' {
            $errors.Count | Should -Be 0
        }

        It 'Uses CmdletBinding, Main function, and dot-source guard' {
            $raw | Should -Match '\[CmdletBinding\('
            $raw | Should -Match '(?m)function Main\b'
            $raw | Should -Match 'if \(\$MyInvocation\.InvocationName -ne ''\.''\) \{ exit \(Main\) \}'
        }

        It 'Contains no PS7-only operators and no #Requires opt-out' {
            ($raw -match '\?\?') | Should -BeFalse
            ($raw -match '\|\|') | Should -BeFalse
            ($raw -match '&&') | Should -BeFalse
            ($raw -match '#Requires\s+-Version') | Should -BeFalse
        }

        It 'Is UTF-8 with BOM and CRLF line endings' {
            $bytes = [IO.File]::ReadAllBytes($scriptPath)
            ($bytes[0], $bytes[1], $bytes[2]) | Should -Be (0xEF, 0xBB, 0xBF)
            ($raw -replace "`r`n", '').Contains("`n") | Should -BeFalse
        }

        It 'Guards the module import inside Main and exits 1 with a [-] line' {
            $raw | Should -Match 'Import-Module DnsServer -ErrorAction Stop'
            $raw | Should -Match 'if \(-not \(Get-Command Get-DnsServerZone -ErrorAction SilentlyContinue\)\)'
        }
    }

    Context 'Behavior' {
        It 'Reports a healthy DNS server and exits 0' {
            $out = Main *>&1
            $text = $out | Out-String
            $text | Should -Match '\[\+\] Zone ''contoso\.com'''
            $text | Should -Match 'Findings: 0'
            $text | Should -Match '\[\+\] DNS server .* passed every check\.'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            Should -Invoke Get-DnsServerZone -Times 1 -Exactly
            Should -Invoke Get-DnsServerScavenging -Times 1 -Exactly
            Should -Invoke Get-DnsServerForwarder -Times 1 -Exactly
            Should -Invoke Get-DnsServerRecursion -Times 1 -Exactly
        }

        It 'Flags a zone whose aging is disabled and exits 2' {
            Mock Get-DnsServerZoneAging { [pscustomobject]@{ AgingEnabled = $false } }
            $out = Main *>&1
            $text = $out | Out-String
            $text | Should -Match '\[!\] Zone ''contoso\.com'' aging is disabled'
            $text | Should -Match 'Zone aging disabled'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 2
        }

        It 'Flags a zone with no Active Directory replication coverage and exits 2' {
            Mock Get-DnsServerZone {
                @(
                    [pscustomobject]@{
                        ZoneName       = 'legacy.local'
                        ZoneType       = 'Primary'
                        IsDsIntegrated = $false
                    }
                )
            }
            $out = Main *>&1
            $text = $out | Out-String
            $text | Should -Match '\[!\] Zone ''legacy\.local'' is not AD-integrated'
            $text | Should -Match 'Replication'
            $text | Should -Match 'Not AD replication coverage|No AD replication coverage'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 2
        }

        It 'Flags only records older than the stale threshold when -IncludeStaleRecords is set' {
            $IncludeStaleRecords = $true
            $ScavengingStaleDays = 7
            Mock Get-DnsServerResourceRecord {
                @(
                    [pscustomobject]@{
                        HostName   = 'oldhost'
                        RecordType = 'A'
                        Timestamp  = (Get-Date).AddDays(-30)
                    }
                    [pscustomobject]@{
                        HostName   = 'freshhost'
                        RecordType = 'A'
                        Timestamp  = (Get-Date).AddDays(-1)
                    }
                )
            }
            $out = Main *>&1
            $text = $out | Out-String
            $text | Should -Match "Stale record 'oldhost'"
            $text | Should -Match 'Stale records found: 1'
            ($text -match "Stale record 'freshhost'") | Should -BeFalse
            ($out | Where-Object { $_ -is [int] }) | Should -Be 2
            Should -Invoke Get-DnsServerResourceRecord -Times 1 -Exactly `
                -ParameterFilter { $ZoneName -eq 'contoso.com' }
        }

        It 'Skips the stale record check when -IncludeStaleRecords is not set' {
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            Should -Invoke Get-DnsServerResourceRecord -Times 0 -Exactly `
                -Because 'the stale record check is opt-in'
        }

        It 'Flags a server scavenging feature that is switched off' {
            Mock Get-DnsServerScavenging { [pscustomobject]@{ ScavengingState = $false } }
            $out = Main *>&1
            $text = $out | Out-String
            $text | Should -Match '\[!\] Server scavenging is disabled'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 2
        }

        It 'Exits 1 with a [-] line when the DnsServer module cannot be imported' {
            Mock Import-Module { throw 'module not found' }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[-\] Error: module not found'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
            Should -Invoke Get-DnsServerZone -Times 0 -Exactly
        }

        It 'Returns 1 for an unsafe -OutputPath without querying the server' {
            $OutputPath = '../escape'
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[-\] Unsafe OutputPath'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
            Should -Invoke Get-DnsServerZone -Times 0 -Exactly
        }

        It 'Writes a JSON report under -OutputPath and leaves the working directory alone' {
            $OutputFormat = 'Json'
            $OutputPath = $TestDrive
            $workingDirectory = (Get-Location).Path
            $out = Main *>&1
            $text = $out | Out-String
            $files = @(Get-ChildItem -LiteralPath $TestDrive -Filter '*.json')
            $files.Count | Should -Be 1
            $text | Should -Match '\[\+\] JSON report written:'
            $report = Get-Content -LiteralPath $files[0].FullName -Raw | ConvertFrom-Json
            $report.Findings | Should -Be 0
            $report.ComputerName | Should -Be $ComputerName
            @($report.Zones).Count | Should -Be 1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            (Get-Location).Path | Should -Be $workingDirectory
        }

        It 'Writes a CSV report with one row per check under -OutputPath' {
            $OutputFormat = 'Csv'
            $OutputPath = $TestDrive
            $out = Main *>&1
            $files = @(Get-ChildItem -LiteralPath $TestDrive -Filter '*.csv')
            $files.Count | Should -Be 1
            $rows = @(Import-Csv -LiteralPath $files[0].FullName)
            $rows.Count | Should -BeGreaterOrEqual 4
            @($rows | Where-Object { $_.Status -ne 'Pass' }).Count | Should -Be 0
            @($rows | Where-Object { $_.Category -eq 'Zone' }).Count | Should -Be 1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
        }

        It 'Is idempotent: repeated runs return the same exit code' {
            $firstRun = (Main *>&1 | Where-Object { $_ -is [int] })
            $secondRun = (Main *>&1 | Where-Object { $_ -is [int] })
            $firstRun | Should -Be 0
            $secondRun | Should -Be 0
        }
    }
}
