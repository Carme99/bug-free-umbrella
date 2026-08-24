#Requires -Modules Pester

Describe "Invoke-Winget1Password" {
    BeforeAll {
        # Mirrored layout: walk up from Tests/... to the repo root, then across to scripts/.
        $repoRoot = $PSScriptRoot
        while (-not (Test-Path (Join-Path $repoRoot '.git'))) { $repoRoot = Split-Path $repoRoot -Parent }
        $scriptRelPath = 'scripts/endpoints/remediation/winget/security/1Password/Invoke-Winget1Password.ps1'
        $scriptPath = Join-Path $repoRoot $scriptRelPath

        # Safe: the script's top-level guard skips Main when dot-sourced.
        . $scriptPath

        # NEVER Mock Get-Command or unfiltered Get-Module - Pester needs them internally.
        # Module-cmdlet stubs are declared per-It so tests that need
        # the genuine CLI-fallback path stay stub-free.
        Mock Stop-Process { }
        Mock Import-Module { }
        Mock Start-Sleep { }
    }


    Context "Help & Metadata" {
        It "Declares required .NOTES fields with Version 1.0.0 and Date 2026-08-23" {
            $raw = Get-Content -Path $scriptPath -Raw
            $raw | Should -Match 'File Name:\s*Invoke-Winget1Password\.ps1'
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

        It "Is idempotent: already-up-to-date package returns 0 with no update activity" {
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
                    Name              = '1Password'
                    InstalledVersion  = '8.10.0'
                    AvailableVersions = @('8.10.0')
                    IsUpdateAvailable = $false
                }
            }
            $out = Main *>&1
            $out | Where-Object { $_ -is [int] } | Should -Be 0
            Should -Invoke Update-WinGetPackage -Times 0 -Exactly -Because "nothing to update"
        }

        It "Skips with exit 1 and no update while the application is running" {
            function Get-WinGetPackage { }
            function Update-WinGetPackage { }
            Mock Update-WinGetPackage { }
            $wingetModuleStub = [pscustomobject] @{ Name = 'Microsoft.WinGet.Client' }
            Mock Get-Module { $wingetModuleStub } `
                -ParameterFilter { $ListAvailable -and $Name -eq 'Microsoft.WinGet.Client' }
            Mock Invoke-WingetWithRetry { throw "unexpected winget.exe CLI call" }
            Mock Get-Process { [pscustomobject] @{ Id = 555; ProcessName = '1Password' } }
            Mock Get-WinGetPackage {
                [pscustomobject] @{
                    Name              = '1Password'
                    InstalledVersion  = '8.9.0'
                    AvailableVersions = @('8.9.0', '8.10.0')
                    IsUpdateAvailable = $true
                }
            }
            $out = Main *>&1
            ($out | Out-String) | Should -Match 'Will try again later'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
            Should -Invoke Update-WinGetPackage -Times 0 -Exactly -Because "the app is running"
        }

        It "Installs the update and returns 0 when the app is closed and verification passes" {
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
                        Name              = '1Password'
                        InstalledVersion  = '8.9.0'
                        AvailableVersions = @('8.9.0', '8.10.0')
                        IsUpdateAvailable = $true
                    }
                }
                else {
                    [pscustomobject] @{
                        Name              = '1Password'
                        InstalledVersion  = '8.10.0'
                        AvailableVersions = @('8.10.0')
                        IsUpdateAvailable = $false
                    }
                }
            }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[\+\]'
            $out | Where-Object { $_ -is [int] } | Should -Be 0
            Should -Invoke Update-WinGetPackage -Times 1 -Exactly
        }

        It "Skips the silent update under -WhatIf (ShouldProcess gate)" {
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
                    Name              = '1Password'
                    InstalledVersion  = '8.9.0'
                    AvailableVersions = @('8.9.0', '8.10.0')
                    IsUpdateAvailable = $true
                }
            }
            Main -WhatIf *> $null
            Should -Invoke Update-WinGetPackage -Times 0 -Exactly -Because "-WhatIf must suppress the update"
        }

        It "Performs the full CLI-fallback upgrade and returns 0 when the process is not running" {
            $script:wCalls = 0
            Mock Invoke-WingetWithRetry {
                $script:wCalls++
                if ($script:wCalls -eq 1) {
                    @(
                        'Name                Version Available'
                        '-------------------- ------- ---------'
                        "$($ID) 8.9.0    8.10.0"
                    ) -join "`n"
                }
                elseif ($script:wCalls -eq 2) { '' }
                else {
                    @('Name                Version', '-------------------- -------', "$($ID) 8.10.0") -join "`n"
                }
            }
            Mock Get-Process { $null }
            $out = Main *>&1
            $out | Where-Object { $_ -is [int] } | Should -Be 0
            Should -Invoke Invoke-WingetWithRetry -Times 3 -Exactly -Because "list, upgrade, verify"
        }

        It "Returns 1 with [-] prefixed output on upstream errors" {
            function Get-WinGetPackage { }
            function Update-WinGetPackage { }
            Mock Update-WinGetPackage { }
            $wingetModuleStub = [pscustomobject] @{ Name = 'Microsoft.WinGet.Client' }
            Mock Get-Module { $wingetModuleStub } `
                -ParameterFilter { $ListAvailable -and $Name -eq 'Microsoft.WinGet.Client' }
            Mock Invoke-WingetWithRetry { throw "unexpected winget.exe CLI call" }
            Mock Get-WinGetPackage { throw "winget exploded" }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[-\]'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }
    }
}
