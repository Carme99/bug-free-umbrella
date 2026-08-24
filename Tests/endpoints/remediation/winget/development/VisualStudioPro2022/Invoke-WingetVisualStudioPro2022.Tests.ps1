#Requires -Modules Pester

Describe "Invoke-WingetVisualStudioPro2022" {
    BeforeAll {
        # Mirrored layout: walk up from Tests/... to the repo root, then across to scripts/.
        $repoRoot = $PSScriptRoot
        while (-not (Test-Path (Join-Path $repoRoot '.git'))) { $repoRoot = Split-Path $repoRoot -Parent }
        $scriptRelPath = 'scripts/endpoints/remediation/winget/development' +
            '/VisualStudioPro2022/Invoke-WingetVisualStudioPro2022.ps1'
        $scriptPath = Join-Path $repoRoot $scriptRelPath

        # Safe: the script's top-level guard skips Main when dot-sourced.
        . $scriptPath

        # NEVER Mock Get-Command or unfiltered Get-Module - Pester needs them internally.
        # Module-cmdlet stubs are declared per-It (see Add-WinGetStubs) so tests that need
        # the genuine CLI-fallback path stay stub-free.
        Mock Import-Module { }
        Mock Start-Sleep { }
    }


    Context "Help & Metadata" {
        It "Declares required .NOTES fields with Version 1.0.0 and Date 2026-08-23" {
            $raw = Get-Content -Path $scriptPath -Raw
            $raw | Should -Match 'File Name:\s*Invoke-WingetVisualStudioPro2022\.ps1'
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
        It "Gates mutation behind ShouldProcess (SupportsShouldProcess declared)" {
            $raw = Get-Content -Path $scriptPath -Raw
            $raw | Should -Match 'SupportsShouldProcess'
            $raw | Should -Match 'ShouldProcess\('
        }
    }

    Context "Behavior" {
        It "Is idempotent: already-up-to-date package returns 0 with no update call" {
            # Stub module surface inline so Pester can Mock these commands.
            function Get-WinGetPackage { }
            function Update-WinGetPackage { }
            Mock Update-WinGetPackage { }
            $wingetModuleStub = [pscustomobject] @{ Name = 'Microsoft.WinGet.Client' }
            Mock Get-Module { $wingetModuleStub } `
                -ParameterFilter { $ListAvailable -and $Name -eq 'Microsoft.WinGet.Client' }
            Mock Invoke-WingetWithRetry { throw "unexpected winget.exe CLI call" }
            Mock Get-Process { $null }
            Mock Get-WinGetPackage {
                [pscustomobject] @{
                    Name                 = 'Visual Studio Professional 2019'
                    InstalledVersion     = '1.93.0'
                    AvailableVersions    = @('1.93.0')
                    IsUpdateAvailable    = $false
                }
            }
            Main *>&1 | Where-Object { $_ -is [int] } | Should -Be 0
            Should -Invoke Update-WinGetPackage -Times 0 -Exactly -Because "nothing to update"
        }

        It "Updates and returns 0 when an update is available and app is not running" {
            # Stub module surface inline so Pester can Mock these commands.
            function Get-WinGetPackage { }
            function Update-WinGetPackage { }
            Mock Update-WinGetPackage { }
            $wingetModuleStub = [pscustomobject] @{ Name = 'Microsoft.WinGet.Client' }
            Mock Get-Module { $wingetModuleStub } `
                -ParameterFilter { $ListAvailable -and $Name -eq 'Microsoft.WinGet.Client' }
            Mock Invoke-WingetWithRetry { throw "unexpected winget.exe CLI call" }
            Mock Get-Process { $null }
            $script:calls = 0
            Mock Get-WinGetPackage {
                $script:calls++
                if ($script:calls -eq 1) {
                    [pscustomobject] @{
                        Name                 = 'Visual Studio Professional 2019'
                        InstalledVersion     = '1.92.0'
                        AvailableVersions    = @('1.92.0', '1.93.0')
                        IsUpdateAvailable    = $true
                    }
                }
                else {
                    [pscustomobject] @{
                        Name                 = 'Visual Studio Professional 2019'
                        InstalledVersion     = '1.93.0'
                        AvailableVersions    = @('1.93.0')
                        IsUpdateAvailable    = $false
                    }
                }
            }
            $out = Main *>&1
            $out | Where-Object { $_ -is [int] } | Should -Be 0
            Should -Invoke Update-WinGetPackage -Times 1 -Exactly
        }

        It "Defers with exit 1 when the app process is running" {
            # Stub module surface inline so Pester can Mock these commands.
            function Get-WinGetPackage { }
            function Update-WinGetPackage { }
            Mock Update-WinGetPackage { }
            $wingetModuleStub = [pscustomobject] @{ Name = 'Microsoft.WinGet.Client' }
            Mock Get-Module { $wingetModuleStub } `
                -ParameterFilter { $ListAvailable -and $Name -eq 'Microsoft.WinGet.Client' }
            Mock Invoke-WingetWithRetry { throw "unexpected winget.exe CLI call" }
            Mock Get-WinGetPackage {
                [pscustomobject] @{
                    Name                 = 'Visual Studio Professional 2019'
                    InstalledVersion     = '1.92.0'
                    AvailableVersions    = @('1.92.0', '1.93.0')
                    IsUpdateAvailable    = $true
                }
            }
            Mock Get-Process { [pscustomobject] @{ ProcessName = 'VisualStudio' } }
            Main *>&1 | Where-Object { $_ -is [int] } | Should -Be 1
            Should -Invoke Update-WinGetPackage -Times 0 -Exactly
        }

        It "Returns 1 with [-] prefixed output when verification fails after update" {
            # Stub module surface inline so Pester can Mock these commands.
            function Get-WinGetPackage { }
            function Update-WinGetPackage { }
            Mock Update-WinGetPackage { }
            $wingetModuleStub = [pscustomobject] @{ Name = 'Microsoft.WinGet.Client' }
            Mock Get-Module { $wingetModuleStub } `
                -ParameterFilter { $ListAvailable -and $Name -eq 'Microsoft.WinGet.Client' }
            Mock Invoke-WingetWithRetry { throw "unexpected winget.exe CLI call" }
            Mock Get-Process { $null }
            Mock Get-WinGetPackage {
                [pscustomobject] @{
                    Name                 = 'Visual Studio Professional 2019'
                    InstalledVersion     = '1.92.0'
                    AvailableVersions    = @('1.92.0', '1.93.0')
                    IsUpdateAvailable    = $true
                }
            }
            Mock Update-WinGetPackage { throw "update failed" }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[-\]'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }
    }
}
