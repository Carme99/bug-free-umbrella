#Requires -Modules Pester

Describe "Test-RemediationFixEdgeCacheSize" -Tag Ep6SysA {
    BeforeAll {
        # Mirrored layout: walk up from Tests/... to the repo root, then across to scripts/.
        $repoRoot = $PSScriptRoot
        while (-not (Test-Path (Join-Path $repoRoot '.git'))) { $repoRoot = Split-Path $repoRoot -Parent }
        $scriptRelPath = 'scripts/endpoints/remediation/system/Test-RemediationFixEdgeCacheSize.ps1'
        $scriptPath = Join-Path $repoRoot $scriptRelPath

        # Safe: the script's top-level guard skips Main when dot-sourced.
        . $scriptPath
    }

    Context "Help & Metadata" {
        It "Declares required .NOTES fields with Version 1.0.0 and Date 2026-08-23" {
            $raw = Get-Content -Path $scriptPath -Raw
            $raw | Should -Match 'File Name:\s*Test-RemediationFixEdgeCacheSize\.ps1'
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
        It "Calls exit only in the top-level dot-source guard" {
            $raw = Get-Content -Path $scriptPath -Raw
            @([regex]::Matches($raw, '\bexit\b')).Count | Should -Be 1
            $raw | Should -BeLike '*if ($MyInvocation.InvocationName -ne ''.'') { exit (Main) }*'
        }
    }

    Context "Behavior" {
        It "Returns 0 when no Edge cache directories exist (converged)" {
            function Get-ChildItem {
                [CmdletBinding()]
                param([string]$Path, [switch]$Directory, [switch]$Recurse, [switch]$File)
            }
            Mock Get-ChildItem {
                if ($Path -eq 'C:\Users') {
                    return @([pscustomobject] @{ FullName = 'C:\Users\alice'; Name = 'alice' })
                }
                return @()
            }
            Mock Test-Path { $false }
            Main *>&1 | Where-Object { $_ -is [int] } | Should -Be 0
            Should -Invoke Test-Path -Times 3 -Exactly -Because "three cache paths per profile are checked"
        }

        It "Returns 1 when the combined cache exceeds the threshold and reports the total" {
            Mock Test-Path { $true }
            function Get-ChildItem {
                [CmdletBinding()]
                param([string]$Path, [switch]$Directory, [switch]$Recurse, [switch]$File)
            }
            Mock Get-ChildItem {
                if ($Path -eq 'C:\Users') {
                    return @([pscustomobject] @{ FullName = 'C:\Users\alice'; Name = 'alice' })
                }
                return @([pscustomobject] @{ Length = 200MB })
            }
            $out = Main *>&1
            $out | Where-Object { $_ -is [int] } | Should -Be 1
            ($out | Out-String) | Should -Match '600 MB'
        }

        It "Returns 0 when cache content is within the threshold across multiple profiles" {
            Mock Test-Path { $true }
            function Get-ChildItem {
                [CmdletBinding()]
                param([string]$Path, [switch]$Directory, [switch]$Recurse, [switch]$File)
            }
            Mock Get-ChildItem {
                if ($Path -eq 'C:\Users') {
                    return @(
                        [pscustomobject] @{ FullName = 'C:\Users\alice'; Name = 'alice' },
                        [pscustomobject] @{ FullName = 'C:\Users\bob'; Name = 'bob' }
                    )
                }
                return @([pscustomobject] @{ Length = 20MB })
            }
            Main *>&1 | Where-Object { $_ -is [int] } | Should -Be 0
        }

        It "Returns 1 with [-] prefixed output when profile enumeration throws" {
            Mock Test-Path { $false }
            function Get-ChildItem {
                [CmdletBinding()]
                param([string]$Path, [switch]$Directory, [switch]$Recurse, [switch]$File)
            }
            Mock Get-ChildItem { throw "profile store gone" } -ParameterFilter { $Path -eq 'C:\Users' }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[-\]'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }
    }
}
