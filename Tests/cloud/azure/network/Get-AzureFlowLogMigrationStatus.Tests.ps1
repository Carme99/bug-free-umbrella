#Requires -Modules Pester
<#
.SYNOPSIS
    Pester tests for scripts/cloud/azure/network/Get-AzureFlowLogMigrationStatus.ps1.
.DESCRIPTION
    Validates help/metadata conformance, static syntax rules, and observable
    behavior of the flow log migration report using fully mocked Az cmdlets.
    Runs offline on Linux pwsh; no network, Azure connectivity, or installed
    product modules required.
.EXAMPLE
    PS C:\> Invoke-Pester -Path ./Tests/cloud/azure/network/Get-AzureFlowLogMigrationStatus.Tests.ps1
    Runs this test file.
.EXAMPLE
    PS C:\> Invoke-Pester -Path ./Tests/cloud/azure/network/Get-AzureFlowLogMigrationStatus.Tests.ps1 -Output Detailed
    Runs this test file with per-test output.
.NOTES
    File Name   : Get-AzureFlowLogMigrationStatus.Tests.ps1
    Author      : Bug-Free Umbrella
    Prerequisite: PowerShell 7.0
    Version     : 2.0.0
    Date        : 2026-09-16
#>

Describe 'Get-AzureFlowLogMigrationStatus' {
    BeforeAll {
        $migration = '../../../../scripts/cloud/azure/network/Get-AzureFlowLogMigrationStatus.ps1'
        $scriptPath = Join-Path $PSScriptRoot $migration

        # Safe: the script's top-level guard skips Main when dot-sourced (spec section 3).
        . $scriptPath

        # The Az module is not installed offline: declare its cmdlets as advanced
        # functions with their real parameter sets, so a Mock parameter filter binds the
        # invocation's arguments instead of resolving them from an unrelated outer scope.
        function Get-AzContext {
            [CmdletBinding()]
            param()
        }
        function Set-AzContext {
            [CmdletBinding()]
            param([string]$SubscriptionId, [string]$SubscriptionName, [string]$Name)
        }
        function Get-AzSubscription {
            [CmdletBinding()]
            param([string]$SubscriptionId, [string]$SubscriptionName, [string]$TenantId)
        }
        function Get-AzVirtualNetwork {
            [CmdletBinding()]
            param(
                [Parameter(Mandatory = $false)][string]$SubscriptionId,
                [Parameter(Mandatory = $false)][string]$ResourceGroupName
            )
        }
        function Get-AzNetworkWatcherFlowLog {
            [CmdletBinding()]
            param(
                [Parameter(Mandatory = $false)][string]$Location,
                [Parameter(Mandatory = $false)][string]$Name,
                [Parameter(Mandatory = $false)][string]$ResourceId,
                [Parameter(Mandatory = $false)]$NetworkWatcher
            )
        }

        $vnet1Id = '/subscriptions/s1/resourceGroups/rg1/providers/Microsoft.Network' +
            '/virtualNetworks/vnet1'
        $vnet2Id = '/subscriptions/s1/resourceGroups/rg2/providers/Microsoft.Network' +
            '/virtualNetworks/vnet2'
        $nsg1Id = '/subscriptions/s1/resourceGroups/rg1/providers/Microsoft.Network' +
            '/networkSecurityGroups/nsg1'
        $saId = '/subscriptions/s1/resourceGroups/rg1/providers/Microsoft.Storage' +
            '/storageAccounts/saflow'

        Mock Import-Module { }
        Mock Get-AzContext {
            [pscustomobject]@{ Subscription = [pscustomobject]@{ Name = 'sub-prod' } }
        }
        Mock Set-AzContext { [pscustomobject]@{ Subscription = [pscustomobject]@{ Name = 'sub-prod' } } }
        Mock Get-AzSubscription {
            @([pscustomobject]@{ Id = 'sub-id-1'; Name = 'sub-prod' })
        }

        # Default inventory: one VNet in eastus, already migrated to a virtual
        # network flow log. Individual tests re-mock to inject drift.
        Mock Get-AzVirtualNetwork {
            @(
                [pscustomobject]@{
                    Name              = 'vnet1'
                    Id                = $vnet1Id
                    Location          = 'eastus'
                    ResourceGroupName = 'rg1'
                    Subnets           = @(
                        [pscustomobject]@{
                            Name                 = 'snet1'
                            NetworkSecurityGroup = [pscustomobject]@{ Id = $nsg1Id }
                        }
                    )
                }
            )
        }
        Mock Get-AzNetworkWatcherFlowLog {
            @(
                [pscustomobject]@{
                    Name             = 'vnetflowlog1'
                    Location         = 'eastus'
                    Enabled          = $true
                    TargetResourceId = $vnet1Id
                    StorageId        = $saId
                }
            )
        }

        $raw = [IO.File]::ReadAllText($scriptPath)
        $tokens = $null
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens,
            [ref]$errors)
    }

    Context 'Help & Metadata' {
        It 'Declares all five NOTES fields with v2.0.0 values' {
            $raw | Should -Match '(?m)File Name\s*:\s*Get-AzureFlowLogMigrationStatus\.ps1'
            $raw | Should -Match '(?m)Author\s*:\s*\S+'
            $raw | Should -Match '(?m)Prerequisite\s*:\s*PowerShell 7\.0'
            $raw | Should -Match '(?m)Version\s*:\s*2\.0\.0'
            $raw | Should -Match '(?m)Date\s*:\s*2026-09-16'
        }

        It 'Has one PARAMETER entry per declared parameter' {
            foreach ($name in @('SubscriptionId', 'OutputFormat', 'OutputPath')) {
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
            $raw | Should -Match '\[CmdletBinding\('
            $raw | Should -Match '(?m)function Main\b'
            $raw | Should -Match 'if \(\$MyInvocation\.InvocationName -ne ''\.''\) \{ exit \(Main\) \}'
        }

        It 'Contains no PS7-only operators and no #Requires opt-out' {
            ($raw -match '\?\?') | Should -BeFalse
            ($raw -match '\|\|') | Should -BeFalse
            ($raw -match '&&') | Should -BeFalse
            ($raw -match '#Requires\s+-Version') | Should -BeFalse
        }

        It 'Is UTF-8 with BOM and CRLF line endings' {
            $bytes = [IO.File]::ReadAllBytes($scriptPath)
            ($bytes[0], $bytes[1], $bytes[2]) | Should -Be (0xEF, 0xBB, 0xBF)
            ($raw -replace "`r`n", '').Contains("`n") | Should -BeFalse
        }

        It 'Cites the NSG flow log retirement and provider registration pages' {
            $raw | Should -Match 'learn\.microsoft\.com/azure/network-watcher/nsg-flow-logs-manage'
            $raw | Should -Match 'learn\.microsoft\.com/azure/network-watcher/vnet-flow-logs-overview'
        }
    }

    Context 'Behavior' {
        It 'Reports a fully migrated environment, the retirement date, and exits 0' {
            $out = Main *>&1
            $text = $out | Out-String
            $text | Should -Match '\[\+\] Azure context: sub-prod'
            $text | Should -Match 'September 30, 2027'
            $text | Should -Match 'Microsoft\.Insights'
            $text | Should -Match 'VNets covered by enabled virtual network flow logs: 1'
            $text | Should -Match 'Legacy NSG flow log resources: 0'
            $text | Should -Match 'VNets with no flow logging: 0'
            $text | Should -Match "VNet flow log 'vnetflowlog1' covers VNet 'vnet1' \(enabled\)"
            $text | Should -Match '\[\+\] Migration complete: every virtual network has enabled flow logging\.'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            Should -Invoke Get-AzNetworkWatcherFlowLog -Times 1 -Exactly `
                -ParameterFilter { $Location -eq 'eastus' }
            Should -Invoke Get-AzVirtualNetwork -Times 1 -Exactly
        }

        It 'Reports legacy NSG flow logs with their storage accounts and exits 2' {
            Mock Get-AzNetworkWatcherFlowLog {
                @(
                    [pscustomobject]@{
                        Name             = 'nsgflow1'
                        Location         = 'eastus'
                        Enabled          = $true
                        TargetResourceId = $nsg1Id
                        StorageId        = $saId
                    }
                )
            }
            $out = Main *>&1
            $text = $out | Out-String
            $text | Should -Match '\[\!\] 1 legacy NSG flow log\(s\) still present\.'
            $text | Should -Match "Legacy NSG flow log 'nsgflow1' on NSG 'nsg1'"
            $text | Should -Match "storage account 'saflow' \(enabled\)"
            $text | Should -Match 'VNets with no flow logging: 0'
            $text | Should -Match '\[\!\] Migration incomplete'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 2
        }

        It 'Reports virtual networks with no flow logging at all and exits 2' {
            Mock Get-AzNetworkWatcherFlowLog { @() }
            $out = Main *>&1
            $text = $out | Out-String
            $text | Should -Match 'VNets covered by enabled virtual network flow logs: 0'
            $text | Should -Match '\[\!\] No virtual network flow logs found\.'
            $text | Should -Match '\[\!\] No flow logging: rg1/vnet1 \(eastus\)'
            $text | Should -Match 'VNets with no flow logging: 1'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 2
        }

        It 'Treats a disabled virtual network flow log as no coverage' {
            Mock Get-AzNetworkWatcherFlowLog {
                @(
                    [pscustomobject]@{
                        Name             = 'vnetflowlog1'
                        Location         = 'eastus'
                        Enabled          = $false
                        TargetResourceId = $vnet1Id
                        StorageId        = $saId
                    }
                )
            }
            $out = Main *>&1
            $text = $out | Out-String
            $text | Should -Match "VNet flow log 'vnetflowlog1' covers VNet 'vnet1' \(disabled\)"
            $text | Should -Match 'Virtual network flow log resources: 1'
            $text | Should -Match 'VNets covered by enabled virtual network flow logs: 0'
            $text | Should -Match '\[\!\] No flow logging: rg1/vnet1'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 2
        }

        It 'Queries flow logs once per unique region across two VNets' {
            Mock Get-AzVirtualNetwork {
                @(
                    [pscustomobject]@{
                        Name              = 'vnet1'
                        Id                = $vnet1Id
                        Location          = 'eastus'
                        ResourceGroupName = 'rg1'
                        Subnets           = @()
                    }
                    [pscustomobject]@{
                        Name              = 'vnet2'
                        Id                = $vnet2Id
                        Location          = 'westus'
                        ResourceGroupName = 'rg2'
                        Subnets           = @()
                    }
                )
            }
            Mock Get-AzNetworkWatcherFlowLog {
                if ($Location -eq 'westus') {
                    return @(
                        [pscustomobject]@{
                            Name             = 'fl-west'
                            Location         = 'westus'
                            Enabled          = $true
                            TargetResourceId = $vnet2Id
                            StorageId        = $saId
                        }
                    )
                }
                return @(
                    [pscustomobject]@{
                        Name             = 'fl-east'
                        Location         = 'eastus'
                        Enabled          = $true
                        TargetResourceId = $vnet1Id
                        StorageId        = $saId
                    }
                )
            }
            $out = Main *>&1
            $text = $out | Out-String
            $text | Should -Match 'VNets covered by enabled virtual network flow logs: 2'
            $text | Should -Match 'VNets with no flow logging: 0'
            Should -Invoke Get-AzNetworkWatcherFlowLog -Times 2 -Exactly
            Should -Invoke Get-AzNetworkWatcherFlowLog -Times 1 -Exactly `
                -ParameterFilter { $Location -eq 'westus' }
            Should -Invoke Get-AzNetworkWatcherFlowLog -Times 1 -Exactly `
                -ParameterFilter { $Location -eq 'eastus' }
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
        }

        It 'Exits 1 when a flow log query fails so the report is incomplete' {
            Mock Get-AzNetworkWatcherFlowLog { throw 'network watcher error' }
            $out = Main *>&1
            $text = $out | Out-String
            $text | Should -Match '\[\!\] Failed to read flow logs in eastus: network watcher error'
            $text | Should -Match '\[\!\] Report incomplete: one or more flow log queries failed\.'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
        }

        It 'Exits 1 with a [-] message when there is no Azure context' {
            Mock Get-AzContext { $null }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[-\].*Not connected to Azure'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
            Should -Invoke Get-AzVirtualNetwork -Times 0 -Exactly -Because 'context check fails first'
        }

        It 'Writes a CSV report to OutputPath without changing the exit code' {
            $OutputFormat = 'Csv'
            $OutputPath = $TestDrive
            try {
                $out = Main *>&1
                ($out | Out-String) | Should -Match '\[\+\] CSV report written:'
                $files = @(Get-ChildItem -LiteralPath $TestDrive -Filter '*.csv')
                $files.Count | Should -Be 1
                $rows = @(Import-Csv -LiteralPath $files[0].FullName)
                $rows.Count | Should -Be 1
                $rows[0].State | Should -Be 'VNetFlowLog'
                $rows[0].Resource | Should -Be 'vnet1'
                ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            }
            finally {
                $OutputFormat = 'Table'
                $OutputPath = $null
            }
        }

        It 'Audits every accessible subscription when SubscriptionId is wildcard' {
            Mock Get-AzSubscription {
                @(
                    [pscustomobject]@{ Id = 'sub-id-1'; Name = 'sub-prod' }
                    [pscustomobject]@{ Id = 'sub-id-2'; Name = 'sub-dev' }
                )
            }
            $out = Main *>&1
            $text = $out | Out-String
            $text | Should -Match '\[\*\] Auditing 2 subscription\(s\)'
            $text | Should -Match '\[\*\] Auditing subscription: sub-dev'
            Should -Invoke Set-AzContext -Times 2 -Exactly
            Should -Invoke Get-AzVirtualNetwork -Times 2 -Exactly
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
        }
    }
}
