#Requires -Modules Pester

Describe "_generate-winget-scripts" {
    BeforeAll {
        # Mirrored layout: walk up from Tests/... to the repo root, then across to scripts/.
        $repoRoot = $PSScriptRoot
        while (-not (Test-Path (Join-Path $repoRoot '.git'))) { $repoRoot = Split-Path $repoRoot -Parent }
        $scriptRelPath = 'scripts/endpoints/remediation/winget/_generate-winget-scripts.ps1'
        $scriptPath = Join-Path $repoRoot $scriptRelPath

        # Safe: the script's top-level guard skips Main when dot-sourced.
        . $scriptPath
    }


    Context "Help & Metadata" {
        It "Declares required .NOTES fields with Version 1.0.0 and Date 2026-08-23" {
            $raw = Get-Content -Path $scriptPath -Raw
            $raw | Should -Match 'File Name:\s*_generate-winget-scripts\.ps1'
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

        It "Preserves the AppDefinitions catalog entries" {
            @($AppDefinitions).Count | Should -Be 15
            $discord = $AppDefinitions | Where-Object { $_.WingetId -eq 'Discord.Discord' }
            $discord.ForceClose | Should -BeTrue
            $discord.NotifySeconds | Should -Be 60
            ($AppDefinitions | Where-Object { $_.ForceClose }).WingetId | Should -Be 'Discord.Discord'
            $python = $AppDefinitions | Where-Object { $_.WingetId -eq 'Python.Python.3.12' }
            $python.Category | Should -Be 'development'
            $python.FolderName | Should -Be 'Python'
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
        It "Defines only approved-verb functions (except the spec-mandated Main entry point)" {
            $functions = $ast.FindAll({ $args[0] `
                -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false)
            @($functions).Count | Should -BeGreaterOrEqual 2
            $verbs = Get-Verb | ForEach-Object Verb
            foreach ($fn in $functions) {
                if ($fn.Name -eq 'Main') { continue }
                $verb = ($fn.Name -split '-')[0]
                $verbs | Should -Contain $verb -Because "$($fn.Name) must use an approved verb"
            }
        }
    }

    Context "Behavior" {
        It "Substitutes WINGETID and writes the detect/remediate pair via Set-Content" {
            Mock Test-Path { $false }
            Mock New-Item { }
            Mock Get-Content {
                if ("$Path" -match 'force_close') {
                    'remediate-force-close WINGETID $NotifyUserBeforeClose = $false $UserNotificationSeconds = 0'
                }
                elseif ("$Path" -match 'standard') {
                    'remediate-standard WINGETID'
                }
                else {
                    'detect-template WINGETID'
                }
            }
            $script:written = @()
            Mock Set-Content {
                param([string]$Path, [AllowNull()][object]$Value)
                $script:written += [pscustomobject] @{ Path = $Path; Value = $Value }
            }

            New-WingetScriptPair -WingetId 'Discord.Discord' -Category 'communication' -FolderName 'Discord' `
                -ForceClose $true `
                -NotifySeconds 60

            @($script:written).Count | Should -Be 2
            $detect = $script:written | Where-Object { $_.Path -like '*detect.ps1' }
            $remediate = $script:written | Where-Object { $_.Path -like '*remediate.ps1' }
            $detect.Value | Should -Match 'Discord\.Discord'
            $detect.Value | Should -Not -Match 'WINGETID'
            $remediate.Value | Should -Match 'Discord\.Discord'
            $remediate.Value | Should -Match '\$NotifyUserBeforeClose = \$true'
            $remediate.Value | Should -Match '\$UserNotificationSeconds = 60'
            Should -Invoke New-Item -Times 1 -Exactly -Because "the app directory does not exist yet"
        }

        It "Uses the standard remediate template for non-force-close apps" {
            Mock Test-Path { $true }
            Mock Get-Content {
                if ("$Path" -match 'standard') { 'remediate-standard WINGETID' }
                elseif ("$Path" -match 'force_close') { throw "force-close template must not be read" }
                else { 'detect-template WINGETID' }
            }
            $script:values = @()
            Mock Set-Content { param([string]$Path, [AllowNull()][object]$Value) $script:values += $Value }

            New-WingetScriptPair -WingetId 'AgileBits.1Password' -Category 'security' -FolderName '1Password' `
                -ForceClose $false `
                -NotifySeconds 0

            @($script:values).Count | Should -Be 2
            $script:values | Should -Contain 'remediate-standard AgileBits.1Password'
        }

        It "Honors -WhatIf: no directories created and no scripts written" {
            Mock Test-Path { $false }
            Mock New-Item { }
            Mock Get-Content { 'template WINGETID' }
            Mock Set-Content { throw "nothing may be written under -WhatIf" }

            $whatIfCall = {
                New-WingetScriptPair -WingetId 'Box.Box' -Category 'cloud-storage' `
                    -FolderName 'Box' -ForceClose $false -NotifySeconds 0 -WhatIf
            }
            $whatIfCall | Should -Not -Throw

            Should -Invoke New-Item -Times 0 -Exactly
            Should -Invoke Set-Content -Times 0 -Exactly -Because "ShouldProcess must gate the write"
        }

        It "Main generates a script pair for every AppDefinitions entry and returns 0" {
            Mock Test-Path { $false }
            Mock New-Item { }
            Mock Get-Content { 'template WINGETID' }
            Mock Set-Content { }

            Main *>&1 | Where-Object { $_ -is [int] } | Should -Be 0

            Should -Invoke Set-Content -Times (@($AppDefinitions).Count * 2) -Exactly
            Should -Invoke New-Item -Times @($AppDefinitions).Count -Exactly
        }

        It "Main returns 1 with [-] output and skips writes when generation fails for every app" {
            Mock Test-Path { $false }
            Mock New-Item { throw "disk full" }
            Mock Get-Content { 'template WINGETID' }
            Mock Set-Content { throw "must never be reached" }

            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[!\]'
            ($out | Out-String) | Should -Match '\[-\]'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
            Should -Invoke Set-Content -Times 0 -Exactly
        }
    }
}
