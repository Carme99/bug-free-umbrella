<#
.SYNOPSIS
    Pester 5 tests for scripts/cloud/azure/avd/removeUSlangpack.ps1.

.DESCRIPTION
    Offline Pester coverage: help/metadata conformance, syntax/static checks, and behavior of
    Main against fully mocked Windows language-stack cmdlets and the native logoff wrapper.

.NOTES
    File Name   : removeUSlangpack.Tests.ps1
    Author      : Bug-Free Umbrella
    Prerequisite: PowerShell 7.0
    Version     : 1.0.0
    Date        : 2026-08-23
#>

#Requires -Modules Pester

Describe "removeUSlangpack" {
    BeforeAll {
        $scriptPath = Join-Path $PSScriptRoot "../../../../scripts/cloud/azure/avd/removeUSlangpack.ps1"
        $scriptContent = Get-Content -Path $scriptPath -Raw

        # Safe: the script's top-level guard skips Main when dot-sourced (RELAUNCH-SPEC §3).
        . $scriptPath

        # Windows-only cmdlets are absent on Linux pwsh; Pester needs a stub before it can mock.
        function Get-CimInstance { }
        function Get-WinSystemLocale { }
        function Get-WinUserLanguageList { }
        function Set-WinUserLanguageList { }
        function New-WinUserLanguageList { }
        function Get-WindowsCapability { }
        function Remove-WindowsCapability { }

        function New-MockLanguage {
            param([string]$Tag, [string[]]$Tips = @())
            [pscustomobject]@{
                LanguageTag     = $Tag
                InputMethodTips = [System.Collections.Generic.List[string]]::new([string[]]$Tips)
            }
        }

        # Mock every external surface: Windows language cmdlets, CIM, registry provider, capabilities,
        # and the native logoff.exe wrapper. Nothing here touches a real system.
        Mock Get-CimInstance { [pscustomobject]@{ Caption = "Microsoft Windows 11 Pro" } }
        Mock Get-WinSystemLocale { [pscustomobject]@{ Name = "en-GB" } }
        Mock Get-WinUserLanguageList { $script:mockLanguages }
        Mock Set-WinUserLanguageList { }
        Mock New-WinUserLanguageList { }
        Mock Get-WindowsCapability { @([pscustomobject]@{ Name = "Language.Basic~~~en-US~0.0.1.0"; State = "Installed" }) }
        Mock Remove-WindowsCapability { }
        Mock Test-Path { $false }
        Mock Get-ItemProperty { }
        Mock Set-ItemProperty { }
        Mock Invoke-Logoff { 0 }

        $script:gbOnly = @(New-MockLanguage "en-GB")
        $script:gbPlusUs = @(
            (New-MockLanguage "en-GB" @("0409:00000809", "0809:00000409"))
            (New-MockLanguage "en-US" @("0409:00000409"))
        )
    }

    Context "Help & Metadata" {
        It "Declares all five required .NOTES fields with relaunch values" {
            $scriptContent | Should -Match '\.NOTES'
            $scriptContent | Should -Match 'File Name\s*:\s*removeUSlangpack\.ps1'
            $scriptContent | Should -Match 'Author\s*:\s*\S+'
            $scriptContent | Should -Match 'Prerequisite\s*:\s*PowerShell 7\.0'
            $scriptContent | Should -Match 'Version\s*:\s*1\.0\.0'
            $scriptContent | Should -Match 'Date\s*:\s*2026-08-23'
        }

        It "Documents one .PARAMETER per declared parameter" {
            $tokens = $null; $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errors)
            $paramNames = @($ast.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath })
            $paramNames | Should -Not -BeNullOrEmpty
            foreach ($p in $paramNames) {
                $scriptContent | Should -Match "\.PARAMETER\s+$([regex]::Escape($p))"
            }
            ([regex]::Matches($scriptContent, '(?m)^\.PARAMETER').Count) | Should -Be $paramNames.Count
        }

        It "Provides at least two examples with prompt lines using the real filename" {
            ([regex]::Matches($scriptContent, '(?m)^\.EXAMPLE').Count) | Should -BeGreaterOrEqual 2
            ($scriptContent -split '\.EXAMPLE')[1] | Should -Match 'PS C:\\>\s+\.\\removeUSlangpack\.ps1'
        }

        It "Declares SupportsShouldProcess because the script is destructive" {
            $scriptContent | Should -Match '\[CmdletBinding\(SupportsShouldProcess\s*=\s*\$true\)\]'
            $scriptContent | Should -Match '\$PSCmdlet\.ShouldProcess'
        }
    }

    Context "Syntax & Static" {
        It "Parses with zero syntax errors" {
            $tokens = $null; $errors = $null
            [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errors) | Out-Null
            $errors | Should -HaveCount 0
        }

        It "Wraps execution in Main behind the dot-source guard with exit only in the guard line" {
            $scriptContent | Should -Match 'function Main\b'
            $scriptContent | Should -Match 'if \(\$MyInvocation\.InvocationName -ne ''\.''\) \{ exit \(Main @PSBoundParameters\) \}'
            @($scriptContent | Select-String '(?m)^\s*exit\b' | Where-Object { $_.Line -notmatch '@PSBoundParameters' }) | Should -BeNullOrEmpty
        }

        It "Routes the native logoff executable through the Invoke-Logoff wrapper" {
            $scriptContent | Should -Match 'function Invoke-Logoff'
            # The only native invocation of logoff must live inside the wrapper body.
            $outsideWrapper = $scriptContent -replace '(?s)function Invoke-Logoff.*?\r?\n\}', ''
            @($outsideWrapper | Select-String '(?i)&\s*logoff(\.exe)?\b|^\s*logoff(\.exe)?\b') | Should -BeNullOrEmpty
        }

        It "Uses no tabs and no trailing whitespace" {
            $scriptContent | Should -Not -Match "`t"
            @($scriptContent | Select-String '(?m)[ \t]+\r?$') | Should -BeNullOrEmpty
        }
    }

    Context "Behavior" {
        It "Is idempotent: converged system (no en-US) returns 0 with zero mutations" {
            $script:mockLanguages = $script:gbOnly
            $out = Main -Force *>&1
            ($out | Out-String) | Should -Match 'nothing to remove'
            $out | Where-Object { $_ -is [int] } | Should -Be 0
            Should -Invoke Set-WinUserLanguageList -Times 0 -Exactly -Because "nothing left to remove"
            Should -Invoke Remove-WindowsCapability -Times 0 -Exactly
        }

        It "Removes en-US, US keyboards, and US capabilities with -Force and returns 0" {
            $script:mockLanguages = $script:gbPlusUs
            $out = Main -Force *>&1
            $out | Where-Object { $_ -is [int] } | Should -Be 0
            # One Set call removes en-US from the list, one persists keyboard layout changes.
            Should -Invoke Set-WinUserLanguageList -Times 2 -Exactly
            Should -Invoke Remove-WindowsCapability -Times 1 -Exactly
            Should -Invoke Invoke-Logoff -Times 0 -Exactly -Because "-Force skips the interactive sign-out prompt"
            ($out | Out-String) | Should -Match '\[\+\].*Removed en-US from language list'
        }

        It "Honors -WhatIf: returns 0 while making zero mutations" {
            $script:mockLanguages = $script:gbPlusUs
            $out = Main -Force -WhatIf *>&1
            $out | Where-Object { $_ -is [int] } | Should -Be 0
            Should -Invoke Set-WinUserLanguageList -Times 0 -Exactly
            Should -Invoke Remove-WindowsCapability -Times 0 -Exactly
        }

        It "Returns 1 under -Force when en-GB is not installed" {
            $script:mockLanguages = @(New-MockLanguage "en-US")
            $out = Main -Force *>&1
            ($out | Out-String) | Should -Match '\[-\]'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
            Should -Invoke Set-WinUserLanguageList -Times 0 -Exactly
        }

        It "-KeepKeyboard keeps US keyboard layouts: only one Set-WinUserLanguageList mutation" {
            $script:mockLanguages = $script:gbPlusUs
            $out = Main -Force -KeepKeyboard *>&1
            $out | Where-Object { $_ -is [int] } | Should -Be 0
            Should -Invoke Set-WinUserLanguageList -Times 1 -Exactly -Because "only the language-list removal should mutate state"
            ($out | Out-String) | Should -Match 'Keeping US keyboard layout as requested'
        }

        It "Cleans en-US from registry Languages only when the key exists with en-US" {
            $script:mockLanguages = $script:gbOnly
            Mock Test-Path { $true }
            Mock Get-ItemProperty { [pscustomobject]@{ Languages = @("en-GB", "en-US") } }
            Main -Force | Should -Be 0
            Should -Invoke Set-ItemProperty -Times 0 -Exactly -Because "converged run has no en-US to remove so no registry write occurs"
        }
    }
}
