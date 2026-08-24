#Requires -Modules Pester

Describe "Invoke-RemediationCheckLocalAdminAccounts" {
    BeforeAll {
        # Mirrored layout: walk up from Tests/... to the repo root, then across to scripts/.
        $repoRoot = $PSScriptRoot
        while (-not (Test-Path (Join-Path $repoRoot '.git'))) { $repoRoot = Split-Path $repoRoot -Parent }
        $scriptRelPath = 'scripts/endpoints/remediation/security/Invoke-RemediationCheckLocalAdminAccounts.ps1'
        $scriptPath = Join-Path $repoRoot $scriptRelPath

        # Safe: the script's top-level guard skips Main when dot-sourced.
        . $scriptPath
    }

    Context "Help & Metadata" {
        It "Declares required .NOTES fields with Version 1.0.0 and Date 2026-08-23" {
            $raw = Get-Content -Path $scriptPath -Raw
            $raw | Should -Match 'File Name:\s*Invoke-RemediationCheckLocalAdminAccounts\.ps1'
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
        It "Contains no PS7-only operators (no #Requires -Version 7.0 opt-out present)" {
            $raw = Get-Content -Path $scriptPath -Raw
            $raw | Should -Not -Match '(?m)&&|\|\||\?\?|\?\?='
            $raw | Should -Not -Match '\$\w+\s*\?\s*[^:]'
        }
    }

    Context "Behavior" {
        It "Returns 0 and does not disable anything when the Administrator account is already disabled" {
            function Get-LocalUser { }
            function Disable-LocalUser { }
            Mock Get-LocalUser { [pscustomobject]@{ Name = 'Administrator'; Enabled = $false } }
            Mock Disable-LocalUser { }
            $out = Main *>&1
            ($out | Out-String) | Should -Match 'No automatic remediation performed'
            $out | Where-Object { $_ -is [int] } | Should -Be 0
            Should -Invoke Disable-LocalUser -Exactly 0 -Scope It
        }

        It "Disables an enabled built-in Administrator account and returns 0" {
            function Get-LocalUser { }
            function Disable-LocalUser { }
            Mock Get-LocalUser { [pscustomobject]@{ Name = 'Administrator'; Enabled = $true } }
            Mock Disable-LocalUser { }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[\+\]'
            ($out | Out-String) | Should -Match 'Disabled built-in Administrator account'
            $out | Where-Object { $_ -is [int] } | Should -Be 0
            Should -Invoke Disable-LocalUser -Exactly 1 -Scope It
        }

        It "Warns but still returns 0 when the disable action fails" {
            function Get-LocalUser { }
            function Disable-LocalUser { }
            Mock Get-LocalUser { [pscustomobject]@{ Name = 'Administrator'; Enabled = $true } }
            Mock Disable-LocalUser { throw 'Access denied' }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[!\]'
            $out | Where-Object { $_ -is [int] } | Should -Be 0
        }

        It "Is idempotent: a missing Administrator account performs no remediation and returns 0" {
            function Get-LocalUser { }
            function Disable-LocalUser { }
            Mock Get-LocalUser { $null }
            Mock Disable-LocalUser { }
            $out = Main *>&1
            $out | Where-Object { $_ -is [int] } | Should -Be 0
            Should -Invoke Disable-LocalUser -Exactly 0 -Scope It
        }
    }
}
