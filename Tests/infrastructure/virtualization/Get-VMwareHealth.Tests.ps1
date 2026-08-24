#Requires -Modules Pester

Describe "Get-VMwareHealth" {
    BeforeAll {
        $scriptPath = Join-Path $PSScriptRoot "../../../scripts/infrastructure/virtualization/Get-VMwareHealth.ps1"

        # Safe: the script's top-level guard skips Main when dot-sourced (RELAUNCH-SPEC §3).
        . $scriptPath
        # Stub PowerCLI/external-module commands up front so Pester can mock them on Linux.
        function Import-Module { }
        function Set-PowerCLIConfiguration { }
        function Connect-VIServer { }
        function Disconnect-VIServer { }
        function Get-VMHost { }
        function Get-VM { }
        function Get-Datastore { }

        # Main validates -vCenter before doing any work.
        $vCenter = 'vcenter.domain.com'

        # Mock ALL external commands/modules (PowerCLI is NOT required at test runtime).
        Mock Import-Module { }
        Mock Set-PowerCLIConfiguration { }
        Mock Connect-VIServer {
            @([pscustomobject]@{ Name = 'vcenter.domain.com'; IsConnected = $true })
        }
        Mock Disconnect-VIServer { }
        Mock Get-VMHost {
            @(
                [pscustomobject]@{ Name = 'esxi01'; ConnectionState = 'Connected' },
                [pscustomobject]@{ Name = 'esxi02'; ConnectionState = 'Connected' }
            )
        }
        Mock Get-VM {
            @(
                [pscustomobject]@{ Name = 'vm01'; PowerState = 'PoweredOn' },
                [pscustomobject]@{ Name = 'vm02'; PowerState = 'PoweredOff' }
            )
        }
        Mock Get-Datastore {
            @([pscustomobject]@{ Name = 'datastore1'; FreeSpaceGB = 50; CapacityGB = 100 })
        }

        $IncludeVMs = $false
    }

    Context "Help & Metadata" {
        It "Declares File Name matching the disk filename" {
            $helpText = Get-Content -Raw $scriptPath
            $helpText | Should -Match 'File Name\s*:\s*Get-VMwareHealth\.ps1'
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
            $expectedOrder = @('vCenter', 'Credential', 'IncludeVMs', 'ExportHTML')
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
        It "Connects, reports hosts and datastores, disconnects cleanly, and returns 0" {
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            Should -Invoke Connect-VIServer -Times 1 -Exactly -Scope It
            Should -Invoke Get-Datastore -Times 1 -Exactly -Scope It
            Should -Invoke Disconnect-VIServer -Times 1 -Exactly -Scope It
        }

        It "Is idempotent: repeated health-check runs complete successfully" {
            $firstRun = (Main *>&1 | Where-Object { $_ -is [int] })
            $secondRun = (Main *>&1 | Where-Object { $_ -is [int] })
            $firstRun | Should -Be 0
            $secondRun | Should -Be 0
        }

        It "Returns 1 with [-] output when PowerCLI cannot be loaded" {
            Mock Import-Module { throw "VMware.PowerCLI module not found" }
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
            ($out | Out-String) | Should -Match '\[-\]'
            Should -Invoke Connect-VIServer -Times 0 -Exactly -Scope It
        }

        It "Returns 1 when vCenter connection fails" {
            Mock Connect-VIServer { throw "connection refused" }
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
            ($out | Out-String) | Should -Match '\[-\]'
        }

        It "Reports VM power states when -IncludeVMs is set" {
            $IncludeVMs = $true
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            Should -Invoke Get-VM -Times 1 -Exactly -Scope It
        }
    }
}
