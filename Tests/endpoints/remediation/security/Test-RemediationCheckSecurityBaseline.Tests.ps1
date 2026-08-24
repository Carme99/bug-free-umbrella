#Requires -Modules Pester

Describe "Test-RemediationCheckSecurityBaseline" {
    BeforeAll {
        # Mirrored layout: walk up from Tests/... to the repo root, then across to scripts/.
        $repoRoot = $PSScriptRoot
        while (-not (Test-Path (Join-Path $repoRoot '.git'))) { $repoRoot = Split-Path $repoRoot -Parent }
        $scriptRelPath = 'scripts/endpoints/remediation/security/Test-RemediationCheckSecurityBaseline.ps1'
        $scriptPath = Join-Path $repoRoot $scriptRelPath

        # Safe: the script's top-level guard skips Main when dot-sourced.
        . $scriptPath
    }

    Context "Help & Metadata" {
        It "Declares required .NOTES fields with Version 1.0.0 and Date 2026-08-23" {
            $raw = Get-Content -Path $scriptPath -Raw
            $raw | Should -Match 'File Name:\s*Test-RemediationCheckSecurityBaseline\.ps1'
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
        It "Contains no PS7-only operators and no emoji" {
            $raw = Get-Content -Path $scriptPath -Raw
            $raw | Should -Not -Match '(?m)&&|\|\||\?\?|\?\?='
            $raw | Should -Not -Match '\$\w+\s*\?\s*[^:]'
            $raw | Should -Not -Match '[\u2705\u274C\u26A0]'
            $raw | Should -Not -Match '[\uD83C-\uDBFF][\uDC00-\uDFFF]'
        }
        It "Is a read-only detection script (plain CmdletBinding)" {
            $raw = Get-Content -Path $scriptPath -Raw
            $raw | Should -Match '\[CmdletBinding\(\)\]'
            $raw | Should -Not -Match 'SupportsShouldProcess'
        }
    }

    Context "Behavior" {
        BeforeAll {

        # Stub externals so Pester Mock can bind them offline.
        function Get-NetFirewallProfile { }
        function Get-MpComputerStatus { }
        }

        It "Returns 0 with [+] output when all baseline settings are compliant (idempotent)" {
            Mock Get-NetFirewallProfile {
                @(
                    [pscustomobject]@{ Name = 'Domain'; Enabled = $true },
                    [pscustomobject]@{ Name = 'Private'; Enabled = $true },
                    [pscustomobject]@{ Name = 'Public'; Enabled = $true }
                )
            }
            Mock Get-MpComputerStatus {
                [pscustomobject]@{ RealTimeProtectionEnabled = $true; AntivirusSignatureAge = 1 }
            }
            Mock Get-ItemProperty {
                param($Path)
                if ($Path -like '*CurrentVersion\Policies\System') { return [pscustomobject]@{ EnableLUA = 1 } }
                return $null
            }

            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[\+\]'
            $out | Where-Object { $_ -is [int] } | Should -Be 0
        }

        It "Returns 1 with [!] output when a firewall profile is disabled" {
            Mock Get-NetFirewallProfile {
                @([pscustomobject]@{ Name = 'Public'; Enabled = $false })
            }
            Mock Get-MpComputerStatus { $null }
            Mock Get-ItemProperty { $null }

            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[!\]'
            ($out | Out-String) | Should -Match 'Firewall Public profile is disabled'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }

        It "Aggregates UAC, signature-age and auto-update drift into one failure" {
            Mock Get-NetFirewallProfile { @() }
            Mock Get-MpComputerStatus {
                [pscustomobject]@{ RealTimeProtectionEnabled = $false; AntivirusSignatureAge = 12 }
            }
            Mock Get-ItemProperty {
                param($Path)
                if ($Path -like '*CurrentVersion\Policies\System') { return [pscustomobject]@{ EnableLUA = 0 } }
                if ($Path -like '*WindowsUpdate\AU') { return [pscustomobject]@{ NoAutoUpdate = 1 } }
                return $null
            }

            $out = Main *>&1
            $text = $out | Out-String
            $text | Should -Match 'UAC is disabled'
            $text | Should -Match 'Real-time protection disabled'
            $text | Should -Match 'Antivirus signatures outdated \(12 days\)'
            $text | Should -Match 'Automatic updates disabled'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }

        It "Returns 1 with [-] output when the firewall query fails" {
            Mock Get-NetFirewallProfile { throw 'RPC unavailable' }

            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[-\]'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }
    }
}
