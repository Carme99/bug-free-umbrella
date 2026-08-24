#Requires -Modules Pester

Describe "Test-RemediationCheckLocalAdminAccounts" {
    BeforeAll {
        # Mirrored layout: walk up from Tests/... to the repo root, then across to scripts/.
        $repoRoot = $PSScriptRoot
        while (-not (Test-Path (Join-Path $repoRoot '.git'))) { $repoRoot = Split-Path $repoRoot -Parent }
        $scriptRelPath = 'scripts/endpoints/remediation/security/Test-RemediationCheckLocalAdminAccounts.ps1'
        $scriptPath = Join-Path $repoRoot $scriptRelPath

        # Safe: the script's top-level guard skips Main when dot-sourced.
        . $scriptPath
    }

    Context "Help & Metadata" {
        It "Declares required .NOTES fields with Version 1.0.0 and Date 2026-08-23" {
            $raw = Get-Content -Path $scriptPath -Raw
            $raw | Should -Match 'File Name:\s*Test-RemediationCheckLocalAdminAccounts\.ps1'
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
        It "Is a read-only detection script (plain CmdletBinding)" {
            $raw = Get-Content -Path $scriptPath -Raw
            $raw | Should -Match '\[CmdletBinding\(\)\]'
            $raw | Should -Not -Match 'SupportsShouldProcess'
        }
    }

    Context "Behavior" {
        BeforeAll {

        # Stub externals so Pester Mock can bind them offline.
        function Get-LocalGroup { }
        function Get-LocalGroupMember { }
        function Get-LocalUser { }
        }

        It "Returns 0 with [+] output when only approved admins are present (idempotent)" {
            Mock Get-LocalGroup { [pscustomobject]@{ Name = 'Administrators' } }
            Mock Get-LocalGroupMember {
                @(
                    [pscustomobject]@{ Name = 'CONTOSO\Administrator'; PrincipalSource = 'Active Directory' },
                    [pscustomobject]@{ Name = 'AzureAD\JackCloud'; PrincipalSource = 'AzureAD' }
                )
            }
            Mock Get-LocalUser { [pscustomobject]@{ Name = 'Administrator'; Enabled = $false } }

            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[\+\]'
            $out | Where-Object { $_ -is [int] } | Should -Be 0
        }

        It "Returns 1 with [!] output listing unauthorized admin accounts" {
            Mock Get-LocalGroup { [pscustomobject]@{ Name = 'Administrators' } }
            Mock Get-LocalGroupMember {
                @(
                    [pscustomobject]@{ Name = 'CONTOSO\Administrator'; PrincipalSource = 'Active Directory' },
                    [pscustomobject]@{ Name = 'CONTOSO\eve'; PrincipalSource = 'Local' }
                )
            }
            Mock Get-LocalUser { [pscustomobject]@{ Name = 'Administrator'; Enabled = $false } }

            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[!\]'
            ($out | Out-String) | Should -Match 'eve'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }

        It "Returns 1 when the built-in Administrator account is enabled" {
            Mock Get-LocalGroup { [pscustomobject]@{ Name = 'Administrators' } }
            Mock Get-LocalGroupMember {
                @([pscustomobject]@{ Name = 'CONTOSO\Administrator'; PrincipalSource = 'Active Directory' })
            }
            Mock Get-LocalUser { [pscustomobject]@{ Name = 'Administrator'; Enabled = $true } }

            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[!\]'
            ($out | Out-String) | Should -Match 'Built-in Administrator account is enabled'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }

        It "Returns 1 with [-] output when group enumeration fails" {
            Mock Get-LocalGroup { throw 'Access denied' }

            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[-\]'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }
    }
}
