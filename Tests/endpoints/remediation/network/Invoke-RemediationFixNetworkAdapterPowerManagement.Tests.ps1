#Requires -Modules Pester

Describe "Invoke-RemediationFixNetworkAdapterPowerManagement" {
    BeforeAll {
        # Mirrored layout: walk up from Tests/... to the repo root, then across to scripts/.
        $repoRoot = $PSScriptRoot
        while (-not (Test-Path (Join-Path $repoRoot '.git'))) { $repoRoot = Split-Path $repoRoot -Parent }
        $scriptRelPath = 'scripts/endpoints/remediation/network/Invoke-RemediationFixNetworkAdapterPowerManagement.ps1'
        $scriptPath = Join-Path $repoRoot $scriptRelPath

        # Safe: the script's top-level guard skips Main when dot-sourced.
        . $scriptPath
    }

    Context "Help & Metadata" {
        It "Declares required .NOTES fields with Version 1.0.0 and Date 2026-08-23" {
            $raw = Get-Content -Path $scriptPath -Raw
            $raw | Should -Match 'File Name:\s*Invoke-RemediationFixNetworkAdapterPowerManagement\.ps1'
            $raw | Should -Match 'Author:'
            $raw | Should -Match 'Version:\s*1\.0\.0'
            $raw | Should -Match 'Date:\s*2026-08-23'
            $raw | Should -Match 'Prerequisite:\s*PowerShell 7\.0'
        }

        It "Has SYNOPSIS, DESCRIPTION with exit-code documentation, and at least two EXAMPLES" {
            $help = Get-Help $scriptPath
            $help.Synopsis | Should -Not -BeNullOrEmpty
            ($help.Description | Out-String) | Should -Match 'Exit codes?'
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
        It "Gates adapter changes behind SupportsShouldProcess" {
            $raw = Get-Content -Path $scriptPath -Raw
            $raw | Should -Match '\[CmdletBinding\(SupportsShouldProcess\)\]'
            $raw | Should -Match 'ShouldProcess\('
        }
    }

    Context "Behavior" {
        BeforeAll {
            # Stub Windows-only cmdlets so Pester can mock them on Linux.
            function Get-NetAdapter { }
            function Disable-NetAdapterPowerManagement { param($Name) }
            Mock Disable-NetAdapterPowerManagement { }
        }

        It "Disables power management only on Up physical adapters and returns 0" {
            Mock Get-NetAdapter {
                @(
                    [pscustomobject]@{ Name = 'Ethernet'; Status = 'Up'; Virtual = $false },
                    [pscustomobject]@{ Name = 'Wi-Fi 2'; Status = 'Disconnected'; Virtual = $false },
                    [pscustomobject]@{ Name = 'Virtual Adapter'; Status = 'Up'; Virtual = $true },
                    [pscustomobject]@{ Name = 'Bluetooth Device'; Status = 'Up'; Virtual = $false },
                    [pscustomobject]@{ Name = 'Loopback Pseudo'; Status = 'Up'; Virtual = $false }
                )
            }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[\+\]'
            $out | Where-Object { $_ -is [int] } | Should -Be 0
            Should -Invoke Disable-NetAdapterPowerManagement -Times 1 -Exactly `
                -ParameterFilter { $Name -eq 'Ethernet' }
        }

        It "Is idempotent: no eligible adapters means no changes and returns 0" {
            Mock Get-NetAdapter {
                @([pscustomobject]@{ Name = 'Virtual Adapter'; Status = 'Up'; Virtual = $true })
            }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[\+\]'
            $out | Where-Object { $_ -is [int] } | Should -Be 0
            Should -Invoke Disable-NetAdapterPowerManagement -Times 0 -Exactly
        }

        It "Honors -WhatIf: no adapter is changed" {
            Mock Get-NetAdapter {
                @([pscustomobject]@{ Name = 'Ethernet'; Status = 'Up'; Virtual = $false })
            }
            $out = Main -WhatIf *>&1
            $out | Where-Object { $_ -is [int] } | Should -Be 0
            Should -Invoke Disable-NetAdapterPowerManagement -Times 0 -Exactly
        }

        It "Returns 1 and writes [-] prefixed output when enumeration fails" {
            Mock Get-NetAdapter { throw "no network stack" }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[-\]'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }
    }
}
