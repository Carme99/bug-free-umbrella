#Requires -Modules Pester

Describe "Set-EnglishUKRegion" {
    BeforeAll {
        # Mirrored layout: this file lives at Tests/infrastructure/windows/system/ -> script is four levels up.
        $scriptRelPath = "../../../../scripts/infrastructure/windows/system/Set-EnglishUKRegion.ps1"
        $scriptPath = Join-Path $PSScriptRoot $scriptRelPath

        # Safe: the script's top-level guard skips Main when dot-sourced.
        . $scriptPath

        # Windows-only cmdlets are absent on Linux CI - define no-op stubs
        # so Pester has an existing command to attach each Mock to.
        foreach ($cmd in @(
                'Get-WinSystemLocale', 'Set-WinSystemLocale', 'Get-WinUILanguageOverride', 'Set-WinUILanguageOverride',
                'Set-Culture', 'Set-WinHomeLocation', 'Get-WinHomeLocation', 'Set-WinUserLanguageList',
                'Set-TimeZone', 'Import-Module', 'Restart-Computer'
            )) {
            if (-not (Get-Command -Name $cmd -ErrorAction SilentlyContinue)) {
                . ([scriptblock]::Create("function script:$cmd { }"))
            }
        }

        function New-FakeTimeZone([string]$Id) {
            return [pscustomobject]@{ Id = $Id; DisplayName = "(UTC+00:00) $Id" }
        }

        # Mock platform/external seams so nothing leaves the machine.
        Mock Test-AdminPrivilege { $true }
        Mock Get-Module { [pscustomobject]@{ Name = 'International' } }
        Mock Import-Module { }
        Mock Invoke-Reg { [pscustomobject]@{ ExitCode = 0; Output = "" } }
        Mock Invoke-ControlIntlCpl { [pscustomobject]@{ ExitCode = 0 } }
        Mock Test-RegistryHiveLoaded { $false }
        Mock Test-Path { $true }
        Mock Set-ItemProperty { }
        Mock Out-File { }
        Mock Remove-Item { }
        Mock Start-Sleep { }
        Mock Restart-Computer { }

        # Non-converged by default so the success path exercises every mutation.
        Mock Get-Culture { [pscustomobject]@{ Name = 'en-US'; DisplayName = 'English (United States)' } }
        Mock Get-WinSystemLocale { [pscustomobject]@{ Name = 'en-US'; DisplayName = 'English (United States)' } }
        Mock Get-WinHomeLocation { [pscustomobject]@{ GeoId = 234; HomeLocation = 234 } }
        Mock Get-WinUILanguageOverride { 'en-US' }
        Mock Get-TimeZone {
            param($ListAvailable)
            if ($ListAvailable) {
                return @(New-FakeTimeZone 'GMT Standard Time')
            }
            return (New-FakeTimeZone 'Pacific Standard Time')
        }

        # Mutators: asserted via Should -Invoke in behavioral tests.
        Mock Set-WinSystemLocale { }
        Mock Set-WinUILanguageOverride { }
        Mock Set-Culture { }
        Mock Set-WinHomeLocation { }
        Mock Set-TimeZone { }
        Mock Set-WinUserLanguageList { }
    }

    Context "Help & Metadata" {
        It "Declares the required header fields with relaunch values" {
            $text = Get-Content -LiteralPath $scriptPath -Raw
            $text | Should -Match '\.SYNOPSIS'
            $text | Should -Match '\.DESCRIPTION'
            $text | Should -Match 'File Name:\s*Set-EnglishUKRegion\.ps1'
            $text | Should -Match 'Version:\s*1\.0\.0'
            $text | Should -Match 'Date:\s*2026-08-23'
            $text | Should -Match 'Prerequisite:\s*PowerShell'
            $text | Should -Match 'Author:\s*\S'
        }

        It "Documents exactly the declared parameters in order" {
            $text = Get-Content -LiteralPath $scriptPath -Raw
            $helpParams = [regex]::Matches($text, '(?m)^\.PARAMETER\s+(\w+)') | ForEach-Object { $_.Groups[1].Value }
            $tokens = $null; $parseErrors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile(
                $scriptPath, [ref]$tokens, [ref]$parseErrors)
            $declared = $ast.ParamBlock.Parameters.Name.VariablePath.UserPath
            $helpParams | Should -Be $declared
        }

        It "Provides at least two examples with PS C:\> prompts" {
            $text = Get-Content -LiteralPath $scriptPath -Raw
            ([regex]::Matches($text, '(?m)^\.EXAMPLE')).Count | Should -BeGreaterOrEqual 2
            ([regex]::Matches($text, 'PS C:\\>')).Count | Should -BeGreaterOrEqual 2
        }
    }

    Context "Syntax & Static" {
        It "Parses cleanly" {
            $tokens = $null; $parseErrors = $null
            $parse = [System.Management.Automation.Language.Parser]::ParseFile(
                $scriptPath, [ref]$tokens, [ref]$parseErrors)
            $parse | Out-Null
            $parseErrors | Should -BeNullOrEmpty
        }

        It "Contains no PS7-only syntax without #Requires -Version 7.0" {
            $text = Get-Content -LiteralPath $scriptPath -Raw
            if ($text -notmatch '(?m)^#Requires\s+-Version\s+7') {
                $text | Should -Not -Match '\?\?'
                $text | Should -Not -Match '\|\|'
                $text | Should -Not -Match '&&'
                $text | Should -Not -Match '-Parallel'
            }
        }

        It "Uses no tabs, max 120 columns and no trailing whitespace" {
            $lines = Get-Content -LiteralPath $scriptPath
            $bad = @($lines | Where-Object { $_ -match "`t" -or $_ -match '\s$' -or $_.Length -gt 120 })
            $bad | Should -BeNullOrEmpty
        }

        It "Uses only approved verbs for its functions" {
            $tokens = $null; $parseErrors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile(
                $scriptPath, [ref]$tokens, [ref]$parseErrors)
            $functions = $ast.FindAll(
                { $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false) |
                Where-Object { $_.Name -notin @('Main') }
            $approved = (Get-Verb).Verb
            $functions.Name | ForEach-Object { ($_ -split '-')[0] } | Should -BeIn $approved
        }
    }

    Context "Behavior" {
        It "Configures all regional settings and returns 0 on success" {
            $out = Main *>&1

            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            ($out | Out-String) | Should -Match '\[\+\]'
            Should -Invoke Set-WinSystemLocale -Times 1 -Exactly
            Should -Invoke Set-WinUILanguageOverride -Times 1 -Exactly
            Should -Invoke Set-Culture -Times 1 -Exactly
            Should -Invoke Set-WinHomeLocation -Times 1 -Exactly
            Should -Invoke Set-TimeZone -Times 1 -Exactly
            Should -Invoke Set-WinUserLanguageList -Times 1 -Exactly
            Should -Invoke Invoke-ControlIntlCpl -Times 1 -Exactly
        }

        It "Returns 1 and writes [-] output when not running as Administrator" {
            Mock Test-AdminPrivilege { $false }

            $out = Main *>&1

            ($out | Out-String) | Should -Match '\[-\]'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
            Should -Invoke Set-WinSystemLocale -Times 0 -Exactly
        }

        It "Returns 1 when the International module cannot be imported" {
            Mock Get-Module { $null }
            Mock Import-Module { throw "module unavailable" }

            $out = Main *>&1

            ($out | Out-String) | Should -Match '\[-\]'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
        }

        It "Is idempotent: converged system returns 0 with no changes" {
            Mock Get-Culture { [pscustomobject]@{ Name = 'en-GB'; DisplayName = 'English (United Kingdom)' } }
            Mock Get-WinSystemLocale { [pscustomobject]@{ Name = 'en-GB'; DisplayName = 'English (United Kingdom)' } }
            Mock Get-WinHomeLocation { [pscustomobject]@{ GeoId = 242; HomeLocation = 242 } }
            Mock Get-WinUILanguageOverride { 'en-GB' }
            Mock Get-TimeZone {
                param($ListAvailable)
                if ($ListAvailable) { return @(New-FakeTimeZone 'GMT Standard Time') }
                return (New-FakeTimeZone 'GMT Standard Time')
            }

            $out = Main *>&1

            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            ($out | Out-String) | Should -Match 'already configured'
            Should -Invoke Set-WinSystemLocale -Times 0 -Exactly -Because "the system has already converged"
            Should -Invoke Set-TimeZone -Times 0 -Exactly
            Should -Invoke Set-ItemProperty -Times 0 -Exactly
            Should -Invoke Invoke-Reg -Times 0 -Exactly
        }

        It "Honours -WhatIf: returns 0 without applying any changes" {
            $out = Main -WhatIf *>&1

            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            Should -Invoke Set-WinSystemLocale -Times 0 -Exactly
            Should -Invoke Set-ItemProperty -Times 0 -Exactly
            Should -Invoke Invoke-Reg -Times 0 -Exactly
        }
    }
}
