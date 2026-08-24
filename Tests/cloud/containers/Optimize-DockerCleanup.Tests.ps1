#Requires -Modules Pester
<#
.SYNOPSIS
    Pester tests for scripts/cloud/containers/Optimize-DockerCleanup.ps1.
.DESCRIPTION
    Validates help/metadata conformance, static syntax rules, and observable behavior
    of the Docker cleanup script. The native docker executable is exercised only via
    the Invoke-Docker wrapper function, which these tests mock by name.
    Runs offline on Linux pwsh; no Docker daemon required.
.EXAMPLE
    PS C:\> Invoke-Pester -Path ./Tests/cloud/containers/Optimize-DockerCleanup.Tests.ps1
    Runs this test file.
.NOTES
    File Name   : Optimize-DockerCleanup.Tests.ps1
    Author      : Bug-Free Umbrella
    Prerequisite: PowerShell 7.0
    Version     : 1.0.0
    Date        : 2026-08-23
#>

Describe 'Optimize-DockerCleanup' {
    BeforeAll {

        # Safe: the script's top-level guard skips Main when dot-sourced (spec section 3).
        $scriptPath = Join-Path $PSScriptRoot '../../../scripts/cloud/containers/Optimize-DockerCleanup.ps1'
        . $scriptPath

        # Native exe is reached only through the Invoke-Docker wrapper; mock the wrapper.
        Mock Invoke-Docker { 0 }

        $raw = [IO.File]::ReadAllText($scriptPath)
        $tokens = $null; $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errors)
    }

    Context 'Help & Metadata' {
        It 'Declares all five NOTES fields with relaunch values' {
            ($raw -match '(?m)^\.NOTES') | Should -BeTrue
            $raw | Should -Match '(?m)File Name\s*:\s*Optimize-DockerCleanup\.ps1'
            $raw | Should -Match '(?m)Author\s*:\s*IT Infrastructure Team'
            $raw | Should -Match '(?m)Prerequisite\s*:\s*PowerShell 7\.0'
            $raw | Should -Match '(?m)Version\s*:\s*1\.0\.0'
            $raw | Should -Match '(?m)Date\s*:\s*2026-08-23'
        }

        It 'Has one PARAMETER entry per declared parameter' {
            foreach ($name in @('RemoveStoppedContainers', 'RemoveDanglingImages',
                    'RemoveUnusedVolumes', 'PruneBuildCache', 'Force')) {
                $raw | Should -Match "(?m)\.PARAMETER\s+$name"
            }
        }

        It 'Provides at least two examples with PS prompts' {
            ([regex]::Matches($raw, '(?m)^\.EXAMPLE')).Count | Should -BeGreaterOrEqual 2
            ([regex]::Matches($raw, '(?m)^\s*PS C:\\>')).Count | Should -BeGreaterOrEqual 2
        }
    }

    Context 'Syntax & Static' {
        It 'Parses with zero syntax errors' {
            $errors.Count | Should -Be 0
        }

        It 'Declares SupportsShouldProcess and gates prunes behind ShouldProcess' {
            $raw | Should -Match '\[CmdletBinding\(SupportsShouldProcess\)\]'
            ([regex]::Matches($raw, '\$PSCmdlet\.ShouldProcess\(')).Count | Should -Be 4
        }

        It 'Never invokes the native docker exe outside the wrapper' {
            ([regex]::Matches($raw, '&\s+docker\b')).Count | Should -Be 1
            # Justified: the native exe must appear only inside the Invoke-Docker wrapper.
            $raw | Should -Match 'function Invoke-Docker'
        }

        It 'Is UTF-8 with BOM and CRLF line endings' {
            $bytes = [IO.File]::ReadAllBytes($scriptPath)
            ($bytes[0], $bytes[1], $bytes[2]) | Should -Be (0xEF, 0xBB, 0xBF)
            ($raw -replace "`r`n", '').Contains("`n") | Should -BeFalse
        }
    }

    Context 'Behavior' {
        It 'With no switches selected: exits 0 and performs zero prune operations' {
            $out = Main *>&1
            $out | Where-Object { $_ -is [int] } | Should -Be 0
            Should -Invoke Invoke-Docker -Times 2 -Exactly -ParameterFilter { $DockerArgs -contains 'df' }
            Should -Invoke Invoke-Docker -Times 0 -Exactly -ParameterFilter { $DockerArgs -contains 'prune' }
        }

        It 'With Force selected: runs all four prunes via wrapper and returns 0 on success' {
            $Force = $true
            $out = Main *>&1
            $text = $out | Out-String
            $text | Should -Match '\[\+\] Cleanup complete'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            Should -Invoke Invoke-Docker -Times 1 -Exactly `
                -ParameterFilter { $DockerArgs -join ' ' -eq 'container prune -f' }
            Should -Invoke Invoke-Docker -Times 1 -Exactly `
                -ParameterFilter { $DockerArgs -join ' ' -eq 'image prune -f' }
            Should -Invoke Invoke-Docker -Times 1 -Exactly `
                -ParameterFilter { $DockerArgs -join ' ' -eq 'volume prune -f' }
            Should -Invoke Invoke-Docker -Times 1 -Exactly `
                -ParameterFilter { $DockerArgs -join ' ' -eq 'builder prune -f' }
        }

        It 'Honors individual category switches without running others' {
            Mock Invoke-Docker { param([string[]]$DockerArgs) if ($DockerArgs -contains 'df') { 0 } else { 1 } }
            $RemoveDanglingImages = $true
            $out = Main *>&1
            $out | Where-Object { $_ -is [int] } | Should -Be 1
            Should -Invoke Invoke-Docker -Times 1 -Exactly -ParameterFilter { $DockerArgs[0] -eq 'image' }
            Should -Invoke Invoke-Docker -Times 0 -Exactly -ParameterFilter { $DockerArgs[0] -eq 'volume' }
        }

        It 'Returns 1 with [-] output when a prune fails' {
            Mock Invoke-Docker { param([string[]]$DockerArgs) if ($DockerArgs -contains 'df') { 0 } else { 1 } }
            $Force = $true
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[-\]'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }
        It 'Is idempotent: converged (clean) system still exits 0' {
            Mock Invoke-Docker { 0 }
            $Force = $true
            Main | Should -Be 0
            Main | Should -Be 0
        }

        It 'Suppresses all mutations under WhatIf preference' {
            $Force = $true
            $WhatIfPreference = $true
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            Should -Invoke Invoke-Docker -Times 0 -Exactly -ParameterFilter { $DockerArgs -contains 'prune' }
        }
    }
}
