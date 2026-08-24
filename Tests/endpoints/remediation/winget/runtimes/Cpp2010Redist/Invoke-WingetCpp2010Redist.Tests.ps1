#Requires -Modules Pester

Describe "Invoke-WingetCpp2010Redist" {
    BeforeAll {
        # Mirrored layout: walk up from Tests/... to the repo root, then across to scripts/.
        $repoRoot = $PSScriptRoot
        while (-not (Test-Path (Join-Path $repoRoot '.git'))) { $repoRoot = Split-Path $repoRoot -Parent }
        $scriptRelPath = 'scripts/endpoints/remediation/winget/runtimes/Cpp2010Redist/Invoke-WingetCpp2010Redist.ps1'
        $scriptPath = Join-Path $repoRoot $scriptRelPath
        $packageId = 'Microsoft.VCRedist.2010.x86'

        # Safe: the script's top-level guard skips Main when dot-sourced.
        . $scriptPath

        # NEVER Mock Get-Command or unfiltered Get-Module - Pester needs them internally.
        # Module-cmdlet stubs are declared per-It so tests that need
        # the genuine CLI-fallback path stay stub-free.
        Mock Import-Module { }
        Mock Start-Sleep { }
        Mock Get-Process { $null }
    }


    Context "Help & Metadata" {
        It "Declares required .NOTES fields with Version 1.0.0 and Date 2026-08-23" {
            $raw = Get-Content -Path $scriptPath -Raw
            $raw | Should -Match 'File Name:\s*Invoke-WingetCpp2010Redist\.ps1'
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
        It "Gates the mutating install behind SupportsShouldProcess" {
            $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] -and
                    $node.GetCommandName() -eq 'Update-WinGetPackage' }, $true) |
                Should -Not -BeNullOrEmpty
            $raw = Get-Content -Path $scriptPath -Raw
            $raw | Should -Match '\[CmdletBinding\(SupportsShouldProcess\)\]'
            $raw | Should -Match 'ShouldProcess\('
        }
    }

    Context "Behavior" {
        It "Skips the update and returns 1 when the app process is running (skip-if-running variant)" {
            function Get-WinGetPackage { }
            function Update-WinGetPackage { }
            $wingetModuleStub = [pscustomobject] @{ Name = 'Microsoft.WinGet.Client' }
            Mock Get-Module { $wingetModuleStub } `
                -ParameterFilter { $ListAvailable -and $Name -eq 'Microsoft.WinGet.Client' }
            Mock Invoke-WingetWithRetry { throw "unexpected winget.exe CLI call" }
            Mock Update-WinGetPackage { throw "must not install while process runs" }
            Mock Get-WinGetPackage {
                [pscustomobject] @{
                    Name                 = 'Microsoft Visual C++ 2010 x86 Redistributable - x86'
                    InstalledVersion     = '9.0.30729'
                    AvailableVersions    = @('9.0.30729', '9.0.6161')
                    IsUpdateAvailable    = $true
                }
            }
            Mock Get-Process { [pscustomobject] @{ Id = 4242; ProcessName = $packageId } }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[!\]'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
            Should -Invoke Update-WinGetPackage -Times 0 -Exactly -Because "the variant must skip, not force close"
        }

        It "Installs a pending update and returns 0 when the process is not running" {
            function Get-WinGetPackage { }
            function Update-WinGetPackage { }
            $wingetModuleStub = [pscustomobject] @{ Name = 'Microsoft.WinGet.Client' }
            Mock Get-Module { $wingetModuleStub } `
                -ParameterFilter { $ListAvailable -and $Name -eq 'Microsoft.WinGet.Client' }
            Mock Invoke-WingetWithRetry { throw "unexpected winget.exe CLI call" }
            Mock Update-WinGetPackage { }
            Mock Get-WinGetPackage {
                if ($null -ne $script:installDone) {
                    return [pscustomobject] @{
                        Name              = 'Microsoft Visual C++ 2010 x86 Redistributable - x86'
                        InstalledVersion  = '9.0.6161'
                        IsUpdateAvailable = $false
                    }
                }
                $script:installDone = $true
                return [pscustomobject] @{
                    Name                 = 'Microsoft Visual C++ 2010 x86 Redistributable - x86'
                    InstalledVersion     = '9.0.30729'
                    AvailableVersions    = @('9.0.30729', '9.0.6161')
                    IsUpdateAvailable    = $true
                }
            }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[\+\]'
            $out | Where-Object { $_ -is [int] } | Should -Be 0
            Should -Invoke Update-WinGetPackage -Times 1 -Exactly
        }

        It "Is idempotent: up-to-date package returns 0 with no install attempt" {
            function Get-WinGetPackage { }
            function Update-WinGetPackage { }
            $wingetModuleStub = [pscustomobject] @{ Name = 'Microsoft.WinGet.Client' }
            Mock Get-Module { $wingetModuleStub } `
                -ParameterFilter { $ListAvailable -and $Name -eq 'Microsoft.WinGet.Client' }
            Mock Invoke-WingetWithRetry { throw "unexpected winget.exe CLI call" }
            Mock Update-WinGetPackage { throw "nothing to install" }
            Mock Get-WinGetPackage {
                [pscustomobject] @{
                    Name                 = 'Microsoft Visual C++ 2010 x86 Redistributable - x86'
                    InstalledVersion     = '9.0.6161'
                    AvailableVersions    = @('9.0.6161')
                    IsUpdateAvailable    = $false
                }
            }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[\+\]'
            $out | Where-Object { $_ -is [int] } | Should -Be 0
            Should -Invoke Update-WinGetPackage -Times 0 -Exactly
        }

        It "Returns 0 when the package is not installed (module path)" {
            function Get-WinGetPackage { }
            function Update-WinGetPackage { }
            $wingetModuleStub = [pscustomobject] @{ Name = 'Microsoft.WinGet.Client' }
            Mock Get-Module { $wingetModuleStub } `
                -ParameterFilter { $ListAvailable -and $Name -eq 'Microsoft.WinGet.Client' }
            Mock Invoke-WingetWithRetry { throw "unexpected winget.exe CLI call" }
            Mock Update-WinGetPackage { throw "nothing to install" }
            Mock Get-WinGetPackage { $null }
            Main *>&1 | Where-Object { $_ -is [int] } | Should -Be 0
        }

        It "Uses the CLI fallback to upgrade and returns 0 when verification succeeds" {
            # No module-cmdlet stubs here so Main exercises the real winget.exe CLI fallback path.
            Mock Invoke-WingetWithRetry {
                @(
                    'Name                Version Available'
                    '-------------------- ------- ---------'
                    "$($packageId) 9.0.30729 9.0.6161"
                ) -join "`n"
            }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[\+\]'
            $out | Where-Object { $_ -is [int] } | Should -Be 0
            Should -Invoke Invoke-WingetWithRetry -Times 3 -Exactly -Because "list + upgrade + verify list"
        }

        It "Returns 1 via the CLI fallback when the app process is running" {
            Mock Invoke-WingetWithRetry {
                @(
                    'Name                Version Available'
                    '-------------------- ------- ---------'
                    "$($packageId) 9.0.30729 9.0.6161"
                ) -join "`n"
            }
            Mock Get-Process { [pscustomobject] @{ Id = 4242; ProcessName = $packageId } }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[!\]'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }

        It "Reports [-] prefixed failure and returns 1 on upstream errors" {
            function Get-WinGetPackage { }
            function Update-WinGetPackage { }
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
