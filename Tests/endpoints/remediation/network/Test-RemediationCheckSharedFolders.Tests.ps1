#Requires -Modules Pester

Describe "Test-RemediationCheckSharedFolders" {
    BeforeAll {
        # Mirrored layout: walk up from Tests/... to the repo root, then across to scripts/.
        $repoRoot = $PSScriptRoot
        while (-not (Test-Path (Join-Path $repoRoot '.git'))) { $repoRoot = Split-Path $repoRoot -Parent }
        $scriptRelPath = 'scripts/endpoints/remediation/network/Test-RemediationCheckSharedFolders.ps1'
        $scriptPath = Join-Path $repoRoot $scriptRelPath

        # Safe: the script's top-level guard skips Main when dot-sourced.
        . $scriptPath

        # Stub Windows-only cmdlets so Pester can mock them on Linux pwsh.
        function Get-SmbShare { }

        # Default mock: only approved system shares exist.
        Mock Get-SmbShare {
            @(
                [pscustomobject]@{ Name = 'ADMIN$'; Path = 'C:\Windows'; Description = 'Remote Admin' },
                [pscustomobject]@{ Name = 'C$'; Path = 'C:\'; Description = 'Default share' },
                [pscustomobject]@{ Name = 'IPC$'; Path = ''; Description = 'IPC' }
            )
        }
    }

    Context "Help & Metadata" {
        It "Declares required .NOTES fields with Version 1.0.0 and Date 2026-08-23" {
            $raw = Get-Content -Path $scriptPath -Raw
            $raw | Should -Match 'File Name:\s*Test-RemediationCheckSharedFolders\.ps1'
            $raw | Should -Match 'Author:'
            $raw | Should -Match 'Prerequisite:\s*PowerShell 7\.0'
            $raw | Should -Match 'Version:\s*1\.0\.0'
            $raw | Should -Match 'Date:\s*2026-08-23'
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
        It "Returns 0 with [+] output when only approved shares are present" {
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[\+\]'
            $out | Where-Object { $_ -is [int] } | Should -Be 0
        }

        It "Returns 1 with [!] output naming an unauthorized share" {
            Mock Get-SmbShare {
                @([pscustomobject]@{ Name = 'HRData'; Path = 'D:\HRData'; Description = '' })
            }
            $out = Main *>&1
            $text = $out | Out-String
            $text | Should -Match '\[!\]'
            $text | Should -Match 'HRData \(D:\\HRData\)'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }

        It "Ignores case-insensitive wildcard matches against the approved list" {
            Mock Get-SmbShare {
                @([pscustomobject]@{ Name = 'c$'; Path = 'C:\'; Description = '' })
            }
            $out = Main *>&1
            $out | Where-Object { $_ -is [int] } | Should -Be 0
        }

        It "Returns 1 and writes [-] prefixed output when share enumeration fails" {
            Mock Get-SmbShare { throw 'SMB server unavailable' }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[-\]'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }
    }
}
