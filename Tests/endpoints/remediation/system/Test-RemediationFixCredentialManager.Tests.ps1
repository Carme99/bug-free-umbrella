#Requires -Modules Pester

Describe "Test-RemediationFixCredentialManager" -Tag Ep6SysA {
    BeforeAll {
        # Mirrored layout: walk up from Tests/... to the repo root, then across to scripts/.
        $repoRoot = $PSScriptRoot
        while (-not (Test-Path (Join-Path $repoRoot '.git'))) { $repoRoot = Split-Path $repoRoot -Parent }
        $scriptRelPath = 'scripts/endpoints/remediation/system/Test-RemediationFixCredentialManager.ps1'
        $scriptPath = Join-Path $repoRoot $scriptRelPath

        # Safe: the script's top-level guard skips Main when dot-sourced.
        . $scriptPath
    }

    Context "Help & Metadata" {
        It "Declares required .NOTES fields with Version 1.0.0 and Date 2026-08-23" {
            $raw = Get-Content -Path $scriptPath -Raw
            $raw | Should -Match 'File Name:\s*Test-RemediationFixCredentialManager\.ps1'
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
        It "Routes the native cmdkey.exe call through a wrapper function" {
            $raw = Get-Content -Path $scriptPath -Raw
            $raw | Should -Match 'function Invoke-CmdKeyList'
        }
    }

    Context "Behavior" {
        It "Returns 0 when only by-design or domain credentials are present" {
                        $credOut = "Target: Domain:target=TERMSRV/fileserver`nTarget: `
                            LegacyGeneric:target=MicrosoftAccount:target=SSO_POP_Device`nTarget: `
                LegacyGeneric:target=virtualapp/didlogical"
            Mock Invoke-CmdKeyList { [pscustomobject] @{ Output = $credOut; ExitCode = 0 } }
            Main *>&1 | Where-Object { $_ -is [int] } | Should -Be 0
            Should -Invoke Invoke-CmdKeyList -Times 1 -Exactly
        }

        It "Returns 1 and lists stale generic credentials when detected" {
            $credOut = "Target: LegacyGeneric:target=SomeOldApp`nTarget: LegacyDiscardable:target=JunkApp"
            Mock Invoke-CmdKeyList { [pscustomobject] @{ Output = $credOut; ExitCode = 0 } }
            $out = Main *>&1
            $out | Where-Object { $_ -is [int] } | Should -Be 1
            ($out | Out-String) | Should -Match 'LegacyGeneric:target=SomeOldApp'
        }

        It "Returns 0 when cmdkey cannot enumerate (transient failure tolerated)" {
            Mock Invoke-CmdKeyList { [pscustomobject] @{ Output = ''; ExitCode = 1 } }
            Main *>&1 | Where-Object { $_ -is [int] } | Should -Be 0
        }

        It "Returns 1 with [-] prefixed output when the check throws" {
            Mock Invoke-CmdKeyList { throw "cmdkey unavailable" }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[-\]'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }
    }
}
