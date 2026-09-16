#Requires -Modules Pester
<#
.SYNOPSIS
    Pester tests for scripts/cloud/azure/monitoring/Get-AzureDiagnosticSettingsReport.ps1.
.DESCRIPTION
    Validates help and metadata conformance, static syntax rules, and observable behavior of the Azure
    Monitor diagnostic settings report using fully mocked Az cmdlets, so no Azure call ever leaves the
    machine. Runs offline on Linux pwsh; no network, Azure connectivity, or installed Az modules are
    required.
.EXAMPLE
    PS C:\> Invoke-Pester -Path ./Tests/cloud/azure/monitoring/Get-AzureDiagnosticSettingsReport.Tests.ps1
    Runs this test file.
.EXAMPLE
    PS C:\> Invoke-Pester -Path ./Tests/cloud/azure/monitoring/Get-AzureDiagnosticSettingsReport.Tests.ps1 `
        -Output Detailed
    Runs this test file with per-test output.
.NOTES
    File Name   : Get-AzureDiagnosticSettingsReport.Tests.ps1
    Author      : Bug-Free Umbrella
    Prerequisite: PowerShell 7.0
    Version     : 2.0.0
    Date        : 2026-09-16
#>

Describe 'Get-AzureDiagnosticSettingsReport' {
    BeforeAll {
        $scriptPath = Join-Path $PSScriptRoot `
            '../../../../scripts/cloud/azure/monitoring/Get-AzureDiagnosticSettingsReport.ps1'

        # Safe: the script's top-level guard skips Main when dot-sourced.
        . $scriptPath

        # The Az modules are not installed offline: declare their cmdlets as advanced functions with
        # the documented parameter sets (see the Learn links in the script help) so an unsupported
        # parameter throws instead of being silently ignored, then Mock each one.
        function Get-AzContext {
            [CmdletBinding()]
            param([Parameter()][object]$DefaultProfile)
        }
        function Get-AzSubscription {
            [CmdletBinding()]
            param(
                [Parameter()][string]$SubscriptionId,
                [Parameter()][string]$SubscriptionName,
                [Parameter()][string]$TenantId,
                [Parameter()][object]$DefaultProfile
            )
        }
        function Set-AzContext {
            [CmdletBinding()]
            param(
                [Parameter()][string]$SubscriptionId,
                [Parameter()][object]$DefaultProfile
            )
        }
        function Get-AzResource {
            [CmdletBinding()]
            param(
                [Parameter()][string]$Name,
                [Parameter()][string]$ResourceType,
                [Parameter()][string]$ODataQuery,
                [Parameter()][string]$ResourceGroupName,
                [Parameter()][string]$TagName,
                [Parameter()][string]$TagValue,
                [Parameter()][hashtable]$Tag,
                [Parameter()][string]$ResourceId,
                [Parameter()][string]$ApiVersion,
                [Parameter()][switch]$ExpandProperties,
                [Parameter()][switch]$Pre,
                [Parameter()][object]$DefaultProfile
            )
        }
        function Get-AzDiagnosticSetting {
            [CmdletBinding()]
            param(
                [Parameter()][string]$Name,
                [Parameter()][string]$ResourceId,
                [Parameter()][object]$InputObject,
                [Parameter()][object]$DefaultProfile
            )
        }

        $vaultId = '/subscriptions/sub-1/resourceGroups/rg-sec/providers/Microsoft.KeyVault/vaults/kv-prod'
        $workspaceId = '/subscriptions/sub-1/resourceGroups/rg-sec/providers/' +
            'Microsoft.OperationalInsights/workspaces/law-prod'

        Mock Import-Module { }
        Mock Get-AzContext { [pscustomobject]@{ Subscription = [pscustomobject]@{ Name = 'sub-prod' } } }
        Mock Get-AzSubscription { @([pscustomobject]@{ Id = 'sub-1'; Name = 'sub-prod' }) }
        Mock Set-AzContext { }

        # Healthy baseline: one resource whose single diagnostic setting sends logs and metrics to a
        # Log Analytics workspace.
        Mock Get-AzResource {
            @(
                [pscustomobject]@{
                    Name              = 'kv-prod'
                    ResourceType      = 'Microsoft.KeyVault/vaults'
                    ResourceGroupName = 'rg-sec'
                    ResourceId        = $vaultId
                }
            )
        }
        Mock Get-AzDiagnosticSetting {
            @(
                [pscustomobject]@{
                    Name        = 'kv-diagnostics'
                    Enabled     = $true
                    WorkspaceId = $workspaceId
                    Log         = @(
                        [pscustomobject]@{ Category = 'AuditEvent'; Enabled = $true }
                    )
                    Metric      = @(
                        [pscustomobject]@{ Category = 'AllMetrics'; Enabled = $true }
                    )
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
            $raw | Should -Match '(?m)File Name\s*:\s*Get-AzureDiagnosticSettingsReport\.ps1'
            $raw | Should -Match '(?m)Author\s*:\s*\S+'
            $raw | Should -Match '(?m)Prerequisite\s*:\s*PowerShell 7\.0'
            $raw | Should -Match '(?m)Version\s*:\s*2\.0\.0'
            $raw | Should -Match '(?m)Date\s*:\s*2026-09-16'
        }

        It 'Has one PARAMETER entry per declared parameter' {
            foreach ($name in @('SubscriptionId', 'ResourceType', 'OutputFormat', 'OutputPath')) {
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

        It 'Cites Microsoft Learn and drives the documented Az cmdlets' {
            $raw | Should -Match 'learn\.microsoft\.com'
            $raw | Should -Match 'Get-AzDiagnosticSetting'
            $raw | Should -Match 'Get-AzResource'
            $raw | Should -Match 'azure-monitor/essentials/diagnostic-settings'
        }
    }

    Context 'Behavior' {
        It 'Reports a compliant resource and returns 0 when the setting has a Log Analytics destination' {
            $SubscriptionId = '*'
            $ResourceType = '*'
            $OutputFormat = 'Table'
            $OutputPath = $TestDrive
            $workingDirectory = (Get-Location).Path

            $out = Main *>&1
            $text = $out | Out-String

            $text | Should -Match '\[\+\] Connected to: sub-prod'
            $text | Should -Match '\[\+\] Resources evaluated: 1'
            $text | Should -Match '\[\+\] Diagnostic settings found: 1'
            $text | Should -Match 'kv-prod \[kv-diagnostics\] -> LogAnalytics'
            $text | Should -Match 'logs: AuditEvent'
            $text | Should -Match 'metrics: AllMetrics'
            $text | Should -Match '\[\+\] Diagnostic settings are compliant'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            Should -Invoke Get-AzResource -Times 1 -Exactly
            Should -Invoke Get-AzDiagnosticSetting -Times 1 -Exactly `
                -ParameterFilter { $ResourceId -like '*kv-prod' }
            (Get-Location).Path | Should -Be $workingDirectory
        }

        It 'Flags a resource with no setting and a setting with no Log Analytics destination, returning 2' {
            $SubscriptionId = '*'
            $ResourceType = '*'
            $OutputFormat = 'Table'
            $OutputPath = $TestDrive

            Mock Get-AzResource {
                @(
                    [pscustomobject]@{
                        Name              = 'kv-prod'
                        ResourceType      = 'Microsoft.KeyVault/vaults'
                        ResourceGroupName = 'rg-sec'
                        ResourceId        = $vaultId
                    }
                    [pscustomobject]@{
                        Name              = 'vm-app'
                        ResourceType      = 'Microsoft.Compute/virtualMachines'
                        ResourceGroupName = 'rg-app'
                        ResourceId        = '/subscriptions/sub-1/resourceGroups/rg-app/providers/' +
                            'Microsoft.Compute/virtualMachines/vm-app'
                    }
                )
            }
            Mock Get-AzDiagnosticSetting {
                if ($ResourceId -like '*kv-prod') {
                    return @(
                        [pscustomobject]@{
                            Name            = 'kv-audit'
                            Enabled         = $true
                            WorkspaceId     = $null
                            StorageAccountId = '/subscriptions/sub-1/resourceGroups/rg-sec/providers/' +
                                'Microsoft.Storage/storageAccounts/stsec'
                            Log             = @(
                                [pscustomobject]@{ Category = 'AuditEvent'; Enabled = $true }
                                [pscustomobject]@{ Category = 'AllLogs'; Enabled = $false }
                            )
                            Metric          = @()
                        }
                    )
                }
                return @()
            }

            $out = Main *>&1
            $text = $out | Out-String

            $text | Should -Match '\[\+\] Resources evaluated: 2'
            $text | Should -Match '\[\+\] Diagnostic settings found: 1'
            $text | Should -Match '\[!\] 1 resource\(s\) have no diagnostic setting'
            $text | Should -Match '    - Microsoft\.Compute/virtualMachines/vm-app'
            $text | Should -Match '\[!\] 1 diagnostic setting\(s\) have no Log Analytics destination'
            $text | Should -Match '    - kv-prod/kv-audit'
            $text | Should -Match '\[!\] 2 diagnostic settings finding\(s\) detected\.'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 2
        }

        It 'Writes a CSV report when OutputFormat is Csv without touching the working directory' {
            $SubscriptionId = '*'
            $ResourceType = '*'
            $OutputFormat = 'Csv'
            $OutputPath = $TestDrive
            $workingDirectory = (Get-Location).Path

            $out = Main *>&1
            $text = $out | Out-String

            $text | Should -Match '\[\+\] Report written to:'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0

            $reports = @(Get-ChildItem -Path $TestDrive -Filter 'AzureDiagnosticSettings-*.csv')
            $reports.Count | Should -Be 1
            (Get-Content -LiteralPath $reports[0].FullName -Raw) | Should -Match 'kv-diagnostics'
            (Get-Location).Path | Should -Be $workingDirectory
        }

        It 'Passes ResourceType through to Get-AzResource when a concrete type is supplied' {
            $SubscriptionId = '*'
            $ResourceType = 'Microsoft.KeyVault/vaults'
            $OutputFormat = 'Table'
            $OutputPath = $TestDrive

            $out = Main *>&1

            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            Should -Invoke Get-AzResource -Times 1 -Exactly `
                -ParameterFilter { $ResourceType -eq 'Microsoft.KeyVault/vaults' }
        }

        It 'Returns 1 with [-] output when not connected to Azure' {
            $SubscriptionId = '*'
            $ResourceType = '*'
            $OutputFormat = 'Table'
            $OutputPath = $TestDrive

            Mock Get-AzContext { $null }

            $out = Main *>&1
            $text = $out | Out-String

            $text | Should -Match '\[-\] Error: Not connected to Azure'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
            Should -Invoke Get-AzDiagnosticSetting -Times 0 -Exactly -Because 'the connection check fails first'
        }

        It 'Returns 1 when the Az.Resources module cannot be imported' {
            $SubscriptionId = '*'
            $ResourceType = '*'
            $OutputFormat = 'Table'
            $OutputPath = $TestDrive

            Mock Import-Module { throw 'Az.Resources is not installed' }

            $out = Main *>&1
            $text = $out | Out-String

            $text | Should -Match '\[-\] Error: Az\.Resources is not installed'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
        }

        It 'Returns 1 when a diagnostic setting query fails so compliance cannot be verified' {
            $SubscriptionId = '*'
            $ResourceType = '*'
            $OutputFormat = 'Table'
            $OutputPath = $TestDrive

            Mock Get-AzDiagnosticSetting { throw 'diagnostic setting query failed with status 429' }

            $out = Main *>&1
            $text = $out | Out-String

            $failureText = '\[!\] Diagnostic setting query failed for ''kv-prod'': ' +
                'diagnostic setting query failed with status 429'
            $text | Should -Match $failureText
            $text | Should -Match '\[-\] Error: diagnostic settings inventory incomplete'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
        }

        It 'Returns 1 when OutputPath is unsafe' {
            $SubscriptionId = '*'
            $ResourceType = '*'
            $OutputFormat = 'Csv'
            $OutputPath = '../outside'

            $out = Main *>&1
            $text = $out | Out-String

            $text | Should -Match '\[-\] Error: Unsafe OutputPath'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
        }

        It 'Is idempotent: repeated read-only runs return the same exit code' {
            $SubscriptionId = '*'
            $ResourceType = '*'
            $OutputFormat = 'Table'
            $OutputPath = $TestDrive

            Main | Should -Be 0
            Main | Should -Be 0
            Should -Invoke Get-AzResource -Times 2 -Exactly -Because 'one resource query per run'
        }
    }
}
