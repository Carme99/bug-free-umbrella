#Requires -Modules Pester

Describe "Reset-NetworkStack" {
    BeforeAll {
        $scriptPath = Join-Path $PSScriptRoot "../../../scripts/infrastructure/network/Reset-NetworkStack.ps1"

        # Safe: the script's top-level guard skips Main when dot-sourced (RELAUNCH-SPEC §3).
        . $scriptPath
        # Stub Windows-only commands up front so Pester can mock them on Linux.
        function Enable-ComputerRestore { }
        function Checkpoint-Computer { }
        function Clear-DnsClientCache { }
        function Get-NetAdapter { }
        function Disable-NetAdapter { }
        function Enable-NetAdapter { }
        function Restart-Computer { }


        # Mock ALL external commands/modules/wrappers so nothing leaves the machine.
        Mock Test-Administrator { $true }
        Mock Read-Host { 'N' }
        Mock Invoke-Netsh { 0 }
        Mock Invoke-Ipconfig { 0 }
        Mock Enable-ComputerRestore { }
        Mock Checkpoint-Computer { }
        Mock Clear-DnsClientCache { }
        Mock Get-NetAdapter { @() }
        Mock Disable-NetAdapter { }
        Mock Enable-NetAdapter { }
        Mock Start-Sleep { }
        Mock Restart-Computer { }
        Mock Export-Csv { }

        # Default parameter state; individual Its override as needed.
        $ResetFirewall = $false
        $ResetProxy = $false
        $FlushDNS = $false
        $ResetAdapters = $false
        $CreateRestorePoint = $false
        $Force = $true
    }

    Context "Help & Metadata" {
        It "Declares File Name matching the disk filename" {
            $helpText = Get-Content -Raw $scriptPath
            $helpText | Should -Match 'File Name\s*:\s*Reset-NetworkStack\.ps1'
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
            $tokens = $null
            $parseErrors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile(
                $scriptPath, [ref]$tokens, [ref]$parseErrors)
            $declaredParams = $ast.ParamBlock.Parameters.Count
            $paramBlocks = ([regex]::Matches($helpText, '(?m)^\.PARAMETER')).Count
            $paramBlocks | Should -Be $declaredParams
            $expectedOrder = @(
                'ResetFirewall', 'ResetProxy', 'FlushDNS', 'ResetAdapters', 'CreateRestorePoint', 'Force')
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
        It "Performs the core stack reset and returns 0 on success" {
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            Should -Invoke Invoke-Netsh -Times 3 -Exactly -Scope It   # winsock, tcp/ip, ipv6
            Should -Invoke Invoke-Ipconfig -Times 2 -Exactly -Scope It   # release, renew
            # Pipeline feeds one record per operation (winsock, tcp/ip, ipv6, dhcp): 4 calls.
            Should -Invoke Export-Csv -Times 4 -Exactly -Scope It
        }

        It "Is idempotent: re-running completes successfully again" {
            $firstRun = (Main *>&1 | Where-Object { $_ -is [int] })
            $secondRun = (Main *>&1 | Where-Object { $_ -is [int] })
            $firstRun | Should -Be 0
            $secondRun | Should -Be 0
        }

        It "Returns 1 and writes [-] prefixed output when a reset operation fails" {
            Mock Invoke-Netsh { 1 }
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
            ($out | Out-String) | Should -Match '\[-\]'
        }

        It "Returns 1 immediately when not running elevated" {
            Mock Test-Administrator { $false }
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
            ($out | Out-String) | Should -Match 'Administrator'
            Should -Invoke Invoke-Netsh -Times 0 -Exactly -Scope It
        }

        It "Honors -WhatIf: performs no mutations" {
            $out = Main -WhatIf *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            Should -Invoke Invoke-Netsh -Times 0 -Exactly -Scope It
            Should -Invoke Invoke-Ipconfig -Times 0 -Exactly -Scope It
        }
    }
}
