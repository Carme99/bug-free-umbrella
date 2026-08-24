#Requires -Modules Pester

Describe "Invoke-RemediationCheckTPMStatus" {
    BeforeAll {
        # Mirrored layout: walk up from Tests/... to the repo root, then across to scripts/.
        $repoRoot = $PSScriptRoot
        while (-not (Test-Path (Join-Path $repoRoot '.git'))) { $repoRoot = Split-Path $repoRoot -Parent }
        $scriptRelPath = 'scripts/endpoints/remediation/security/Invoke-RemediationCheckTPMStatus.ps1'
        $scriptPath = Join-Path $repoRoot $scriptRelPath

        # Safe: the script's top-level guard skips Main when dot-sourced.
        . $scriptPath
    }

    Context "Help & Metadata" {
        It "Declares required .NOTES fields with Version 1.0.0 and Date 2026-08-23" {
            $raw = Get-Content -Path $scriptPath -Raw
            $raw | Should -Match 'File Name:\s*Invoke-RemediationCheckTPMStatus\.ps1'
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
        It "Returns 0 without touching the TPM when it is already healthy" {
            function Get-Tpm { }
            function Initialize-Tpm { }
            function Invoke-CimMethod { }
            Mock Get-Tpm {
                [pscustomobject]@{
                    TpmPresent = $true
                    TpmReady = $true
                    TpmEnabled = $true
                    TpmActivated = $true
                    TpmOwned = $true
                }
            }
            Mock Initialize-Tpm { }
            Mock Invoke-CimMethod { }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[\+\]'
            ($out | Out-String) | Should -Match 'already in a healthy state'
            $out | Where-Object { $_ -is [int] } | Should -Be 0
            Should -Invoke Initialize-Tpm -Exactly 0 -Scope It
            Should -Invoke Invoke-CimMethod -Exactly 0 -Scope It
        }

        It "Initializes an unready TPM and returns 0" {
            function Get-Tpm { }
            function Initialize-Tpm { }
            function Invoke-CimMethod { }
            Mock Get-Tpm {
                [pscustomobject]@{
                    TpmPresent = $true
                    TpmReady = $false
                    TpmEnabled = $true
                    TpmActivated = $true
                    TpmOwned = $true
                }
            }
            Mock Initialize-Tpm { }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[\+\]'
            ($out | Out-String) | Should -Match 'Attempted TPM initialization'
            $out | Where-Object { $_ -is [int] } | Should -Be 0
            Should -Invoke Initialize-Tpm -Exactly 1 -Scope It
        }

        It "Returns 1 with [!] output when no TPM is present" {
            function Get-Tpm { }
            Mock Get-Tpm { $null }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[!\]'
            ($out | Out-String) | Should -Match 'BIOS/UEFI enablement'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }

        It "Returns 1 and reports BIOS/UEFI intervention for a disabled TPM" {
            function Get-Tpm { }
            function Initialize-Tpm { }
            Mock Get-Tpm {
                [pscustomobject]@{
                    TpmPresent = $true
                    TpmReady = $false
                    TpmEnabled = $false
                    TpmActivated = $false
                    TpmOwned = $false
                }
            }
            Mock Initialize-Tpm { throw 'Cannot initialize' }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[!\]'
            ($out | Out-String) | Should -Match 'BIOS/UEFI firmware'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }
    }
}
