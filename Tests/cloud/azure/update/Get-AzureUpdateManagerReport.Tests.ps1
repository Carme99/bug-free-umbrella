#Requires -Modules Pester
<#
.SYNOPSIS
    Pester tests for scripts/cloud/azure/update/Get-AzureUpdateManagerReport.ps1.
.DESCRIPTION
    Validates help and metadata conformance, static syntax rules, and observable behavior of the
    Azure Update Manager compliance report using fully mocked Az cmdlets, so no Azure or Azure
    Resource Graph call ever leaves the machine. Runs offline on Linux pwsh; no network, Azure
    connectivity, or installed Az modules are required.
.EXAMPLE
    PS C:\> Invoke-Pester -Path ./Tests/cloud/azure/update/Get-AzureUpdateManagerReport.Tests.ps1
    Runs this test file.
.EXAMPLE
    PS C:\> Invoke-Pester -Path ./Tests/cloud/azure/update/Get-AzureUpdateManagerReport.Tests.ps1 -Output Detailed
    Runs this test file with per-test output.
.NOTES
    File Name   : Get-AzureUpdateManagerReport.Tests.ps1
    Author      : Bug-Free Umbrella
    Prerequisite: PowerShell 7.0
    Version     : 2.0.0
    Date        : 2026-09-16
#>

