#Requires -Modules Pester
<#
.SYNOPSIS
    Pester tests for scripts/cloud/azure/network/Get-AzureNetworkSecurityAudit.ps1.
.DESCRIPTION
    Validates help/metadata conformance, static syntax rules, and observable
    behavior of the Azure network security audit using fully mocked Az cmdlets.
    Runs offline on Linux pwsh; no network, Azure connectivity, or installed
    product modules required.
.EXAMPLE
    PS C:\> Invoke-Pester -Path ./Tests/cloud/azure/network/Get-AzureNetworkSecurityAudit.Tests.ps1
    Runs this test file.
.EXAMPLE
    PS C:\> Invoke-Pester -Path ./Tests/cloud/azure/network/Get-AzureNetworkSecurityAudit.Tests.ps1 -Output Detailed
    Runs this test file with per-test output.
.NOTES
    File Name   : Get-AzureNetworkSecurityAudit.Tests.ps1
    Author      : Bug-Free Umbrella
    Prerequisite: PowerShell 7.0
    Version     : 2.0.0
    Date        : 2026-09-16
#>

Describe 'Get-AzureNetworkSecurityAudit' {
    BeforeAll {
        $audit = '../../../../scripts/cloud/azure/network/Get-AzureNetworkSecurityAudit.ps1'
        $scriptPath = Join-Path $PSScriptRoot $audit

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
        function Get-AzNetworkSecurityGroup {
            [CmdletBinding()]
            param(
                [Parameter(Mandatory = $false)][string]$SubscriptionId,
                [Parameter(Mandatory = $false)][string]$ResourceGroupName
            )
        }
        function Get-AzVirtualNetwork {
            [CmdletBinding()]
            param(
                [Parameter(Mandatory = $false)][string]$SubscriptionId,
                [Parameter(Mandatory = $false)][string]$ResourceGroupName
            )
        }
        function Get-AzNetworkInterface {
            [CmdletBinding()]
            param(
                [Parameter(Mandatory = $false)][string]$SubscriptionId,
                [Parameter(Mandatory = $false)][string]$ResourceGroupName
            )
        }
        function Get-AzPublicIpAddress {
            [CmdletBinding()]
            param([string]$Name, [string]$ResourceGroupName)
        }

        $nsgCleanId = '/subscriptions/s1/resourceGroups/rg1/providers/Microsoft.Network' +
            '/networkSecurityGroups/nsg-clean'
        $vnetId = '/subscriptions/s1/resourceGroups/rg1/providers/Microsoft.Network' +
            '/virtualNetworks/vnet1'
        $vmId = '/subscriptions/s1/resourceGroups/rg1/providers/Microsoft.Compute' +
            '/virtualMachines/vm-web'

        Mock Import-Module { }
        Mock Get-AzContext {
            [pscustomobject]@{ Subscription = [pscustomobject]@{ Name = 'sub-prod' } }
        }
        Mock Set-AzContext { [pscustomobject]@{ Subscription = [pscustomobject]@{ Name = 'sub-prod' } } }
        Mock Get-AzSubscription {
            @([pscustomobject]@{ Id = 'sub-id-1'; Name = 'sub-prod' })
        }

        # Default inventory: compliant. Individual tests re-mock to inject findings.
        Mock Get-AzNetworkSecurityGroup {
            @(
                [pscustomobject]@{
                    Name          = 'nsg-clean'
                    SecurityRules = @(
                        [pscustomobject]@{
                            Name                 = 'AllowHttps'
                            Direction            = 'Inbound'
                            Access               = 'Allow'
                            Protocol             = 'TCP'
                            SourceAddressPrefix  = 'Internet'
                            DestinationPortRange = '443'
                        }
                    )
                }
            )
        }
        Mock Get-AzVirtualNetwork {
            @(
                [pscustomobject]@{
                    Name              = 'vnet1'
                    Id                = $vnetId
                    Location          = 'eastus'
                    ResourceGroupName = 'rg1'
                    Subnets           = @(
                        [pscustomobject]@{
                            Name                 = 'snet1'
                            NetworkSecurityGroup = [pscustomobject]@{ Id = $nsgCleanId }
                        }
                    )
                }
            )
        }
        Mock Get-AzNetworkInterface {
            @(
                [pscustomobject]@{
                    Name                 = 'nic1'
                    NetworkSecurityGroup = [pscustomobject]@{ Id = $nsgCleanId }
                    VirtualMachine       = $null
                }
            )
        }
        Mock Get-AzPublicIpAddress { @() }

        $raw = [IO.File]::ReadAllText($scriptPath)
        $tokens = $null
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errors)
    }

    Context 'Help & Metadata' {
        It 'Declares all five NOTES fields with v2.0.0 values' {
            $raw | Should -Match '(?m)File Name\s*:\s*Get-AzureNetworkSecurityAudit\.ps1'
            $raw | Should -Match '(?m)Author\s*:\s*\S+'
            $raw | Should -Match '(?m)Prerequisite\s*:\s*PowerShell 7\.0'
            $raw | Should -Match '(?m)Version\s*:\s*2\.0\.0'
            $raw | Should -Match '(?m)Date\s*:\s*2026-09-16'
        }

        It 'Has one PARAMETER entry per declared parameter' {
            foreach ($name in @('SubscriptionId', 'ResourceGroupName', 'OutputFormat', 'OutputPath')) {
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

        It 'Cites Microsoft Learn in its help' {
            $raw | Should -Match 'learn\.microsoft\.com'
        }
    }

    Context 'Behavior' {
        It 'Reports a compliant environment and exits 0' {
            $out = Main *>&1
            $text = $out | Out-String
            $text | Should -Match '\[\+\] Azure context: sub-prod'
            $text | Should -Match '\[\+\] Inventory: 1 NSGs, 1 VNets, 1 NICs, 0 public IPs'
            $text | Should -Match '\[\+\] Audit complete: no findings\.'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            Should -Invoke Get-AzSubscription -Times 1 -Exactly `
                -ParameterFilter { -not $PesterBoundParameters.SubscriptionId }
            Should -Invoke Get-AzNetworkSecurityGroup -Times 1 -Exactly
            Should -Invoke Get-AzPublicIpAddress -Times 1 -Exactly
        }

        It 'Flags permissive NSG rules, bare subnets, bare NICs, and VM public IPs with exit 2' {
            Mock Get-AzNetworkSecurityGroup {
                @(
                    [pscustomobject]@{
                        Name          = 'nsg-open'
                        SecurityRules = @(
                            [pscustomobject]@{
                                Name                 = 'AllowAnyInbound'
                                Direction            = 'Inbound'
                                Access               = 'Allow'
                                Protocol             = 'Any'
                                SourceAddressPrefix  = 'Internet'
                                DestinationPortRange = '*'
                            }
                            [pscustomobject]@{
                                Name                  = 'AllowAnySource'
                                Direction             = 'Inbound'
                                Access                = 'Allow'
                                Protocol              = 'Any'
                                SourceAddressPrefixes = @('10.0.0.0/8', '0.0.0.0/0')
                                DestinationPortRanges = @('0-65535')
                            }
                            [pscustomobject]@{
                                Name                 = 'DenyAll'
                                Direction            = 'Inbound'
                                Access               = 'Deny'
                                Protocol             = 'Any'
                                SourceAddressPrefix  = 'Internet'
                                DestinationPortRange = '*'
                            }
                            [pscustomobject]@{
                                Name                 = 'AllowSshScoped'
                                Direction            = 'Inbound'
                                Access               = 'Allow'
                                Protocol             = 'TCP'
                                SourceAddressPrefix  = '10.0.0.0/8'
                                DestinationPortRange = '22'
                            }
                        )
                    }
                )
            }
            Mock Get-AzVirtualNetwork {
                @(
                    [pscustomobject]@{
                        Name              = 'vnet1'
                        Id                = $vnetId
                        Location          = 'eastus'
                        ResourceGroupName = 'rg1'
                        Subnets           = @(
                            [pscustomobject]@{ Name = 'snet-open'; NetworkSecurityGroup = $null }
                        )
                    }
                )
            }
            Mock Get-AzNetworkInterface {
                @(
                    [pscustomobject]@{
                        Name                 = 'nic-web'
                        NetworkSecurityGroup = $null
                        VirtualMachine       = [pscustomobject]@{
                            Id = $vmId
                        }
                    }
                )
            }
            Mock Get-AzPublicIpAddress {
                @(
                    [pscustomobject]@{
                        Name            = 'pip-web'
                        IpConfiguration = [pscustomobject]@{
                            Id = '/subscriptions/s1/resourceGroups/rg1/providers/Microsoft.Network' +
                                '/networkInterfaces/nic-web/ipConfigurations/ipconfig1'
                        }
                    }
                )
            }

            $out = Main *>&1
            $text = $out | Out-String
            $text | Should -Match '\[!\] Audit complete: 5 finding\(s\) require review\.'
            $text | Should -Match 'PermissiveInboundRule'
            $text | Should -Match 'nsg-open/AllowAnyInbound'
            $text | Should -Match 'nsg-open/AllowAnySource'
            $text | Should -Match 'SubnetWithoutNsg'
            $text | Should -Match 'NicWithoutNsg'
            $text | Should -Match 'PublicIpOnVmNic'
            $text | Should -Match "Public IP attached directly to NIC 'nic-web' of VM 'vm-web'"
            ($text -match 'nsg-open/DenyAll') | Should -BeFalse
            ($text -match 'nsg-open/AllowSshScoped') | Should -BeFalse
            ($out | Where-Object { $_ -is [int] }) | Should -Be 2
        }

        It 'Exits 1 with a [-] message when there is no Azure context' {
            Mock Get-AzContext { $null }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[-\].*Not connected to Azure'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
            Should -Invoke Get-AzNetworkSecurityGroup -Times 0 -Exactly -Because 'context check fails first'
        }

        It 'Exits 1 when an inventory query fails so the audit is incomplete' {
            Mock Get-AzVirtualNetwork { throw 'provider error' }
            $out = Main *>&1
            $text = $out | Out-String
            $text | Should -Match '\[!\] Failed to read VNets: provider error'
            $text | Should -Match '\[!\] Audit incomplete: one or more inventory queries failed\.'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
        }

        It 'Applies the subscription and resource group filter to every inventory query' {
            $SubscriptionId = '22222222-2222-2222-2222-222222222222'
            $ResourceGroupName = 'rg-prod'
            try {
                Main | Should -Be 0
                Should -Invoke Get-AzSubscription -Times 1 -Exactly `
                    -ParameterFilter { $SubscriptionId -eq '22222222-2222-2222-2222-222222222222' }
                Should -Invoke Get-AzNetworkSecurityGroup -Times 1 -Exactly `
                    -ParameterFilter { $ResourceGroupName -eq 'rg-prod' }
                Should -Invoke Get-AzVirtualNetwork -Times 1 -Exactly `
                    -ParameterFilter { $ResourceGroupName -eq 'rg-prod' }
                Should -Invoke Get-AzNetworkInterface -Times 1 -Exactly `
                    -ParameterFilter { $ResourceGroupName -eq 'rg-prod' }
                Should -Invoke Get-AzPublicIpAddress -Times 1 -Exactly `
                    -ParameterFilter { $ResourceGroupName -eq 'rg-prod' }
            }
            finally {
                $SubscriptionId = '*'
                $ResourceGroupName = $null
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
            Should -Invoke Get-AzNetworkSecurityGroup -Times 2 -Exactly
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
        }

        It 'Writes a JSON report to OutputPath without changing the exit code' {
            $OutputFormat = 'Json'
            $OutputPath = $TestDrive
            try {
                $out = Main *>&1
                ($out | Out-String) | Should -Match '\[\+\] JSON report written:'
                $files = @(Get-ChildItem -LiteralPath $TestDrive -Filter '*.json')
                $files.Count | Should -Be 1
                $report = Get-Content -LiteralPath $files[0].FullName -Raw | ConvertFrom-Json
                $report.Subscriptions | Should -Be 'sub-prod'
                @($report.Findings).Count | Should -Be 0
                ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            }
            finally {
                $OutputFormat = 'Table'
                $OutputPath = $null
            }
        }

        It 'Rejects an unsafe OutputPath without querying Azure' {
            $OutputPath = '..\..\escape'
            try {
                $out = Main *>&1
                ($out | Out-String) | Should -Match '\[-\] Unsafe OutputPath:'
                ($out | Where-Object { $_ -is [int] }) | Should -Be 1
                Should -Invoke Get-AzSubscription -Times 0 -Exactly
            }
            finally {
                $OutputPath = $null
            }
        }
    }
}
