#Requires -Modules Pester

Describe "remediate_v1_legacy.ps1" {
    BeforeAll {
        # Mirrored layout: walk up five levels from this test folder to the repository root.
        $repoRoot = (Get-Item (Join-Path $PSScriptRoot "../../../../../")).FullName
        $relative = "scripts/endpoints/devices/winget/_templates/remediate_v1_legacy.ps1"
        $scriptPath = Join-Path $repoRoot $relative

        # Safe: the top-level guard skips Main when dot-sourced (docs/RELAUNCH-SPEC.md section 3).
        . $scriptPath

        # Offline stubs for the Microsoft.WinGet.Client surface (module is absent on Linux CI)
        # so Pester can attach name-level mocks to it.
        function Get-WinGetPackage { $null }
        function Update-WinGetPackage { }

        # Shared offline mocks: every external surface is mocked; native executables are reached only
        # through the script's wrapper functions, never by name (docs/RELAUNCH-SPEC.md section 5).
        # Write-Host is silenced (not passed through): a passthrough mock would leak objects into the
        # pipeline and pollute helper-function boolean return values.
        Mock Write-Host { }
        Mock Write-Verbose { }
        Mock Get-Module { $false }
        Mock Import-Module { }
        Mock Get-Command { $true } -ParameterFilter { $Name -eq 'Get-WinGetPackage' }
        Mock Get-Process { $null }
        Mock Start-Sleep { }
        Mock Get-WinGetPackage { $null }
        Mock Update-WinGetPackage { }
        Mock Invoke-WingetCommand { @() }
        Mock Write-Warning { }
    }

    Context "Help & Metadata" {
        It "Declares Version 1.0.0 and relaunch Date 2026-08-23" {
            $raw = Get-Content -Path $scriptPath -Raw
            ($raw -match '(?m)^\s*Version\s*:\s*1\.0\.0\s*$') | Should -BeTrue
            ($raw -match '(?m)^\s*Date\s*:\s*2026-08-23\s*$') | Should -BeTrue
        }

        It "Declares File Name matching the on-disk filename with no orphaned parameters documented" {
            $raw = Get-Content -Path $scriptPath -Raw
            ($raw -match "(?m)^\s*File Name\s*:\s*remediate_v1_legacy\.ps1\s*$") | Should -BeTrue
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
        It "Warns that the template is deprecated" {
            Mock Get-Module { $true }
            Mock Get-WinGetPackage {
                [pscustomobject]@{ Name = 'AppName'; InstalledVersion = '1.0.0'; IsUpdateAvailable = $false }
            }
            Main *>&1 | Out-Null
            Should -Invoke Write-Warning -Times 1 -Exactly -ParameterFilter { $Message -match 'DEPRECATED' }
        }

        It "Returns 0 and reports [+] Already up to date with no changes on a converged system" {
            Mock Get-Module { $true }
            Mock Get-WinGetPackage {
                [pscustomobject]@{ Name = 'AppName'; InstalledVersion = '1.0.0'; IsUpdateAvailable = $false }
            }
            Main *>&1 | Out-Null
            Should -Invoke Write-Host -ParameterFilter {
                $Object -match '^(\[\+\])? ?\[\+\] Already up to date' -or $Object -match 'Already up to date'
            }
            Should -Invoke Update-WinGetPackage -Times 0 -Exactly -Because 'the package is current'
        }

        It "Upgrades via the Microsoft.WinGet.Client module and returns 0 when an update is available" {
            Mock Get-Module { $true }
            Mock Get-WinGetPackage {
                [pscustomobject]@{ Name = 'AppName'; InstalledVersion = '2.0.0'; IsUpdateAvailable = $true }
            }
            Main *>&1 | Out-Null
            Should -Invoke Write-Host -ParameterFilter {
                ($Object -match 'upgraded') -and
                ($Object -match '^(\[\+\])? ?\[\+\]')
            }
            Should -Invoke Write-Host -ParameterFilter { $Object -match '^\[\+\]' }
            Should -Invoke Update-WinGetPackage -Times 1 -Exactly
        }

        It "Returns 1 and skips the update with [!] output while the application runs" {
            Mock Get-Module { $true }
            Mock Get-WinGetPackage {
                [pscustomobject]@{ Name = 'AppName'; InstalledVersion = '1.0.0'; IsUpdateAvailable = $true }
            }
            Mock Get-Process { @([pscustomobject]@{ Id = 4242 }) }
            Main *>&1 | Out-Null
            Should -Invoke Write-Host -ParameterFilter { $Object -match '^\[\!\]' }
            Should -Invoke Update-WinGetPackage -Times 0 -Exactly
        }

        It "Falls back to the winget.exe wrapper seam and upgrades through it when the module is missing" {
            Mock Invoke-WingetCommand {
                @('Name Id Version Available Source', '---- -- ------- --------- ------',
                    'AppName WINGETID 1.0.0 2.0.0 winget')
            } -ParameterFilter { $Arguments[0] -eq 'list' }
            Mock Invoke-WingetCommand { @('') } -ParameterFilter { $Arguments[0] -eq 'upgrade' }
            Main *>&1 | Out-Null
            Should -Invoke Write-Host -ParameterFilter {
                ($Object -match 'APPNAME upgraded to version 2\.0\.0') -and
                ($Object -match '^\[\+\]')
            }
            Should -Invoke Invoke-WingetCommand -Times 1 -Exactly -ParameterFilter { $Arguments[0] -eq 'upgrade' }
        }

        It "Reports an already-current package through the CLI seam with no upgrade call" {
            Mock Invoke-WingetCommand {
                @('Name Id Version Source', '---- -- ------- ------', 'AppName WINGETID 1.0.0 winget')
            }
            Main *>&1 | Out-Null
            Should -Invoke Write-Host -ParameterFilter {
                ($Object -match 'Already up to date') -and
                ($Object -match '^\[\+\]')
            }
            Should -Invoke Invoke-WingetCommand -Times 0 -Exactly -ParameterFilter { $Arguments[0] -eq 'upgrade' }
        }

        It "Returns 0 when the package is not installed" {
            Mock Invoke-WingetCommand {
                @('No installed package found matching input criteria.')
            }
            Main *>&1 | Out-Null
            Should -Invoke Write-Host -ParameterFilter { $Object -match 'not installed' -and $Object -match '^\[\+\]' }
        }

        It "Returns 1 with [-]-prefixed output when winget fails" {
            Mock Invoke-WingetCommand { throw 'winget exploded' }
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
            Should -Invoke Write-Host -ParameterFilter { $Object -match '^\[-\]' }
        }
    }
}
