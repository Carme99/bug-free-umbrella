#Requires -Modules Pester

Describe "Test-NetworkDiagnostics" {
    BeforeAll {
        $scriptPath = Join-Path $PSScriptRoot "../../../scripts/infrastructure/network/Test-NetworkDiagnostics.ps1"

        # Safe: the script's top-level guard skips Main when dot-sourced (RELAUNCH-SPEC §3).
        . $scriptPath
        # Stub Windows-only commands up front so Pester can mock them on Linux.
        function Get-NetAdapter { }
        function Get-NetIPAddress { }
        function Get-NetRoute { }
        function Test-Connection { }
        function Test-NetConnection { }
        function Get-DnsClientServerAddress { }
        function Resolve-DnsName { }
        function Get-NetAdapterStatistics { }
        function Out-File { }



        # Mock ALL external commands/modules/wrappers so nothing leaves the machine
        # (including the report writes: Out-File / New-Item are mocked).
        Mock Get-NetAdapter {
            @(
                [pscustomobject]@{
                    Name           = 'Ethernet'
                    Status         = 'Up'
                    InterfaceIndex = 5
                    LinkSpeed      = '1 Gbps'
                    MacAddress     = 'AA-BB-CC-DD-EE-FF'
                }
            )
        }
        Mock Get-NetIPAddress {
            @([pscustomobject]@{ IPAddress = '192.168.1.10'; AddressFamily = 'IPv4'; PrefixLength = 24 })
        }
        Mock Get-NetRoute { @([pscustomobject]@{ NextHop = '192.168.1.1' }) }
        Mock Test-Connection { $true }
        Mock Get-DnsClientServerAddress {
            @([pscustomobject]@{ ServerAddresses = @('192.168.1.1', '8.8.8.8') })
        }
        Mock Resolve-DnsName { @([pscustomobject]@{ IPAddress = '93.184.216.34' }) }
        Mock Test-NetConnection { [pscustomobject]@{ TraceRoute = @('192.168.1.1', '10.0.0.1') } }
        Mock Get-NetAdapterStatistics {
            @(
                [pscustomobject]@{
                    Name           = 'Ethernet'
                    ReceivedBytes  = 2GB
                    SentBytes      = 1GB
                    ReceivedErrors = 0
                    OutboundErrors = 0
                }
            )
        }
        Mock Test-Path { $true }
        Mock New-Item { }
        Mock Out-File { }

        $TestInternetConnectivity = $false
        $TraceRoute = $false
        $TestDNS = $false
        $ScanPorts = $false
        $OutputPath = (Join-Path $TestDrive "reports")
    }

    Context "Help & Metadata" {
        It "Declares File Name matching the disk filename" {
            $helpText = Get-Content -Raw $scriptPath
            $helpText | Should -Match 'File Name\s*:\s*Test-NetworkDiagnostics\.ps1'
        }

        It "Preserves Author and declares Prerequisite" {
            $helpText = Get-Content -Raw $scriptPath
            $helpText | Should -Match 'Author\s*:\s*\S'
            $helpText | Should -Match 'Prerequisite\s*:\s*PowerShell'
        }

        It "Declares Version 1.0.0 and Date 2026-08-23" {
            $helpText = Get-Content -Raw $scriptPath
            $helpText | Should -Match 'Version\s*:\s*1\.0\.0'
            $helpText | Should -Match 'Date\s*:\s*2026-08-23'
        }

        It "Has one .PARAMETER block per declared parameter, in order" {
            $helpText = Get-Content -Raw $scriptPath
            $paramBlocks = ([regex]::Matches($helpText, '(?m)^\.PARAMETER')).Count
            $declaredParams = ([regex]::Matches($helpText, '\[Parameter\(')).Count
            $paramBlocks | Should -Be $declaredParams
            $expectedOrder = @('OutputPath', 'TestInternetConnectivity', 'TraceRoute', 'TestDNS', 'ScanPorts')
            $foundOrder = [regex]::Matches($helpText, '(?m)^\.PARAMETER\s+(\S+)') |
                ForEach-Object { $_.Groups[1].Value }
            $foundOrder | Should -Be $expectedOrder
        }

        It "Has at least two .EXAMPLE blocks with PS C:\> prompts" {
            $helpText = Get-Content -Raw $scriptPath
            ([regex]::Matches($helpText, '(?m)^\.EXAMPLE')).Count | Should -BeGreaterOrEqual 2
            ([regex]::Matches($helpText, 'PS C:\\>')).Count | Should -BeGreaterOrEqual 2
        }
    }

    Context "Syntax & Static" {
        It "Parses with zero parser errors" {
            $tokens = $null
            $parseErrors = $null
            [System.Management.Automation.Language.Parser]::ParseFile(
                $scriptPath, [ref]$tokens, [ref]$parseErrors) | Out-Null
            $parseErrors.Count | Should -Be 0
        }

        It "Contains no PS7-only syntax without a #Requires -Version 7.0 line" {
            $raw = Get-Content -Raw $scriptPath
            if (-not ($raw -match '(?m)^#Requires\s+-Version\s+7')) {
                $raw | Should -Not -Match '\?\?'
                $raw | Should -Not -Match '\|\|'
                $raw | Should -Not -Match '&&'
                $raw | Should -Not -Match '-Parallel\b'
            }
        }

        It "Uses UTF-8 BOM and CRLF line endings" {
            $bytes = [System.IO.File]::ReadAllBytes($scriptPath)
            ($bytes[0], $bytes[1], $bytes[2]) | Should -Be (0xEF, 0xBB, 0xBF)
            $raw = [System.Text.Encoding]::UTF8.GetString($bytes)
            $bareLf = [regex]::Matches($raw, "(?<!`r)`n")
            $bareLf.Count | Should -Be 0
        }
    }

    Context "Behavior" {
        It "Completes diagnostics and exports both JSON and HTML reports" {
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            Should -Invoke Out-File -Times 2 -Exactly -Scope It   # JSON results + HTML report
        }

        It "Is idempotent: repeated diagnostic runs complete successfully" {
            $firstRun = (Main *>&1 | Where-Object { $_ -is [int] })
            $secondRun = (Main *>&1 | Where-Object { $_ -is [int] })
            $firstRun | Should -Be 0
            $secondRun | Should -Be 0
        }

        It "Returns 1 with [-] output when adapter enumeration fails" {
            Mock Get-NetAdapter { throw "WMI exploded" }
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
            ($out | Out-String) | Should -Match '\[-\]'
        }

        It "Rejects unsafe OutputPath traversal without probing the network" {
            $OutputPath = "..\..\evil"
            Should -Invoke Get-NetAdapter -Times 0 -Exactly -Scope It
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
            ($out | Out-String) | Should -Match '\[-\]'
        }
    }
}
