#Requires -Modules Pester

Describe "Test-RemediationFixOutdatedDrivers" -Tag Ep6SysA {
    BeforeAll {
        # Mirrored layout: walk up from Tests/... to the repo root, then across to scripts/.
        $repoRoot = $PSScriptRoot
        while (-not (Test-Path (Join-Path $repoRoot '.git'))) { $repoRoot = Split-Path $repoRoot -Parent }
        $scriptRelPath = 'scripts/endpoints/remediation/system/Test-RemediationFixOutdatedDrivers.ps1'
        $scriptPath = Join-Path $repoRoot $scriptRelPath

        # Safe: the script's top-level guard skips Main when dot-sourced.
        . $scriptPath
    }

    Context "Help & Metadata" {
        It "Declares required .NOTES fields with Version 1.0.0 and Date 2026-08-23" {
            $raw = Get-Content -Path $scriptPath -Raw
            $raw | Should -Match 'File Name:\s*Test-RemediationFixOutdatedDrivers\.ps1'
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
        It "Returns 0 when no problem devices exist and no driver updates are offered (converged)" {
            function Get-WmiObject { }
            Mock Get-WmiObject { $null } -ParameterFilter { $Class -eq 'Win32_PnPEntity' }
            Mock Find-DriverUpdate { [pscustomobject] @{ Updates = @() } }
            Main *>&1 | Where-Object { $_ -is [int] } | Should -Be 0
            Should -Invoke Find-DriverUpdate -Times 1 -Exactly
        }

        It "Returns 1 and lists titles when Windows Update offers driver updates" {
            function Get-WmiObject { }
            Mock Get-WmiObject { $null } -ParameterFilter { $Class -eq 'Win32_PnPEntity' }
            Mock Find-DriverUpdate {
                [pscustomobject] @{
                    Updates = @(
                        [pscustomobject] @{ Title = 'Realtek Audio Driver' },
                        [pscustomobject] @{ Title = 'Intel Graphics Driver' }
                    )
                }
            }
            $out = Main *>&1
            $out | Where-Object { $_ -is [int] } | Should -Be 1
            $text = $out | Out-String
            $text | Should -Match 'Realtek Audio Driver'
            $text | Should -Match 'Intel Graphics Driver'
        }

        It "Returns 1 for problem devices even when the update search fails (warning tolerated)" {
            function Get-WmiObject { }
            Mock Get-WmiObject {
                @([pscustomobject] @{ Name = 'Ethernet Controller'; ConfigManagerErrorCode = 28 })
            }
            Mock Find-DriverUpdate { throw "Windows Update unreachable" }
            $out = Main *>&1
            $out | Where-Object { $_ -is [int] } | Should -Be 1
            $text = $out | Out-String
            $text | Should -Match 'Ethernet Controller'
            $text | Should -Match '\[\!\]'
        }

        It "Returns 0 with a warning when only the update search fails and devices are healthy" {
            function Get-WmiObject { }
            Mock Get-WmiObject { $null } -ParameterFilter { $Class -eq 'Win32_PnPEntity' }
            Mock Find-DriverUpdate { throw "COM class not registered" }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[\!\]'
            Main *>&1 | Where-Object { $_ -is [int] } | Should -Be 0
        }
    }
}
