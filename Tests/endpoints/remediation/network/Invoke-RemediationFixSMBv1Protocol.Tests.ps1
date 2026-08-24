#Requires -Modules Pester

Describe "Invoke-RemediationFixSMBv1Protocol" {
    BeforeAll {
        # Mirrored layout: walk up from Tests/... to the repo root, then across to scripts/.
        $repoRoot = $PSScriptRoot
        while (-not (Test-Path (Join-Path $repoRoot '.git'))) { $repoRoot = Split-Path $repoRoot -Parent }
        $scriptRelPath = 'scripts/endpoints/remediation/network/Invoke-RemediationFixSMBv1Protocol.ps1'
        $scriptPath = Join-Path $repoRoot $scriptRelPath

        # Safe: the script's top-level guard skips Main when dot-sourced.
        . $scriptPath
    }

    Context "Help & Metadata" {
        It "Declares required .NOTES fields with Version 1.0.0 and Date 2026-08-23" {
            $raw = Get-Content -Path $scriptPath -Raw
            $raw | Should -Match 'File Name:\s*Invoke-RemediationFixSMBv1Protocol\.ps1'
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
        It "Gates configuration changes behind SupportsShouldProcess" {
            $raw = Get-Content -Path $scriptPath -Raw
            $raw | Should -Match '\[CmdletBinding\(SupportsShouldProcess\)\]'
            $raw | Should -Match 'ShouldProcess\('
        }
    }

    Context "Behavior" {
        BeforeAll {
            # Stub Windows-only cmdlets so Pester can mock them on Linux.
            function Get-WindowsOptionalFeature { }
            function Disable-WindowsOptionalFeature { }
            function Get-SmbServerConfiguration { }
            function Set-SmbServerConfiguration { }
            $regPath = 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters'
            Mock Disable-WindowsOptionalFeature { }
            Mock Set-SmbServerConfiguration { }
            Mock Set-ItemProperty { }
        }

        It "Disables SMBv1 via feature, server config and registry when all are enabled, returns 0" {
            Mock Test-Path { $true }
            Mock Get-WindowsOptionalFeature { [pscustomobject]@{ FeatureName = 'SMB1Protocol'; State = 'Enabled' } }
            Mock Get-SmbServerConfiguration { [pscustomobject]@{ EnableSMB1Protocol = $true } }
            Mock Get-ItemProperty { [pscustomobject]@{ SMB1 = 1 } }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[\+\]'
            $out | Where-Object { $_ -is [int] } | Should -Be 0
            Should -Invoke Disable-WindowsOptionalFeature -Times 1 -Exactly
            Should -Invoke Set-SmbServerConfiguration -Times 1 -Exactly
            Should -Invoke Set-ItemProperty -Times 1 -Exactly -ParameterFilter { $Name -eq 'SMB1' -and $Value -eq 0 }
        }

        It "Is idempotent: already-disabled SMBv1 makes no changes and returns 0" {
            Mock Test-Path { $true }
            Mock Get-WindowsOptionalFeature { [pscustomobject]@{ FeatureName = 'SMB1Protocol'; State = 'Disabled' } }
            Mock Get-SmbServerConfiguration { [pscustomobject]@{ EnableSMB1Protocol = $false } }
            Mock Get-ItemProperty { [pscustomobject]@{ SMB1 = 0 } }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[\+\]'
            $out | Where-Object { $_ -is [int] } | Should -Be 0
            Should -Invoke Disable-WindowsOptionalFeature -Times 0 -Exactly
            Should -Invoke Set-SmbServerConfiguration -Times 0 -Exactly
            Should -Invoke Set-ItemProperty -Times 0 -Exactly
        }

        It "Honors -WhatIf: no configuration change is made even with SMBv1 enabled" {
            Mock Test-Path { $true }
            Mock Get-WindowsOptionalFeature { [pscustomobject]@{ FeatureName = 'SMB1Protocol'; State = 'Enabled' } }
            Mock Get-SmbServerConfiguration { [pscustomobject]@{ EnableSMB1Protocol = $true } }
            Mock Get-ItemProperty { [pscustomobject]@{ SMB1 = 1 } }
            $out = Main -WhatIf *>&1
            $out | Where-Object { $_ -is [int] } | Should -Be 0
            Should -Invoke Disable-WindowsOptionalFeature -Times 0 -Exactly
            Should -Invoke Set-SmbServerConfiguration -Times 0 -Exactly
            Should -Invoke Set-ItemProperty -Times 0 -Exactly
        }

        It "Returns 1 and writes [-] prefixed output when the feature query fails fatally" {
            Mock Get-WindowsOptionalFeature { throw "DISM unavailable" }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[-\]'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }
    }
}
