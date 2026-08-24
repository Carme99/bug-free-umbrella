#Requires -Modules Pester

Describe "Test-RemediationFixTimeSync" {
    BeforeAll {
        # Mirrored layout: walk up from Tests/... to the repo root, then across to scripts/.
        $repoRoot = $PSScriptRoot
        while (-not (Test-Path (Join-Path $repoRoot '.git'))) { $repoRoot = Split-Path $repoRoot -Parent }
        $scriptRelPath = 'scripts/endpoints/remediation/system/Test-RemediationFixTimeSync.ps1'
        $scriptPath = Join-Path $repoRoot $scriptRelPath

        # Safe: the script's top-level guard skips Main when dot-sourced.
        . $scriptPath
    }

    Context "Help & Metadata" {
        It "Declares required .NOTES fields with Version 1.0.0 and Date 2026-08-23" {
            $raw = Get-Content -Path $scriptPath -Raw
            $raw | Should -Match 'File Name:\s*Test-RemediationFixTimeSync\.ps1'
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
        It "Returns 0 when the service is healthy and the last sync is fresh" {
            # Get-Service does not exist on Linux: stub it inline so Pester can Mock it.
            function Get-Service { }
            Mock Get-Service { [pscustomobject]@{ Status = 'Running'; StartType = 'Automatic' } }
            Mock Invoke-W32tm {
                [pscustomobject]@{
                    ExitCode = 0
                                        Output   = "Source: time.windows.com`nLast Successful Sync Time: `
                        $((Get-Date).AddHours(-2).ToString())"
                }
            }
            Main *>&1 | Where-Object { $_ -is [int] } | Should -Be 0
        }

        It "Returns 1 when the time source is the Local CMOS Clock" {
            function Get-Service { }
            Mock Get-Service { [pscustomobject]@{ Status = 'Running'; StartType = 'Automatic' } }
            Mock Invoke-W32tm {
                [pscustomobject]@{
                    ExitCode = 0
                    Output   = "Source: Local CMOS Clock`nLast Successful Sync Time: unspecified"
                }
            }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[!\]'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }

        It "Returns 1 when w32tm reports a non-zero exit code" {
            function Get-Service { }
            Mock Get-Service { [pscustomobject]@{ Status = 'Running'; StartType = 'Automatic' } }
            Mock Invoke-W32tm { [pscustomobject]@{ ExitCode = 1; Output = '' } }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[!\]'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }

        It "Returns 1 and writes [-] prefixed output when the wrapper throws" {
            function Get-Service { }
            Mock Get-Service { [pscustomobject]@{ Status = 'Running'; StartType = 'Automatic' } }
            Mock Invoke-W32tm { throw "w32tm not found" }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[-\]'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }
    }
}
