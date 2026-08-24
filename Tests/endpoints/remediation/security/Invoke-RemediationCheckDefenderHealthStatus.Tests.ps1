#Requires -Modules Pester

Describe "Invoke-RemediationCheckDefenderHealthStatus" {
    BeforeAll {
        # Mirrored layout: walk up from Tests/... to the repo root, then across to scripts/.
        $repoRoot = $PSScriptRoot
        while (-not (Test-Path (Join-Path $repoRoot '.git'))) { $repoRoot = Split-Path $repoRoot -Parent }
        $scriptRelPath = 'scripts/endpoints/remediation/security/Invoke-RemediationCheckDefenderHealthStatus.ps1'
        $scriptPath = Join-Path $repoRoot $scriptRelPath

        # Safe: the script's top-level guard skips Main when dot-sourced.
        . $scriptPath
    }

    Context "Help & Metadata" {
        It "Declares required .NOTES fields with Version 1.0.0 and Date 2026-08-23" {
            $raw = Get-Content -Path $scriptPath -Raw
            $raw | Should -Match 'File Name:\s*Invoke-RemediationCheckDefenderHealthStatus\.ps1'
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
        It "Returns 0 and takes no action when Defender is fully healthy" {
            function Get-Service { }
            function Start-Service { }
            function Get-MpPreference { }
            function Get-MpComputerStatus { }
            function Set-MpPreference { }
            function Update-MpSignature { }
            function Start-MpScan { }
            Mock Get-Service { [pscustomobject]@{ Name = 'WinDefend'; Status = 'Running' } }
            Mock Start-Service { }
            Mock Get-MpPreference { [pscustomobject]@{ DisableRealtimeMonitoring = $false } }
            Mock Get-MpComputerStatus {
                [pscustomobject]@{
                    AntivirusEnabled = $true
                    AntivirusSignatureLastUpdated = (Get-Date).AddDays(-1)
                    QuickScanAge = 1
                }
            }
            Mock Update-MpSignature { }
            Mock Start-MpScan { }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[\*\]'
            ($out | Out-String) | Should -Match 'No remediation actions were necessary'
            $out | Where-Object { $_ -is [int] } | Should -Be 0
            Should -Invoke Start-Service -Exactly 0 -Scope It
            Should -Invoke Update-MpSignature -Exactly 0 -Scope It
            Should -Invoke Start-MpScan -Exactly 0 -Scope It
        }

        It "Applies every remediation action when Defender drift is detected" {
            function Get-Service { }
            function Start-Service { }
            function Set-MpPreference { }
            function Update-MpSignature { }
            function Start-MpScan { }
            function Get-MpPreference { }
            function Get-MpComputerStatus { }
            Mock Get-Service { [pscustomobject]@{ Name = 'WinDefend'; Status = 'Stopped' } }
            Mock Start-Service { }
            Mock Get-MpPreference { [pscustomobject]@{ DisableRealtimeMonitoring = $true } }
            Mock Get-MpComputerStatus {
                [pscustomobject]@{
                    AntivirusEnabled = $false
                    AntivirusSignatureLastUpdated = (Get-Date).AddDays(-14)
                    QuickScanAge = 30
                }
            }
            Mock Set-MpPreference { }
            Mock Update-MpSignature { }
            Mock Start-MpScan { }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[\+\]'
            $out | Where-Object { $_ -is [int] } | Should -Be 0
            Should -Invoke Start-Service -Exactly 1 -Scope It
            Should -Invoke Set-MpPreference -Exactly 2 -Scope It
            Should -Invoke Update-MpSignature -Exactly 1 -Scope It
            Should -Invoke Start-MpScan -Exactly 1 -Scope It
        }

        It "Returns 1 with [-] output when the Defender status cannot be read" {
            function Get-Service { }
            function Get-MpPreference { }
            Mock Get-Service { [pscustomobject]@{ Name = 'WinDefend'; Status = 'Running' } }
            Mock Get-MpPreference { throw 'Defender module unavailable' }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[-\]'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }
    }
}
