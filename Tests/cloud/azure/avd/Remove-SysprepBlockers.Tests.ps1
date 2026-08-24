#Requires -Modules Pester
<#
.SYNOPSIS
    Pester tests for scripts/cloud/azure/avd/Remove-SysprepBlockers.ps1.
.DESCRIPTION
    Validates help/metadata conformance, static syntax rules, and observable behavior
    of the Sysprep blocker removal script using fully mocked AppX/service cmdlets.
    Runs offline on Linux pwsh; no network, admin elevation, or Windows required.
.EXAMPLE
    PS C:\> Invoke-Pester -Path ./Tests/cloud/azure/avd/Remove-SysprepBlockers.Tests.ps1
    Runs this test file.
.NOTES
    File Name   : Remove-SysprepBlockers.Tests.ps1
    Author      : Bug-Free Umbrella
    Prerequisite: PowerShell 7.0
    Version     : 1.0.0
    Date        : 2026-08-23
#>

Describe 'Remove-SysprepBlockers' {
    BeforeAll {
        $scriptPath = Join-Path $PSScriptRoot '../../../../scripts/cloud/azure/avd/Remove-SysprepBlockers.ps1'

        # Safe: the script's top-level guard skips Main when dot-sourced (spec section 3).
        . $scriptPath

        # Seed no-op stubs for Windows-only cmdlets that do not resolve on Linux
        # pwsh, so Pester can attach mocks to them offline (spec section 5).
        foreach ($winOnlyCmd in @('Get-Service', 'Stop-Service', 'Start-Service',
                'Get-AppxPackage', 'Get-AppxProvisionedPackage',
                'Remove-AppxPackage', 'Remove-AppxProvisionedPackage')) {
            if (-not (Get-Command $winOnlyCmd -ErrorAction SilentlyContinue)) {
                Set-Item -Path "function:global:$winOnlyCmd" -Value { }
            }
        }

        # Mock ALL external commands so nothing leaves the machine and no real
        # registry/provider/AppX surface is touched.
        Mock Test-IsAdministrator { $true }
        Mock Add-Content { }
        Mock Test-Path { $true }
        Mock New-Item { }
        Mock Get-Service { $null }
        Mock Stop-Service { }
        Mock Start-Service { }
        Mock Get-Process { $null }
        Mock Stop-Process { }
        Mock Get-AppxPackage { @() }
        Mock Get-AppxProvisionedPackage { @() }
        Mock Remove-AppxPackage { }
        Mock Remove-AppxProvisionedPackage { }
        Mock Export-Csv { }
        Mock Read-Host { 'N' }

        # Canonical non-system AppX blocker used by the behavioral tests.
        $script:blockerFullName = 'Contoso.Blocker_1.0.0.0_x64__abcde12345'
        $script:sysprepBlocker = [pscustomobject]@{
            Name            = 'Contoso.Blocker'
            PackageFullName = $script:blockerFullName
            Version         = '1.0.0.0'
            Publisher       = 'CN=Contoso'
            SignatureKind   = 'Private'
            NonRemovable    = $false
            IsFramework     = $false
            InstallLocation = 'C:\Program Files\WindowsApps\Contoso.Blocker_1.0.0.0_x64__abcde12345'
        }

        $raw = [IO.File]::ReadAllText($scriptPath)
        $tokens = $null
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errors)
    }

    Context 'Help & Metadata' {
        It 'Declares all five NOTES fields with relaunch values' {
            ($raw -match '(?m)^\.NOTES') | Should -BeTrue
            $raw | Should -Match '(?m)File Name\s*:\s*Remove-SysprepBlockers\.ps1'
            $raw | Should -Match '(?m)Author\s*:\s*\S+'
            $raw | Should -Match '(?m)Prerequisite\s*:\s*PowerShell 7\.0'
            $raw | Should -Match '(?m)Version\s*:\s*1\.0\.0'
            $raw | Should -Match '(?m)Date\s*:\s*2026-08-23'
        }

        It 'Has one PARAMETER entry per declared parameter' {
            $paramNames = @('Force', 'LogPath', 'ExportBlockersList')
            foreach ($name in $paramNames) {
                $raw | Should -Match "(?m)\.PARAMETER\s+$name"
            }
            # No orphaned PARAMETER help without a matching parameter
            $helpParams = [regex]::Matches($raw, '(?m)^\.PARAMETER\s+(\w+)') | ForEach-Object { $_.Groups[1].Value }
            $helpParams | Should -Be $paramNames
        }

        It 'Has at least two EXAMPLES with PS C:\> prompt lines' {
            $examples = [regex]::Matches($raw, '(?m)^\.EXAMPLE')
            $examples.Count | Should -BeGreaterOrEqual 2
            ([regex]::Matches($raw, 'PS C:\\>')).Count | Should -BeGreaterOrEqual 2
        }

        It 'Has an imperative SYNOPSIS under 120 characters' {
            $raw | Should -Match '(?m)^\.SYNOPSIS\r?\n\s+\S'
            $synopsisLine = (($raw -split "`r?`n") |
                Where-Object { $_ -match '^\s{4}\S' } |
                Select-Object -First 1)
            $synopsisLine.Length | Should -BeLessOrEqual 120
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
    }

    Context 'Behavior' {
        It 'Returns 0 and mutates nothing on a converged system (idempotent)' {
            Mock Get-AppxPackage { @() }
            $out = Main *>&1
            $out | Where-Object { $_ -is [int] } | Should -Be 0
            ($out | Out-String) | Should -Match '\[\+\]'
            Should -Invoke Remove-AppxPackage -Times 0 -Exactly -Because 'nothing left to remove'
            Should -Invoke Remove-AppxProvisionedPackage -Times 0 -Exactly
            Should -Invoke Stop-Service -Times 0 -Exactly
        }

        It 'Detects blockers, removes them under -Force, and returns 0' {
            Mock Get-AppxPackage {
                if ($PSBoundParameters.ContainsKey('Name')) {
                    if ($Name -like '*Contoso.Blocker*') {
                        return @([pscustomobject]@{ PackageFullName = $script:blockerFullName })
                    }
                    return @()   # explicit offender lookup finds nothing extra
                }
                return @($script:sysprepBlocker)
            }
            $prevForce = $Force
            $Force = $true
            try {
                $out = Main *>&1
                $out | Where-Object { $_ -is [int] } | Should -Be 0
                ($out | Out-String) | Should -Match '\[\+\] Removed package for all users'
            }
            finally {
                $Force = $prevForce
            }
            Should -Invoke Remove-AppxPackage -Times 1 -Exactly -Scope It
        }

        It 'Prompts first and removes nothing when the user declines' {
            Mock Get-AppxPackage { @($script:sysprepBlocker) }
            Mock Get-UserConfirmation { 'N' }
            $out = Main *>&1
            $out | Where-Object { $_ -is [int] } | Should -Be 0
            ($out | Out-String) | Should -Match '\[!\] Operation cancelled by user'
            Should -Invoke Remove-AppxPackage -Times 0 -Exactly
            Should -Invoke Stop-Service -Times 0 -Exactly
        }

        It 'Returns 1 and logs [-] output when package removal fails' {
            Mock Get-AppxPackage {
                if ($PSBoundParameters.ContainsKey('Name')) {
                    if ($Name -like '*Contoso.Blocker*') {
                        return @([pscustomobject]@{ PackageFullName = $script:blockerFullName })
                    }
                    return @()
                }
                return @($script:sysprepBlocker)
            }
            Mock Remove-AppxPackage { throw 'package in use' }
            $prevForce = $Force
            $Force = $true
            try {
                $out = Main *>&1
                $out | Where-Object { $_ -is [int] } | Should -Be 1
                ($out | Out-String) | Should -Match '\[-\]'
            }
            finally {
                $Force = $prevForce
            }
        }

        It 'Honors -WhatIf: detects blockers but performs zero mutations' {
            Mock Get-AppxPackage { @($script:sysprepBlocker) }
            $prevForce = $Force
            $Force = $true
            try {
                $out = Main -WhatIf *>&1
                $out | Where-Object { $_ -is [int] } | Should -Be 0
            }
            finally {
                $Force = $prevForce
            }
            Should -Invoke Remove-AppxPackage -Times 0 -Exactly -Scope It
            Should -Invoke Remove-AppxProvisionedPackage -Times 0 -Exactly -Scope It
            Should -Invoke Stop-Service -Times 0 -Exactly -Scope It
            Should -Invoke Stop-Process -Times 0 -Exactly -Scope It
        }

        It 'Returns 1 with [-] prefix when not running elevated' {
            Mock Test-IsAdministrator { $false }
            $out = Main *>&1
            $out | Where-Object { $_ -is [int] } | Should -Be 1
            ($out | Out-String) | Should -Match '\[-\]'
        }
    }
}
