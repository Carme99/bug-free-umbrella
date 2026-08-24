#Requires -Modules Pester

Describe "Test-RemediationCheckTPMStatus" {
    BeforeAll {
        # Mirrored layout: walk up from Tests/... to the repo root, then across to scripts/.
        $repoRoot = $PSScriptRoot
        while (-not (Test-Path (Join-Path $repoRoot '.git'))) { $repoRoot = Split-Path $repoRoot -Parent }
        $scriptRelPath = 'scripts/endpoints/remediation/security/Test-RemediationCheckTPMStatus.ps1'
        $scriptPath = Join-Path $repoRoot $scriptRelPath

        # Safe: the script's top-level guard skips Main when dot-sourced.
        . $scriptPath
    }

    Context "Help & Metadata" {
        It "Declares required .NOTES fields with Version 1.0.0 and Date 2026-08-23" {
            $raw = Get-Content -Path $scriptPath -Raw
            $raw | Should -Match 'File Name:\s*Test-RemediationCheckTPMStatus\.ps1'
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
        function Get-Tpm { }
        function Get-WmiObject { }
        }

        It "Returns 0 with [+] output for a healthy TPM 2.0 (idempotent)" {
            Mock Get-Tpm {
                [pscustomobject]@{
                    TpmPresent = $true; TpmEnabled = $true; TpmActivated = $true; TpmReady = $true; TpmOwned = $false
                }
            }
            Mock Get-WmiObject { [pscustomobject]@{ SpecVersion = '2,0' } }

            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[\+\]'
            ($out | Out-String) | Should -Match 'TPM is healthy and ready'
            $out | Where-Object { $_ -is [int] } | Should -Be 0
        }

        It "Treats TpmOwned = false as healthy on modern Windows" {
            Mock Get-Tpm {
                [pscustomobject]@{
                    TpmPresent = $true; TpmEnabled = $true; TpmActivated = $true; TpmReady = $true; TpmOwned = $false
                }
            }
            Mock Get-WmiObject { $null }

            $out = Main *>&1
            $out | Where-Object { $_ -is [int] } | Should -Be 0
            ($out | Out-String) | Should -Not -Match 'issues detected'
        }

        It "Returns 1 with [!] output listing multiple TPM issues" {
            Mock Get-Tpm {
                [pscustomobject]@{
                    TpmPresent = $true; TpmEnabled = $false; TpmActivated = $false; TpmReady = $false; TpmOwned = $false
                }
            }
            Mock Get-WmiObject { $null }

            $out = Main *>&1
            $text = $out | Out-String
            $text | Should -Match '\[!\]'
            $text | Should -Match 'not enabled'
            $text | Should -Match 'not activated'
            $text | Should -Match 'not ready'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }

        It "Returns 1 with a TPM 1.2 version warning but keeps it non-blocking only below 2.0" {
            Mock Get-Tpm {
                [pscustomobject]@{ TpmPresent = $true; TpmEnabled = $true; TpmActivated = $true; TpmReady = $true }
            }
            Mock Get-WmiObject { [pscustomobject]@{ SpecVersion = '1,2' } }

            $out = Main *>&1
            ($out | Out-String) | Should -Match 'TPM version is 1,2'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }

        It "Returns 1 with [!] output when no TPM is present at all" {
            Mock Get-Tpm { $null }
            Mock Get-WmiObject { $null }

            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[!\]'
            ($out | Out-String) | Should -Match 'TPM is not present'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }

        It "Returns 1 with [-] output when the TPM query throws" {
            Mock Get-Tpm { throw 'TPM WMI failure' }

            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[-\]'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }
    }
}
