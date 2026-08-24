#Requires -Modules Pester

Describe "remediate_v3_standard.ps1" {
    BeforeAll {
        # Mirrored layout: walk up five levels from this test folder to the repository root.
        $repoRoot = (Get-Item (Join-Path $PSScriptRoot "../../../../../")).FullName
        $relative = "scripts/endpoints/remediation/winget/_templates/remediate_v3_standard.ps1"
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

    }

    Context "Help & Metadata" {
        It "Declares Version 1.0.0 and relaunch Date 2026-08-23" {
            $raw = Get-Content -Path $scriptPath -Raw
            ($raw -match '(?m)^\s*Version\s*:\s*1\.0\.0\s*$') | Should -BeTrue
            ($raw -match '(?m)^\s*Date\s*:\s*2026-08-23\s*$') | Should -BeTrue
        }

        It "Declares File Name matching the on-disk filename with no orphaned parameters documented" {
            $raw = Get-Content -Path $scriptPath -Raw
            ($raw -match "(?m)^\s*File Name\s*:\s*remediate_v3_standard\.ps1\s*$") | Should -BeTrue
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
        It "Returns 0 and reports [+] Already up to date with no changes on a converged system" {
            Mock Get-Module { $true }
            Mock Get-WinGetPackage {
                [pscustomobject]@{ Name = 'Slack'; InstalledVersion = '4.0'; IsUpdateAvailable = $false }
            }
            Main *>&1 | Out-Null
            Should -Invoke Write-Host -ParameterFilter {
                ($Object -match 'Already up to date') -and
                ($Object -match '^\[\+\]')
            }
            Should -Invoke Update-WinGetPackage -Times 0 -Exactly
            Should -Invoke Start-Sleep -Times 0 -Exactly
        }

        It "Runs pre/post update hooks around a successful module upgrade and returns 0" {
            Mock Get-Module { $true }
            Mock Get-WinGetPackage {
                [pscustomobject]@{
                    Name = 'Slack'
                    InstalledVersion = '4.0'
                    AvailableVersions = @('4.1')
                    IsUpdateAvailable = $true
                }
            }
            $script:hookLog = @()
            $PreUpdateScriptBlock = { $script:hookLog += 'pre' }
            $PostUpdateScriptBlock = { $script:hookLog += 'post' }
            Main *>&1 | Out-Null
            $script:hookLog | Should -Be @('pre', 'post')
            Should -Invoke Update-WinGetPackage -Times 1 -Exactly
        }

        It "Returns 1 and skips the update with [!] output while the application runs" {
            Mock Get-Module { $true }
            Mock Get-WinGetPackage {
                [pscustomobject]@{
                    Name = 'Slack'
                    InstalledVersion = '4.0'
                    AvailableVersions = @('4.1')
                    IsUpdateAvailable = $true
                }
            }
            Mock Get-Process { @([pscustomobject]@{ Id = 4242 }) }
            Main *>&1 | Out-Null
            Should -Invoke Write-Host -ParameterFilter { $Object -match '^\[\!\]' }
            Should -Invoke Update-WinGetPackage -Times 0 -Exactly
        }

        It "Retries transient winget failures with exponential backoff through the wrapper seam" {
            $script:wCalls = 0
            Mock Invoke-WingetCommand {
                $script:wCalls++
                if ($script:wCalls -le 2) { throw 'transient winget failure' }
                @('Name Id Version', '---- -- -------', 'Slack WINGETID 4.0 winget')
            }
            Main *>&1 | Out-Null
            $script:wCalls | Should -Be 3 -Because 'two transient failures then one success'
            Should -Invoke Start-Sleep -Times 2 -Exactly -Because 'backoff delays run between retry attempts'
        }

        It "Returns 1 with [-]-prefixed output after exhausting all retries" {
            Mock Invoke-WingetCommand { throw 'winget down' }
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
            Should -Invoke Write-Host -ParameterFilter { $Object -match '^\[-\]' }
            Should -Invoke Invoke-WingetCommand -Times 3 -Exactly -Because 'MaxRetries defaults to 3'
        }

        It "Returns 1 with [-]-prefixed output when post-update verification fails" {
            Mock Get-Module { $true }
            $script:pCalls = 0
            Mock Get-WinGetPackage {
                $script:pCalls++
                if ($script:pCalls -eq 1) {
                    [pscustomobject]@{
                        Name = 'Slack'
                        InstalledVersion = '4.0'
                        AvailableVersions = @('4.1')
                        IsUpdateAvailable = $true
                    }
                } else { $null }
            }
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
            Should -Invoke Write-Host -ParameterFilter { $Object -match '^\[-\]' }
        }
    }
}
