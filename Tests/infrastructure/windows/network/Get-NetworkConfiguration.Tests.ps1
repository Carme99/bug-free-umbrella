#Requires -Modules Pester

Describe "Get-NetworkConfiguration" {
    BeforeAll {
        $scriptPath = Join-Path $PSScriptRoot `
            ""../../../../scripts/infrastructure/windows/network/Get-NetworkConfiguration.ps1""

        # Safe: the script's top-level guard skips Main when dot-sourced.
        . $scriptPath

        # Stub Windows-only commands so Pester can attach mocks on Linux.
        function Get-CimInstance { }
        function Get-NetAdapter { }
        function Get-NetIPConfiguration { }
        function Get-DnsClient { }
        function Get-DnsClientServerAddress { }

        # Mock ALL externals so nothing touches the machine or network.
        Mock Test-AdminPrivilege { $true }
        Mock Get-CimInstance {
            [pscustomobject]@{ Domain = 'CONTOSO'; Manufacturer = 'Contoso'; Model = 'HV-1' }
        }
        Mock Get-NetAdapter {
            @([pscustomobject]@{
                Name = 'Ethernet'; InterfaceDescription = 'Virtual Adapter'; Status = 'Up'
                MacAddress = 'AA-BB-CC-DD-EE-FF'; LinkSpeed = '10 Gbps'; MediaType = '802.3'
                InterfaceIndex = 3; DriverVersion = '10.0.0'; DriverDate = (Get-Date '2025-01-01')
                DriverProvider = 'Contoso'
            })
        }
        Mock Get-NetIPConfiguration {
            @([pscustomobject]@{
                InterfaceAlias = 'Ethernet'; InterfaceIndex = 3; InterfaceDescription = 'Virtual Adapter'
                IPv4Address = @([pscustomobject]@{ IPAddress = '192.168.1.10'; PrefixLength = 24 })
                IPv4DefaultGateway = @([pscustomobject]@{ NextHop = '192.168.1.1' })
                IPv6Address = @(); IPv6DefaultGateway = @()
                DNSServer = [pscustomobject]@{ ServerAddresses = @('192.168.1.53') }
                NetProfile = [pscustomobject]@{ Name = 'Ethernet'; NetworkCategory = 'DomainAuthenticated' }
            })
        }
        Mock Get-DnsClient {
            @([pscustomobject]@{
                InterfaceAlias = 'Ethernet'; InterfaceIndex = 3
                ConnectionSpecificSuffix = 'contoso.local'
                RegisterThisConnectionsAddress = $true; UseSuffixWhenRegistering = $false
            })
        }
        Mock Get-DnsClientServerAddress {
            [pscustomobject]@{ ServerAddresses = @('192.168.1.53', '192.168.1.54') }
        }

        $scriptText = Get-Content -Raw $scriptPath
    }

    Context "Help & Metadata" {
        It "Declares Version 1.0.0" {
            $scriptText | Should -Match '(?m)^\s*Version\s*:\s*1\.0\.0\s*$'
        }

        It "Declares relaunch Date 2026-08-23" {
            $scriptText | Should -Match '(?m)^\s*Date\s*:\s*2026-08-23\s*$'
        }

        It "Declares File Name matching the disk filename" {
            $expected = Split-Path -Leaf $scriptPath
            $scriptText | Should -Match "(?m)^\s*File Name\s*:\s*$([regex]::Escape($expected))\s*$"
        }

        It "Declares an Author and Prerequisite" {
            $scriptText | Should -Match '(?m)^\s*Author\s*:\s*\S'
            $scriptText | Should -Match '(?m)^\s*Prerequisite\s*:\s*PowerShell'
        }

        It "Has at least two EXAMPLE blocks with PS C:\> prompts" {
            ([regex]::Matches($scriptText, '(?m)^\.EXAMPLE')).Count | Should -BeGreaterOrEqual 2
            ([regex]::Matches($scriptText, 'PS C:\\>')).Count | Should -BeGreaterOrEqual 2
        }

        It "Has one .PARAMETER per declared parameter, in order" {
            $tokens = $null; $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseInput($scriptText, [ref]$tokens, [ref]$errors)
            $declared = @($ast.ParamBlock.Parameters.Name.VariablePath.UserPath)
            $documented = @([regex]::Matches($scriptText, '(?m)^\.PARAMETER\s+(\w+)') |
                ForEach-Object { $_.Groups[1].Value })
            $documented.Count | Should -Be $declared.Count
            for ($i = 0; $i -lt $declared.Count; $i++) {
                $documented[$i] | Should -Be $declared[$i]
            }
        }
    }

    Context "Syntax & Static" {
        It "Parses cleanly via the PowerShell parser" {
            $tokens = $null; $errors = $null
            [System.Management.Automation.Language.Parser]::ParseFile(
                $scriptPath, [ref]$tokens, [ref]$errors) | Out-Null
            $errors | Should -BeNullOrEmpty
        }

        It "Contains no PS7-only syntax (no #Requires -Version 7.0 present)" {
            $scriptText | Should -Not -Match '#Requires\s+-Version\s+7'
            $scriptText | Should -Not -Match '\?\?'
            $scriptText | Should -Not -Match '&&'
            $scriptText | Should -Not -Match '\|\|'
            $scriptText | Should -Not -Match '-Parallel\b'
        }

        It "Wraps execution in Main and exits only via the top-level guard" {
            $scriptText | Should -Match '(?m)^function Main \{'
            $guardLine = [regex]::Escape("if (`$MyInvocation.InvocationName -ne '.') { exit (Main) }")
            $scriptText | Should -Match $guardLine
            ([regex]::Matches($scriptText, '\bexit\b')).Count | Should -Be 1
        }

        It "Uses UTF-8 BOM and CRLF line endings" {
            $raw = [System.IO.File]::ReadAllBytes($scriptPath)
            ($raw[0], $raw[1], $raw[2]) | Should -Be (0xEF, 0xBB, 0xBF)
            [System.Text.Encoding]::UTF8.GetString($raw) | Should -Not -Match "(?<!`r)`n"
        }
    }

    Context "Behavior" {
        It "Documents adapters, IP configuration, and DNS, then returns 0" {
            $out = Main *>&1
            $rc = $out | Where-Object { $_ -is [int] } | Select-Object -First 1
            $rc | Should -Be 0
            ($out | Out-String) | Should -Match '\[\+\]'
            $script:report.Adapters.Count | Should -Be 1
            $script:report.IPConfig.Count | Should -Be 1
            $script:report.IPConfig[0].IPv4Address | Should -Be '192.168.1.10'
            $script:report.IPConfig[0].IPv4Gateway | Should -Be '192.168.1.1'
            $script:report.DNS.Count | Should -Be 1
            $script:report.DNS[0].DNSServers | Should -Be '192.168.1.53, 192.168.1.54'
        }

        It "Is idempotent: repeated documentation runs succeed with identical results" {
            (Main *>&1 | Where-Object { $_ -is [int] }) | Should -Contain 0
            $script:report.Adapters.Count | Should -Be 1
        }

        It "Returns 1 with [-] output when adapter enumeration fails upstream" {
            Mock Get-NetAdapter { throw "adapter query failed" }
            $out = Main *>&1
            $rc = $out | Where-Object { $_ -is [int] } | Select-Object -First 1
            $rc | Should -Be 1
            ($out | Out-String) | Should -Match '\[-\]'
        }

        It "Returns 1 with [-] output when administrator privileges are missing" {
            Mock Test-AdminPrivilege { $false }
            $out = Main *>&1
            $rc = $out | Where-Object { $_ -is [int] } | Select-Object -First 1
            $rc | Should -Be 1
            ($out | Out-String) | Should -Match '\[-\]'
        }
    }
}
