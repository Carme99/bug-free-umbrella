#Requires -Modules Pester

Describe "Test-RemediationFixStaleProfiles" {
    BeforeAll {
        # Mirrored layout: walk up from Tests/... to the repo root, then across to scripts/.
        $repoRoot = $PSScriptRoot
        while (-not (Test-Path (Join-Path $repoRoot '.git'))) { $repoRoot = Split-Path $repoRoot -Parent }
        $scriptRelPath = 'scripts/endpoints/remediation/system/Test-RemediationFixStaleProfiles.ps1'
        $scriptPath = Join-Path $repoRoot $scriptRelPath

        # Safe: the script's top-level guard skips Main when dot-sourced.
        . $scriptPath
    }

    Context "Help & Metadata" {
        It "Declares required .NOTES fields with Version 1.0.0 and Date 2026-08-23" {
            $raw = Get-Content -Path $scriptPath -Raw
            $raw | Should -Match 'File Name:\s*Test-RemediationFixStaleProfiles\.ps1'
            $raw | Should -Match 'Version:\s*1\.0\.0'
            $raw | Should -Match 'Date:\s*2026-08-23'
            $raw | Should -Match 'Author:'
            $raw | Should -Match 'Prerequisite:\s*PowerShell 7\.0'
        }

        It "Has SYNOPSIS, DESCRIPTION documenting exit codes, and at least two EXAMPLES" {
            $help = Get-Help $scriptPath
            $help.Synopsis | Should -Not -BeNullOrEmpty
            $help.Description | Should -Not -BeNullOrEmpty
            ($help.Description | Out-String) | Should -Match 'exit'
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
        It "Has Main plus exactly one exit statement on the top-level guard line" {
            $raw = Get-Content -Path $scriptPath -Raw
            $raw | Should -Match '(?m)^\s*\$ErrorActionPreference\s*=\s*''Stop'''
            $raw | Should -Match 'if \(\$MyInvocation\.InvocationName -ne ''\.''\) \{ exit \(Main\) \}'
            ([regex]::Matches($raw, 'exit\s*\(')).Count | Should -Be 1
        }
        It "Defines only approved-verb functions" {
            $isFunctionDef = { $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }
            $functions = $ast.FindAll($isFunctionDef, $true)
            $approved = (Get-Verb).Verb
            foreach ($f in $functions) {
                if ($f.Name -eq 'Main') { continue }
                $verb = ($f.Name -split '-')[0]
                $approved | Should -Contain $verb -Because "function $($f.Name) must use an approved verb"
            }
        }
    }

    Context "Behavior" {
        It "Returns 0 and does not measure size when all profiles were used recently" {
            # Get-CimInstance does not exist on Linux - stub inline so Pester can Mock it.
            function Get-CimInstance { }
            Mock Get-CimInstance {
@([pscustomobject] @{ Special = $false; LocalPath = 'C:\Users\alice'; Loaded = $false; LastUseTime =
                (Get-Date).AddDays(-10) })
            }
            Mock Get-ChildItem { throw "unexpected profile enumeration" }
            $out = Main *>&1
            $out | Where-Object { $_ -is [int] } | Should -Be 0
            ($out | Out-String) | Should -Match '\[\+\]'
            Should -Invoke Get-ChildItem -Times 0 -Exactly -Because "no stale profile should be measured"
        }

        It "Returns 1 and reports age and size for a stale profile found via DMTF LastUseTime" {
            function Get-CimInstance { }
            # Explicit-parameter stub: Pester mock proxies lack provider-dynamic params like -File.
            function Get-ChildItem {
                [CmdletBinding()]
                param([Parameter(Position = 0)][string[]]$Path, [string]$Filter, [switch]$Recurse, [switch]$File)
            }
            Mock Get-CimInstance {
@([pscustomobject] @{ Special = $false; LocalPath = 'C:\Users\alice'; Loaded = $false; LastUseTime =
                '20200101080910.000000+000' })
            }
            Mock Get-ChildItem {
                @([pscustomobject] @{ Length = 5GB })
            }
            $out = Main *>&1
            $out | Where-Object { $_ -is [int] } | Should -Be 1
            ($out | Out-String) | Should -Match '\[!\]'
            ($out | Out-String) | Should -Match 'alice'
        }

        It "Excludes special and loaded profiles from flagging (idempotent re-check)" {
            function Get-CimInstance { }
            Mock Get-CimInstance {
                @(
[pscustomobject] @{ Special = $true; LocalPath = 'C:\Users\Public'; Loaded = $false; LastUseTime =
                    '20200101080910.000000+000' },
[pscustomobject] @{ Special = $false; LocalPath = 'C:\Users\bob'; Loaded = $true; LastUseTime =
                    '20200101080910.000000+000' }
                )
            }
            Mock Get-ChildItem { throw "unexpected profile enumeration" }
            Main *>&1 | Where-Object { $_ -is [int] } | Should -Be 0
            Should -Invoke Get-ChildItem -Times 0 -Exactly
        }

        It "Skips profiles with unparseable LastUseTime and still returns 0" {
            function Get-CimInstance { }
            Mock Get-CimInstance {
@([pscustomobject] @{ Special = $false; LocalPath = 'C:\Users\carol'; Loaded = $false; LastUseTime =
                'not-a-date' })
            }
            Mock Get-ChildItem { throw "unexpected profile enumeration" }
            Main *>&1 | Where-Object { $_ -is [int] } | Should -Be 0
        }

        It "Returns 1 with [-] prefixed output when the WMI scan fails" {
            function Get-CimInstance { }
            Mock Get-CimInstance { throw "wmi unavailable" }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[-\]'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }
    }
}
