#Requires -Modules Pester

Describe "Test-WingetTeamViewerFull" {
    BeforeAll {
        # Mirrored layout: walk up from Tests/... to the repo root, then across to scripts/.
        $repoRoot = $PSScriptRoot
        while (-not (Test-Path (Join-Path $repoRoot '.git'))) { $repoRoot = Split-Path $repoRoot -Parent }
        $scriptRelPath = 'scripts/endpoints/remediation/winget/remote-access/TeamViewerFull/Test-WingetTeamViewerFull.ps1'
        $scriptPath = Join-Path $repoRoot $scriptRelPath

        # Safe: the script's top-level guard skips Main when dot-sourced.
        . $scriptPath

        # NEVER Mock Get-Command or unfiltered Get-Module - Pester needs them internally.
        # Module-cmdlet stubs are declared per-It so tests that need
        # the genuine CLI-fallback path stay stub-free.
        Mock Test-Connection { $true }
        Mock Import-Module { }
        Mock Start-Sleep { }
    }

    Context "Help & Metadata" {
        It "Declares required .NOTES fields with Version 1.0.0 and Date 2026-08-23" {
            $raw = Get-Content -Path $scriptPath -Raw
            $raw | Should -Match 'File Name:\s*Test-WingetTeamViewerFull\.ps1'
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
        It "Returns 1 with [!] output when an update is available via the module path" {
            function Get-WinGetPackage { }
            $wingetModuleStub = [pscustomobject] @{ Name = 'Microsoft.WinGet.Client' }
            Mock Get-Module { $wingetModuleStub } `
                -ParameterFilter { $ListAvailable -and $Name -eq 'Microsoft.WinGet.Client' }
            Mock Invoke-WingetWithRetry { throw "unexpected winget.exe CLI call" }
            Mock Get-WinGetPackage {
                [pscustomobject] @{
                    Name              = 'TeamViewer Full'
                    InstalledVersion  = '14.0.0'
                    AvailableVersions = @('14.0.0', '15.0.0')
                    IsUpdateAvailable = $true
                }
            }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[!\]'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
            Should -Invoke Invoke-WingetWithRetry -Times 0 -Exactly -Because "module path should be used"
        }

        It "Is idempotent: up-to-date package returns 0 compliant with no remediation trigger" {
            function Get-WinGetPackage { }
            $wingetModuleStub = [pscustomobject] @{ Name = 'Microsoft.WinGet.Client' }
            Mock Get-Module { $wingetModuleStub } `
                -ParameterFilter { $ListAvailable -and $Name -eq 'Microsoft.WinGet.Client' }
            Mock Invoke-WingetWithRetry { throw "unexpected winget.exe CLI call" }
            Mock Get-WinGetPackage {
                [pscustomobject] @{
                    Name              = 'TeamViewer Full'
                    InstalledVersion  = '15.0.0'
                    AvailableVersions = @('15.0.0')
                    IsUpdateAvailable = $false
                }
            }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[\+\]'
            $out | Where-Object { $_ -is [int] } | Should -Be 0
        }

        It "Returns 0 when the package is not installed (module path)" {
            function Get-WinGetPackage { }
            $wingetModuleStub = [pscustomobject] @{ Name = 'Microsoft.WinGet.Client' }
            Mock Get-Module { $wingetModuleStub } `
                -ParameterFilter { $ListAvailable -and $Name -eq 'Microsoft.WinGet.Client' }
            Mock Invoke-WingetWithRetry { throw "unexpected winget.exe CLI call" }
            Mock Get-WinGetPackage { $null }
            Main *>&1 | Where-Object { $_ -is [int] } | Should -Be 0
        }

        It "Returns 0 with a [!] warning when offline (fail-safe compliance)" {
            Mock Test-Connection { $false }
            Mock Invoke-WingetWithRetry { throw "unexpected winget.exe CLI call" }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[!\]'
            $out | Where-Object { $_ -is [int] } | Should -Be 0
        }

        It "Uses the CLI fallback and reports not installed as compliant (exit 0)" {
            # No module-cmdlet stubs here so Main exercises the real winget.exe CLI fallback path.
            Mock Invoke-WingetWithRetry { "No installed package found matching input criteria" }
            $out = Main *>&1
            $out | Where-Object { $_ -is [int] } | Should -Be 0
            Should -Invoke Invoke-WingetWithRetry -Times 1 -Exactly
        }

        It "Uses the CLI fallback to report an available update as non-compliant (exit 1)" {
            Mock Invoke-WingetWithRetry {
                @(
                    'Name                Version Available'
                    '-------------------- ------- ---------'
                    "$($ID) 14.0.0    15.0.0"
                ) -join "`n"
            }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[!\]'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }

        It "Reports [-] prefixed failure but stays compliant (exit 0) on upstream errors" {
            function Get-WinGetPackage { }
            $wingetModuleStub = [pscustomobject] @{ Name = 'Microsoft.WinGet.Client' }
            Mock Get-Module { $wingetModuleStub } `
                -ParameterFilter { $ListAvailable -and $Name -eq 'Microsoft.WinGet.Client' }
            Mock Invoke-WingetWithRetry { throw "unexpected winget.exe CLI call" }
            Mock Get-WinGetPackage { throw "winget exploded" }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[-\]'
            $out | Where-Object { $_ -is [int] } | Should -Be 0
        }
    }
}
