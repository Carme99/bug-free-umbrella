#Requires -Modules Pester
<#
.SYNOPSIS
    Pester tests for scripts/cloud/azure/cost/Get-AzureCostOptimizationReport.ps1.
.DESCRIPTION
    Validates help and metadata conformance, static syntax rules, and observable behavior of the
    Azure cost optimisation report using fully mocked Az cmdlets and a mocked Invoke-AzRestMethod,
    so no Cost Management API call ever leaves the machine. Runs offline on Linux pwsh; no network,
    Azure connectivity, or installed Az modules are required.
.EXAMPLE
    PS C:\> Invoke-Pester -Path ./Tests/cloud/azure/cost/Get-AzureCostOptimizationReport.Tests.ps1
    Runs this test file.
.EXAMPLE
    PS C:\> Invoke-Pester -Path ./Tests/cloud/azure/cost/Get-AzureCostOptimizationReport.Tests.ps1 -Output Detailed
    Runs this test file with per-test output.
.NOTES
    File Name   : Get-AzureCostOptimizationReport.Tests.ps1
    Author      : Bug-Free Umbrella
    Prerequisite: PowerShell 7.0
    Version     : 2.0.0
    Date        : 2026-09-16
#>

Describe 'Get-AzureCostOptimizationReport' {
    BeforeAll {
        $scriptPath = Join-Path $PSScriptRoot `
            '../../../../scripts/cloud/azure/cost/Get-AzureCostOptimizationReport.ps1'

        # Safe: the script's top-level guard skips Main when dot-sourced.
        . $scriptPath

        # The Az modules are not installed offline: declare their cmdlets as empty functions so
        # Pester can mock them, then Mock each one.
        function Get-AzContext {
            [CmdletBinding()]
            param()
        }
        function Get-AzSubscription {
            [CmdletBinding()]
            param([string]$SubscriptionId, [string]$SubscriptionName, [string]$TenantId)
        }
        function Set-AzContext {
            [CmdletBinding()]
            param([string]$SubscriptionId, [string]$SubscriptionName, [string]$Name)
        }
        function Invoke-AzRestMethod {
            [CmdletBinding()]
            param([string]$Path, [string]$Method, [string]$Payload, [string]$ApiVersion)
        }
        function Get-AzVM {
            [CmdletBinding()]
            param([string]$ResourceGroupName, [string]$Name, [switch]$Status)
        }
        function Get-AzDisk {
            [CmdletBinding()]
            param([string]$ResourceGroupName, [string]$DiskName)
        }
        function Get-AzPublicIpAddress {
            [CmdletBinding()]
            param([string]$Name, [string]$ResourceGroupName)
        }

        Mock Import-Module { }
        Mock Get-AzContext { [pscustomobject]@{ Subscription = [pscustomobject]@{ Name = 'sub-prod' } } }
        Mock Get-AzSubscription { @([pscustomobject]@{ Id = 'sub-1'; Name = 'sub-prod' }) }
        Mock Set-AzContext { }

        # Cost Management Query API responses: one grouped by ServiceName, one grouped by
        # ResourceGroupName, one ungrouped MonthToDate total. Shape per
        # https://learn.microsoft.com/en-us/rest/api/cost-management/query/usage
        Mock Invoke-AzRestMethod {
            param($Method, $Path, $Payload)

            if ($Payload -match 'ServiceName') {
                return [pscustomobject]@{
                    StatusCode = 200
                    Content    = '{"properties":{"columns":[{"name":"PreTaxCost","type":"Number"},' +
                        '{"name":"ServiceName","type":"String"},{"name":"Currency","type":"String"}],' +
                        '"rows":[[120.5,"Virtual Machines","GBP"],[80.25,"Storage","GBP"]]}}'
                }
            }
            if ($Payload -match 'ResourceGroupName') {
                return [pscustomobject]@{
                    StatusCode = 200
                    Content    = '{"properties":{"columns":[{"name":"PreTaxCost","type":"Number"},' +
                        '{"name":"ResourceGroupName","type":"String"},{"name":"Currency","type":"String"}],' +
                        '"rows":[[150.0,"rg-app","GBP"],[50.75,"rg-db","GBP"]]}}'
                }
            }
            if ($Payload -match 'MonthToDate') {
                return [pscustomobject]@{
                    StatusCode = 200
                    Content    = '{"properties":{"columns":[{"name":"PreTaxCost","type":"Number"},' +
                        '{"name":"Currency","type":"String"}],"rows":[[456.25,"GBP"]]}}'
                }
            }
            return [pscustomobject]@{ StatusCode = 204; Content = '' }
        }

        # Healthy resource inventory: nothing idle, nothing unattached.
        Mock Get-AzVM {
            @(
                [pscustomobject]@{
                    Name              = 'vm-app-1'
                    ResourceGroupName = 'rg-app'
                    Statuses          = @(
                        [pscustomobject]@{ Code = 'PowerState/running'; DisplayStatus = 'VM running' }
                    )
                }
            )
        }
        Mock Get-AzDisk {
            $attachedTo = '/subscriptions/sub-1/resourceGroups/rg-app/providers/Microsoft.Compute' +
                '/virtualMachines/vm-app-1'
            @(
                [pscustomobject]@{
                    Name              = 'disk-app-1'
                    ResourceGroupName = 'rg-app'
                    ManagedBy         = $attachedTo
                }
            )
        }
        Mock Get-AzPublicIpAddress {
            @(
                [pscustomobject]@{
                    Name              = 'pip-app-1'
                    ResourceGroupName = 'rg-app'
                    IpConfiguration   = @([pscustomobject]@{ Id = 'nic-app-1' })
                    NatGateway        = $null
                }
            )
        }

        $raw = [IO.File]::ReadAllText($scriptPath)
        $tokens = $null
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errors)
    }

    Context 'Help & Metadata' {
        It 'Declares all five NOTES fields with v2.0.0 values' {
            $raw | Should -Match '(?m)File Name\s*:\s*Get-AzureCostOptimizationReport\.ps1'
            $raw | Should -Match '(?m)Author\s*:\s*\S+'
            $raw | Should -Match '(?m)Prerequisite\s*:\s*PowerShell 7\.0'
            $raw | Should -Match '(?m)Version\s*:\s*2\.0\.0'
            $raw | Should -Match '(?m)Date\s*:\s*2026-09-16'
        }

        It 'Has one PARAMETER entry per declared parameter' {
            foreach ($name in @('SubscriptionId', 'LookbackDays', 'TopN', 'OutputFormat', 'OutputPath')) {
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

        It 'Cites Microsoft Learn and targets the Cost Management query API' {
            $raw | Should -Match 'learn\.microsoft\.com'
            $raw | Should -Match 'Microsoft\.CostManagement/query'
        }

        It 'Does not call the deprecated Consumption Usage Details cmdlet' {
            ($raw -match 'Get-AzConsumptionUsageDetail\s+-[A-Za-z]') | Should -BeFalse
        }
    }

    Context 'Behavior' {
        It 'Reports month-to-date spend and top cost drivers, returning 0 when nothing is idle' {
            $SubscriptionId = '*'
            $LookbackDays = 30
            $TopN = 10
            $OutputFormat = 'Table'

            $out = Main *>&1
            $text = $out | Out-String

            $text | Should -Match '\[\+\] Connected to: sub-prod'
            $text | Should -Match 'Lookback      : 30 day\(s\), top 10 drivers'
            $text | Should -Match 'Month-to-date : sub-prod = 456\.25 GBP'
            $text | Should -Match 'Virtual Machines'
            $text | Should -Match 'rg-app'
            $text | Should -Match '\[\+\] No optimisation findings detected\.'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            Should -Invoke Invoke-AzRestMethod -Times 3 -Exactly -Because 'one query per dimension and month-to-date'
            Should -Invoke Get-AzVM -Times 1 -Exactly
            Should -Invoke Get-AzDisk -Times 1 -Exactly
            Should -Invoke Get-AzPublicIpAddress -Times 1 -Exactly
        }

        It 'Flags stopped-but-allocated VMs, unattached disks and idle public IPs, returning 2' {
            $SubscriptionId = '*'
            $OutputFormat = 'Table'

            Mock Get-AzVM {
                @(
                    [pscustomobject]@{
                        Name              = 'vm-stopped'
                        ResourceGroupName = 'rg-app'
                        Statuses          = @(
                            [pscustomobject]@{ Code = 'PowerState/stopped'; DisplayStatus = 'VM stopped' }
                        )
                    }
                    [pscustomobject]@{
                        Name              = 'vm-deallocated'
                        ResourceGroupName = 'rg-app'
                        Statuses          = @(
                            [pscustomobject]@{ Code = 'PowerState/deallocated'; DisplayStatus = 'VM deallocated' }
                        )
                    }
                )
            }
            Mock Get-AzDisk {
                @([pscustomobject]@{ Name = 'disk-orphan'; ResourceGroupName = 'rg-app'; ManagedBy = $null })
            }
            Mock Get-AzPublicIpAddress {
                @(
                    [pscustomobject]@{
                        Name              = 'pip-idle'
                        ResourceGroupName = 'rg-db'
                        IpConfiguration   = $null
                        NatGateway        = $null
                    }
                )
            }

            $out = Main *>&1
            $text = $out | Out-String

            $text | Should -Match '\[!\] 1 VM\(s\) stopped but still allocated \(still billing\)\.'
            $text | Should -Match '\[!\] 1 unattached managed disk\(s\) \(still billing\)\.'
            $text | Should -Match '\[!\] 1 idle public IP address\(es\) \(still billing\)\.'
            $text | Should -Match '\[!\] 3 optimisation finding\(s\) detected\.'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 2 -Because 'deallocated VMs are not findings'
        }

        It 'Writes a CSV report file when OutputFormat is Csv and keeps the findings exit code' {
            $SubscriptionId = '*'
            $OutputFormat = 'Csv'
            $OutputPath = $TestDrive

            Mock Get-AzVM {
                @(
                    [pscustomobject]@{
                        Name              = 'vm-stopped'
                        ResourceGroupName = 'rg-app'
                        Statuses          = @(
                            [pscustomobject]@{ Code = 'PowerState/stopped'; DisplayStatus = 'VM stopped' }
                        )
                    }
                )
            }

            $out = Main *>&1
            $text = $out | Out-String

            $text | Should -Match '\[\+\] Report written to:'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 2

            $reports = @(Get-ChildItem -Path $TestDrive -Filter 'AzureCostOptimization-*.csv')
            $reports.Count | Should -Be 1
            (Get-Content -LiteralPath $reports[0].FullName -Raw) | Should -Match 'StoppedButBilling'
        }

        It 'Returns 1 with [-] output when not connected to Azure' {
            Mock Get-AzContext { $null }

            $out = Main *>&1
            $text = $out | Out-String

            $text | Should -Match '\[-\] Error: Not connected to Azure'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
            Should -Invoke Invoke-AzRestMethod -Times 0 -Exactly -Because 'the connection check fails first'
        }

        It 'Returns 1 when the Az.Accounts module cannot be imported' {
            Mock Import-Module { throw 'Az.Accounts is not installed' }

            $out = Main *>&1
            $text = $out | Out-String

            $text | Should -Match '\[-\] Error: Az\.Accounts is not installed'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
        }

        It 'Returns 1 when every Cost Management query fails' {
            Mock Invoke-AzRestMethod { throw 'Cost Management query failed with status 429' }

            $out = Main *>&1
            $text = $out | Out-String

            $text | Should -Match '\[!\] Service cost query failed'
            $text | Should -Match '\[-\] Error: Every Cost Management query failed'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
        }

        It 'Is idempotent: repeated read-only runs return the same exit code' {
            $SubscriptionId = '*'
            $OutputFormat = 'Table'

            Main | Should -Be 0
            Main | Should -Be 0
            Should -Invoke Invoke-AzRestMethod -Times 6 -Exactly -Because 'three queries per run, nothing accumulates'
        }
    }
}
