#Requires -Modules Pester

Describe "Invoke-WingetPowerShell7MaintenanceWindow" {
    BeforeAll {
        # Mirrored layout: walk up from Tests/... to the repo root, then across to scripts/.
        $repoRoot = $PSScriptRoot
        while (-not (Test-Path (Join-Path $repoRoot '.git'))) { $repoRoot = Split-Path $repoRoot -Parent }
        $scriptRelPath = 'scripts/endpoints/remediation/winget/development' +
            '/PowerShell7/Invoke-WingetPowerShell7MaintenanceWindow.ps1'
        $scriptPath = Join-Path $repoRoot $scriptRelPath

        # Safe: the script's top-level guard skips Main when dot-sourced.
        . $scriptPath

        # Keep the suite offline: disable file logging for this dot-sourced copy.
        $EnableLogging = $false

        # NEVER Mock Get-Command or unfiltered Get-Module - Pester needs them internally.
        Mock Import-Module { }
        Mock Start-Sleep { }
    }


    Context "Help & Metadata" {
        It "Declares required .NOTES fields with Version 1.0.0 and Date 2026-08-23" {
            $raw = Get-Content -Path $scriptPath -Raw
            $raw | Should -Match 'File Name:\s*Invoke-WingetPowerShell7MaintenanceWindow\.ps1'
            $raw | Should -Match 'Version:\s*1\.0\.0'
            $raw | Should -Match 'Date:\s*2026-08-23'
            $raw | Should -Match 'Author:'
            $raw | Should -Match 'Prerequisite:\s*PowerShell 7\.0'
        }

        It "Has SYNOPSIS, DESCRIPTION documenting exit codes and at least two EXAMPLES" {
            $help = Get-Help $scriptPath
            $help.Synopsis | Should -Not -BeNullOrEmpty
            $help.Description | Should -Not -BeNullOrEmpty
            ((Get-Content -Path $scriptPath -Raw) | Out-String) | Should -Match 'Exit codes?:'
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
        It "Exits 0 without touching winget when outside the maintenance window" {
            # Monday noon is outside the configured Saturday/Sunday 02-06 window.
            Mock Get-Date { [datetime]'2026-08-17T12:00:00' }
            function Update-WinGetPackage { }
            Mock Update-WinGetPackage { }
            Mock Invoke-WingetWithRetry { throw "unexpected winget.exe CLI call" }
            $out = Main *>&1
            $out | Where-Object { $_ -is [int] } | Should -Be 0
            Should -Invoke Update-WinGetPackage -Times 0 -Exactly
            Should -Invoke Invoke-WingetWithRetry -Times 0 -Exactly
        }

        It "Is idempotent inside the window: up-to-date package returns 0 with no update" {
            # Saturday 03:00 is inside the configured maintenance window.
            Mock Get-Date { [datetime]'2026-08-22T03:00:00' }
            function Get-WinGetPackage { }
            function Update-WinGetPackage { }
            Mock Update-WinGetPackage { }
            $wingetModuleStub = [pscustomobject] @{ Name = 'Microsoft.WinGet.Client' }
            Mock Get-Module { $wingetModuleStub } `
                -ParameterFilter { $ListAvailable -and $Name -eq 'Microsoft.WinGet.Client' }
            Mock Invoke-WingetWithRetry { throw "unexpected winget.exe CLI call" }
            Mock Get-WinGetPackage {
                [pscustomobject] @{
                    Name                 = 'PowerShell 7 (pwsh)'
                    InstalledVersion     = '7.5.0'
                    AvailableVersions    = @('7.5.0')
                    IsUpdateAvailable    = $false
                }
            }
            Main *>&1 | Where-Object { $_ -is [int] } | Should -Be 0
            Should -Invoke Update-WinGetPackage -Times 0 -Exactly
        }

        It "Force-closes pwsh and updates during the maintenance window (exit 0)" {
            Mock Get-Date { [datetime]'2026-08-22T03:00:00' }
            Mock Get-Process {
                $script:procCalls++
                if ($script:procCalls -eq 1) { [pscustomobject] @{ ProcessName = 'pwsh' } } else { $null }
            }
            # Stub module surface inline so Pester can Mock these commands.
            function Get-WinGetPackage { }
            function Update-WinGetPackage { }
            Mock Update-WinGetPackage { }
            Mock Stop-Process { }
            $wingetModuleStub = [pscustomobject] @{ Name = 'Microsoft.WinGet.Client' }
            Mock Get-Module { $wingetModuleStub } `
                -ParameterFilter { $ListAvailable -and $Name -eq 'Microsoft.WinGet.Client' }
            Mock Invoke-WingetWithRetry { throw "unexpected winget.exe CLI call" }
            $script:calls = 0
            Mock Get-WinGetPackage {
                $script:calls++
                if ($script:calls -eq 1) {
                    [pscustomobject] @{
                        Name                 = 'PowerShell 7 (pwsh)'
                        InstalledVersion     = '7.4.0'
                        AvailableVersions    = @('7.4.0', '7.5.0')
                        IsUpdateAvailable    = $true
                    }
                }
                else {
                    [pscustomobject] @{
                        Name                 = 'PowerShell 7 (pwsh)'
                        InstalledVersion     = '7.5.0'
                        AvailableVersions    = @('7.5.0')
                        IsUpdateAvailable    = $false
                    }
                }
            }
            $out = Main *>&1
            $out | Where-Object { $_ -is [int] } | Should -Be 0
            Should -Invoke Stop-Process -Times 1 -Exactly -Because "force close is enabled in the maintenance window"
            Should -Invoke Update-WinGetPackage -Times 1 -Exactly
        }

        It "Returns 1 with [-] prefixed output when verification fails after update" {
            Mock Get-Date { [datetime]'2026-08-22T03:00:00' }
            function Get-WinGetPackage { }
            function Update-WinGetPackage { }
            Mock Stop-Process { }
            $wingetModuleStub = [pscustomobject] @{ Name = 'Microsoft.WinGet.Client' }
            Mock Get-Module { $wingetModuleStub } `
                -ParameterFilter { $ListAvailable -and $Name -eq 'Microsoft.WinGet.Client' }
            Mock Invoke-WingetWithRetry { throw "unexpected winget.exe CLI call" }
            Mock Get-Process { $null }
            Mock Get-WinGetPackage {
                [pscustomobject] @{
                    Name                 = 'PowerShell 7 (pwsh)'
                    InstalledVersion     = '7.4.0'
                    AvailableVersions    = @('7.4.0', '7.5.0')
                    IsUpdateAvailable    = $true
                }
            }
            Mock Update-WinGetPackage { throw "update failed" }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[-\]'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }

        It "Returns 0 with no update when not installed via the CLI fallback" {
            Mock Get-Date { [datetime]'2026-08-22T03:00:00' }
            # No module stubs here: Linux probes fail naturally so Main exercises the winget.exe CLI fallback.
            Mock Invoke-WingetWithRetry { "No installed package found matching input criteria" }
            $out = Main *>&1
            $out | Where-Object { $_ -is [int] } | Should -Be 0
            Should -Invoke Invoke-WingetWithRetry -Times 1 -Exactly
        }
    }
}
