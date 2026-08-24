#Requires -Modules Pester

<#
.SYNOPSIS
    Pester 5 tests for scripts/cloud/azure/core/Monitor-AzureResources.ps1.

.DESCRIPTION
    Offline tests: all Az cmdlets are mocked at command-name level (the Az module
    is not installed in CI). Asserts Main return codes, output prefixes, mock
    interaction counts, and idempotent behavior. No network or Azure connectivity.

.NOTES
    File Name: Monitor-AzureResources.Tests.ps1
    Author: Bug-Free Umbrella
    Prerequisite: PowerShell 7.0, Pester 5.7.1
    Version: 1.0.0
    Date: 2026-08-23
#>

Describe "Monitor-AzureResources" {
    BeforeAll {
        $script:eap = $ErrorActionPreference
        $script:scriptPath = Join-Path $PSScriptRoot '../../../../scripts/cloud/azure/core/Monitor-AzureResources.ps1'

        # Stub every mocked external command so Pester can resolve it offline.
        function Get-Module { }
        function Import-Module { }
        function Get-AzContext { }
        function Set-AzContext { }
        function Get-AzSubscription { }
        function Get-AzResourceGroup { }
        function Get-AzResource { }
        function Get-AzVM { }
        function Get-AzDisk { }
        function Get-AzPublicIpAddress { }

        # Az modules are absent offline; mock the whole surface at command-name level.
        Mock Get-Module { $true }
        Mock Import-Module { }
        Mock Get-AzContext { [pscustomobject]@{ Account = 'test@contoso.com'; Subscription = 'Sub 1' } }
        Mock Set-AzContext { [pscustomobject]@{ Subscription = 'Sub 1' } }
        Mock Get-AzSubscription {
            @([pscustomobject]@{ Name = 'Sub 1'; Id = [guid]'00000000-0000-0000-0000-000000000001'; State = 'Enabled' })
        }
        Mock Get-AzResourceGroup {
            @([pscustomobject]@{ ResourceGroupName = 'rg-1'; Location = 'westeurope'; Tags = @{} })
        }
        Mock Get-AzResource { @([pscustomobject]@{ Name = 'res-1' }) }
        Mock Get-AzVM { @() }
        Mock Get-AzDisk { @() }
        Mock Get-AzPublicIpAddress { @() }
        Mock New-Item -ParameterFilter { $ItemType -eq 'Directory' } { }
        Mock Out-File { }

        # Safe: the script's top-level guard skips Main when dot-sourced.
        . $script:scriptPath

        # Keep behavioral runs off the file-writing report branches by default.
        $OutputFormat = 'Console'

        # Static analysis inputs
        $tokens = $null
        $script:parseErrors = $null
        $script:ast = [System.Management.Automation.Language.Parser]::ParseFile(
            $script:scriptPath, [ref]$tokens, [ref]$script:parseErrors)
        $script:paramBlock = $ast.Find(
            { param($a) $a -is [System.Management.Automation.Language.ParamBlockAst] }, $true)
        $script:paramNames = @($paramBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath })

        $script:raw = [IO.File]::ReadAllText($script:scriptPath)
        $script:header = ($raw -split '\[CmdletBinding\(\)\]')[0]
        $script:bom = ([IO.File]::ReadAllBytes($script:scriptPath)[0..2]) -join ','
        $bareLf = 0
        for ($i = 1; $i -lt $raw.Length; $i++) {
            if ($raw[$i] -eq "`n" -and $raw[$i - 1] -ne "`r") { $bareLf++ }
        }
        $script:bareLfCount = $bareLf
        $script:exitStatements = @($ast.Find(
            { param($a) $a -is [System.Management.Automation.Language.ExitStatementAst] }, $true))
    }

    AfterAll {
        $ErrorActionPreference = $script:eap
    }

    Context "Help & Metadata" {
        It "declares File Name matching the disk filename" {
            $raw | Should -Match '(?m)^\s*File Name:\s*Monitor-AzureResources\.ps1\s*$'
        }

        It "declares Version 1.0.0 and Date 2026-08-23" {
            $raw | Should -Match '(?m)^\s*Version:\s*1\.0\.0\s*$'
            $raw | Should -Match '(?m)^\s*Date:\s*2026-08-23\s*$'
        }

        It "declares Author and PowerShell 7.0 prerequisite" {
            $raw | Should -Match '(?m)^\s*Author:\s*\S'
            $raw | Should -Match '(?m)^\s*Prerequisite:.*PowerShell 7\.0'
        }

        It "has one .PARAMETER per declared parameter, in param order" {
            $helpRegex = '(?m)^\s*\.PARAMETER\s+(\S+)'
            $helpParams = @([regex]::Matches($script:header, $helpRegex) |
                ForEach-Object { $_.Groups[1].Value })
            $helpParams | Should -Be $paramNames
        }

        It "binds comment-based help so Get-Help -Detailed renders fully" {
            $h = Get-Help -Name $script:scriptPath -Detailed
            $h.Synopsis | Should -Not -Match [regex]::Escape($script:scriptPath)
            @($h.examples.example).Count | Should -BeGreaterOrEqual 2
        }
        It "has at least two examples with PS C:\> prompts" {
            ($raw -split '\.EXAMPLE').Count - 1 | Should -BeGreaterOrEqual 2
            $raw | Should -Match 'PS C:\\>'
        }
    }

    Context "Syntax & Static" {
        It "parses with zero errors" {
            $parseErrors | Should -BeNullOrEmpty
        }

        It "is UTF-8 BOM with CRLF line endings" {
            $bom | Should -Be '239,187,191'
            $bareLfCount | Should -Be 0
        }

        It "uses exit only in the top-level dot-source guard" {
            $exitStatements.Count | Should -Be 1
            $guardLine = (Get-Content -LiteralPath $script:scriptPath)[$exitStatements[0].Extent.StartLineNumber - 1]
            $guardLine | Should -Match 'if \(\$MyInvocation\.InvocationName -ne'
        }

        It "keeps lines within 120 columns" {
            $long = @((Get-Content -LiteralPath $script:scriptPath) |
                Where-Object { $_.Length -gt 120 })
            $long | Should -BeNullOrEmpty
        }
    }

    Context "Behavior" {
        It "returns 0 and reports subscription analysis in console format" {
            $OutputFormat = 'Console'
            $out = Main *>&1
            $out | Where-Object { $_ -is [int] } | Should -Be 0
            ($out | Out-String) | Should -Match '\[\*\] Analyzing Azure resources'
            ($out | Out-String) | Should -Match '\[\+\] Analysis complete!'
            Should -Invoke Set-AzContext -Times 1 -Exactly -Because 'one mocked subscription is processed'
        }

        It "collects resource groups and VM counts from the mocked Az surface" {
            $OutputFormat = 'Console'
            $out = Main *>&1
            ($out | Out-String) | Should -Match 'Sub 1: 1 resources'
            Should -Invoke Get-AzResourceGroup -Times 1 -Exactly
            Should -Invoke Get-AzVM -Times 1 -Exactly
        }

        It "is idempotent: a second run succeeds again with no extra mutations" {
            $OutputFormat = 'Console'
            Main | Should -Be 0
            Main | Should -Be 0
            Should -Invoke Get-AzResourceGroup -Times 2 -Exactly -Because 'each run queries once; nothing accumulates'
        }

        It "returns 1 and writes [-] output when not authenticated" {
            Mock Get-AzContext { $null }
            $out = Main *>&1
            $out | Where-Object { $_ -is [int] } | Should -Be 1
            ($out | Out-String) | Should -Match '\[-\]'
        }

        It "returns 1 when the Az.Accounts module is unavailable" {
            Mock Get-Module { $null }
            $out = Main *>&1
            $out | Where-Object { $_ -is [int] } | Should -Be 1
            ($out | Out-String) | Should -Match '\[-\]'
        }

        It "returns 1 on unsafe OutputPath traversal without touching Azure" {
            $OutputFormat = 'Console'
            $OutputPath = '/tmp/../etc'
            $out = Main *>&1
            $out | Where-Object { $_ -is [int] } | Should -Be 1
            Should -Invoke Get-AzContext -Times 0 -Exactly -Because 'path validation happens before any Azure call'
        }
    }
}
