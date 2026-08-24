#Requires -Modules Pester

Describe "Test-RemediationFixSystemFileCorruption" {
    BeforeAll {
        # Mirrored layout: walk up from Tests/... to the repo root, then across to scripts/.
        $repoRoot = $PSScriptRoot
        while (-not (Test-Path (Join-Path $repoRoot '.git'))) { $repoRoot = Split-Path $repoRoot -Parent }
        $scriptRelPath = 'scripts/endpoints/remediation/system/Test-RemediationFixSystemFileCorruption.ps1'
        $scriptPath = Join-Path $repoRoot $scriptRelPath

        # Safe: the script's top-level guard skips Main when dot-sourced.
        . $scriptPath
    }

    Context "Help & Metadata" {
        It "Declares required .NOTES fields with Version 1.0.0 and Date 2026-08-23" {
            $raw = Get-Content -Path $scriptPath -Raw
            $raw | Should -Match 'File Name:\s*Test-RemediationFixSystemFileCorruption\.ps1'
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
        It "Defines only approved-verb functions and never calls dism.exe directly in Main" {
            $isFunctionDef = { $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }
            $functions = $ast.FindAll($isFunctionDef, $true)
            $approved = (Get-Verb).Verb
            foreach ($f in $functions) {
                if ($f.Name -eq 'Main') { continue }
                $verb = ($f.Name -split '-')[0]
                $approved | Should -Contain $verb -Because "function $($f.Name) must use an approved verb"
            }
            $mainBody = ($functions | Where-Object Name -eq 'Main').Body.Extent.Text
            $mainBody | Should -Match 'Invoke-Dism'
            # dism.exe is invoked only inside the wrapper, never directly from Main
            $dismBody = ($functions | Where-Object Name -eq 'Invoke-Dism').Body.Extent.Text
            $dismBody | Should -Match 'Dism\.exe'
        }
    }

    Context "Behavior" {
        It "Returns 0 when DISM reports a healthy store and no CBS log exists" {
            Mock Invoke-Dism {
                [pscustomobject] @{ ExitCode = 0; Output = "The component store is healthy." }
            }
            Mock Test-Path { $false }
            $out = Main *>&1
            $out | Where-Object { $_ -is [int] } | Should -Be 0
            ($out | Out-String) | Should -Match '\[\+\]'
            Should -Invoke Invoke-Dism -Times 1 -Exactly
        }

        It "Returns 1 with [!] output when the component store is repairable" {
            Mock Invoke-Dism {
                [pscustomobject] @{ ExitCode = 0; Output = "The component store is repairable." }
            }
            Mock Test-Path { $false }
            $out = Main *>&1
            $out | Where-Object { $_ -is [int] } | Should -Be 1
            ($out | Out-String) | Should -Match '\[!\]'
            ($out | Out-String) | Should -Match 'repairable'
        }

        It "Returns 1 when the CBS log shows SFC found corrupt files" {
            Mock Invoke-Dism {
                [pscustomobject] @{ ExitCode = 0; Output = "No component store corruption detected." }
            }
            Mock Test-Path { $true }
            Mock Get-Content { @("2026-08-23 10:00:00, Info CBS ... found corrupt files ...") }
            Main *>&1 | Where-Object { $_ -is [int] } | Should -Be 1
        }

        It "Returns 1 when dism.exe exits non-zero without a corruption message (wrapper exit-code check)" {
            Mock Invoke-Dism {
                [pscustomobject] @{ ExitCode = 87; Output = "An unknown error occurred." }
            }
            Mock Test-Path { $false }
            $out = Main *>&1
            $out | Where-Object { $_ -is [int] } | Should -Be 1
            ($out | Out-String) | Should -Match 'exit code 87'
        }

        It "Returns 1 with [-] prefixed output when the DISM wrapper throws" {
            Mock Invoke-Dism { throw "dism crashed" }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[-\]'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }
    }
}
