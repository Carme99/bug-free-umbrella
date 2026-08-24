#Requires -Modules Pester

Describe "Invoke-RemediationFixCertificateExpiry" {
    BeforeAll {
        # Mirrored layout: walk up from Tests/... to the repo root, then across to scripts/.
        $repoRoot = $PSScriptRoot
        while (-not (Test-Path (Join-Path $repoRoot '.git'))) { $repoRoot = Split-Path $repoRoot -Parent }
        $scriptRelPath = 'scripts/endpoints/remediation/security/Invoke-RemediationFixCertificateExpiry.ps1'
        $scriptPath = Join-Path $repoRoot $scriptRelPath

        # Safe: the script's top-level guard skips Main when dot-sourced.
        . $scriptPath
    }

    Context "Help & Metadata" {
        It "Declares required .NOTES fields with Version 1.0.0 and Date 2026-08-23" {
            $raw = Get-Content -Path $scriptPath -Raw
            $raw | Should -Match 'File Name:\s*Invoke-RemediationFixCertificateExpiry\.ps1'
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
        It "Uses SupportsShouldProcess and routes reg.exe through a wrapper" {
            $raw = Get-Content -Path $scriptPath -Raw
            $raw | Should -Match '\[CmdletBinding\(SupportsShouldProcess\)\]'
            $raw | Should -Match '\$PSCmdlet\.ShouldProcess\('
            # reg.exe is only invoked inside the thin wrapper function.
            ($raw -split "`n" | Where-Object { $_ -match '& reg\.exe' }).Count | Should -Be 1
        }
    }

    Context "Behavior" {
        BeforeAll {

        # Stub externals so Pester Mock can bind them offline.
        function Get-CimInstance { }
        }

        It "Is idempotent: no profiles and no cert stores returns 0 without removals" {
            Mock Get-CimInstance { @() }
            Mock Test-Path { $false }
            Mock Remove-Item { }

            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[\+\]'
            $out | Where-Object { $_ -is [int] } | Should -Be 0
            Should -Invoke Remove-Item -Exactly 0 -Scope It
        }

        It "Removes an expired certificate from the LocalMachine store" {
            Mock Test-Path { $true }
            Mock Get-CimInstance { @() }
            Mock Get-ChildItem {
                param($Path)
                if ($Path -eq 'Cert:\LocalMachine\My') {
                    @([pscustomobject]@{
                        Thumbprint = 'ABCD1234EXPIRED'
                        Subject = 'CN=Old Cert'
                        NotAfter = (Get-Date).AddDays(-5)
                        PSPath = 'Cert:\LocalMachine\My\ABCD1234EXPIRED'
                    })
                }
                else { @() }
            }
            Mock Remove-Item { }
            Mock Get-ItemProperty { $null }

            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[\+\]'
            ($out | Out-String) | Should -Match 'CN=Old Cert'
            $out | Where-Object { $_ -is [int] } | Should -Be 0
            Should -Invoke Remove-Item -Exactly 1 -Scope It
        }

        It "Keeps valid (unexpired) certificates untouched" {
            Mock Test-Path { $true }
            Mock Get-CimInstance { @() }
            Mock Get-ChildItem {
                param($Path)
                if ($Path -eq 'Cert:\LocalMachine\My') {
                    @([pscustomobject]@{
                        Thumbprint = 'GOOD1234'
                        Subject = 'CN=Valid Cert'
                        NotAfter = (Get-Date).AddYears(2)
                        PSPath = 'Cert:\LocalMachine\My\GOOD1234'
                    })
                }
                else { @() }
            }
            Mock Remove-Item { }
            Mock Get-ItemProperty { $null }

            $out = Main *>&1
            $out | Where-Object { $_ -is [int] } | Should -Be 0
            Should -Invoke Remove-Item -Exactly 0 -Scope It
        }

        It "Returns 1 with [-] output when profile enumeration fails" {
            Mock Test-Path { $false }
            Mock Get-CimInstance { throw 'WMI unavailable' }
            Mock Remove-Item { }

            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[-\]'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }
    }
}
