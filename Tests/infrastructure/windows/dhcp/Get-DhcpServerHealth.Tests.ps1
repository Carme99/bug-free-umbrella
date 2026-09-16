#Requires -Modules Pester
<#
.SYNOPSIS
    Pester tests for scripts/infrastructure/windows/dhcp/Get-DhcpServerHealth.ps1.
.DESCRIPTION
    Validates help/metadata conformance, static syntax rules, and observable behaviour of the
    DHCP server health audit using fully mocked DhcpServer cmdlets. Runs offline on Linux pwsh;
    no network, elevation, or installed product modules required.
.EXAMPLE
    PS C:\> Invoke-Pester -Path ./Tests/infrastructure/windows/dhcp/Get-DhcpServerHealth.Tests.ps1
    Runs this test file.
.EXAMPLE
    PS C:\> Invoke-Pester -Path ./Tests/infrastructure/windows/dhcp/Get-DhcpServerHealth.Tests.ps1 `
        -Output Detailed
    Runs this test file with per-test output.
.NOTES
    File Name   : Get-DhcpServerHealth.Tests.ps1
    Author      : Bug-Free Umbrella
    Prerequisite: PowerShell 7.0
    Version     : 2.0.0
    Date        : 2026-09-16
#>

Describe 'Get-DhcpServerHealth' {
    BeforeAll {
        $relativePath = '../../../../scripts/infrastructure/windows/dhcp/Get-DhcpServerHealth.ps1'
        $scriptPath = Join-Path $PSScriptRoot $relativePath

        # Safe: the script's top-level guard skips Main when dot-sourced (RELAUNCH-SPEC section 3).
        . $scriptPath

        # The DhcpServer module is not installed offline: declare its cmdlets as empty advanced
        # functions with their real parameter sets, then Mock each one.
        function Get-DhcpServerv4Scope {
            [CmdletBinding()]
            param(
                [Parameter()][string]$ComputerName,
                [Parameter()][object[]]$ScopeId,
                [Parameter()][object[]]$CimSession,
                [Parameter()][int]$ThrottleLimit,
                [Parameter()][switch]$AsJob
            )
        }

        function Get-DhcpServerv4ScopeStatistics {
            [CmdletBinding()]
            param(
                [Parameter()][object[]]$ScopeId,
                [Parameter()][string]$ComputerName,
                [Parameter()][switch]$Failover,
                [Parameter()][object[]]$CimSession,
                [Parameter()][int]$ThrottleLimit,
                [Parameter()][switch]$AsJob
            )
        }

        function Get-DhcpServerv4OptionValue {
            [CmdletBinding()]
            param(
                [Parameter()][string]$VendorClass,
                [Parameter()][string]$ComputerName,
                [Parameter()][object]$ScopeId,
                [Parameter()][object]$ReservedIP,
                [Parameter()][object[]]$OptionId,
                [Parameter()][string]$UserClass,
                [Parameter()][switch]$All,
                [Parameter()][switch]$Brief,
                [Parameter()][string]$PolicyName,
                [Parameter()][object[]]$CimSession,
                [Parameter()][int]$ThrottleLimit,
                [Parameter()][switch]$AsJob
            )
        }

        function Get-DhcpServerv4Failover {
            [CmdletBinding()]
            param(
                [Parameter()][string[]]$Name,
                [Parameter()][object[]]$ScopeId,
                [Parameter()][string]$ComputerName,
                [Parameter()][object[]]$CimSession,
                [Parameter()][int]$ThrottleLimit,
                [Parameter()][switch]$AsJob
            )
        }

        Mock Import-Module { }

        # Default inventory: one healthy scope with ample free addresses, both required options
        # configured and a failover relationship in the Normal state.
        Mock Get-DhcpServerv4Scope {
            @(
                [pscustomobject]@{
                    ScopeId    = '10.10.10.0'
                    Name       = 'Head Office'
                    State      = 'Active'
                    StartRange = '10.10.10.20'
                    EndRange   = '10.10.10.250'
                    SubnetMask = '255.255.255.0'
                }
            )
        }

        Mock Get-DhcpServerv4ScopeStatistics {
            @(
                [pscustomobject]@{
                    ScopeId         = '10.10.10.0'
                    AddressesFree   = 200
                    AddressesInUse  = 50
                    PendingOffers   = 0
                    ReservedAddress = 5
                    PercentageInUse = 20
                }
            )
        }

        Mock Get-DhcpServerv4OptionValue {
            @(
                [pscustomobject]@{ OptionId = 3; Name = 'Router'; Value = @('10.10.10.1') }
                [pscustomobject]@{ OptionId = 6; Name = 'DNS Servers'; Value = @('10.10.10.10') }
            )
        }

        Mock Get-DhcpServerv4Failover {
            @(
                [pscustomobject]@{
                    Name          = 'DC1-DC2'
                    State         = 'Normal'
                    Mode          = 'LoadBalance'
                    PartnerServer = '10.10.10.2'
                }
            )
        }

        $raw = [IO.File]::ReadAllText($scriptPath)
        $tokens = $null
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens,
            [ref]$errors)
    }

    Context 'Help & Metadata' {
        It 'Declares all five NOTES fields with v2.0.0 values' {
            $raw | Should -Match '(?m)File Name\s*:\s*Get-DhcpServerHealth\.ps1'
            $raw | Should -Match '(?m)Author\s*:\s*\S+'
            $raw | Should -Match '(?m)Prerequisite\s*:\s*PowerShell 7\.0'
            $raw | Should -Match '(?m)Version\s*:\s*2\.0\.0'
            $raw | Should -Match '(?m)Date\s*:\s*2026-09-16'
        }

        It 'Has one PARAMETER entry per declared parameter' {
            foreach ($name in @('ComputerName', 'ScopeId', 'LowFreeAddressThreshold',
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
            $raw | Should -Match 'learn\.microsoft\.com/powershell/module/dhcpserver/'
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
            $raw | Should -Match 'Import-Module DhcpServer -ErrorAction Stop'
            $raw | Should -Match 'Get-Command Get-DhcpServerv4Scope -ErrorAction SilentlyContinue'
        }
    }

    Context 'Behavior' {
        It 'Reports a healthy DHCP server and exits 0' {
            $out = Main *>&1
            $text = $out | Out-String
            $text | Should -Match '\[\+\] Found 1 scope\(s\)'
            $text | Should -Match '\[\+\] Scope 10\.10\.10\.0 is 80% free'
            $text | Should -Match "\[\+\] Failover 'DC1-DC2' is Normal"
            $text | Should -Match 'Findings: 0'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            Should -Invoke Get-DhcpServerv4Scope -Times 1 -Exactly
            Should -Invoke Get-DhcpServerv4ScopeStatistics -Times 1 -Exactly
            Should -Invoke Get-DhcpServerv4Failover -Times 1 -Exactly
        }

        It 'Flags a scope below the free address threshold and exits 2' {
            Mock Get-DhcpServerv4ScopeStatistics {
                @(
                    [pscustomobject]@{
                        ScopeId         = '10.10.10.0'
                        AddressesFree   = 20
                        AddressesInUse  = 380
                        PendingOffers   = 0
                        ReservedAddress = 0
                        PercentageInUse = 95
                    }
                )
            }
            $out = Main *>&1
            $text = $out | Out-String
            $text | Should -Match '\[!\] Scope 10\.10\.10\.0 is only 5% free'
            $text | Should -Match 'below the 20% threshold'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 2
        }

        It 'Honours a raised -LowFreeAddressThreshold' {
            $LowFreeAddressThreshold = 90
            $out = Main *>&1
            $text = $out | Out-String
            $text | Should -Match 'below the 90% threshold'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 2
        }

        It 'Flags a failover relationship whose state is not Normal and exits 2' {
            Mock Get-DhcpServerv4Failover {
                @(
                    [pscustomobject]@{
                        Name          = 'DC1-DC2'
                        State         = 'CommunicationInterrupted'
                        Mode          = 'LoadBalance'
                        PartnerServer = '10.10.10.2'
                    }
                )
            }
            $out = Main *>&1
            $text = $out | Out-String
            $text | Should -Match "\[!\] Failover 'DC1-DC2' is CommunicationInterrupted"
            $text | Should -Match 'Failover state CommunicationInterrupted'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 2
        }

        It 'Flags a scope with no router or DNS option anywhere and exits 2' {
            Mock Get-DhcpServerv4OptionValue { @() }
            $out = Main *>&1
            $text = $out | Out-String
            $text | Should -Match '\[!\] Scope 10\.10\.10\.0 is missing option\(s\): Router, DNS Servers'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 2
        }

        It 'Accepts router and DNS options inherited from the server level' {
            Mock Get-DhcpServerv4OptionValue { @() } -ParameterFilter { $ScopeId }
            Mock Get-DhcpServerv4OptionValue {
                @(
                    [pscustomobject]@{ OptionId = 3; Value = @('10.10.10.1') }
                    [pscustomobject]@{ OptionId = 6; Value = @('10.10.10.10') }
                )
            } -ParameterFilter { -not $ScopeId }
            $out = Main *>&1
            $text = $out | Out-String
            ($text -match 'missing option') | Should -BeFalse
            $text | Should -Match 'Router and DNS server options configured'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
        }

        It 'Flags a scope with no lease statistics and exits 2' {
            Mock Get-DhcpServerv4ScopeStatistics { @() }
            $out = Main *>&1
            $text = $out | Out-String
            $text | Should -Match '\[!\] No lease statistics for scope 10\.10\.10\.0'
            $text | Should -Match 'Lease statistics unavailable'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 2
        }

        It 'Passes the -ScopeId filter to the scope query' {
            $ScopeId = '10.10.10.0'
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            Should -Invoke Get-DhcpServerv4Scope -Times 1 -Exactly `
                -ParameterFilter { "$ScopeId" -eq '10.10.10.0' }
        }

        It 'Exits 1 when -ScopeId matches no scope' {
            $ScopeId = '10.10.99.0'
            Mock Get-DhcpServerv4Scope { @() }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[-\] Error: No DHCPv4 scope matched'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
        }

        It 'Exits 1 with a [-] line when the DhcpServer module cannot be imported' {
            Mock Import-Module { throw 'module not found' }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[-\] Error: module not found'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
            Should -Invoke Get-DhcpServerv4Scope -Times 0 -Exactly
        }

        It 'Returns 1 for an unsafe -OutputPath without querying the server' {
            $OutputPath = '../escape'
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[-\] Unsafe OutputPath'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
            Should -Invoke Get-DhcpServerv4Scope -Times 0 -Exactly
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
            $report.FreeThresholdPct | Should -Be 20
            @($report.Scopes).Count | Should -Be 1
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
            @($rows | Where-Object { $_.Category -eq 'Lease' }).Count | Should -Be 1
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
