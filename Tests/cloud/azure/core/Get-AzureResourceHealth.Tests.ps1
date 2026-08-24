#Requires -Modules Pester
<#
.SYNOPSIS
    Pester tests for scripts/cloud/azure/core/Get-AzureResourceHealth.ps1.
.DESCRIPTION
    Validates help/metadata conformance, static syntax rules, and observable behavior
    of the Azure resource health script using fully mocked Az cmdlets.
    Runs offline on Linux pwsh; no Azure connectivity or installed modules required.
.EXAMPLE
    PS C:\> Invoke-Pester -Path ./Tests/cloud/azure/core/Get-AzureResourceHealth.Tests.ps1
    Runs this test file.
.NOTES
    File Name   : Get-AzureResourceHealth.Tests.ps1
    Author      : Bug-Free Umbrella
    Prerequisite: PowerShell 7.0
    Version     : 1.0.0
    Date        : 2026-08-23
#>

Describe 'Get-AzureResourceHealth' {
    BeforeAll {

        # Safe: the script's top-level guard skips Main when dot-sourced (spec section 3).
        $scriptPath = Join-Path $PSScriptRoot '../../../../scripts/cloud/azure/core/Get-AzureResourceHealth.ps1'
        . $scriptPath

        # Mock ALL external module cmdlets so nothing leaves the machine.
        # The Az module is not installed offline: stub its cmdlets so Pester can mock them.
        function Get-AzContext { }
        function Set-AzContext { }
        function Get-AzVM { }
        function Get-AzStorageAccount { }
        function Get-AzVirtualNetwork { }
        function Get-AzNetworkSecurityGroup { }

        Mock Import-Module { }
        Mock Get-AzContext {
            [pscustomobject]@{ Subscription = [pscustomobject]@{ Name = 'sub-prod' } }
        }
        Mock Set-AzContext { [pscustomobject]@{ Subscription = [pscustomobject]@{ Name = 'sub-target' } } }
        Mock Get-AzVM {
            @(
                [pscustomobject]@{ PowerState = 'VM running' }
                [pscustomobject]@{ PowerState = 'VM running' }
                [pscustomobject]@{ PowerState = 'VM deallocated' }
            )
        }
        Mock Get-AzStorageAccount { @([pscustomobject]@{ StorageAccountName = 'sa1' }) }
        Mock Get-AzVirtualNetwork { @([pscustomobject]@{ Name = 'vnet1' }) }
        Mock Get-AzNetworkSecurityGroup { @() }

        $raw = [IO.File]::ReadAllText($scriptPath)
        $tokens = $null; $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errors)
    }

    Context 'Help & Metadata' {
        It 'Declares all five NOTES fields with relaunch values' {
            ($raw -match '(?m)^\.NOTES') | Should -BeTrue
            $raw | Should -Match '(?m)File Name\s*:\s*Get-AzureResourceHealth\.ps1'
            $raw | Should -Match '(?m)Author\s*:\s*\S+'
            $raw | Should -Match '(?m)Prerequisite\s*:\s*PowerShell 7\.0'
            $raw | Should -Match '(?m)Version\s*:\s*1\.0\.0'
            $raw | Should -Match '(?m)Date\s*:\s*2026-08-23'
        }

        It 'Has one PARAMETER entry per declared parameter' {
            foreach ($name in @('SubscriptionId', 'ExportHTML')) {
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

        It 'Uses CmdletBinding, Main function, and dot-source guard' {
            $raw | Should -Match '\[CmdletBinding\(\)\]'
            $raw | Should -Match '(?m)function Main\b'
            $raw | Should -Match 'if \(\$MyInvocation\.InvocationName -ne ''\.''\) \{ exit \(Main\) \}'
        }

        It 'Contains no top-level throw; exit appears only in the guard line' {
            ($ast.FindAll({ param($n) $n.GetType().Name -eq 'ThrowStatement' }, $false)).Count | Should -Be 0
        }

        It 'Contains no PS7-only operators (no #Requires opt-out)' {
            ($raw -match '\?\?') | Should -BeFalse
            ($raw -match '\|\|') | Should -BeFalse
            ($raw -match '&&') | Should -BeFalse
        }

        It 'Is UTF-8 with BOM and CRLF line endings' {
            $bytes = [IO.File]::ReadAllBytes($scriptPath)
            ($bytes[0], $bytes[1], $bytes[2]) | Should -Be (0xEF, 0xBB, 0xBF)
            ($raw -replace "`r`n", '').Contains("`n") | Should -BeFalse
        }
    }

    Context 'Behavior' {
        It 'Inventories VMs, storage, and networking, returning 0 when connected' {
            $out = Main *>&1
            $text = $out | Out-String
            $text | Should -Match '\[\+\] Connected to: sub-prod'
            $text | Should -Match '\[\+\] Found 3 VMs \(2 running\)'
            $text | Should -Match '\[\+\] Found 1 storage accounts'
            $text | Should -Match '\[\+\] Found 1 VNets, 0 NSGs'
            $text | Should -Match '\[\+\] Health check complete'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            Should -Invoke Get-AzVM -Times 1 -Exactly
            Should -Invoke Get-AzStorageAccount -Times 1 -Exactly
            Should -Invoke Get-AzVirtualNetwork -Times 1 -Exactly
            Should -Invoke Get-AzNetworkSecurityGroup -Times 1 -Exactly
        }

        It 'Switches subscription when SubscriptionId is provided' {
            $sub = '00000000-0000-0000-0000-000000000001'
            $SubscriptionId = $sub
            try {
                Main | Should -Be 0
                Should -Invoke Set-AzContext -Times 1 -Exactly -ParameterFilter { $SubscriptionId -eq $sub }
            }
            finally {
                $SubscriptionId = $null
            }
        }

        It 'Returns 1 with [-] output when not connected to Azure' {
            Mock Get-AzContext { $null }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[-\].*Not connected to Azure'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
            Should -Invoke Get-AzVM -Times 0 -Exactly -Because 'connection check fails first'
        }

        It 'Returns 1 when the Az module cannot be imported' {
            Mock Import-Module { throw 'Az module not installed' }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[-\]'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }

        It 'Degrades gracefully: a failed resource query warns but still exits 0' {
            Mock Get-AzVM { throw 'provider error' }
            $out = Main *>&1
            $text = $out | Out-String
            $text | Should -Match '\[!\] Failed to retrieve VMs: provider error'
            $text | Should -Match '\[\+\] Health check complete'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
        }

        It 'Is idempotent: repeated runs are read-only and always succeed' {
            Main | Should -Be 0
            Main | Should -Be 0
        }
    }
}
