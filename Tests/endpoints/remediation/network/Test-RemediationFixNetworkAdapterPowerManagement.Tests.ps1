#Requires -Modules Pester

Describe "Test-RemediationFixNetworkAdapterPowerManagement" {
    BeforeAll {
        # Mirrored layout: walk up from Tests/... to the repo root, then across to scripts/.
        $repoRoot = $PSScriptRoot
        while (-not (Test-Path (Join-Path $repoRoot '.git'))) { $repoRoot = Split-Path $repoRoot -Parent }
        $scriptRelPath = 'scripts/endpoints/remediation/network/Test-RemediationFixNetworkAdapterPowerManagement.ps1'
        $scriptPath = Join-Path $repoRoot $scriptRelPath

        # Safe: the script's top-level guard skips Main when dot-sourced.
        . $scriptPath

        # Stub Windows-only cmdlets so Pester can mock them on Linux pwsh.
        function Get-NetAdapter { }
        function Get-WmiObject { }

        # Default mock: one healthy physical adapter with power saving disabled.
        Mock Get-NetAdapter {
            @([pscustomobject]@{ Name = 'Ethernet'; Status = 'Up'; Virtual = $false;
                InterfaceGuid = '{11111111-1111}' })
        }
        Mock Get-WmiObject {
            @([pscustomobject]@{ InstanceName = 'ROOT\WMI\{11111111-1111}_0'; Enable = $false })
        }
    }

    Context "Help & Metadata" {
        It "Declares required .NOTES fields with Version 1.0.0 and Date 2026-08-23" {
            $raw = Get-Content -Path $scriptPath -Raw
            $raw | Should -Match 'File Name:\s*Test-RemediationFixNetworkAdapterPowerManagement\.ps1'
            $raw | Should -Match 'Author:'
            $raw | Should -Match 'Prerequisite:\s*PowerShell 7\.0'
            $raw | Should -Match 'Version:\s*1\.0\.0'
            $raw | Should -Match 'Date:\s*2026-08-23'
        }

        It "Has SYNOPSIS, DESCRIPTION and at least two EXAMPLES" {
            $help = Get-Help $scriptPath
            $help.Synopsis | Should -Not -BeNullOrEmpty
            $help.Description | Should -Not -BeNullOrEmpty
            @($help.Examples.Example).Count | Should -BeGreaterOrEqual 2
        }

        It "Declares one .PARAMETER per param() parameter" {
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$null, [ref]$null)
            if ($null -eq $ast.ParamBlock) { $declared = @() }
            else { $declared = @($ast.ParamBlock.Parameters.Name.VariableText) }
            $raw = Get-Content -Path $scriptPath -Raw
            $paramHelpMatches = [regex]::Matches($raw, '(?m)^\s*\.PARAMETER\s+(\S+)')
            $documented = @($paramHelpMatches | ForEach-Object { $_.Groups[1].Value })
            @($documented).Count | Should -Be @($declared).Count
            foreach ($p in $declared) { $documented | Should -Contain $p }
        }
    }

    Context "Syntax & Static" {
        BeforeAll {
            $tokens = $null
            $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errors)
        }
        It "Parses with zero errors" {
            $errors | Should -BeNullOrEmpty
        }
        It "Contains no PS7-only operators (no #Requires -Version 7.0 opt-out present)" {
            $raw = Get-Content -Path $scriptPath -Raw
            $raw | Should -Not -Match '(?m)&&|\|\||\?\?|\?\?='
            $raw | Should -Not -Match '\$\w+\s*\?\s*[^:]'
        }
    }

    Context "Behavior" {
        It "Returns 0 with [+] output when no adapter allows power saving" {
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[\+\]'
            $out | Where-Object { $_ -is [int] } | Should -Be 0
        }

        It "Returns 1 with [!] output naming adapters with power saving enabled" {
            Mock Get-WmiObject {
                @([pscustomobject]@{ InstanceName = 'ROOT\WMI\{11111111-1111}_0'; Enable = $true })
            }
            $out = Main *>&1
            $text = $out | Out-String
            $text | Should -Match '\[!\]'
            $text | Should -Match 'Ethernet'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }

        It "Excludes virtual, Bluetooth and loopback adapters from the check" {
            Mock Get-NetAdapter {
                @(
                    [pscustomobject]@{ Name = 'Ethernet'; Status = 'Up'; Virtual = $false;
                        InterfaceGuid = '{AAAA}' },
                    [pscustomobject]@{ Name = 'Bluetooth Device'; Status = 'Up'; Virtual = $false;
                        InterfaceGuid = '{BBBB}' },
                    [pscustomobject]@{ Name = 'vEthernet (WSL)'; Status = 'Up'; Virtual = $true;
                        InterfaceGuid = '{CCCC}' }
                )
            }
            Mock Get-WmiObject {
                @([pscustomobject]@{ InstanceName = 'ROOT\WMI\{BBBB}_0'; Enable = $true })
            }
            $out = Main *>&1
            ($out | Out-String) | Should -Not -Match 'Bluetooth Device'
            $out | Where-Object { $_ -is [int] } | Should -Be 0
            Should -Invoke Get-WmiObject -Times 1 -Exactly
        }

        It "Tolerates a missing MSPower_DeviceEnable instance as compliant" {
            Mock Get-WmiObject { @() }
            $out = Main *>&1
            $out | Where-Object { $_ -is [int] } | Should -Be 0
        }

        It "Returns 1 and writes [-] prefixed output when adapter enumeration fails" {
            Mock Get-NetAdapter { throw 'CIM unavailable' }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[-\]'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }
    }
}
