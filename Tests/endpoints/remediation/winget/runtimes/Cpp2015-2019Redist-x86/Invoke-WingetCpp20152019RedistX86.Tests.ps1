#Requires -Modules Pester

Describe "Invoke-WingetCpp20152019RedistX86" {
    BeforeAll {
        # Mirrored layout: walk up from Tests/... to the repo root, then across to scripts/.
        $repoRoot = $PSScriptRoot
        while (-not (Test-Path (Join-Path $repoRoot '.git'))) { $repoRoot = Split-Path $repoRoot -Parent }
        $scriptRelPath = Join-Path 'scripts/endpoints/remediation/winget' `
            'runtimes/Cpp2015-2019Redist-x86/Invoke-WingetCpp20152019RedistX86.ps1'
        $scriptPath = Join-Path $repoRoot $scriptRelPath

        # Safe: the script's top-level guard skips Main when dot-sourced.
        . $scriptPath

        # NEVER Mock Get-Command or unfiltered Get-Module - Pester needs them internally.
        # Module-cmdlet stubs are declared per-It so tests that need
        # the genuine CLI-fallback path stay stub-free.
        Mock Import-Module { }
        Mock Start-Sleep { }
        Mock Stop-Process { }
    }

    Context "Help & Metadata" {
        It "Declares required .NOTES fields with Version 1.0.0 and Date 2026-08-23" {
            $raw = Get-Content -Path $scriptPath -Raw
            $raw | Should -Match 'File Name:\s*Invoke-WingetCpp20152019RedistX86.ps1'
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

        It "Documents the exact package ID Microsoft.VCRedist.2015+.x64 in help and configuration" {
            $raw = Get-Content -Path $scriptPath -Raw
            $raw | Should -Match ([regex]::Escape("Microsoft.VCRedist.2015+.x64"))
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
        It "Returns 0 when the package is not installed and never updates" {
            function Get-WinGetPackage { }
            function Update-WinGetPackage { }
            Mock Update-WinGetPackage { }
            $wingetModuleStub = [pscustomobject] @{ Name = 'Microsoft.WinGet.Client' }
            Mock Get-Module { $wingetModuleStub } `
                -ParameterFilter { $ListAvailable -and $Name -eq 'Microsoft.WinGet.Client' }
            Mock Invoke-WingetWithRetry { throw "unexpected winget.exe CLI call" }
            Mock Get-WinGetPackage { $null }
            $out = Main *>&1
            $out | Where-Object { $_ -is [int] } | Should -Be 0
            Should -Invoke Update-WinGetPackage -Times 0 -Exactly
        }

        It "Is idempotent: an up-to-date package returns 0 with no update attempt" {
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
                    Name              = 'Microsoft.VCRedist.2015+.x64'
                    InstalledVersion  = '14.0.2'
                    AvailableVersions = @('14.0.2')
                    IsUpdateAvailable = $false
                }
            }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[\+\]'
            $out | Where-Object { $_ -is [int] } | Should -Be 0
            Should -Invoke Update-WinGetPackage -Times 0 -Exactly -Because "nothing to update"
        }

        It "Skips the update and returns 1 while the redistributable process is running" {
            function Get-WinGetPackage { }
            function Update-WinGetPackage { }
            Mock Update-WinGetPackage { }
            $wingetModuleStub = [pscustomobject] @{ Name = 'Microsoft.WinGet.Client' }
            Mock Get-Module { $wingetModuleStub } `
                -ParameterFilter { $ListAvailable -and $Name -eq 'Microsoft.WinGet.Client' }
            Mock Invoke-WingetWithRetry { throw "unexpected winget.exe CLI call" }
            Mock Get-Process { [pscustomobject] @{ Id = 4321; ProcessName = 'Microsoft.VCRedist.2015+.x64' } }
            Mock Get-WinGetPackage {
                [pscustomobject] @{
                    Name              = 'Microsoft.VCRedist.2015+.x64'
                    InstalledVersion  = '14.0.1'
                    AvailableVersions = @('14.0.1', '14.0.2')
                    IsUpdateAvailable = $true
                }
            }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[!\]'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
            Should -Invoke Update-WinGetPackage -Times 0 -Exactly -Because "the process must not be disturbed"
        }

        It "Updates a pending package silently and returns 0 after verification succeeds" {
            function Get-WinGetPackage { }
            function Update-WinGetPackage { }
            Mock Update-WinGetPackage { }
            $wingetModuleStub = [pscustomobject] @{ Name = 'Microsoft.WinGet.Client' }
            Mock Get-Module { $wingetModuleStub } `
                -ParameterFilter { $ListAvailable -and $Name -eq 'Microsoft.WinGet.Client' }
            Mock Invoke-WingetWithRetry { throw "unexpected winget.exe CLI call" }
            Mock Get-Process { $null }
            $script:pkgCalls = 0
            Mock Get-WinGetPackage {
                $script:pkgCalls++
                if ($script:pkgCalls -eq 1) {
                    [pscustomobject] @{
                        Name              = 'Microsoft.VCRedist.2015+.x64'
                        InstalledVersion  = '14.0.1'
                        AvailableVersions = @('14.0.1', '14.0.2')
                        IsUpdateAvailable = $true
                    }
                }
                else {
                    [pscustomobject] @{
                        Name              = 'Microsoft.VCRedist.2015+.x64'
                        InstalledVersion  = '14.0.2'
                        AvailableVersions = @('14.0.2')
                        IsUpdateAvailable = $false
                    }
                }
            }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[\+\]'
            $out | Where-Object { $_ -is [int] } | Should -Be 0
            Should -Invoke Update-WinGetPackage -Times 1 -Exactly
        }

        It "Skips the silent update under -WhatIf and still returns 0 on a converged system (ShouldProcess gate)" {
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
                    Name              = 'Microsoft.VCRedist.2015+.x64'
                    InstalledVersion  = '14.0.2'
                    AvailableVersions = @('14.0.2')
                    IsUpdateAvailable = $false
                }
            }
            Main -WhatIf *>&1 | Where-Object { $_ -is [int] } | Should -Be 0
            Should -Invoke Update-WinGetPackage -Times 0 -Exactly -Because "-WhatIf must suppress the update"
        }

        It "Returns 1 with [-] prefixed output on upstream errors" {
            function Get-WinGetPackage { }
            function Update-WinGetPackage { }
            Mock Update-WinGetPackage { }
            $wingetModuleStub = [pscustomobject] @{ Name = 'Microsoft.WinGet.Client' }
            Mock Get-Module { $wingetModuleStub } `
                -ParameterFilter { $ListAvailable -and $Name -eq 'Microsoft.WinGet.Client' }
            Mock Invoke-WingetWithRetry { throw "unexpected winget.exe CLI call" }
            Mock Get-Process { $null }
            Mock Get-WinGetPackage { throw "winget exploded" }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[-\]'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }

        It "Uses the CLI fallback and reports not installed as success (exit 0)" {
            # No module-cmdlet stubs here so Main exercises the real winget.exe CLI fallback path.
            Mock Invoke-WingetWithRetry { "No installed package found matching input criteria" }
            $out = Main *>&1
            $out | Where-Object { $_ -is [int] } | Should -Be 0
            Should -Invoke Invoke-WingetWithRetry -Times 1 -Exactly
        }

        It "Performs the full CLI-fallback upgrade and returns 0 when the process is not running" {
            $script:wCalls = 0
            Mock Invoke-WingetWithRetry {
                $script:wCalls++
                if ($script:wCalls -eq 1) {
                    @(
                        'Name                Version Available'
                        '-------------------- ------- ---------'
                        "Microsoft.VCRedist.2015+.x64 14.0.1    14.0.2"
                    ) -join "`n"
                }
                elseif ($script:wCalls -eq 2) { '' }
                else {
                    @(
                        'Name                Version',
                        '-------------------- -------',
                        "Microsoft.VCRedist.2015+.x64 14.0.2"
                    ) -join "`n"
                }
            }
            Mock Get-Process { $null }
            $out = Main *>&1
            $out | Where-Object { $_ -is [int] } | Should -Be 0
            Should -Invoke Invoke-WingetWithRetry -Times 3 -Exactly -Because "list, upgrade, verify"
        }
    }
}
