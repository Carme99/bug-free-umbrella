#Requires -Modules Pester
<#
.SYNOPSIS
    Pester tests for scripts/cloud/azure/arc/servers/Get-AzureArcServerFleet.ps1.
.DESCRIPTION
    Validates help/metadata conformance, static syntax rules, and observable behavior
    using fully mocked Az.ConnectedMachine cmdlets. Runs offline on Linux pwsh; no network,
    elevation, or installed product modules required.
.EXAMPLE
    PS C:\> Invoke-Pester -Path ./Tests/cloud/azure/arc/servers/Get-AzureArcServerFleet.Tests.ps1
    Runs this test file.
.EXAMPLE
    PS C:\> Invoke-Pester -Path ./Tests/cloud/azure/arc/servers/Get-AzureArcServerFleet.Tests.ps1 -Output Detailed
    Runs this test file with per-test output.
.NOTES
    File Name   : Get-AzureArcServerFleet.Tests.ps1
    Author      : Bug-Free Umbrella
    Prerequisite: PowerShell 7.0
    Version     : 2.0.0
    Date        : 2026-09-16
#>

Describe 'Get-AzureArcServerFleet' {
    BeforeAll {
        $repoRoot = Join-Path $PSScriptRoot '../../../../..'
        $scriptPath = Join-Path $repoRoot 'scripts/cloud/azure/arc/servers/Get-AzureArcServerFleet.ps1'

        # Safe: the script's top-level guard skips Main when dot-sourced (spec section 3).
        . $scriptPath

        # The product module is not installed offline: declare its cmdlets as empty
        # functions so Pester can mock them, then Mock each one.
        function Get-AzContext { }
        function Get-AzSubscription { }
        function Get-AzConnectedMachine {
            param([string[]]$SubscriptionId, [string]$ResourceGroupName)
        }
        function Get-AzConnectedMachineExtension {
            param([string]$ResourceGroupName, [string]$MachineName, [string[]]$SubscriptionId)
        }

        Mock Import-Module { }
        Mock Get-AzContext {
            [pscustomobject]@{ Subscription = [pscustomobject]@{ Name = 'sub-prod'; Id = 'sub-prod-id' } }
        }
        Mock Get-AzSubscription { @() }
        Mock Get-AzConnectedMachine { @() }
        Mock Get-AzConnectedMachineExtension { @() }

        function New-FleetMachine {
            param(
                [string]$MachineName = 'srv-1',
                [string]$AgentVersion = '1.40.0',
                [string]$Status = 'Connected',
                [datetime]$LastStatusChange = (Get-Date).AddHours(-2),
                [string]$ResourceGroup = 'rg-hybrid'
            )

            [pscustomobject]@{
                Name             = $MachineName
                Id               = (
                    "/subscriptions/sub-1/resourceGroups/$ResourceGroup" +
                    "/providers/Microsoft.HybridCompute/machines/$MachineName")
                Location         = 'eastus'
                Status           = $Status
                AgentVersion     = $AgentVersion
                LastStatusChange = $LastStatusChange
                OSName           = 'linux'
                OSSku            = 'Ubuntu 22.04'
                Tag              = @{ env = 'prod'; owner = 'platform' }
            }
        }

        $script:monitorAgent = @([pscustomobject]@{ Name = 'AzureMonitorAgent' })
        $script:healthyFleet = @(
            New-FleetMachine -MachineName 'srv-1'
            New-FleetMachine -MachineName 'srv-2'
        )
        $script:mixedFleet = @(
            New-FleetMachine -MachineName 'srv-ok'
            New-FleetMachine -MachineName 'srv-gaps' -AgentVersion '1.30.0' -Status 'Disconnected' `
                -LastStatusChange (Get-Date).AddDays(-40)
        )
        $script:boundaryFleet = @(
            New-FleetMachine -MachineName 'srv-fresh' -LastStatusChange (Get-Date).AddDays(-29)
            New-FleetMachine -MachineName 'srv-old' -LastStatusChange (Get-Date).AddDays(-31)
        )
        $script:singleFleet = @(New-FleetMachine -MachineName 'srv-solo' -ResourceGroup 'rg-solo')

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
            $raw | Should -Match '(?m)File Name\s*:\s*Get-AzureArcServerFleet\.ps1'
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

        It 'Documents the 0/2/1 exit-code contract' {
            $raw | Should -Match 'Exit codes: 0 when the fleet is healthy, 2 when'
            $raw | Should -Match '1 when the script cannot complete'
        }

        It 'Cites the Microsoft Learn pages for the Arc inventory API family' {
            $raw | Should -Match 'learn\.microsoft\.com/powershell/module/az\.connectedmachine/get-azconnectedmachine'
            $raw | Should -Match 'learn\.microsoft\.com/azure/azure-arc/servers/organize-inventory-servers'
            $raw | Should -Match 'learn\.microsoft\.com/azure/azure-arc/servers/manage-agent'
        }
    }

    Context 'Syntax & Static' {
        It 'Parses with zero syntax errors' {
            $errors.Count | Should -Be 0
        }

        It 'Uses CmdletBinding, a Main function, and the dot-source guard' {
            $raw | Should -Match '\[CmdletBinding\('
            $raw | Should -Match '(?m)^function Main\b'
            $raw | Should -Match 'if \(\$MyInvocation\.InvocationName -ne ''\.''\) \{ exit \(Main\) \}'
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
        It 'Returns 0 and reports the inventory for a healthy fleet' {
            $SubscriptionId = @('sub-1')
            $ResourceGroupName = '*'
            $AgentStaleDays = 30
            $OutputFormat = 'Table'
            $OutputPath = $null

            Mock Get-AzConnectedMachine { $script:healthyFleet }
            Mock Get-AzConnectedMachineExtension { $script:monitorAgent }

            $out = Main *>&1
            $text = $out | Out-String
            $text | Should -Match '\[\+\] Connected to: sub-prod'
            $text | Should -Match '\[\+\] Found 2 Arc-enabled servers in ''sub-1'''
            $text | Should -Match 'srv-1 \[rg-hybrid\] status=Connected agent=1\.40\.0'
            $text | Should -Match 'tags: env=prod; owner=platform'
            $text | Should -Match 'extensions: AzureMonitorAgent'
            $text | Should -Match '\[\+\] Fleet healthy: 2 Arc-enabled servers, no findings'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            Should -Invoke Get-AzConnectedMachine -Times 1 -Exactly
            Should -Invoke Get-AzConnectedMachineExtension -Times 2 -Exactly
        }

        It 'Returns 2 and flags disconnected, stale, behind-fleet, and extension-less machines' {
            $SubscriptionId = @('sub-1')
            $ResourceGroupName = '*'
            $AgentStaleDays = 30
            $OutputFormat = 'Table'
            $OutputPath = $null

            Mock Get-AzConnectedMachine { $script:mixedFleet }
            Mock Get-AzConnectedMachineExtension {
                param($MachineName)
                if ($MachineName -eq 'srv-ok') { $script:monitorAgent } else { @() }
            }

            $out = Main *>&1
            $text = $out | Out-String
            $text | Should -Match "\[!\] srv-gaps: Status is 'Disconnected'"
            $text | Should -Match '\[!\] srv-gaps: Stale heartbeat'
            $text | Should -Match '\[!\] srv-gaps: Agent version 1\.30\.0 is behind fleet maximum 1\.40\.0'
            $text | Should -Match '\[!\] srv-gaps: AzureMonitorAgent extension is not installed'
            @([regex]::Matches($text, '(?m)^\[!\] srv-ok:')).Count | Should -Be 0
            ($out | Where-Object { $_ -is [int] }) | Should -Be 2
            Should -Invoke Get-AzConnectedMachineExtension -Times 1 -Exactly `
                -ParameterFilter { $MachineName -eq 'srv-gaps' }
        }

        It 'Only flags heartbeats older than AgentStaleDays' {
            $SubscriptionId = @('sub-1')
            $ResourceGroupName = '*'
            $AgentStaleDays = 30
            $OutputFormat = 'Table'
            $OutputPath = $null

            Mock Get-AzConnectedMachine { $script:boundaryFleet }
            Mock Get-AzConnectedMachineExtension { $script:monitorAgent }

            $out = Main *>&1
            $text = $out | Out-String
            @([regex]::Matches($text, 'srv-fresh: Stale heartbeat')).Count | Should -Be 0
            $text | Should -Match '\[!\] srv-old: Stale heartbeat'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 2
        }

        It 'Enumerates every enabled subscription when SubscriptionId is *' {
            $SubscriptionId = @('*')
            $ResourceGroupName = '*'
            $AgentStaleDays = 30
            $OutputFormat = 'Table'
            $OutputPath = $null

            Mock Get-AzSubscription {
                @(
                    [pscustomobject]@{ Id = 'sub-1'; State = 'Enabled' }
                    [pscustomobject]@{ Id = 'sub-2'; State = 'Enabled' }
                    [pscustomobject]@{ Id = 'sub-3'; State = 'Disabled' }
                )
            }
            Mock Get-AzConnectedMachine { $script:singleFleet }
            Mock Get-AzConnectedMachineExtension { $script:monitorAgent }

            $out = Main *>&1
            $text = $out | Out-String
            $text | Should -Match '\[\*\] Subscriptions in scope: sub-1, sub-2'
            $text | Should -Match '\[\+\] Found 1 Arc-enabled servers in ''sub-2'''
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            Should -Invoke Get-AzConnectedMachine -Times 2 -Exactly
            Should -Invoke Get-AzConnectedMachine -Times 1 -Exactly `
                -ParameterFilter { $SubscriptionId -eq 'sub-2' }
        }

        It 'Scopes the inventory to one resource group and writes the JSON report' {
            $SubscriptionId = @('sub-1')
            $ResourceGroupName = 'rg-solo'
            $AgentStaleDays = 30
            $OutputFormat = 'Json'
            $OutputPath = Join-Path $TestDrive 'arc-fleet.json'

            Mock Get-AzConnectedMachine { $script:singleFleet }
            Mock Get-AzConnectedMachineExtension { $script:monitorAgent }

            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[\+\] Report written to: '
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            Should -Invoke Get-AzConnectedMachine -Times 1 -Exactly `
                -ParameterFilter { $ResourceGroupName -eq 'rg-solo' }

            Test-Path -LiteralPath $OutputPath | Should -BeTrue
            $json = @(Get-Content -LiteralPath $OutputPath -Raw | ConvertFrom-Json)
            $json.Count | Should -Be 1
            $json[0].Name | Should -Be 'srv-solo'
            $json[0].ResourceGroup | Should -Be 'rg-solo'
            @($json[0].Extensions) | Should -Contain 'AzureMonitorAgent'
        }

        It 'Renders the CSV inventory to the console when OutputFormat is Csv' {
            $SubscriptionId = @('sub-1')
            $ResourceGroupName = '*'
            $AgentStaleDays = 30
            $OutputFormat = 'Csv'
            $OutputPath = $null

            Mock Get-AzConnectedMachine { $script:singleFleet }
            Mock Get-AzConnectedMachineExtension { $script:monitorAgent }

            $out = Main *>&1
            $text = $out | Out-String
            $text | Should -Match '"Name","SubscriptionId","ResourceGroup"'
            $text | Should -Match 'srv-solo'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
        }

        It 'Warns about a failed extension lookup but still reports the machine' {
            $SubscriptionId = @('sub-1')
            $ResourceGroupName = '*'
            $AgentStaleDays = 30
            $OutputFormat = 'Table'
            $OutputPath = $null

            Mock Get-AzConnectedMachine { $script:singleFleet }
            Mock Get-AzConnectedMachineExtension { throw 'extension provider unavailable' }

            $out = Main *>&1
            $text = $out | Out-String
            $text | Should -Match '\[!\] Could not read extensions for srv-solo: extension provider unavailable'
            $text | Should -Match '\[!\] srv-solo: AzureMonitorAgent extension is not installed'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 2
        }

        It 'Returns 1 when the machine enumeration fails' {
            $SubscriptionId = @('sub-1')
            $ResourceGroupName = '*'
            $AgentStaleDays = 30
            $OutputFormat = 'Table'
            $OutputPath = $null

            Mock Get-AzConnectedMachine { throw 'ARM throttled the request' }

            $out = Main *>&1
            $text = $out | Out-String
            $text | Should -Match '\[-\] Error: Failed to enumerate Arc-enabled servers in ''sub-1'''
            $text | Should -Match 'ARM throttled the request'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
        }

        It 'Returns 1 when there is no Azure context' {
            $SubscriptionId = @('sub-1')
            $ResourceGroupName = '*'
            $AgentStaleDays = 30
            $OutputFormat = 'Table'
            $OutputPath = $null

            Mock Get-AzContext { $null }

            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[-\].*Not connected to Azure'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
            Should -Invoke Get-AzConnectedMachine -Times 0 -Exactly
        }

        It 'Returns 1 when the Az module cannot be imported' {
            $SubscriptionId = @('sub-1')
            $ResourceGroupName = '*'
            $AgentStaleDays = 30
            $OutputFormat = 'Table'
            $OutputPath = $null

            Mock Import-Module { throw 'Az module not installed' }

            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[-\] Error: Az module not installed'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
        }

        It 'Is idempotent: repeat runs of a healthy fleet return 0 and write no report' {
            $SubscriptionId = @('sub-1')
            $ResourceGroupName = '*'
            $AgentStaleDays = 30
            $OutputFormat = 'Table'
            $OutputPath = $null

            Mock Get-AzConnectedMachine { $script:healthyFleet }
            Mock Get-AzConnectedMachineExtension { $script:monitorAgent }

            $first = Main *>&1
            $second = Main *>&1
            ($first | Where-Object { $_ -is [int] }) | Should -Be 0
            ($second | Where-Object { $_ -is [int] }) | Should -Be 0
            ($second | Out-String) | Should -Not -Match 'Report written to'
            Should -Invoke Get-AzConnectedMachineExtension -Times 4 -Exactly
        }
    }
}