Describe 'Get-AzureUpdateManagerReport' {
    BeforeAll {
        $scriptPath = Join-Path $PSScriptRoot `
            '../../../../scripts/cloud/azure/update/Get-AzureUpdateManagerReport.ps1'

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
        function Get-AzMaintenanceConfiguration {
            [CmdletBinding()]
            param([string]$ResourceGroupName, [string]$Name)
        }
        function Search-AzGraph {
            [CmdletBinding()]
            param([string]$Query, [string[]]$Subscription, [int]$First, [int]$Skip, [string]$SkipToken)
        }

        Mock Import-Module { }
        Mock Get-AzContext { [pscustomobject]@{ Subscription = [pscustomobject]@{ Name = 'sub-prod' } } }
        Mock Get-AzSubscription { @([pscustomobject]@{ Id = 'sub-1'; Name = 'sub-prod' }) }
        Mock Set-AzContext { }

        # Default fixture is a non-compliant environment: vm-app-2 has no assessment, vm-db-1 has no
        # maintenance configuration assignment, and mc-orphan has no machines.
        Mock Search-AzGraph {
            param($Query, $Subscription, $First, $SkipToken)

            $appMachine = '/subscriptions/sub-1/resourceGroups/rg-app/providers/Microsoft.Compute' +
                '/virtualMachines/vm-app-1'
            $brokenMachine = '/subscriptions/sub-1/resourceGroups/rg-app/providers/Microsoft.Compute' +
                '/virtualMachines/vm-app-2'
            $dbMachine = '/subscriptions/sub-1/resourceGroups/rg-db/providers/Microsoft.Compute' +
                '/virtualMachines/vm-db-1'
            $configurationId = '/subscriptions/sub-1/resourceGroups/rg-patch/providers/Microsoft.Maintenance' +
                '/maintenanceConfigurations/mc-weekly'
            $assignmentSuffix = '/providers/Microsoft.Maintenance/configurationAssignments/one'

            if ($Query -match 'patchassessmentresources') {
                return @(
                    [pscustomobject]@{
                        id            = "$appMachine/patchAssessmentResults/latest"
                        criticalCount = 2
                        securityCount = 3
                    }
                )
            }
            if ($Query -match 'maintenanceresources') {
                return @(
                    [pscustomobject]@{
                        id                         = "$appMachine$assignmentSuffix"
                        resourceId                 = $appMachine
                        maintenanceConfigurationId = $configurationId
                    }
                    [pscustomobject]@{
                        id                         = "$brokenMachine$assignmentSuffix"
                        resourceId                 = $brokenMachine
                        maintenanceConfigurationId = $configurationId
                    }
                )
            }
            return @(
                [pscustomobject]@{
                    id = $appMachine; name = 'vm-app-1'; resourceGroup = 'rg-app'; subscriptionId = 'sub-1'
                }
                [pscustomobject]@{
                    id = $brokenMachine; name = 'vm-app-2'; resourceGroup = 'rg-app'; subscriptionId = 'sub-1'
                }
                [pscustomobject]@{
                    id = $dbMachine; name = 'vm-db-1'; resourceGroup = 'rg-db'; subscriptionId = 'sub-1'
                }
            )
        }

        Mock Get-AzMaintenanceConfiguration {
            $usedConfiguration = '/subscriptions/sub-1/resourceGroups/rg-patch/providers/Microsoft.Maintenance' +
                '/maintenanceConfigurations/mc-weekly'
            $orphanConfiguration = '/subscriptions/sub-1/resourceGroups/rg-patch/providers/Microsoft.Maintenance' +
                '/maintenanceConfigurations/mc-orphan'
            @(
                [pscustomobject]@{
                    Name              = 'mc-weekly'
                    Id                = $usedConfiguration
                    MaintenanceScope  = 'InGuestPatch'
                    ResourceGroupName = 'rg-patch'
                }
                [pscustomobject]@{
                    Name              = 'mc-orphan'
                    Id                = $orphanConfiguration
                    MaintenanceScope  = 'InGuestPatch'
                    ResourceGroupName = 'rg-patch'
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
            $raw | Should -Match '(?m)File Name\s*:\s*Get-AzureUpdateManagerReport\.ps1'
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

        It 'Cites Microsoft Learn and reads the Update Manager Resource Graph tables' {
            $raw | Should -Match 'learn\.microsoft\.com'
            $raw | Should -Match 'patchassessmentresources'
            $raw | Should -Match 'maintenanceresources'
            $raw | Should -Match 'Get-AzMaintenanceConfiguration'
        }

        It 'Is read-only: no configuration-mutating cmdlet is referenced' {
            ($raw -match 'New-AzMaintenanceConfiguration') | Should -BeFalse
            ($raw -match 'Update-AzMaintenanceConfiguration') | Should -BeFalse
            ($raw -match 'Remove-AzMaintenanceConfiguration') | Should -BeFalse
        }
    }

    Context 'Behavior' {
        It 'Reports unassessed machines, pending updates, unassigned machines and orphan schedules' {
            $SubscriptionId = '*'
            $ResourceGroupName = '*'
            $OutputFormat = 'Table'

            $out = Main *>&1
            $text = $out | Out-String

            $text | Should -Match '\[\+\] Connected to: sub-prod'
            $text | Should -Match '\[\+\] Found 3 machine\(s\), 1 assessment result\(s\), 2 maintenance'
            $text | Should -Match '\[!\] 2 machine\(s\) have no update assessment result\.'
            $text | Should -Match '\[!\] 1 machine\(s\) have pending critical/security updates\.'
            $text | Should -Match '\[!\] 1 machine\(s\) have no maintenance configuration assigned\.'
            $text | Should -Match '\[!\] 1 maintenance configuration\(s\) have no machines assigned\.'
            $text | Should -Match '\[!\] 5 finding\(s\) detected\.'
            $text | Should -Match 'PendingCriticalSecurityUpdates'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 2
            Should -Invoke Search-AzGraph -Times 3 -Exactly -Because 'machines, assessments and assignments'
            Should -Invoke Get-AzMaintenanceConfiguration -Times 1 -Exactly
        }

        It 'Returns 0 when every machine is assessed and assigned to a maintenance configuration' {
            $SubscriptionId = '*'
            $ResourceGroupName = '*'
            $OutputFormat = 'Table'

            Mock Search-AzGraph {
                param($Query, $Subscription, $First, $SkipToken)

                $machineId = '/subscriptions/sub-1/resourceGroups/rg-app/providers/Microsoft.Compute' +
                    '/virtualMachines/vm-app-1'
                $configurationId = '/subscriptions/sub-1/resourceGroups/rg-patch' +
                    '/providers/Microsoft.Maintenance/maintenanceConfigurations/mc-weekly'
                $assignmentSuffix = '/providers/Microsoft.Maintenance/configurationAssignments/one'

                if ($Query -match 'patchassessmentresources') {
                    return @(
                        [pscustomobject]@{
                            id            = "$machineId/patchAssessmentResults/latest"
                            criticalCount = 0
                            securityCount = 0
                        }
                    )
                }
                if ($Query -match 'maintenanceresources') {
                    return @(
                        [pscustomobject]@{
                            id                         = "$machineId$assignmentSuffix"
                            resourceId                 = $machineId
                            maintenanceConfigurationId = $configurationId
                        }
                    )
                }
                return @(
                    [pscustomobject]@{
                        id = $machineId; name = 'vm-app-1'; resourceGroup = 'rg-app'; subscriptionId = 'sub-1'
                    }
                )
            }
            Mock Get-AzMaintenanceConfiguration {
                @(
                    [pscustomobject]@{
                        Name              = 'mc-weekly'
                        Id                = '/subscriptions/sub-1/resourceGroups/rg-patch' +
                            '/providers/Microsoft.Maintenance/maintenanceConfigurations/mc-weekly'
                        MaintenanceScope  = 'InGuestPatch'
                        ResourceGroupName = 'rg-patch'
                    }
                )
            }

            $out = Main *>&1
            $text = $out | Out-String

            $text | Should -Match '\[\+\] Found 1 machine\(s\), 1 assessment result\(s\), 1 maintenance'
            $text | Should -Match '\[\+\] All machines are assessed and assigned to a maintenance configuration\.'
            $text | Should -Not -Match '\[!\]'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
        }

        It 'Filters the report by ResourceGroupName and passes the filter to the cmdlet' {
            $SubscriptionId = '*'
            $ResourceGroupName = 'rg-app'
            $OutputFormat = 'Table'

            $out = Main *>&1
            $text = $out | Out-String

            $text | Should -Match 'Resource group filter: rg-app'
            $text | Should -Match '\[\+\] Found 2 machine\(s\), 1 assessment result\(s\)'
            $text | Should -Match '\[!\] 1 machine\(s\) have no update assessment result\.'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 2 -Because 'vm-app-2 is unscanned'
            Should -Invoke Get-AzMaintenanceConfiguration -Times 1 -Exactly `
                -ParameterFilter { $ResourceGroupName -eq 'rg-app' }
        }

        It 'Writes a CSV report when OutputFormat is Csv and keeps the findings exit code' {
            $SubscriptionId = '*'
            $ResourceGroupName = '*'
            $OutputFormat = 'Csv'
            $OutputPath = $TestDrive

            $out = Main *>&1
            $text = $out | Out-String

            $text | Should -Match '\[\+\] Report written to:'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 2

            $reports = @(Get-ChildItem -Path $TestDrive -Filter 'AzureUpdateManager-*.csv')
            $reports.Count | Should -Be 1
            $csv = Get-Content -LiteralPath $reports[0].FullName -Raw
            $csv | Should -Match 'NoUpdateAssessment'
            $csv | Should -Match 'UnusedMaintenanceConfiguration'
        }

        It 'Returns 1 with [-] output when not connected to Azure' {
            Mock Get-AzContext { $null }

            $out = Main *>&1
            $text = $out | Out-String

            $text | Should -Match '\[-\] Error: Not connected to Azure'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
            Should -Invoke Search-AzGraph -Times 0 -Exactly -Because 'the connection check fails first'
        }

        It 'Returns 1 when the Az.Accounts module cannot be imported' {
            Mock Import-Module { throw 'Az.Accounts is not installed' }

            $out = Main *>&1
            $text = $out | Out-String

            $text | Should -Match '\[-\] Error: Az\.Accounts is not installed'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
        }

        It 'Returns 1 when the machine inventory fails for every subscription' {
            Mock Search-AzGraph { throw 'Resource Graph query was throttled' }

            $out = Main *>&1
            $text = $out | Out-String

            $text | Should -Match '\[!\] Failed to enumerate machines: Resource Graph query was throttled'
            $text | Should -Match '\[-\] Error: The machine inventory could not be read for any subscription\.'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
        }

        It 'Is idempotent: repeated read-only runs return the same exit code' {
            $SubscriptionId = '*'
            $ResourceGroupName = '*'
            $OutputFormat = 'Table'

            Main | Should -Be 2
            Main | Should -Be 2
            Should -Invoke Search-AzGraph -Times 6 -Exactly -Because 'three queries per run, nothing accumulates'
        }
    }
}
