#Requires -Modules Pester

Describe "Test-NetworkConnectivity" {
    BeforeAll {
        $scriptPath = Join-Path $PSScriptRoot "../../../scripts/infrastructure/network/Test-NetworkConnectivity.ps1"

        # Safe: the script's top-level guard skips Main when dot-sourced (RELAUNCH-SPEC §3).
        . $scriptPath
        # Stub Windows-only commands up front so Pester can mock them on Linux.
        function Get-NetAdapter { }
        function Get-NetIPAddress { }
        function Get-NetRoute { }
        function Test-Connection { }
        function Get-DnsClientServerAddress { }
        function Resolve-DnsName { }
        function Get-Counter { }
        function Invoke-WebRequest { }


        # Mock ALL external commands/modules/wrappers so nothing leaves the machine.
        Mock Invoke-Netsh { @() }
        Mock Get-NetAdapter {
            @(
                [pscustomobject]@{
                    Name                 = 'Ethernet'
                    Status               = 'Up'
                    InterfaceDescription = 'Intel Ethernet Adapter'
                    LinkSpeed            = '1 Gbps'
                    MediaType            = '802.3'
                    ifIndex              = 5
                    MacAddress           = 'AA-BB-CC-DD-EE-FF'
                }
            )
        }
        Mock Get-NetIPAddress { @([pscustomobject]@{ IPAddress = '192.168.1.10' }) }
        Mock Get-NetRoute { @([pscustomobject]@{ NextHop = '192.168.1.1' }) }
        Mock Test-Connection {
            @(
                [pscustomobject]@{ ResponseTime = 10 },
                [pscustomobject]@{ ResponseTime = 20 }
            )
        }
        Mock Get-DnsClientServerAddress {
            @([pscustomobject]@{ ServerAddresses = @('192.168.1.1', '8.8.8.8') })
        }
        Mock Resolve-DnsName { @([pscustomobject]@{ IPAddress = '93.184.216.34' }) }
        Mock Get-Counter { [pscustomobject]@{ CounterSamples = @() } }
        Mock Invoke-WebRequest { throw "Simulated offline: no HTTP fallback" }

        $TestEndpoints = @('google.com', 'microsoft.com')
        $DNSServers = @('8.8.8.8')
    }

    Context "Help & Metadata" {
        It "Declares File Name matching the disk filename" {
            $helpText = Get-Content -Raw $scriptPath
            $helpText | Should -Match 'File Name\s*:\s*Test-NetworkConnectivity\.ps1'
        }

        It "Declares Author and Prerequisite" {
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
            $expectedOrder = @('OutputFormat', 'OutputPath', 'TestEndpoints', 'DNSServers')
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
        It "Returns 0 and reports Excellent status when everything is reachable" {
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            $script:NetworkDiag.OverallStatus | Should -Be 'Excellent'
            $script:NetworkDiag.Connectivity.Count | Should -Be 2
            ($out | Out-String) | Should -Match '\[\+\]'
        }

        It "Is idempotent: repeated diagnostic runs return the same healthy result" {
            $firstRun = (Main *>&1 | Where-Object { $_ -is [int] })
            $secondRun = (Main *>&1 | Where-Object { $_ -is [int] })
            $firstRun | Should -Be 0
            $secondRun | Should -Be 0
        }

        It "Returns 1 with [-] output when probes fail (gateway unreachable, DNS dead)" {
            Mock Test-Connection { $null }
            Mock Resolve-DnsName { $null }
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
            ($out | Out-String) | Should -Match '\[-\]'
            $script:NetworkDiag.Issues.Count | Should -BeGreaterThan 0
        }

        It "Falls back to HTTPS reachability when ICMP is blocked" {
            Mock Test-Connection { $null }
            # No default gateway: its absence is only a warning, keeping focus on HTTPS fallback.
            Mock Get-NetRoute { @() }

            Mock Invoke-WebRequest { [pscustomobject]@{ StatusCode = 200 } }
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            $script:NetworkDiag.Connectivity[0].Status | Should -Match 'HTTPS'
        }
    }
}
