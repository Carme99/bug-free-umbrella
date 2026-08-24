#Requires -Modules Pester

Describe "Invoke-WingetMicrosoftTeams" {
    BeforeAll {
        # Mirrored layout: walk up from Tests/... to the repo root, then across to scripts/.
        $repoRoot = $PSScriptRoot
        while (-not (Test-Path (Join-Path $repoRoot '.git'))) { $repoRoot = Split-Path $repoRoot -Parent }
        $scriptRelPath = 'scripts/endpoints/remediation/winget/productivity/MicrosoftTeams'
            $scriptRelPath += '/Invoke-WingetMicrosoftTeams.ps1'
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
            $raw | Should -Match 'File Name:\s*Invoke-WingetMicrosoftTeams\.ps1'
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
            # Stub module surface inline so Pester can Mock these commands.
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

        It "Is idempotent: already-up-to-date package returns 0 with no close/update activity" {
            function Get-WinGetPackage { }
            function Update-WinGetPackage { }
            Mock Update-WinGetPackage { }
            $wingetModuleStub = [pscustomobject] @{ Name = 'Microsoft.WinGet.Client' }
            Mock Get-Module { $wingetModuleStub } `
                -ParameterFilter { $ListAvailable -and $Name -eq 'Microsoft.WinGet.Client' }
            Mock Invoke-WingetWithRetry { throw "unexpected winget.exe CLI call" }
            Mock Get-LoggedOnUserSession { @() }
            Mock Get-Process { $null }
            Mock Get-WinGetPackage {
                [pscustomobject] @{
                    Name              = 'Microsoft Teams'
                    InstalledVersion  = '1.8.0'
                    AvailableVersions = @('1.8.0')
                    IsUpdateAvailable = $false
                }
            }
            $out = Main *>&1
            $out | Where-Object { $_ -is [int] } | Should -Be 0
            Should -Invoke Update-WinGetPackage -Times 0 -Exactly -Because "nothing to update"
        }

        It "Notifies, force closes a running ms-teams process, updates and returns 0" {
            function Get-WinGetPackage { }
            function Update-WinGetPackage { }
            Mock Update-WinGetPackage { }
            $wingetModuleStub = [pscustomobject] @{ Name = 'Microsoft.WinGet.Client' }
            Mock Get-Module { $wingetModuleStub } `
                -ParameterFilter { $ListAvailable -and $Name -eq 'Microsoft.WinGet.Client' }
            Mock Invoke-WingetWithRetry { throw "unexpected winget.exe CLI call" }
            Mock Get-LoggedOnUserSession { @('jack contoso') }
            Mock Send-UserMessage { }
            $script:procCalls = 0
            Mock Get-Process {
                $script:procCalls++
                if ($script:procCalls -eq 1) { [pscustomobject] @{ Id = 555; ProcessName = 'ms-teams' } } else { $null }
            }
            $script:calls = 0
            Mock Get-WinGetPackage {
                $script:calls++
                if ($script:calls -eq 1) {
                    [pscustomobject] @{
                        Name              = 'Microsoft Teams'
                        InstalledVersion  = '1.7.0'
                        AvailableVersions = @('1.7.0', '1.8.0')
                        IsUpdateAvailable = $true
                    }
                }
                else {
                    [pscustomobject] @{
                        Name              = 'Microsoft Teams'
                        InstalledVersion  = '1.8.0'
                        AvailableVersions = @('1.8.0')
                        IsUpdateAvailable = $false
                    }
                }
            }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[\*\]'
            ($out | Out-String) | Should -Match '\[\+\]'
            $out | Where-Object { $_ -is [int] } | Should -Be 0
            Should -Invoke Send-UserMessage -Times 1 -Exactly -Because "the user should be warned before close"
            Should -Invoke Update-WinGetPackage -Times 1 -Exactly
        }

        It "Aborts with exit 1 and no update when the ms-teams process cannot be closed" {
            function Get-WinGetPackage { }
            function Update-WinGetPackage { }
            Mock Update-WinGetPackage { }
            $wingetModuleStub = [pscustomobject] @{ Name = 'Microsoft.WinGet.Client' }
            Mock Get-Module { $wingetModuleStub } `
                -ParameterFilter { $ListAvailable -and $Name -eq 'Microsoft.WinGet.Client' }
            Mock Invoke-WingetWithRetry { throw "unexpected winget.exe CLI call" }
            Mock Get-LoggedOnUserSession { @() }
            Mock Get-Process { [pscustomobject] @{ Id = 555; ProcessName = 'ms-teams' } }
            Mock Get-WinGetPackage {
                [pscustomobject] @{
                    Name              = 'Microsoft Teams'
                    InstalledVersion  = '1.7.0'
                    AvailableVersions = @('1.7.0', '1.8.0')
                    IsUpdateAvailable = $true
                }
            }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[-\]'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
            Should -Invoke Update-WinGetPackage -Times 0 -Exactly -Because "the app could not be closed"
        }

        It "Skips the silent update under -WhatIf and still returns 0 (ShouldProcess gate)" {
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
                    Name              = 'Microsoft Teams'
                    InstalledVersion  = '1.8.0'
                    AvailableVersions = @('1.8.0')
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
                        "$($ID) 1.7.0    1.8.0"
                    ) -join "`n"
                }
                elseif ($script:wCalls -eq 2) { '' }
                else {
                    @('Name                Version', '-------------------- -------', "$($ID) 1.8.0") -join "`n"
                }
            }
            Mock Get-Process { $null }
            $out = Main *>&1
            $out | Where-Object { $_ -is [int] } | Should -Be 0
            Should -Invoke Invoke-WingetWithRetry -Times 3 -Exactly -Because "list, upgrade, verify"
        }
    }
}
