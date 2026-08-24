#Requires -Modules Pester
<#
.SYNOPSIS
    Pester tests for scripts/cloud/azure/avd/Update-M365Apps.ps1.
.DESCRIPTION
    Validates help/metadata conformance, static syntax rules, and observable behavior
    of the M365 Apps update manager using fully mocked registry/web/ODT surfaces.
    Runs offline on Linux pwsh; no network, admin elevation, or Windows required.
.EXAMPLE
    PS C:\> Invoke-Pester -Path ./Tests/cloud/azure/avd/Update-M365Apps.Tests.ps1
    Runs this test file.
.NOTES
    File Name   : Update-M365Apps.Tests.ps1
    Author      : Bug-Free Umbrella
    Prerequisite: PowerShell 7.0
    Version     : 1.0.0
    Date        : 2026-08-23
#>

Describe 'Update-M365Apps' {
    BeforeAll {

        $scriptPath = Join-Path $PSScriptRoot '../../../../scripts/cloud/azure/avd/Update-M365Apps.ps1'
        . $scriptPath

        # Mock ALL external commands so nothing leaves the machine and no real
        # registry/provider/filesystem surface is touched.
        Mock Test-Elevation { $true }
        Mock Add-Content { }
        Mock New-Item { }
        Mock Test-Path { $true }
        Mock Get-ChildItem { @() }
        Mock Remove-Item { }
        Mock Set-ItemProperty { }
        Mock Read-Host { '' }
        Mock Start-Sleep { }

        # Connectivity + version endpoint (converged by default: latest == installed)
        Mock Invoke-WebRequest { $null }
        Mock Invoke-RestMethod {
            @([pscustomobject]@{ channelId = 'Current'; channel = 'Current'; latestVersion = '16.0.18526.20168' })
        }

        # ClickToRun registry surface: Current Channel, version equal to mocked latest.
        Mock Get-ItemProperty {
            [pscustomobject]@{
                VersionToReport   = '16.0.18526.20168'
                Platform          = 'x64'
                UpdateChannel     = 'http://officecdn.microsoft.com/pr/492350f6-3a01-4f97-b9c0-c7c6ddf67d60'
                CDNBaseUrl        = $null
                ProductReleaseIds = 'O365ProPlusRetail'
                InstallationPath  = 'C:\Program Files\Microsoft Office'
            }
        }

        # Native ODT wrapper and interactive prompts are the mock seams (spec sections 3 and 5).
        Mock Invoke-OdtSetup { 0 }
        Mock Invoke-OfficeDownload { $true }
        Mock Invoke-OfficeInstall { $true }
        Mock New-DownloadConfiguration { }

        # Sequential confirmation queue: tests enqueue Y/N answers; empty queue declines.
        Mock Get-UserConfirmation {
            if ($script:M365Confirmations.Count -gt 0) {
                return $script:M365Confirmations.Dequeue()
            }
            return $false
        }

        $raw = [IO.File]::ReadAllText($scriptPath)
        $tokens = $null
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errors)
    }

    Context 'Help & Metadata' {
        It 'Declares all five NOTES fields with relaunch values' {
            ($raw -match '(?m)^\.NOTES') | Should -BeTrue
            $raw | Should -Match '(?m)File Name\s*:\s*Update-M365Apps\.ps1'
            $raw | Should -Match '(?m)Author\s*:\s*\S+'
            $raw | Should -Match '(?m)Prerequisite\s*:\s*PowerShell 7\.0'
            $raw | Should -Match '(?m)Version\s*:\s*1\.0\.0'
            $raw | Should -Match '(?m)Date\s*:\s*2026-08-23'
        }

        It 'Has one PARAMETER entry per declared parameter' {
            $paramNames = @('InstallPath')
            foreach ($name in $paramNames) {
                $raw | Should -Match "(?m)\.PARAMETER\s+$name"
            }
            $helpParams = [regex]::Matches($raw, '(?m)^\.PARAMETER\s+(\w+)') | ForEach-Object { $_.Groups[1].Value }
            $helpParams | Should -Be $paramNames
        }

        It 'Has at least two EXAMPLES with PS C:\> prompt lines' {
            ([regex]::Matches($raw, '(?m)^\.EXAMPLE')).Count | Should -BeGreaterOrEqual 2
            ([regex]::Matches($raw, 'PS C:\\>')).Count | Should -BeGreaterOrEqual 2
        }

        It 'Documents exit codes in DESCRIPTION' {
            $raw | Should -Match '(?ms)^\.DESCRIPTION.*?Exit codes:'
        }
    }

    Context 'Syntax & Static' {
        It 'Parses with zero syntax errors' {
            $errors.Count | Should -Be 0
        }

        It 'Is saved as UTF-8 with BOM and CRLF line endings' {
            $bytes = [IO.File]::ReadAllBytes($scriptPath)
            ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) | Should -BeTrue
            [Text.RegularExpressions.Regex]::IsMatch($raw, "(?<!`r)`n") | Should -BeFalse
        }

        It 'Uses only approved verbs on internal functions (Main exempt)' {
            $functions = $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
            $approved = (Get-Verb).Verb
            foreach ($fn in $functions) {
                if ($fn.Name -eq 'Main') { continue }
                $verb = ($fn.Name -split '-')[0]
                $approved | Should -Contain $verb -Because "function $($fn.Name) must use an approved verb"
            }
        }

        It 'Contains no PS7-only operators (no #Requires -Version opt-out present)' {
            $raw | Should -Not -Match '\|\|'
            $raw | Should -Not -Match '&&'
            $raw | Should -Not -Match '\?\??='
        }

        It 'Keeps lines within 120 columns with no trailing whitespace' {
            foreach ($line in ($raw -split "`r`n")) {
                $line.Length | Should -BeLessOrEqual 120
                $line | Should -Not -Match '\s+$'
            }
        }

        It 'Restricts exit to the single top-level dot-source guard line' {
            $lines = $raw -split "`r`n"
            $exitLines = @($lines | Where-Object { $_ -like '*exit (Main)*' })
            $exitLines.Count | Should -Be 1
            $exitLines[0] |
                Should -BeExactly "if (`$MyInvocation.InvocationName -ne '.') { exit (Main) }"
        }

        It 'Routes the native ODT executable only through the wrapper function' {
            # Start-Process may appear ONLY inside Invoke-OdtSetup.
            $functions = $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
            foreach ($fn in $functions) {
                $hasStartProcess = ($fn.Extent.Text -match 'Start-Process')
                if ($hasStartProcess) {
                    $fn.Name | Should -Be 'Invoke-OdtSetup' -Because 'native exes need a single mockable wrapper seam'
                }
            }
        }
    }

    Context 'Behavior' {
        It 'Returns 1 with [-] output when ODT prerequisites are missing' {
            Mock Test-Path { param($Path) $Path -notlike '*.exe' }
            $out = Main *>&1
            $out | Where-Object { $_ -is [int] } | Should -Be 1
            ($out | Out-String) | Should -Match '\[-\]'
            Should -Invoke Invoke-OdtSetup -Times 0 -Exactly
            Should -Invoke Invoke-RestMethod -Times 0 -Exactly
        }

        It 'Is idempotent on a converged system: up to date returns 0 with zero mutations' {
            $out = Main *>&1
            $out | Where-Object { $_ -is [int] } | Should -Be 0
            ($out | Out-String) | Should -Match '\[\+\] M365 Apps are up to date!'
            Should -Invoke Invoke-RestMethod -Times 1 -Exactly
            Should -Invoke Invoke-OfficeDownload -Times 0 -Exactly -Because 'already converged'
            Should -Invoke Invoke-OfficeInstall -Times 0 -Exactly
            Should -Invoke Invoke-OdtSetup -Times 0 -Exactly
            Should -Invoke Set-ItemProperty -Times 0 -Exactly
        }

        It 'Declines fresh installation when Office is absent and returns 0' {
            Mock Test-Path { param($Path) $Path -notmatch '^HKLM:' }
            Mock Get-ItemProperty { $null }
            $out = Main *>&1
            $out | Where-Object { $_ -is [int] } | Should -Be 0
            ($out | Out-String) | Should -Match '\[\*\] Installation cancelled by user'
            Should -Invoke Invoke-OdtSetup -Times 0 -Exactly
        }

        It 'Downloads an available update but skips install when user declines install' {
            # Offer a newer build so the update flow actually engages.
            Mock Invoke-RestMethod {
                @([pscustomobject]@{ channelId = 'Current'; channel = 'Current'; latestVersion = '16.0.19999.99999' })
            }
            $script:M365Confirmations = [System.Collections.Queue]::new(@($false, $true, $false))
            $out = Main *>&1
            $out | Where-Object { $_ -is [int] } | Should -Be 0
            Should -Invoke New-DownloadConfiguration -Times 1 -Exactly -Scope It
            Should -Invoke Invoke-OfficeDownload -Times 1 -Exactly -Scope It
            Should -Invoke Invoke-OfficeInstall -Times 0 -Exactly -Scope It
            ($out | Out-String) | Should -Match 'Updates downloaded but not installed'
        }

        It 'Completes the full update flow when the user accepts download and install' {
            # Offer a newer build so the update flow actually engages.
            Mock Invoke-RestMethod {
                @([pscustomobject]@{ channelId = 'Current'; channel = 'Current'; latestVersion = '16.0.19999.99999' })
            }
            $script:M365Confirmations = [System.Collections.Queue]::new(@($false, $true, $true, $false))
            $out = Main *>&1
            $out | Where-Object { $_ -is [int] } | Should -Be 0
            Should -Invoke Invoke-OfficeInstall -Times 1 -Exactly -Scope It
            ($out | Out-String) | Should -Match '\[\+\] Update installation completed!'
        }

        It 'Honors -WhatIf: update offered and accepted, but no download mutation occurs' {
            # Offer a newer build so the update flow actually engages.
            Mock Invoke-RestMethod {
                @([pscustomobject]@{ channelId = 'Current'; channel = 'Current'; latestVersion = '16.0.19999.99999' })
            }
            $script:M365Confirmations = [System.Collections.Queue]::new(@($false, $true))
            $out = Main -WhatIf *>&1
            $out | Where-Object { $_ -is [int] } | Should -Be 0
            Should -Invoke New-DownloadConfiguration -Times 0 -Exactly -Scope It
            Should -Invoke Invoke-OfficeDownload -Times 0 -Exactly -Scope It
            Should -Invoke Invoke-OdtSetup -Times 0 -Exactly -Scope It
        }

        It 'Returns 1 with [-] prefix when not running elevated' {
            Mock Test-Elevation { $false }
            $out = Main *>&1
            $out | Where-Object { $_ -is [int] } | Should -Be 1
            ($out | Out-String) | Should -Match '\[-\]'
        }
    }
}
