#Requires -Modules Pester

Describe "Test-RemediationRegionLanguageSettings" {
    BeforeAll {
        # Mirrored layout: walk up from Tests/... to the repo root, then across to scripts/.
        $repoRoot = $PSScriptRoot
        while (-not (Test-Path (Join-Path $repoRoot '.git'))) { $repoRoot = Split-Path $repoRoot -Parent }
        $scriptPath = Join-Path $repoRoot `
            'scripts/endpoints/remediation/system/Test-RemediationRegionLanguageSettings.ps1'

        # Safe: the script's top-level guard skips Main when dot-sourced.
        . $scriptPath
    }

    Context "Help & Metadata" {
        It "Declares required .NOTES fields with Version 1.0.0 and Date 2026-08-23" {
            $raw = Get-Content -Path $scriptPath -Raw
            $raw | Should -Match 'File Name:\s*Test-RemediationRegionLanguageSettings\.ps1'
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
        It "Returns 0 when all regional settings match UK standards" {
            function Get-WinHomeLocation { }
            function Get-WinSystemLocale { }
            function Get-WinUserLanguageList { }
            Mock Get-Culture { [pscustomobject]@{ Name = 'en-GB' } }
            Mock Get-WinHomeLocation { [pscustomobject]@{ GeoId = 242 } }
            Mock Get-TimeZone { [pscustomobject]@{ Id = 'GMT Standard Time' } }
            Mock Get-WinSystemLocale { [pscustomobject]@{ Name = 'en-GB' } }
            Mock Get-WinUserLanguageList { @([pscustomobject]@{ LanguageTag = 'en-GB' }) }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[\+\]'
            ($out | Out-String) | Should -Match 'compliant'
            $out | Where-Object { $_ -is [int] } | Should -Be 0
        }

        It "Returns 1 and lists every deviation when settings do not match" {
            function Get-WinHomeLocation { }
            function Get-WinSystemLocale { }
            function Get-WinUserLanguageList { }
            Mock Get-Culture { [pscustomobject]@{ Name = 'en-US' } }
            Mock Get-WinHomeLocation { [pscustomobject]@{ GeoId = 244 } }
            Mock Get-TimeZone { [pscustomobject]@{ Id = 'Pacific Standard Time' } }
            Mock Get-WinSystemLocale { [pscustomobject]@{ Name = 'de-DE' } }
            Mock Get-WinUserLanguageList { @([pscustomobject]@{ LanguageTag = 'en-US' }) }
            $out = Main *>&1
            $text = $out | Out-String
            $text | Should -Match '\[!\]'
            $fragments = @(
                'Culture: en-US',
                'Geographic Location: 244',
                'Time Zone:',
                'System Locale: de-DE',
                'Primary Language: en-US'
            )
            foreach ($fragment in $fragments) {
                $text | Should -Match ([regex]::Escape($fragment))
            }
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }

        It "Returns 1 when only the primary user language deviates" {
            function Get-WinHomeLocation { }
            function Get-WinSystemLocale { }
            function Get-WinUserLanguageList { }
            Mock Get-Culture { [pscustomobject]@{ Name = 'en-GB' } }
            Mock Get-WinHomeLocation { [pscustomobject]@{ GeoId = 242 } }
            Mock Get-TimeZone { [pscustomobject]@{ Id = 'GMT Standard Time' } }
            Mock Get-WinSystemLocale { [pscustomobject]@{ Name = 'en-GB' } }
            Mock Get-WinUserLanguageList { @([pscustomobject]@{ LanguageTag = 'en-AU' }) }
            $out = Main *>&1
            ($out | Out-String) | Should -Match 'Primary Language: en-AU'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }

        It "Returns 1 with [-] prefixed output when a settings query fails" {
            function Get-WinHomeLocation { }
            Mock Get-Culture { throw "culture query failed" }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[-\]'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }
    }
}
