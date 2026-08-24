#Requires -Modules Pester

Describe "Test-RemediationCheckDefenderHealthStatus" {
    BeforeAll {
        # Mirrored layout: walk up from Tests/... to the repo root, then across to scripts/.
        $repoRoot = $PSScriptRoot
        while (-not (Test-Path (Join-Path $repoRoot '.git'))) { $repoRoot = Split-Path $repoRoot -Parent }
        $scriptRelPath = 'scripts/endpoints/remediation/security/Test-RemediationCheckDefenderHealthStatus.ps1'
        $scriptPath = Join-Path $repoRoot $scriptRelPath

        # Safe: the script's top-level guard skips Main when dot-sourced.
        . $scriptPath
    }

    Context "Help & Metadata" {
        It "Declares required .NOTES fields with Version 1.0.0 and Date 2026-08-23" {
            $raw = Get-Content -Path $scriptPath -Raw
            $raw | Should -Match 'File Name:\s*Test-RemediationCheckDefenderHealthStatus\.ps1'
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
        function Get-Service { }
        function Get-MpPreference { }
        function Get-MpComputerStatus { }
        }

        It "Returns 0 with [+] output when Defender is healthy (idempotent)" {
            Mock Get-Service { [pscustomobject]@{ Name = 'WinDefend'; Status = 'Running' } }
            Mock Get-MpPreference { [pscustomobject]@{ DisableRealtimeMonitoring = $false } }
            Mock Get-MpComputerStatus {
                [pscustomobject]@{
                    AntivirusSignatureLastUpdated = (Get-Date).AddHours(-2)
                    AntivirusEnabled = $true
                    FullScanAge = 3
                }
            }

            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[\+\]'
            $out | Where-Object { $_ -is [int] } | Should -Be 0
        }

        It "Returns 1 with [!] output when the Defender service is not running" {
            Mock Get-Service { [pscustomobject]@{ Name = 'WinDefend'; Status = 'Stopped' } }
            Mock Get-MpPreference { [pscustomobject]@{ DisableRealtimeMonitoring = $false } }
            Mock Get-MpComputerStatus {
                [pscustomobject]@{
                    AntivirusSignatureLastUpdated = (Get-Date)
                    AntivirusEnabled = $true
                    FullScanAge = 3
                }
            }

            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[!\]'
            ($out | Out-String) | Should -Match 'not running'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }

        It "Flags outdated signatures older than 7 days and disabled antivirus together" {
            Mock Get-Service { [pscustomobject]@{ Name = 'WinDefend'; Status = 'Running' } }
            Mock Get-MpPreference { [pscustomobject]@{ DisableRealtimeMonitoring = $true } }
            Mock Get-MpComputerStatus {
                [pscustomobject]@{
                    AntivirusSignatureLastUpdated = (Get-Date).AddDays(-14)
                    AntivirusEnabled = $false
                    FullScanAge = 45
                }
            }

            $out = Main *>&1
            $text = $out | Out-String
            $text | Should -Match 'signatures are outdated'
            $text | Should -Match 'disabled'
            $text | Should -Match 'Full scan has not run in 45 days'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }

        It "Returns 1 with [-] output when the status query throws" {
            Mock Get-Service { throw 'Access denied' }

            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[-\]'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }
    }
}
