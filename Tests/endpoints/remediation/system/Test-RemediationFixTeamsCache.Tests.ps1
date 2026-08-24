#Requires -Modules Pester

Describe "Test-RemediationFixTeamsCache" {
    BeforeAll {
        # Mirrored layout: walk up from Tests/... to the repo root, then across to scripts/.
        $repoRoot = $PSScriptRoot
        while (-not (Test-Path (Join-Path $repoRoot '.git'))) { $repoRoot = Split-Path $repoRoot -Parent }
        $scriptRelPath = 'scripts/endpoints/remediation/system/Test-RemediationFixTeamsCache.ps1'
        $scriptPath = Join-Path $repoRoot $scriptRelPath

        # Safe: the script's top-level guard skips Main when dot-sourced.
        . $scriptPath
    }

    Context "Help & Metadata" {
        It "Declares required .NOTES fields with Version 1.0.0 and Date 2026-08-23" {
            $raw = Get-Content -Path $scriptPath -Raw
            $raw | Should -Match 'File Name:\s*Test-RemediationFixTeamsCache\.ps1'
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
        It "Returns 0 when no eligible user profiles are found" {
            # Get-CimInstance does not exist on Linux - stub inline so Pester can Mock it.
            function Get-CimInstance { }
            Mock Get-CimInstance { @() }
            Mock Join-Path { "$Path\$ChildPath" }
            Mock Test-Path { throw "unexpected path probe" }
            $out = Main *>&1
            $out | Where-Object { $_ -is [int] } | Should -Be 0
            ($out | Out-String) | Should -Match 'No eligible user profiles'
        }

        It "Returns 0 on a converged system with a small healthy Teams cache" {
            function Get-CimInstance { }
            Mock Get-CimInstance {
@([pscustomobject] @{ Special = $false; LocalPath = 'C:\Users\alice'; Loaded = $true; LastUseTime =
                (Get-Date) })
            }
            Mock Join-Path { "$Path\$ChildPath" }
            Mock Test-Path { $true }
            Mock Get-ChildItem { @() }
            $out = Main *>&1
            $out | Where-Object { $_ -is [int] } | Should -Be 0
            ($out | Out-String) | Should -Match '\[\+\].*healthy'
        }

        It "Returns 1 with [!] output when a per-user cache location exceeds the size threshold" {
            function Get-CimInstance { }
            Mock Get-CimInstance {
@([pscustomobject] @{ Special = $false; LocalPath = 'C:\Users\alice'; Loaded = $true; LastUseTime =
                (Get-Date) })
            }
            Mock Join-Path { "$Path\$ChildPath" }
            Mock Test-Path { $true }
            Mock Get-ChildItem {
                @([pscustomobject] @{ Name = 'big.dat'; Length = 600MB; LastWriteTime = (Get-Date) })
            }
            $out = Main *>&1
            $out | Where-Object { $_ -is [int] } | Should -Be 1
            ($out | Out-String) | Should -Match '\[!\]'
            ($out | Out-String) | Should -Match 'Large cache in alice'
        }

        It "Returns 0 when Teams is not installed for any scanned profile" {
            function Get-CimInstance { }
            Mock Get-CimInstance {
@([pscustomobject] @{ Special = $false; LocalPath = 'C:\Users\bob'; Loaded = $false; LastUseTime =
                (Get-Date) })
            }
            Mock Join-Path { "$Path\$ChildPath" }
            Mock Test-Path { $false }
            Mock Get-ChildItem { throw "unexpected enumeration" }
            $out = Main *>&1
            $out | Where-Object { $_ -is [int] } | Should -Be 0
            ($out | Out-String) | Should -Match 'not installed or not used'
        }

        It "Deliberately returns 0 (documented transient-failure semantics) with [-] output when the WMI scan fails" {
            function Get-CimInstance { }
            Mock Get-CimInstance { throw "wmi unavailable" }
            $out = Main *>&1
            $out | Where-Object { $_ -is [int] } | Should -Be 0
            ($out | Out-String) | Should -Match '\[-\]'
        }
    }
}
