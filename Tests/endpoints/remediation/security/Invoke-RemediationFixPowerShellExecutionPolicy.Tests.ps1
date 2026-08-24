#Requires -Modules Pester

Describe "Invoke-RemediationFixPowerShellExecutionPolicy" {
    BeforeAll {
        # Mirrored layout: walk up from Tests/... to the repo root, then across to scripts/.
        $repoRoot = $PSScriptRoot
        while (-not (Test-Path (Join-Path $repoRoot '.git'))) { $repoRoot = Split-Path $repoRoot -Parent }
        $scriptRelPath = 'scripts/endpoints/remediation/security/Invoke-RemediationFixPowerShellExecutionPolicy.ps1'
        $scriptPath = Join-Path $repoRoot $scriptRelPath

        # Safe: the script's top-level guard skips Main when dot-sourced.
        . $scriptPath
    }

    Context "Help & Metadata" {
        It "Declares required .NOTES fields with Version 1.0.0 and Date 2026-08-23" {
            $raw = Get-Content -Path $scriptPath -Raw
            $raw | Should -Match 'File Name:\s*Invoke-RemediationFixPowerShellExecutionPolicy\.ps1'
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
        It "Uses SupportsShouldProcess for its mutating operation" {
            $raw = Get-Content -Path $scriptPath -Raw
            $raw | Should -Match '\[CmdletBinding\(SupportsShouldProcess\)\]'
            $raw | Should -Match '\$PSCmdlet\.ShouldProcess\('
        }
    }

    Context "Behavior" {
        It "Returns 0 with [+] output when the effective policy is already RemoteSigned (idempotent)" {
            Mock Get-ExecutionPolicy -ParameterFilter { $List } {
                @(
                    [pscustomobject]@{ Scope = 'MachinePolicy'; ExecutionPolicy = 'Undefined' },
                    [pscustomobject]@{ Scope = 'UserPolicy'; ExecutionPolicy = 'Undefined' },
                    [pscustomobject]@{ Scope = 'Process'; ExecutionPolicy = 'Bypass' },
                    [pscustomobject]@{ Scope = 'LocalMachine'; ExecutionPolicy = 'RemoteSigned' }
                )
            }
            Mock Get-ExecutionPolicy -ParameterFilter { $Scope -eq 'LocalMachine' } { 'RemoteSigned' }
            Mock Set-ExecutionPolicy { }

            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[\+\]'
            $out | Where-Object { $_ -is [int] } | Should -Be 0
            Should -Invoke Set-ExecutionPolicy -Exactly 0 -Scope It
        }

        It "Sets and verifies LocalMachine to RemoteSigned when it was Restricted" {
            $script:localMachineReads = 0
            Mock Get-ExecutionPolicy -ParameterFilter { $Scope -eq 'LocalMachine' } {
                $script:localMachineReads++
                if ($script:localMachineReads -eq 1) { return 'Restricted' }
                return 'RemoteSigned'
            }
            $script:listReads = 0
            Mock Get-ExecutionPolicy -ParameterFilter { $List } {
                $script:listReads++
                if ($script:listReads -eq 1) {
                    return @(
                        [pscustomobject]@{ Scope = 'MachinePolicy'; ExecutionPolicy = 'Undefined' },
                        [pscustomobject]@{ Scope = 'LocalMachine'; ExecutionPolicy = 'Restricted' }
                    )
                }
                return @(
                    [pscustomobject]@{ Scope = 'MachinePolicy'; ExecutionPolicy = 'Undefined' },
                    [pscustomobject]@{ Scope = 'LocalMachine'; ExecutionPolicy = 'RemoteSigned' }
                )
            }
            Mock Set-ExecutionPolicy { }

            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[\+\]'
            $out | Where-Object { $_ -is [int] } | Should -Be 0
            Should -Invoke Set-ExecutionPolicy -Exactly 1 -Scope It
        }

        It "Returns 1 with [-] output when the LocalMachine change does not stick" {
            Mock Get-ExecutionPolicy -ParameterFilter { $Scope -eq 'LocalMachine' } { 'Restricted' }
            Mock Get-ExecutionPolicy -ParameterFilter { $List } {
                @(
                    [pscustomobject]@{ Scope = 'MachinePolicy'; ExecutionPolicy = 'Undefined' },
                    [pscustomobject]@{ Scope = 'LocalMachine'; ExecutionPolicy = 'Restricted' }
                )
            }
            Mock Set-ExecutionPolicy { }

            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[-\]'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
            Should -Invoke Set-ExecutionPolicy -Exactly 1 -Scope It
        }

        It "Returns 1 with [-] output when a higher-priority scope still overrides after the change" {
            # LocalMachine change sticks, but Group Policy MachinePolicy keeps overriding.
            Mock Get-ExecutionPolicy -ParameterFilter { $Scope -eq 'LocalMachine' } { 'RemoteSigned' }
            Mock Get-ExecutionPolicy -ParameterFilter { $List } {
                @(
                    [pscustomobject]@{ Scope = 'MachinePolicy'; ExecutionPolicy = 'AllSigned' },
                    [pscustomobject]@{ Scope = 'LocalMachine'; ExecutionPolicy = 'RemoteSigned' }
                )
            }
            Mock Set-ExecutionPolicy { }

            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[-\]'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }
    }
}
