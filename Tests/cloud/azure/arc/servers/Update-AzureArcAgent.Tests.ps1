#Requires -Modules Pester
<#
.SYNOPSIS
    Pester tests for scripts/cloud/azure/arc/servers/Update-AzureArcAgent.ps1.
.DESCRIPTION
    Validates help/metadata conformance, static syntax rules, and observable behavior
    using fully mocked Az.ConnectedMachine cmdlets. Runs offline on Linux pwsh; no network,
    elevation, or installed product modules required.
.EXAMPLE
    PS C:\> Invoke-Pester -Path ./Tests/cloud/azure/arc/servers/Update-AzureArcAgent.Tests.ps1
    Runs this test file.
.EXAMPLE
    PS C:\> Invoke-Pester -Path ./Tests/cloud/azure/arc/servers/Update-AzureArcAgent.Tests.ps1 -Output Detailed
    Runs this test file with per-test output.
.NOTES
    File Name   : Update-AzureArcAgent.Tests.ps1
    Author      : Bug-Free Umbrella
    Prerequisite: PowerShell 7.0
    Version     : 2.0.0
    Date        : 2026-09-16
#>

Describe 'Update-AzureArcAgent' {
    BeforeAll {
        $repoRoot = Join-Path $PSScriptRoot '../../../../..'
        $scriptPath = Join-Path $repoRoot 'scripts/cloud/azure/arc/servers/Update-AzureArcAgent.ps1'

        # Safe: the script's top-level guard skips Main when dot-sourced (spec section 3).
        . $scriptPath

        # The product module is not installed offline: declare its cmdlets as empty
        # functions so Pester can mock them, then Mock each one.
        function Get-AzContext {
            [CmdletBinding()]
            param()
        }
        function Get-AzSubscription {
            [CmdletBinding()]
            param([string]$SubscriptionId, [string]$SubscriptionName, [string]$TenantId)
        }
        function Get-AzConnectedMachine {
            [CmdletBinding()]
            param([string[]]$SubscriptionId, [string]$ResourceGroupName, [string]$Name, [string]$Expand)
        }
        function Update-AzConnectedMachine {
            [CmdletBinding()]
            param([string]$Name, [string]$ResourceGroupName, [string]$SubscriptionId, [string]$AgentUpgradeDesiredVersion, [string]$AgentUpgradeCorrelationId, [string]$Kind, [hashtable]$Tag, [switch]$AgentUpgradeEnableAutomatic)
        }

        Mock Import-Module { }
        Mock Get-AzContext {
            [pscustomobject]@{ Subscription = [pscustomobject]@{ Name = 'sub-prod'; Id = 'sub-prod-id' } }
        }
        Mock Get-AzSubscription { @() }
        Mock Get-AzConnectedMachine { @() }
        Mock Update-AzConnectedMachine { }

        function New-AgentMachine {
            param(
                [string]$MachineId = 'srv-1',
                [string]$AgentVersion = '1.57.0',
                [string]$Status = 'Connected',
                [string]$ResourceGroup = 'rg-hybrid'
            )

            [pscustomobject]@{
                Name             = $MachineId
                Id               = (
                    "/subscriptions/sub-1/resourceGroups/$ResourceGroup" +
                    "/providers/Microsoft.HybridCompute/machines/$MachineId")
                Location         = 'eastus'
                Status           = $Status
                AgentVersion     = $AgentVersion
                LastStatusChange = (Get-Date).AddHours(-1)
            }
        }

        $script:upToDateFleet = @(
            New-AgentMachine -MachineId 'srv-1'
            New-AgentMachine -MachineId 'srv-2'
        )
        $script:behindFleet = @(
            New-AgentMachine -MachineId 'srv-new' -AgentVersion '1.57.0'
            New-AgentMachine -MachineId 'srv-legacy' -AgentVersion '1.40.0'
        )
        $script:prodFleet = @(
            New-AgentMachine -MachineId 'srv-prod-1' -AgentVersion '1.40.0'
            New-AgentMachine -MachineId 'srv-dev-1' -AgentVersion '1.40.0'
        )
        $script:blankFleet = @(New-AgentMachine -MachineId 'srv-blank' -AgentVersion '')

        $raw = [IO.File]::ReadAllText($scriptPath)
        $tokens = $null
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errors)
        $paramBlock = $ast.Find({ param($a) $a -is [System.Management.Automation.Language.ParamBlockAst] }, $true)
        $paramNames = @($paramBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath })
        $header = ($raw -split '\[CmdletBinding', 2)[0]
    }

    Context 'Help & Metadata' {
        It 'Declares all five NOTES fields with v2.0.0 values' {
            $raw | Should -Match '(?m)^\.NOTES'
            $raw | Should -Match '(?m)File Name\s*:\s*Update-AzureArcAgent\.ps1'
            $raw | Should -Match '(?m)Author\s*:\s*\S+'
            $raw | Should -Match '(?m)Prerequisite\s*:\s*PowerShell 7\.0'
            $raw | Should -Match '(?m)Version\s*:\s*2\.0\.0'
            $raw | Should -Match '(?m)Date\s*:\s*2026-09-16'
        }

        It 'Has one PARAMETER entry per declared parameter, in param order' {
            $helpParams = @([regex]::Matches($header, '(?m)^\s*\.PARAMETER\s+(\S+)') |
                ForEach-Object { $_.Groups[1].Value })
            $helpParams | Should -Be $paramNames
        }

        It 'Provides at least two examples with PS prompts' {
            ([regex]::Matches($raw, '(?m)^\.EXAMPLE')).Count | Should -BeGreaterOrEqual 2
            ([regex]::Matches($raw, '(?m)^\s*PS C:\\>')).Count | Should -BeGreaterOrEqual 2
        }

        It 'Documents the 0/1 exit-code contract and the idempotent no-op message' {
            $raw | Should -Match 'Exit codes: 0 when the fleet is converged'
            $raw | Should -Match '(\[\+\] Already up to date|Already up to date)'
        }

        It 'Cites the Microsoft Learn pages for the agent upgrade API family' {
            $raw | Should -Match 'learn\.microsoft\.com/powershell/module/az\.connectedmachine/update-'
            $raw | Should -Match 'update-azconnectedmachine'
            $raw | Should -Match 'learn\.microsoft\.com/azure/azure-arc/servers/manage-agent'
        }
    }

    Context 'Syntax & Static' {
        It 'Parses with zero syntax errors' {
            $errors.Count | Should -Be 0
        }

        It 'Uses SupportsShouldProcess, a Main function, and the dot-source guard' {
            $raw | Should -Match '\[CmdletBinding\(SupportsShouldProcess\)\]'
            $raw | Should -Match '(?m)^function Main\b'
            $raw | Should -Match 'if \(\$MyInvocation\.InvocationName -ne ''\.''\) \{ exit \(Main\) \}'
        }

        It 'Gates the agent upgrade behind ShouldProcess' {
            $raw | Should -Match 'if \(\$PSCmdlet\.ShouldProcess\('
            $raw | Should -Match 'Update-AzConnectedMachine @updateParams'
        }

        It 'Contains no PS7-only operators and no #Requires opt-out' {
            ($raw -match '\?\?') | Should -BeFalse
            ($raw -match '\|\|') | Should -BeFalse
            ($raw -match '&&') | Should -BeFalse
            ($raw -match '#Requires\s+-Version') | Should -BeFalse
        }

        It 'Uses exit only in the top-level guard and never throws at the top level' {
            @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.ExitStatementAst] },
                $true)).Count | Should -Be 1
            @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.ThrowStatementAst] },
                $false)).Count | Should -Be 0
        }

        It 'Is UTF-8 with BOM and CRLF line endings' {
            $bytes = [IO.File]::ReadAllBytes($scriptPath)
            ($bytes[0], $bytes[1], $bytes[2]) | Should -Be (0xEF, 0xBB, 0xBF)
            ($raw -replace "`r`n", '').Contains("`n") | Should -BeFalse
        }

        It 'Keeps every line within 120 columns' {
            $long = @(Get-Content -LiteralPath $scriptPath | Where-Object { $_.Length -gt 120 })
            $long.Count | Should -Be 0
        }
    }

    Context 'Behavior' {
        It 'Reports [+] Already up to date and makes no change when the fleet is on target' {
            $SubscriptionId = @('sub-1')
            $ResourceGroupName = '*'
            $MachineName = '*'
            $MinimumAgentVersion = $null
            $OutputPath = $null

            Mock Get-AzConnectedMachine { $script:upToDateFleet }

            $out = Main *>&1
            $text = $out | Out-String
            $text | Should -Match '\[\*\] Target agent version: 1\.57\.0'
            $text | Should -Match '\[\+\] srv-1 already up to date \(agent 1\.57\.0\)'
            $text | Should -Match '\[\+\] Already up to date: 2 Arc-enabled servers on agent 1\.57\.0 or newer'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            Should -Invoke Update-AzConnectedMachine -Times 0 -Exactly
        }

        It 'Upgrades only the machines below -MinimumAgentVersion' {
            $SubscriptionId = @('sub-1')
            $ResourceGroupName = '*'
            $MachineName = '*'
            $MinimumAgentVersion = '1.57.0'
            $OutputPath = $null

            Mock Get-AzConnectedMachine { $script:behindFleet }

            $out = Main *>&1
            $text = $out | Out-String
            $text | Should -Match '\[\+\] Upgrade requested for srv-legacy: 1\.40\.0 -> 1\.57\.0'
            $text | Should -Match '\[\+\] Requested 1 agent upgrade\(s\) targeting 1\.57\.0'
            $text | Should -Match '\[\+\] srv-new already up to date \(agent 1\.57\.0\)'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            Should -Invoke Update-AzConnectedMachine -Times 1 -Exactly `
                -ParameterFilter { $Name -eq 'srv-legacy' -and $AgentUpgradeDesiredVersion -eq '1.57.0' }
        }

        It 'Uses the newest fleet version as the target when -MinimumAgentVersion is omitted' {
            $SubscriptionId = @('sub-1')
            $ResourceGroupName = '*'
            $MachineName = '*'
            $MinimumAgentVersion = $null
            $OutputPath = $null

            Mock Get-AzConnectedMachine { $script:behindFleet }

            $out = Main *>&1
            $text = $out | Out-String
            $text | Should -Match '\[\*\] Target agent version: 1\.57\.0'
            $text | Should -Match '\[\+\] Upgrade requested for srv-legacy'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            Should -Invoke Update-AzConnectedMachine -Times 1 -Exactly
        }

        It 'Honours -WhatIf: no update is sent and the skip is reported' {
            $SubscriptionId = @('sub-1')
            $ResourceGroupName = '*'
            $MachineName = '*'
            $MinimumAgentVersion = '1.57.0'
            $OutputPath = $null

            Mock Get-AzConnectedMachine { $script:behindFleet }

            $out = Main -WhatIf *>&1
            $text = $out | Out-String
            $text | Should -Match '\[!\] Skipped srv-legacy because ShouldProcess was not approved\.'
            $text | Should -Match '\[!\] 1 agent upgrade\(s\) skipped by ShouldProcess; nothing was changed'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            Should -Invoke Update-AzConnectedMachine -Times 0 -Exactly
        }

        It 'Filters machines with -MachineName wildcards' {
            $SubscriptionId = @('sub-1')
            $ResourceGroupName = '*'
            $MachineName = 'srv-prod-*'
            $MinimumAgentVersion = '1.57.0'
            $OutputPath = $null

            Mock Get-AzConnectedMachine { $script:prodFleet }

            $out = Main *>&1
            $text = $out | Out-String
            $text | Should -Match '\[\+\] Matched 1 Arc-enabled servers'
            $text | Should -Not -Match 'srv-dev-1'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            Should -Invoke Update-AzConnectedMachine -Times 1 -Exactly `
                -ParameterFilter { $Name -eq 'srv-prod-1' }
        }

        It 'Writes the per-machine assessment report to -OutputPath' {
            $SubscriptionId = @('sub-1')
            $ResourceGroupName = '*'
            $MachineName = '*'
            $MinimumAgentVersion = '1.57.0'
            $OutputPath = Join-Path $TestDrive 'arc-agent.json'

            Mock Get-AzConnectedMachine { $script:behindFleet }

            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[\+\] Assessment report written to: '
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0

            Test-Path -LiteralPath $OutputPath | Should -BeTrue
            $json = @(Get-Content -LiteralPath $OutputPath -Raw | ConvertFrom-Json)
            $json.Count | Should -Be 2
            ($json | Where-Object { $_.Machine -eq 'srv-legacy' }).Action | Should -Be 'UpgradeRequested'
            ($json | Where-Object { $_.Machine -eq 'srv-new' }).Action | Should -Be 'AlreadyUpToDate'
        }

        It 'Returns 1 when -MinimumAgentVersion is not a valid version' {
            $SubscriptionId = @('sub-1')
            $ResourceGroupName = '*'
            $MachineName = '*'
            $MinimumAgentVersion = 'latest'
            $OutputPath = $null

            Mock Get-AzConnectedMachine { $script:upToDateFleet }

            $out = Main *>&1
            ($out | Out-String) | Should -Match "\[-\] Error: -MinimumAgentVersion 'latest' is not a valid version\."
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
            Should -Invoke Get-AzConnectedMachine -Times 0 -Exactly -Because 'validation precedes enumeration'
        }

        It 'Returns 1 when the machine enumeration fails' {
            $SubscriptionId = @('sub-1')
            $ResourceGroupName = '*'
            $MachineName = '*'
            $MinimumAgentVersion = $null
            $OutputPath = $null

            Mock Get-AzConnectedMachine { throw 'ARM throttled the request' }

            $out = Main *>&1
            $text = $out | Out-String
            $text | Should -Match '\[-\] Error: Failed to enumerate Arc-enabled servers in ''sub-1'''
            $text | Should -Match 'ARM throttled the request'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
            Should -Invoke Update-AzConnectedMachine -Times 0 -Exactly
        }

        It 'Returns 1 when there is no Azure context' {
            $SubscriptionId = @('sub-1')
            $ResourceGroupName = '*'
            $MachineName = '*'
            $MinimumAgentVersion = $null
            $OutputPath = $null

            Mock Get-AzContext { $null }

            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[-\].*Not connected to Azure'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
            Should -Invoke Update-AzConnectedMachine -Times 0 -Exactly
        }

        It 'Reports nothing to upgrade when no machine exposes a usable agent version' {
            $SubscriptionId = @('sub-1')
            $ResourceGroupName = '*'
            $MachineName = '*'
            $MinimumAgentVersion = $null
            $OutputPath = $null

            Mock Get-AzConnectedMachine { $script:blankFleet }

            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[!\] No Arc-enabled server reported a usable agent version'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            Should -Invoke Update-AzConnectedMachine -Times 0 -Exactly
        }

        It 'Is idempotent: repeat runs over a converged fleet change nothing' {
            $SubscriptionId = @('sub-1')
            $ResourceGroupName = '*'
            $MachineName = '*'
            $MinimumAgentVersion = '1.57.0'
            $OutputPath = $null

            Mock Get-AzConnectedMachine { $script:upToDateFleet }

            Main | Should -Be 0
            Main | Should -Be 0
            Should -Invoke Update-AzConnectedMachine -Times 0 -Exactly
            Should -Invoke Get-AzConnectedMachine -Times 2 -Exactly
        }
    }
}
