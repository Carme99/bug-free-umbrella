#Requires -Modules Pester

Describe "Test-RemediationFixDiskSpace" -Tag Ep6SysA {
    BeforeAll {
        # Mirrored layout: walk up from Tests/... to the repo root, then across to scripts/.
        $repoRoot = $PSScriptRoot
        while (-not (Test-Path (Join-Path $repoRoot '.git'))) { $repoRoot = Split-Path $repoRoot -Parent }
        $scriptRelPath = 'scripts/endpoints/remediation/system/Test-RemediationFixDiskSpace.ps1'
        $scriptPath = Join-Path $repoRoot $scriptRelPath

        # Safe: the script's top-level guard skips Main when dot-sourced.
        . $scriptPath
    }

    Context "Help & Metadata" {
        It "Declares required .NOTES fields with Version 1.0.0 and Date 2026-08-23" {
            $raw = Get-Content -Path $scriptPath -Raw
            $raw | Should -Match 'File Name:\s*Test-RemediationFixDiskSpace\.ps1'
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
        It "Returns 0 when all fixed volumes meet both free-space thresholds" {
            function Get-Volume { }
            Mock Get-Volume {
                @(
                    [pscustomobject] @{ DriveLetter = 'C'; DriveType = 'Fixed'; Size = 100GB; SizeRemaining = 50GB },
                    [pscustomobject] @{ DriveLetter = 'D'; DriveType = 'Fixed'; Size = 200GB; SizeRemaining = 100GB }
                )
            }
            Main *>&1 | Where-Object { $_ -is [int] } | Should -Be 0
        }

        It "Returns 1 and names each volume below a threshold (percent or absolute GB)" {
            function Get-Volume { }
            Mock Get-Volume {
                @(
                    [pscustomobject] @{ DriveLetter = 'C'; DriveType = 'Fixed'; Size = 100GB; SizeRemaining = 5GB },
                    [pscustomobject] @{ DriveLetter = 'E'; DriveType = 'Fixed'; Size = 1000GB; SizeRemaining = 80GB }
                )
            }
            $out = Main *>&1
            $out | Where-Object { $_ -is [int] } | Should -Be 1
            ($out | Out-String) | Should -Match 'C:'
            ($out | Out-String) | Should -Match 'E:'
        }

        It "Ignores non-fixed drives without drive letters" {
            function Get-Volume { }
            Mock Get-Volume {
                @(
[pscustomobject] @{ DriveLetter = $null; DriveType = 'Removable'; Size = 10GB; SizeRemaining = 1KB
                    },
                    [pscustomobject] @{ DriveLetter = 'X'; DriveType = 'CD-ROM'; Size = 5GB; SizeRemaining = 0 }
                )
            }
            Main *>&1 | Where-Object { $_ -is [int] } | Should -Be 0
        }

        It "Returns 1 with [-] prefixed output when volume enumeration fails" {
            function Get-Volume { }
            Mock Get-Volume { throw "storage provider unavailable" }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[-\]'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }
    }
}
