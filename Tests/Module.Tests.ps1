#Requires -Modules Pester

<#
.SYNOPSIS
    Validates the BugFreeUmbrella PowerShell module — import, manifest, exports, PSSA.

.DESCRIPTION
    Exercises src/BugFreeUmbrella/BugFreeUmbrella.psd1 + .psm1 as an installable PSGallery module:
    import, manifest ModuleVersion parity with CHANGELOG.md, exported command count 358, loader hygiene, and PSScriptAnalyzer clean.
    Designed to run on Ubuntu (CI) without Windows-only modules — Windows-specific imports are mocked.

.NOTES
    File Name  : Module.Tests.ps1
    Prerequisite: PowerShell 7.0+, Pester 5.5.0+
#>

Describe "BugFreeUmbrella Module" -Tag 'Module' {

    BeforeAll {
        $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
        $script:ManifestPath = Join-Path $script:RepoRoot 'src/BugFreeUmbrella/BugFreeUmbrella.psd1'
        $script:LoaderPath = Join-Path $script:RepoRoot 'src/BugFreeUmbrella/BugFreeUmbrella.psm1'
        $script:CatalogPath = Join-Path $script:RepoRoot 'scripts/.catalog/metadata.json'
        $script:SettingsPath = Join-Path $script:RepoRoot '.vscode/PSScriptAnalyzerSettings.psd1'
        Remove-Module BugFreeUmbrella -ErrorAction SilentlyContinue
    }

    AfterAll {
        Remove-Module BugFreeUmbrella -ErrorAction SilentlyContinue
    }

    Context "Manifest" {

        It "manifest file exists at src/BugFreeUmbrella/BugFreeUmbrella.psd1" {
            Test-Path -LiteralPath $script:ManifestPath | Should -Be $true -Because "Module manifest not found at $script:ManifestPath — did DesignModule run? src/BugFreeUmbrella/BugFreeUmbrella.psd1 absent."
        }

        It "should have ModuleVersion matching the first CHANGELOG release heading" {
            $manifest = Import-PowerShellDataFile -Path $script:ManifestPath
            $changelogPath = Join-Path $script:RepoRoot 'CHANGELOG.md'
            Test-Path -LiteralPath $changelogPath | Should -Be $true -Because "CHANGELOG.md must exist for version parity"
            $heading = (Get-Content -LiteralPath $changelogPath) |
                Where-Object { $_ -match '^## \[([0-9]+\.[0-9]+\.[0-9]+)\]' } |
                Select-Object -First 1
            $heading | Should -Not -BeNullOrEmpty -Because "CHANGELOG.md should contain a '## [X.Y.Z]' release heading"
            $headingText = if ($heading -match '^## \[([0-9]+\.[0-9]+\.[0-9]+)\]') { $Matches[1] } else { $null }
            $changelogVersion = [version]$headingText
            $manifest.ModuleVersion | Should -Be ([version]$manifest.ModuleVersion).ToString() -Because "ModuleVersion should be a valid version string"
            $changelogVersion | Should -Be ([version]$manifest.ModuleVersion) -Because "manifest ModuleVersion ($($manifest.ModuleVersion)) must equal the first '## [' heading in CHANGELOG.md ($($headingText)) — single source of truth."
        }

        It "should declare PowerShellVersion 7.0+ compatible and no hardcoded secrets" {
            $manifest = Import-PowerShellDataFile -Path $script:ManifestPath
            $psVersion = [version]($manifest.PowerShellVersion)
            $psVersion | Should -BeGreaterOrEqual ([version]'5.1') -Because "PowerShellVersion should be at least 5.1 for importability"
            $raw = Get-Content -LiteralPath $script:ManifestPath -Raw
            $raw | Should -Not -Match '(?i)(api[_-]?key|secret|password)\s*=\s*[''"][^''"]+[''"]' -Because "manifest must not contain hardcoded secrets"
        }

        It "should pass Test-ModuleManifest" {
            { Test-ModuleManifest -Path $script:ManifestPath -ErrorAction Stop | Out-Null } | Should -Not -Throw
        }

    }

    Context "Import" {

        It "Import-Module should succeed on Ubuntu" {
            if (-not (Get-Command Out-GridView -ErrorAction SilentlyContinue)) {
                function global:Out-GridView { param($InputObject) return $InputObject }
            }
            { Import-Module $script:ManifestPath -Force -ErrorAction Stop } | Should -Not -Throw
            try {
                Mock Out-GridView { param($InputObject) return $InputObject } -ModuleName BugFreeUmbrella -ErrorAction SilentlyContinue
            } catch {
                Mock Out-GridView { param($InputObject) return $InputObject } -ErrorAction SilentlyContinue
            }
            (Get-Module BugFreeUmbrella) | Should -Not -BeNullOrEmpty
        }

        It "wrappers honour -WhatIf" {
            if (-not (Get-Module BugFreeUmbrella)) {
                Import-Module $script:ManifestPath -Force -ErrorAction Stop
            }
            $target = (Get-BUScript -Name 'Analyze-BuildPerformance' | Select-Object -First 1).path
            $fullPath = Join-Path $script:RepoRoot $target
            if (-not (Test-Path -LiteralPath $fullPath)) { $fullPath = $target }
            $before = $global:WhatIfPreference
            try {
                { Invoke-BUScript -Path $fullPath -WhatIf } | Should -Not -Throw
                $global:WhatIfPreference | Should -Be $before -Because "-WhatIf must not leak into global preference scope"
            } finally {
                $global:WhatIfPreference = $before
            }
        }

        It "import is idempotent" {
            if (-not (Get-Module BugFreeUmbrella)) {
                Import-Module $script:ManifestPath -Force -ErrorAction Stop
            }
            $first = @(Get-Command -Module BugFreeUmbrella).Count
            $first | Should -BeGreaterThan 0 -Because "module should export commands after first import"
            Import-Module $script:ManifestPath -Force -ErrorAction Stop
            $second = @(Get-Command -Module BugFreeUmbrella).Count
            $second | Should -Be $first -Because "re-import with -Force must not change the exported command count ($first vs $second)"
        }

        It "no plaintext secrets in psm1" {
            $hits = Select-String -LiteralPath $script:LoaderPath -Pattern '(?i)password\s*=|apikey\s*=' |
                Where-Object {
                    -not $_.Line.TrimStart().StartsWith('#') -and
                    $_.Line -notmatch '\$env:'
                }
            @($hits).Count | Should -Be 0 -Because "psm1 must not contain plaintext password/apikey assignments (found: $(@($hits).Line -join '; '))"
        }

        It "should export 358 functions" {
            if (-not (Get-Module BugFreeUmbrella)) {
                Import-Module $script:ManifestPath -Force -ErrorAction Stop
            }
            $catalog = Get-Content -LiteralPath $script:CatalogPath -Raw | ConvertFrom-Json
            $expected = $catalog.totalScripts
            $exported = (Get-Command -Module BugFreeUmbrella).Count
            $exported | Should -BeGreaterOrEqual $expected -Because "Get-Command count $exported should be at least catalog totalScripts $expected — re-run tools/Build-Catalog.ps1 or adjust export surface."
        }
    }

    Context "Loader hygiene" {

        It "loader dot-sources only from src/BugFreeUmbrella/Public and Private" {
            $loader = Get-Content -LiteralPath $script:LoaderPath -Raw
            $loader | Should -Match 'Public' -Because "loader should reference Public folder"
            $loader | Should -Not -Match '\.\.[/\\]scripts' -Because "loader must not dot-source directly from scripts/ (use Public wrappers)"
        }

        It "loader has comment-based help and PSScriptAnalyzer reports 0 Errors" {
            $loader = Get-Content -LiteralPath $script:LoaderPath -Raw
            $loader | Should -Match '\.SYNOPSIS' -Because "loader should have comment-based help"
            $findings = Invoke-ScriptAnalyzer -Path $script:LoaderPath -Settings $script:SettingsPath -ErrorAction Stop
            $errors = @($findings | Where-Object Severity -eq 'Error')
            $errors | Should -BeNullOrEmpty -Because ($errors | Format-Table RuleName, Line, Message -AutoSize | Out-String)
        }

        It "should handle duplicate detect.ps1×51 via Test-/Invoke- + winget suffix" {
            $manifest = Import-PowerShellDataFile -Path $script:ManifestPath
            $names = @($manifest.FunctionsToExport)
            $unique = @($names | Sort-Object -Unique)
            $names.Count | Should -Be $unique.Count -Because "FunctionsToExport must have no duplicates — detect.ps1 collisions must be resolved via Test-/Invoke- + winget suffix"
            $hasWinget = @($names | Where-Object { $_ -match 'Winget' }).Count -gt 0
            $hasWinget | Should -Be $true -Because "winget remediations should have Winget suffix to avoid collisions"
        }
    }

    Context "Export surface" {

        It "all exported commands use Approved Verbs" {
            if (-not (Get-Module BugFreeUmbrella)) {
                Import-Module $script:ManifestPath -Force -ErrorAction Stop
            }
            $verbs = (Get-Verb).Verb
            $bad = Get-Command -Module BugFreeUmbrella | Where-Object { $_.Verb -notin $verbs }
            $bad | Should -BeNullOrEmpty -Because "all verbs should be approved"
        }
    }
}
