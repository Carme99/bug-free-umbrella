#Requires -Modules Pester

Describe "Test-RemediationFixWindowsSearch" {
    BeforeAll {
        # Mirrored layout: walk up from Tests/... to the repo root, then across to scripts/.
        $repoRoot = $PSScriptRoot
        while (-not (Test-Path (Join-Path $repoRoot '.git'))) { $repoRoot = Split-Path $repoRoot -Parent }
        $scriptRelPath = 'scripts/endpoints/remediation/system/Test-RemediationFixWindowsSearch.ps1'
        $scriptPath = Join-Path $repoRoot $scriptRelPath

        # Safe: the script's top-level guard skips Main when dot-sourced.
        . $scriptPath
    }

    Context "Help & Metadata" {
        It "Declares required .NOTES fields with Version 1.0.0 and Date 2026-08-23" {
            $raw = Get-Content -Path $scriptPath -Raw
            $raw | Should -Match 'File Name:\s*Test-RemediationFixWindowsSearch\.ps1'
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
        It "Returns 1 with [!] output when the WSearch service is not found" {
            # Get-Service does not exist on Linux: stub it inline so Pester can Mock it.
            function Get-Service { param([string]$Name) }
            Mock Get-Service { $null }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[!\]'
            ($out | Out-String) | Should -Match 'not found'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }

        It "Returns 1 with [!] output when the WSearch service is stopped" {
            function Get-Service { param([string]$Name) }
            Mock Get-Service { [pscustomobject]@{ Status = 'Stopped'; StartType = 'Automatic' } }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[!\]'
            ($out | Out-String) | Should -Match 'not running'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }

        It "Returns 0 when the service is healthy and the index is idle" {
            function Get-Service { param([string]$Name) }
            Mock Get-Service { [pscustomobject]@{ Status = 'Running'; StartType = 'Automatic' } }
            Mock Get-SearchCatalogManager {
                $mgr = [pscustomobject]@{}
                $mgr | Add-Member ScriptMethod GetCatalog {
                    param([string]$Name)
                    $cat = [pscustomobject]@{}
                    $cat | Add-Member ScriptMethod GetCatalogStatus { 0 }
                    $cat
                }
                $mgr
            }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[\+\]'
            $out | Where-Object { $_ -is [int] } | Should -Be 0
        }

        It "Returns 1 with [!] output when the search index is paused" {
            function Get-Service { param([string]$Name) }
            Mock Get-Service { [pscustomobject]@{ Status = 'Running'; StartType = 'AutomaticDelayedStart' } }
            Mock Get-SearchCatalogManager {
                $mgr = [pscustomobject]@{}
                $mgr | Add-Member ScriptMethod GetCatalog {
                    param([string]$Name)
                    $cat = [pscustomobject]@{}
                    $cat | Add-Member ScriptMethod GetCatalogStatus { 3 }
                    $cat
                }
                $mgr
            }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[!\]'
            ($out | Out-String) | Should -Match 'paused or recovering'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }

        It "Treats an inaccessible COM index check as non-fatal and still returns 0" {
            function Get-Service { param([string]$Name) }
            Mock Get-Service { [pscustomobject]@{ Status = 'Running'; StartType = 'Automatic' } }
            Mock Get-SearchCatalogManager { throw "COM not available" }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[\+\]'
            $out | Where-Object { $_ -is [int] } | Should -Be 0
        }
    }
}
