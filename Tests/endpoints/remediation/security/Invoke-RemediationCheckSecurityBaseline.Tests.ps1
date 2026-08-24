#Requires -Modules Pester

Describe "Invoke-RemediationCheckSecurityBaseline" {
    BeforeAll {
        # Mirrored layout: walk up from Tests/... to the repo root, then across to scripts/.
        $repoRoot = $PSScriptRoot
        while (-not (Test-Path (Join-Path $repoRoot '.git'))) { $repoRoot = Split-Path $repoRoot -Parent }
        $scriptRelPath = 'scripts/endpoints/remediation/security/Invoke-RemediationCheckSecurityBaseline.ps1'
        $scriptPath = Join-Path $repoRoot $scriptRelPath

        # Safe: the script's top-level guard skips Main when dot-sourced.
        . $scriptPath
    }

    Context "Help & Metadata" {
        It "Declares required .NOTES fields with Version 1.0.0 and Date 2026-08-23" {
            $raw = Get-Content -Path $scriptPath -Raw
            $raw | Should -Match 'File Name:\s*Invoke-RemediationCheckSecurityBaseline\.ps1'
            $raw | Should -Match 'Version:\s*1\.0\.0'
            $raw | Should -Match 'Date:\s*2026-08-23'
            $raw | Should -Match 'Author:'
            $raw | Should -Match 'Prerequisite:\s*PowerShell 7\.0'
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
            else { $declared = @($ast.ParamBlock.Parameters | ForEach-Object { $_.Name.Extent.Text.TrimStart('$') }) }
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
        It "Returns 0 on a converged baseline, refreshing only signatures" {
            function Get-NetFirewallProfile { }
            function Set-NetFirewallProfile { }
            function Get-MpComputerStatus { }
            function Set-MpPreference { }
            function Update-MpSignature { }
            function Set-ItemProperty { }
            Mock Get-NetFirewallProfile {
                @(
                    [pscustomobject]@{ Name = 'Domain'; Enabled = $true },
                    [pscustomobject]@{ Name = 'Private'; Enabled = $true },
                    [pscustomobject]@{ Name = 'Public'; Enabled = $true }
                )
            }
            Mock Get-MpComputerStatus { [pscustomobject]@{ RealTimeProtectionEnabled = $true } }
            Mock Get-ItemProperty { [pscustomobject]@{ EnableLUA = 1 } }
            Mock Set-NetFirewallProfile { }
            Mock Set-MpPreference { }
            Mock Update-MpSignature { }
            Mock Set-ItemProperty { }
            $out = Main *>&1
            $out | Where-Object { $_ -is [int] } | Should -Be 0
            Should -Invoke Update-MpSignature -Exactly 1 -Scope It
            Should -Invoke Set-NetFirewallProfile -Exactly 0 -Scope It
            Should -Invoke Set-MpPreference -Exactly 0 -Scope It
            Should -Invoke Set-ItemProperty -Exactly 0 -Scope It
        }

        It "Re-applies drifted firewall, Defender and UAC settings and returns 0" {
            function Get-NetFirewallProfile { }
            function Set-NetFirewallProfile { }
            function Get-MpComputerStatus { }
            function Set-MpPreference { }
            function Update-MpSignature { }
            function Set-ItemProperty { }
            Mock Get-NetFirewallProfile {
                @(
                    [pscustomobject]@{ Name = 'Domain'; Enabled = $false },
                    [pscustomobject]@{ Name = 'Private'; Enabled = $true },
                    [pscustomobject]@{ Name = 'Public'; Enabled = $false }
                )
            }
            Mock Get-MpComputerStatus { [pscustomobject]@{ RealTimeProtectionEnabled = $false } }
            Mock Get-ItemProperty { [pscustomobject]@{ EnableLUA = 0 } }
            Mock Set-NetFirewallProfile { }
            Mock Set-MpPreference { }
            Mock Update-MpSignature { }
            Mock Set-ItemProperty { }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[\+\]'
            ($out | Out-String) | Should -Match 'Remediated 5 issues'
            $out | Where-Object { $_ -is [int] } | Should -Be 0
            Should -Invoke Set-NetFirewallProfile -Exactly 2 -Scope It
            Should -Invoke Set-MpPreference -Exactly 1 -Scope It
            Should -Invoke Update-MpSignature -Exactly 1 -Scope It
            Should -Invoke Set-ItemProperty -Exactly 1 -Scope It
        }

        It "Returns 1 with [-] output when the firewall profiles cannot be read" {
            function Get-NetFirewallProfile { }
            Mock Get-NetFirewallProfile { throw 'WMI unavailable' }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[-\]'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }
    }
}
