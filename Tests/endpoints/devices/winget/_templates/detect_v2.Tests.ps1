#Requires -Modules Pester

Describe "detect_v2.ps1" {
    BeforeAll {
        # Mirrored layout: walk up ../../../../../../ levels from this test folder to the repository root.
        $repoRoot = (Get-Item (Join-Path $PSScriptRoot "../../../../../")).FullName
        $scriptPath = Join-Path $repoRoot "scripts/endpoints/devices/winget/_templates/detect_v2.ps1"

        # Safe: the top-level guard skips Main when dot-sourced (docs/RELAUNCH-SPEC.md section 3).
        . $scriptPath

        # Pass console output through so prefix assertions can inspect it.
        Mock Write-Host { param($Object) $Object }
        Mock Write-Verbose { }

        $updatePackage = [pscustomobject]@{
            Name              = 'Foo'
            Id                = 'WINGETID'
            IsUpdateAvailable = $true
            InstalledVersion  = '1.0.0'
            AvailableVersions = @('2.0.0')
        }
        $currentPackage = [pscustomobject]@{
            Name              = 'Foo'
            Id                = 'WINGETID'
            IsUpdateAvailable = $false
            InstalledVersion  = '2.0.0'
            AvailableVersions = @('2.0.0')
        }
    }

    Context "Help & Metadata" {
        It "Declares Version 1.0.0 and relaunch Date 2026-08-23" {
            $raw = Get-Content -Path $scriptPath -Raw
            ($raw -match '(?m)^\s*Version\s*:\s*1\.0\.0\s*$') | Should -BeTrue
            ($raw -match '(?m)^\s*Date\s*:\s*2026-08-23\s*$') | Should -BeTrue
        }

        It "Declares File Name matching the on-disk filename with no orphaned parameters documented" {
            $raw = Get-Content -Path $scriptPath -Raw
            ($raw -match "(?m)^\s*File Name\s*:\s*detect_v2\.ps1\s*$") | Should -BeTrue
            ($raw -match '\.PARAMETER') | Should -BeFalse  # param() is intentionally empty
        }

        It "Provides at least two examples" {
            $raw = Get-Content -Path $scriptPath -Raw
            ([regex]::Matches($raw, '(?m)^\.EXAMPLE')).Count | Should -BeGreaterOrEqual 2
        }
    }

    Context "Syntax & Static" {
        It "Parses with zero errors" {
            $tokens = $null
            $parseErrors = $null
            $null = [System.Management.Automation.Language.Parser]::ParseFile(
                $scriptPath, [ref]$tokens, [ref]$parseErrors)
            $parseErrors | Should -BeNullOrEmpty
        }

        It "Is UTF-8 BOM encoded with CRLF line endings" {
            $bytes = [System.IO.File]::ReadAllBytes($scriptPath)
            (@($bytes[0], $bytes[1], $bytes[2])) | Should -Be @(0xEF, 0xBB, 0xBF)
            $text = [System.Text.Encoding]::UTF8.GetString($bytes)
            $bareLfLines = @(($text -split "`n") | Where-Object { $_ -and ($_ -notmatch "`r$") })
            $bareLfLines.Count | Should -Be 0
        }

        It "Contains no PS7-only operators without an opt-out pragma" {
            $raw = Get-Content -Path $scriptPath -Raw
            foreach ($pattern in '&&', '\|\|', '\?\?') {
                ($raw -match $pattern) | Should -BeFalse
            }
        }

        It "Declares CmdletBinding, a Main function, a dot-source guard, and exit only in the guard line" {
            $raw = Get-Content -Path $scriptPath -Raw
            ($raw -match '\[CmdletBinding\(\)\]') | Should -BeTrue
            ($raw -match '(?m)^function Main \{') | Should -BeTrue
            ($raw -match [regex]::Escape('if ($MyInvocation.InvocationName -ne '.')')) | Should -BeTrue
            ([regex]::Matches($raw, '\bexit\s*\(')).Count | Should -Be 1
        }
    }

    Context "Behavior" {
        It "Detects an available update via Microsoft.WinGet.Client and returns 1" {
            Mock Get-Module { [pscustomobject]@{ Name = 'Microsoft.WinGet.Client' } }
            Mock Import-Module { }
            Mock Get-Command -ParameterFilter { $Name -eq 'Get-WinGetPackage' } {
                [pscustomobject]@{ Name = 'Get-WinGetPackage' }
            }
            Mock Invoke-WingetPackageLookup { $updatePackage }
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
            ($out | Out-String) | Should -Match '\[!\]'
        }

        It "Returns 0 with [+] output when Microsoft.WinGet.Client reports the package up to date (idempotent)" {
            Mock Get-Module { [pscustomobject]@{ Name = 'Microsoft.WinGet.Client' } }
            Mock Import-Module { }
            Mock Get-Command -ParameterFilter { $Name -eq 'Get-WinGetPackage' } {
                [pscustomobject]@{ Name = 'Get-WinGetPackage' }
            }
            Mock Invoke-WingetPackageLookup { $currentPackage }
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            ($out | Out-String) | Should -Match '\[\+\]'
        }

        It "Returns 0 with [+] output when the package is not installed (module path)" {
            Mock Get-Module { [pscustomobject]@{ Name = 'Microsoft.WinGet.Client' } }
            Mock Import-Module { }
            Mock Get-Command -ParameterFilter { $Name -eq 'Get-WinGetPackage' } {
                [pscustomobject]@{ Name = 'Get-WinGetPackage' }
            }
            Mock Invoke-WingetPackageLookup { $null }
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            ($out | Out-String) | Should -Match '\[\+\]'
            ($out | Out-String) | Should -Match 'not installed'
        }

        It "Falls back to the winget.exe CLI wrapper and returns 1 on a Version Available match" {
            Mock Get-Module { $null }
            Mock Resolve-Path { [pscustomobject]@{ Path = 'C:\Program Files\WindowsApps\fake\winget.exe' } }
            Mock Invoke-WingetList {
                @(
                    'Name   Id       Version Available Source',
                    '----------------------------------------',
                    'Foo    WINGETID 1.0.0   2.0.0     winget'
                )
            }
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
            ($out | Out-String) | Should -Match '\[!\]'
            Should -Invoke Invoke-WingetList -Times 1 -Exactly -ParameterFilter { $PackageId -eq 'WINGETID' }
        }

        It "Falls back to the winget.exe CLI wrapper and returns 0 when the package is not installed" {
            Mock Get-Module { $null }
            Mock Resolve-Path { [pscustomobject]@{ Path = 'C:\Program Files\WindowsApps\fake\winget.exe' } }
            Mock Invoke-WingetList { @('No installed package found matching input criteria.') }
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            ($out | Out-String) | Should -Match '\[\+\]'
        }

        It "Falls back to the winget.exe CLI wrapper and returns 0 when already up to date" {
            Mock Get-Module { $null }
            Mock Resolve-Path { [pscustomobject]@{ Path = 'C:\Program Files\WindowsApps\fake\winget.exe' } }
            Mock Invoke-WingetList {
                @(
                    'Name   Id       Version Source',
                    'Foo    WINGETID 1.0.0   winget'
                )
            }
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            ($out | Out-String) | Should -Match '\[\+\]'
        }

        It "Auto-detects the display name from winget CLI output when name is not configured" {
            Mock Get-Module { $null }
            Mock Resolve-Path { [pscustomobject]@{ Path = 'C:\Program Files\WindowsApps\fake\winget.exe' } }
            Mock Invoke-WingetList {
                @(
                    'WINGETID Foo 1.0.0 2.0.0 winget'
                )
            }
            $name = $null
            $out = Main *>&1
            ($out | Out-String) | Should -Match 'Foo'
        }

        It "Returns 0 with [-] prefixed output on unexpected errors so remediation is not triggered" {
            Mock Get-Module { $null }
            Mock Resolve-Path { throw 'winget.exe missing' }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[-\]'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
        }
    }
}
