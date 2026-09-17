#Requires -Modules Pester
<#
.SYNOPSIS
    Pester tests for scripts/cloud/azure/governance/policy/Get-AzurePolicyComplianceReport.ps1.
.DESCRIPTION
    Validates help and metadata conformance, static syntax rules, and observable behavior of the Azure
    Policy compliance report using fully mocked Az.PolicyInsights cmdlets, so no Azure call ever leaves the
    machine. Runs offline on Linux pwsh; no network, Azure connectivity, or installed Az modules required.
.EXAMPLE
    PS C:\> Invoke-Pester -Path ./Tests/cloud/azure/governance/policy/Get-AzurePolicyComplianceReport.Tests.ps1
    Runs this test file.
.EXAMPLE
    PS C:\> Invoke-Pester -Path ./Tests/cloud/azure/governance/policy -Output Detailed
    Runs the tests of this directory with per-test output.
.NOTES
    File Name   : Get-AzurePolicyComplianceReport.Tests.ps1
    Author      : Bug-Free Umbrella
    Prerequisite: PowerShell 7.0
    Version     : 2.0.0
    Date        : 2026-09-16
#>

Describe 'Get-AzurePolicyComplianceReport' {
    BeforeAll {
        $scriptPath = Join-Path $PSScriptRoot `
            '../../../../../scripts/cloud/azure/governance/policy/Get-AzurePolicyComplianceReport.ps1'

        $workingDirectory = (Get-Location).Path

        # Safe: the script's top-level guard skips Main when dot-sourced.
        . $scriptPath

        # Az.PolicyInsights is not installed offline: declare every external cmdlet the script calls as an
        # advanced function with the real parameter set, so an unsupported parameter fails this test
        # instead of passing silently. The parameter sets match the Microsoft Learn references.
        function Get-AzContext {
            [CmdletBinding()]
            param()
        }
        function Get-AzSubscription {
            [CmdletBinding()]
            param([string]$SubscriptionId, [string]$SubscriptionName, [string]$TenantId)
        }
        function Get-AzPolicyState {
            [CmdletBinding()]
            param(
                [Parameter(Mandatory = $false)][string[]]$SubscriptionId,
                [Parameter(Mandatory = $false)][string]$ResourceGroupName,
                [Parameter(Mandatory = $false)][string]$PolicyAssignmentName,
                [Parameter(Mandatory = $false)][string]$Filter,
                [Parameter(Mandatory = $false)][switch]$All,
                [Parameter(Mandatory = $false)][int]$Top
            )
        }
        function Get-AzPolicyStateSummary {
            [CmdletBinding()]
            param(
                [Parameter(Mandatory = $false)][string]$SubscriptionId,
                [Parameter(Mandatory = $false)][string]$ResourceGroupName,
                [Parameter(Mandatory = $false)][string]$PolicyAssignmentName,
                [Parameter(Mandatory = $false)][string]$Filter,
                [Parameter(Mandatory = $false)][int]$Top
            )
        }
        function Start-AzPolicyComplianceScan {
            [CmdletBinding()]
            param(
                [Parameter(Mandatory = $false)][string]$SubscriptionId,
                [Parameter(Mandatory = $false)][string]$ResourceGroupName,
                [Parameter(Mandatory = $false)][switch]$NoWait,
                [Parameter(Mandatory = $false)][switch]$AsJob,
                [Parameter(Mandatory = $false)][switch]$PassThru
            )
        }

        Mock Import-Module { }
        Mock Get-AzContext { [pscustomobject]@{ Subscription = [pscustomobject]@{ Name = 'sub-prod' } } }
        Mock Get-AzSubscription { @([pscustomobject]@{ Id = 'sub-1'; Name = 'sub-prod' }) }
        Mock Start-AzPolicyComplianceScan { }

        # Default fixture: 'deny-public-ip' belongs to initiative 'baseline' and has one compliant plus one
        # non-compliant resource; 'audit-tags' has one non-compliant resource and was last evaluated 30
        # hours ago, which is beyond the 24-hour automatic evaluation cycle.
        Mock Get-AzPolicyState {
            $denyAssignment = '/subscriptions/sub-1/providers/Microsoft.Authorization/policyAssignments' +
                '/deny-public-ip'
            $auditAssignment = '/subscriptions/sub-1/providers/Microsoft.Authorization/policyAssignments' +
                '/audit-tags'
            $initiative = '/subscriptions/sub-1/providers/Microsoft.Authorization/policySetDefinitions' +
                '/baseline'
            $recent = (Get-Date).ToUniversalTime().AddHours(-2)
            $stale = (Get-Date).ToUniversalTime().AddHours(-30)

            @(
                [pscustomobject]@{
                    ResourceId = '/subscriptions/sub-1/resourceGroups/rg-app/providers/Microsoft.Compute' +
                        '/virtualMachines/vm-app-1'
                    PolicyAssignmentId = $denyAssignment
                    PolicySetDefinitionId = $initiative
                    ComplianceState = 'Compliant'
                    PolicyDefinitionAction = 'deny'
                    Timestamp = $recent
                }
                [pscustomobject]@{
                    ResourceId = '/subscriptions/sub-1/resourceGroups/rg-app/providers/Microsoft.Compute' +
                        '/virtualMachines/vm-app-2'
                    PolicyAssignmentId = $denyAssignment
                    PolicySetDefinitionId = $initiative
                    ComplianceState = 'NonCompliant'
                    PolicyDefinitionAction = 'deny'
                    Timestamp = $recent
                }
                [pscustomobject]@{
                    ResourceId = '/subscriptions/sub-1/resourceGroups/rg-db/providers/Microsoft.Storage' +
                        '/storageAccounts/stg-db-1'
                    PolicyAssignmentId = $auditAssignment
                    PolicySetDefinitionId = ''
                    ComplianceState = 'NonCompliant'
                    PolicyDefinitionAction = 'audit'
                    Timestamp = $stale
                }
            )
        }

        Mock Get-AzPolicyStateSummary {
            [pscustomobject]@{ ResultNonCompliantResource = 2; ResultNonCompliantPolicy = 3 }
        }

        $raw = [IO.File]::ReadAllText($scriptPath)
        $tokens = $null
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens,
            [ref]$errors)
    }

    Context 'Help & Metadata' {
        It 'Declares all five NOTES fields with v2.0.0 values' {
            $raw | Should -Match '(?m)File Name\s*:\s*Get-AzurePolicyComplianceReport\.ps1'
            $raw | Should -Match '(?m)Author\s*:\s*\S+'
            $raw | Should -Match '(?m)Prerequisite\s*:\s*PowerShell 7\.0'
            $raw | Should -Match '(?m)Version\s*:\s*2\.0\.0'
            $raw | Should -Match '(?m)Date\s*:\s*2026-09-16'
        }

        It 'Has one PARAMETER entry per declared parameter' {
            foreach ($name in @('SubscriptionId', 'PolicyAssignmentId', 'ResourceGroupName', 'TriggerScan',
                    'OutputFormat', 'OutputPath')) {
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

        It 'Cites Microsoft Learn and drives the documented PolicyInsights cmdlets' {
            $raw | Should -Match 'learn\.microsoft\.com/en-us/azure/governance/policy/how-to/get-compliance-data'
            $raw | Should -Match 'get-azpolicystate'
            $raw | Should -Match 'get-azpolicystatesummary'
            $raw | Should -Match 'start-azpolicycompliancescan'
            $raw | Should -Match 'Get-AzPolicyStateSummary'
            $raw | Should -Match 'Get-AzPolicyState\s'
        }

        It 'Is read-only: no Azure resource is created, changed or removed' {
            ($raw -match 'New-AzResource') | Should -BeFalse
            ($raw -match 'Set-AzContext') | Should -BeFalse
            ($raw -match 'Remove-AzResource') | Should -BeFalse
            ($raw -match 'Start-AzPolicyRemediation') | Should -BeFalse
        }
    }

    Context 'Behavior' {
        It 'Rolls up compliance per assignment and per initiative and lists the non-compliant resources' {
            $SubscriptionId = '*'
            $PolicyAssignmentId = ''
            $ResourceGroupName = '*'
            $TriggerScan = $false
            $OutputFormat = 'Table'

            $out = Main *>&1
            $text = $out | Out-String

            $text | Should -Match '\[\+\] Connected to: sub-prod'
            $text | Should -Match '\[\+\] Policy state records read: 3'
            $text | Should -Match '\[\+\] Assignments with state records: 2'
            $text | Should -Match '\[\+\] Initiatives with state records: 1'
            $text | Should -Match '\[\+\] Service summary non-compliant resources: 2, non-compliant policies: 3'
            ([regex]::Matches($text, 'compliant=1 non-compliant=1 other=0')).Count | Should -Be 2
            $text | Should -Match 'vm-app-2'
            $text | Should -Match 'stg-db-1'
            $text | Should -Match 'older than the documented 24-hour automatic evaluation cycle'
            $text | Should -Not -Match 'deny-public-ip.*has no timestamped evaluation record'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 2
            Should -Invoke Get-AzPolicyState -Times 1 -Exactly
            Should -Invoke Get-AzPolicyStateSummary -Times 1 -Exactly
        }

        It 'Returns 0 and prints no warnings when every resource is compliant and recently evaluated' {
            Mock Get-AzPolicyState {
                @(
                    [pscustomobject]@{
                        ResourceId = '/subscriptions/sub-1/resourceGroups/rg-app/providers/Microsoft.Compute' +
                            '/virtualMachines/vm-app-1'
                        PolicyAssignmentId = '/subscriptions/sub-1/providers/Microsoft.Authorization' +
                            '/policyAssignments/audit-tags'
                        PolicySetDefinitionId = ''
                        ComplianceState = 'Compliant'
                        PolicyDefinitionAction = 'audit'
                        Timestamp = (Get-Date).ToUniversalTime().AddHours(-1)
                    }
                )
            }
            Mock Get-AzPolicyStateSummary {
                [pscustomobject]@{ ResultNonCompliantResource = 0; ResultNonCompliantPolicy = 0 }
            }

            $SubscriptionId = '*'
            $PolicyAssignmentId = ''
            $ResourceGroupName = '*'
            $TriggerScan = $false
            $OutputFormat = 'Table'

            $out = Main *>&1
            $text = $out | Out-String

            $text | Should -Match '\[\+\] Policy state records read: 1'
            $text | Should -Match '\[\+\] Compliant: no non-compliant resources were reported'
            $text | Should -Not -Match '\[!\]'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
        }

        It 'Sends the PolicyAssignmentId filter and the resource group to the policy state cmdlets' {
            $SubscriptionId = 'sub-1'
            $PolicyAssignmentId = '/subscriptions/sub-1/providers/Microsoft.Authorization/policyAssignments' +
                '/audit-tags'
            $ResourceGroupName = 'rg-db'
            $TriggerScan = $false
            $OutputFormat = 'Table'

            $out = Main *>&1

            Should -Invoke Get-AzPolicyState -Times 1 -Exactly `
                -ParameterFilter { $PesterBoundParameters.Filter -like "*policyAssignments/audit-tags*" }
            Should -Invoke Get-AzPolicyState -Times 1 -Exactly `
                -ParameterFilter { $PesterBoundParameters.ResourceGroupName -eq 'rg-db' }
            Should -Invoke Get-AzPolicyState -Times 1 -Exactly `
                -ParameterFilter { $PesterBoundParameters.SubscriptionId -contains 'sub-1' }
            Should -Invoke Get-AzPolicyStateSummary -Times 1 -Exactly `
                -ParameterFilter { $PesterBoundParameters.ResourceGroupName -eq 'rg-db' }
            Should -Invoke Get-AzSubscription -Times 0 -Exactly -Because 'the subscription was named'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 2
        }

        It 'Triggers an on-demand compliance scan when -TriggerScan is set' {
            $SubscriptionId = '*'
            $PolicyAssignmentId = ''
            $ResourceGroupName = '*'
            $TriggerScan = $true
            $OutputFormat = 'Table'

            $out = Main *>&1
            $text = $out | Out-String

            $text | Should -Match "\[\*\] Starting on-demand compliance scan for 'sub-prod'"
            Should -Invoke Start-AzPolicyComplianceScan -Times 1 -Exactly `
                -ParameterFilter { $PesterBoundParameters.SubscriptionId -eq 'sub-1' }
            Should -Invoke Start-AzPolicyComplianceScan -Times 1 -Exactly `
                -ParameterFilter { $PesterBoundParameters.ContainsKey('ResourceGroupName') -eq $false }
            ($out | Where-Object { $_ -is [int] }) | Should -Be 2
        }

        It 'Writes a JSON report under -OutputPath and leaves the working directory untouched' {
            $SubscriptionId = '*'
            $PolicyAssignmentId = ''
            $ResourceGroupName = '*'
            $TriggerScan = $false
            $OutputFormat = 'Json'
            $OutputPath = $TestDrive

            $out = Main *>&1
            $text = $out | Out-String

            $text | Should -Match '\[\+\] Report written to:'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 2

            $reports = @(Get-ChildItem -Path $TestDrive -Filter 'AzurePolicyCompliance-*.json')
            $reports.Count | Should -Be 1
            $json = @(Get-Content -LiteralPath $reports[0].FullName -Raw | ConvertFrom-Json)
            @($json | Where-Object { $_.Category -eq 'NonCompliantResource' }).Count | Should -Be 2
            @($json | Where-Object { $_.Category -eq 'Initiative' }).Count | Should -Be 1

            (Get-Location).Path | Should -Be $workingDirectory
        }

        It 'Returns 1 with [-] output when the policy states cannot be read' {
            Mock Get-AzPolicyState { throw 'PolicyInsights is unavailable' }

            $SubscriptionId = '*'
            $PolicyAssignmentId = ''
            $ResourceGroupName = '*'
            $TriggerScan = $false
            $OutputFormat = 'Table'

            $out = Main *>&1
            $text = $out | Out-String

            $text | Should -Match '\[-\] Error: PolicyInsights is unavailable'
            $text | Should -Not -Match '\[\+\] Compliant'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
        }

        It 'Returns 1 with [-] output when not connected to Azure' {
            Mock Get-AzContext { $null }

            $SubscriptionId = '*'
            $PolicyAssignmentId = ''
            $ResourceGroupName = '*'
            $TriggerScan = $false
            $OutputFormat = 'Table'

            $out = Main *>&1
            $text = $out | Out-String

            $text | Should -Match '\[-\] Error: Not connected to Azure'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
        }
    }
}
