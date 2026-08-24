#Requires -Modules Pester

Describe "Test-RemediationCheckOutdatedCriticalApps" {
    BeforeAll {
        # Mirrored layout: walk up from Tests/... to the repo root, then across to scripts/.
        $repoRoot = $PSScriptRoot
        while (-not (Test-Path (Join-Path $repoRoot '.git'))) { $repoRoot = Split-Path $repoRoot -Parent }
        $scriptRelPath = 'scripts/endpoints/remediation/security/Test-RemediationCheckOutdatedCriticalApps.ps1'
        $scriptPath = Join-Path $repoRoot $scriptRelPath

        # Safe: the script's top-level guard skips Main when dot-sourced.
        . $scriptPath
    }

    Context "Help & Metadata" {
        It "Declares required .NOTES fields with Version 1.0.0 and Date 2026-08-23" {
            $raw = Get-Content -Path $scriptPath -Raw
            $raw | Should -Match 'File Name:\s*Test-RemediationCheckOutdatedCriticalApps\.ps1'
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
        It "Is a read-only detection script (plain CmdletBinding) that wraps winget" {
            $raw = Get-Content -Path $scriptPath -Raw
            $raw | Should -Match '\[CmdletBinding\(\)\]'
            $raw | Should -Not -Match 'SupportsShouldProcess'
            # winget.exe is only invoked inside the thin wrapper function.
            ($raw -split "`n" | Where-Object { $_ -match '& winget' }).Count | Should -Be 1
        }
    }

    Context "Behavior" {
        BeforeAll {
            # Stub externals so Pester Mock can bind them offline.
            function Test-NetConnection { }
            Mock Get-Command { [pscustomobject]@{ Source = '/usr/bin/winget' } }
            Mock Test-NetConnection { $true }
        }

        It "Returns 1 with [-]/CRITICAL output when a priority app has an update available" {
            $wingetTable = @"
Name                 Id                     Version      Available
----                 --                     -------      ---------
Google Chrome        Google.Chrome          120.0.6099   121.0.6167
VLC media player     VideoLAN.VLC           3.0.18       3.0.20
"@
            Mock Invoke-Winget {
                [pscustomobject]@{ Output = $wingetTable; ExitCode = 0 }
            }

            $out = Main *>&1
            $text = $out | Out-String
            $text | Should -Match 'CRITICAL UPDATES DETECTED'
            $text | Should -Match 'Google\.Chrome'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
            Should -Invoke Invoke-Winget -Exactly 1 -Scope It
        }

        It "Returns 0 when only apps outside both configured lists have updates (idempotent)" {
            $wingetTable = @"
Name                 Id                     Version      Available
----                 --                     -------      ---------
Some Random App      RandomVendor.RandomApp 1.0.0        1.0.1
"@
            Mock Invoke-Winget {
                [pscustomobject]@{ Output = $wingetTable; ExitCode = 0 }
            }

            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[\+\]'
            $out | Where-Object { $_ -is [int] } | Should -Be 0
        }

        It "Returns 0 with no outdated applications at all" {
            $wingetTable = @"
Name                 Id                     Version      Available
----                 --                     -------      ---------
No installed package has an upgrade available.
"@
            Mock Invoke-Winget {
                [pscustomobject]@{ Output = $wingetTable; ExitCode = 0 }
            }

            $out = Main *>&1
            $out | Where-Object { $_ -is [int] } | Should -Be 0
        }

        It "Returns 1 when winget is not available" {
            Mock Get-Command { throw 'CommandNotFound' }

            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[-\]'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }

        It "Returns 1 when network connectivity is unavailable" {
            Mock Test-NetConnection { throw 'Network unreachable' }

            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[-\]'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }
    }
}
