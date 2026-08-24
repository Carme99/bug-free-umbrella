#Requires -Modules Pester

Describe "Test-RemediationFixWindowsStoreLicensing" {
    BeforeAll {
        # Mirrored layout: walk up from Tests/... to the repo root, then across to scripts/.
        $repoRoot = $PSScriptRoot
        while (-not (Test-Path (Join-Path $repoRoot '.git'))) { $repoRoot = Split-Path $repoRoot -Parent }
        $scriptRelPath = 'scripts/endpoints/remediation/system/Test-RemediationFixWindowsStoreLicensing.ps1'
        $scriptPath = Join-Path $repoRoot $scriptRelPath

        # Safe: the script's top-level guard skips Main when dot-sourced.
        . $scriptPath
    }

    Context "Help & Metadata" {
        It "Declares required .NOTES fields with Version 1.0.0 and Date 2026-08-23" {
            $raw = Get-Content -Path $scriptPath -Raw
            $raw | Should -Match 'File Name:\s*Test-RemediationFixWindowsStoreLicensing\.ps1'
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
        It "Returns 0 when services are healthy and the Store app is registered" {
            # Get-Service and Get-AppxPackage do not exist on Linux: stub them inline so Pester can Mock them.
            function Get-Service { param([string]$Name) }
            function Get-AppxPackage { }
            Mock Get-Service {
                if ($Name -eq 'ClipSVC') {
                    [pscustomobject]@{ Status = 'Running'; StartType = 'Automatic' }
                }
                else {
                    [pscustomobject]@{ Status = 'Running'; StartType = 'Manual' }
                }
            }
            Mock Get-AppxPackage { [pscustomobject]@{ Name = 'Microsoft.WindowsStore' } }
            Main *>&1 | Where-Object { $_ -is [int] } | Should -Be 0
        }

        It "Returns 1 with [!] output when ClipSVC is not running" {
            function Get-Service { param([string]$Name) }
            function Get-AppxPackage { }
            Mock Get-Service {
                if ($Name -eq 'ClipSVC') {
                    [pscustomobject]@{ Status = 'Stopped'; StartType = 'Manual' }
                }
                else {
                    [pscustomobject]@{ Status = 'Running'; StartType = 'Manual' }
                }
            }
            Mock Get-AppxPackage { [pscustomobject]@{ Name = 'Microsoft.WindowsStore' } }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[!\]'
            ($out | Out-String) | Should -Match 'ClipSVC\) is not running'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }

        It "Returns 1 with [!] output when the Microsoft Store app is missing" {
            function Get-Service { param([string]$Name) }
            function Get-AppxPackage { }
            Mock Get-Service {
                if ($Name -eq 'ClipSVC') {
                    [pscustomobject]@{ Status = 'Running'; StartType = 'Automatic' }
                }
                else {
                    [pscustomobject]@{ Status = 'Running'; StartType = 'Manual' }
                }
            }
            Mock Get-AppxPackage { $null }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[!\]'
            ($out | Out-String) | Should -Match 'not installed or registered'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }

        It "Returns 1 with [!] output when the licensing cache file is empty" {
            function Get-Service { param([string]$Name) }
            function Get-AppxPackage { }
            Mock Test-Path { $true }
            Mock Get-Item { [pscustomobject]@{ Length = 0 } }
            Mock Get-Service {
                if ($Name -eq 'ClipSVC') {
                    [pscustomobject]@{ Status = 'Running'; StartType = 'Automatic' }
                }
                else {
                    [pscustomobject]@{ Status = 'Running'; StartType = 'Manual' }
                }
            }
            Mock Get-AppxPackage { [pscustomobject]@{ Name = 'Microsoft.WindowsStore' } }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[!\]'
            ($out | Out-String) | Should -Match 'empty or corrupted'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }

        It "Returns 1 with [!] output when Windows Update service is disabled" {
            function Get-Service { param([string]$Name) }
            function Get-AppxPackage { }
            Mock Get-Service {
                if ($Name -eq 'ClipSVC') {
                    [pscustomobject]@{ Status = 'Running'; StartType = 'Automatic' }
                }
                else {
                    [pscustomobject]@{ Status = 'Stopped'; StartType = 'Disabled' }
                }
            }
            Mock Get-AppxPackage { [pscustomobject]@{ Name = 'Microsoft.WindowsStore' } }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[!\]'
            ($out | Out-String) | Should -Match 'Windows Update service is disabled'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }
    }
}
