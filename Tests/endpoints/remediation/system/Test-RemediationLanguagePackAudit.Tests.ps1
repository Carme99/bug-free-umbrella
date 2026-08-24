#Requires -Modules Pester

Describe "Test-RemediationLanguagePackAudit" {
    BeforeAll {
        # Mirrored layout: walk up from Tests/... to the repo root, then across to scripts/.
        $repoRoot = $PSScriptRoot
        while (-not (Test-Path (Join-Path $repoRoot '.git'))) { $repoRoot = Split-Path $repoRoot -Parent }
        $scriptPath = Join-Path $repoRoot `
            'scripts/endpoints/remediation/system/Test-RemediationLanguagePackAudit.ps1'

        # Safe: the script's top-level guard skips Main when dot-sourced.
        . $scriptPath
    }

    Context "Help & Metadata" {
        It "Declares required .NOTES fields with Version 1.0.0 and Date 2026-08-23" {
            $raw = Get-Content -Path $scriptPath -Raw
            $raw | Should -Match 'File Name:\s*Test-RemediationLanguagePackAudit\.ps1'
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
            if ($null -eq $ast.ParamBlock) {
                $declared = @()
            }
            else {
                $declared = @($ast.ParamBlock.Parameters.Name.VariableText)
            }
            $raw = Get-Content -Path $scriptPath -Raw
            $documented = @([regex]::Matches($raw, '(?m)^\s*\.PARAMETER\s+(\S+)') |
                    ForEach-Object { $_.Groups[1].Value })
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
        It "Returns 0 when only allowed language packs are installed" {
            function Get-WindowsPackage { }
            function Get-WinSystemLocale { }
            $pkgBase = 'Microsoft-Windows-Client-LanguagePack-Package~31bf3856ad364e35~amd64~~'
            Mock Get-WindowsPackage {
                @(
                    [pscustomobject]@{ PackageName = "${pkgBase}en-GB~" },
                    [pscustomobject]@{ PackageName = "${pkgBase}en-US~" }
                )
            }
            Mock Get-WinSystemLocale { [pscustomobject]@{ Name = 'en-GB' } }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[\+\]'
            $out | Where-Object { $_ -is [int] } | Should -Be 0
        }

        It "Returns 0 when no language packs are found via DISM" {
            function Get-WindowsPackage { }
            function Get-WinSystemLocale { }
            Mock Get-WindowsPackage { $null }
            Mock Get-WinSystemLocale { [pscustomobject]@{ Name = 'en-GB' } }
            $out = Main *>&1
            ($out | Out-String) | Should -Match 'No installed language packs'
            $out | Where-Object { $_ -is [int] } | Should -Be 0
        }

        It "Returns 1 and names the packs when an unnecessary language pack is installed" {
            function Get-WindowsPackage { }
            function Get-WinSystemLocale { }
            $pkgBase = 'Microsoft-Windows-Client-LanguagePack-Package~31bf3856ad364e35~amd64~~'
            Mock Get-WindowsPackage {
                @(
                    [pscustomobject]@{ PackageName = "${pkgBase}en-GB~" },
                    [pscustomobject]@{ PackageName = "${pkgBase}ja-JP~" }
                )
            }
            Mock Get-WinSystemLocale { [pscustomobject]@{ Name = 'en-GB' } }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[!\]'
            ($out | Out-String) | Should -Match 'ja-JP'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }

        It "Returns 1 when the system locale is not en-GB or en-US" {
            function Get-WindowsPackage { }
            function Get-WinSystemLocale { }
            $pkgBase = 'Microsoft-Windows-Client-LanguagePack-Package~31bf3856ad364e35~amd64~~'
            Mock Get-WindowsPackage {
                @([pscustomobject]@{ PackageName = "${pkgBase}en-GB~" })
            }
            Mock Get-WinSystemLocale { [pscustomobject]@{ Name = 'fr-FR' } }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[!\]'
            ($out | Out-String) | Should -Match 'System locale is fr-FR'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }

        It "Returns 1 with [-] prefixed output when the DISM enumeration fails" {
            function Get-WindowsPackage { }
            function Get-WinSystemLocale { }
            Mock Get-WindowsPackage { throw "dism error 0x800f081f" }
            Mock Get-WinSystemLocale { [pscustomobject]@{ Name = 'en-GB' } }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[-\]'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }
    }
}
