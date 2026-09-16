#Requires -Modules Pester
<#
.SYNOPSIS
    Pester tests for scripts/cloud/azure/governance/policy/Start-AzurePolicyRemediation.ps1.
.DESCRIPTION
    Validates help and metadata conformance, static syntax rules, and observable behavior of the Azure
    Policy remediation task starter using fully mocked Az.PolicyInsights cmdlets, so no Azure call ever
    leaves the machine. Runs offline on Linux pwsh; no network, Azure connectivity, or installed Az modules
    required.
.EXAMPLE
    PS C:\> Invoke-Pester -Path ./Tests/cloud/azure/governance/policy/Start-AzurePolicyRemediation.Tests.ps1
    Runs this test file.
.EXAMPLE
    PS C:\> Invoke-Pester -Path ./Tests/cloud/azure/governance/policy -Output Detailed
    Runs the tests of this directory with per-test output.
.NOTES
    File Name   : Start-AzurePolicyRemediation.Tests.ps1
    Author      : Bug-Free Umbrella
    Prerequisite: PowerShell 7.0
    Version     : 2.0.0
    Date        : 2026-09-16
#>

Describe 'Start-AzurePolicyRemediation' {
    BeforeAll {
        $scriptPath = Join-Path $PSScriptRoot `
            '../../../../../scripts/cloud/azure/governance/policy/Start-AzurePolicyRemediation.ps1'

        $workingDirectory = (Get-Location).Path
        $assignmentId = '/subscriptions/sub-1/providers/Microsoft.Authorization/policyAssignments' +
            '/deploy-diag'

        # Safe: the script's top-level guard skips Main when dot-sourced. The mandatory
        # -PolicyAssignmentId is bound during dot-sourcing so binding never prompts; the behavioral
        # tests override it in scope.
        . $scriptPath -PolicyAssignmentId $assignmentId

        # Az.PolicyInsights is not installed offline: declare every external cmdlet the script calls as an
        # advanced function with the real parameter set, so an unsupported parameter fails this test
        # instead of passing silently. The parameter sets match the Microsoft Learn references.
        function Get-AzContext {
            [CmdletBinding()]
            param()
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
        function Start-AzPolicyRemediation {
            [CmdletBinding(SupportsShouldProcess)]
            param(
                [Parameter(Mandatory = $true)][string]$Name,
                [Parameter(Mandatory = $true)][string]$PolicyAssignmentId,
                [Parameter(Mandatory = $false)][string]$SubscriptionId,
                [Parameter(Mandatory = $false)][single]$FailureThresholdPercentage,
                [Parameter(Mandatory = $false)][int]$ParallelDeployment,
                [Parameter(Mandatory = $false)][int]$ResourceCount,
                [Parameter(Mandatory = $false)][string[]]$FilterLocation,
                [Parameter(Mandatory = $false)][string]$ResourceDiscoveryMode,
                [Parameter(Mandatory = $false)][switch]$NoWait,
                [Parameter(Mandatory = $false)][switch]$AsJob
            )
        }

        Mock Import-Module { }
        Mock Get-AzContext { [pscustomobject]@{ Subscription = [pscustomobject]@{ Name = 'sub-prod' } } }
        Mock Start-AzPolicyRemediation { [pscustomobject]@{ Name = $Name } }

        # Default fixture: one compliant resource plus one resource that is non-compliant to a
        # deployIfNotExists policy, so a remediation task is outstanding.
        Mock Get-AzPolicyState {
            @(
                [pscustomobject]@{
                    ResourceId = '/subscriptions/sub-1/resourceGroups/rg-app/providers/Microsoft.Compute' +
                        '/virtualMachines/vm-app-1'
                    PolicyAssignmentId = $assignmentId
                    ComplianceState = 'Compliant'
                    PolicyDefinitionAction = 'deployIfNotExists'
                    Timestamp = (Get-Date).ToUniversalTime().AddHours(-1)
                }
                [pscustomobject]@{
                    ResourceId = '/subscriptions/sub-1/resourceGroups/rg-app/providers/Microsoft.Compute' +
                        '/virtualMachines/vm-app-2'
                    PolicyAssignmentId = $assignmentId
                    ComplianceState = 'NonCompliant'
                    PolicyDefinitionAction = 'deployIfNotExists'
                    Timestamp = (Get-Date).ToUniversalTime().AddHours(-1)
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
            $raw | Should -Match '(?m)File Name\s*:\s*Start-AzurePolicyRemediation\.ps1'
            $raw | Should -Match '(?m)Author\s*:\s*\S+'
            $raw | Should -Match '(?m)Prerequisite\s*:\s*PowerShell 7\.0'
            $raw | Should -Match '(?m)Version\s*:\s*2\.0\.0'
            $raw | Should -Match '(?m)Date\s*:\s*2026-09-16'
        }

        It 'Has one PARAMETER entry per declared parameter' {
            foreach ($name in @('PolicyAssignmentId', 'SubscriptionId', 'ResourceCount',
                    'ParallelDeploymentCount', 'FailureThresholdPercentage')) {
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

        It 'Cites Microsoft Learn and gates the mutation behind ShouldProcess' {
            $raw | Should -Match 'learn\.microsoft\.com/en-us/azure/governance/policy/how-to/' +
                'remediate-resources'
            $raw | Should -Match 'learn\.microsoft\.com/en-us/powershell/module/az\.policyinsights/' +
                'start-azpolicyremediation'
            $raw | Should -Match '\[CmdletBinding\(SupportsShouldProcess\)\]'
            $raw | Should -Match '\$PSCmdlet\.ShouldProcess\('
            $raw | Should -Match 'Start-AzPolicyRemediation'
        }

        It 'Scopes the documented remediation settings to the documented ranges' {
            $raw | Should -Match '\[ValidateRange\(1, 50000\)\]'
            $raw | Should -Match '\[ValidateRange\(1, 30\)\]'
            $raw | Should -Match '\[ValidateRange\(0, 100\)\]'
        }
    }

    Context 'Behavior' {
        It 'Starts a remediation task for the non-compliant resources and returns 0' {
            $PolicyAssignmentId = $assignmentId
            $SubscriptionId = 'sub-1'
            $ResourceCount = 1234
            $ParallelDeploymentCount = 25
            $FailureThresholdPercentage = 25

            $out = Main *>&1
            $text = $out | Out-String

            $text | Should -Match '\[\+\] Policy state records for the assignment: 2'
            $text | Should -Match '\[\+\] Non-compliant resources: 1'
            $text | Should -Match "\[\*\] Starting remediation 'bfu-remediation-\d{8}-\d{6}' for 1"
            $text | Should -Match "\[\+\] Remediation 'bfu-remediation-\d{8}-\d{6}' started for 1"
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0

            Should -Invoke Get-AzPolicyState -Times 1 -Exactly `
                -ParameterFilter { $PesterBoundParameters.Filter -eq "PolicyAssignmentId eq '$assignmentId'" }
            Should -Invoke Start-AzPolicyRemediation -Times 1 -Exactly
            Should -Invoke Start-AzPolicyRemediation -Times 1 -Exactly `
                -ParameterFilter { $PesterBoundParameters.PolicyAssignmentId -eq $assignmentId }
            Should -Invoke Start-AzPolicyRemediation -Times 1 -Exactly `
                -ParameterFilter { $PesterBoundParameters.ResourceCount -eq 1234 }
            Should -Invoke Start-AzPolicyRemediation -Times 1 -Exactly `
                -ParameterFilter { $PesterBoundParameters.ParallelDeployment -eq 25 }
            Should -Invoke Start-AzPolicyRemediation -Times 1 -Exactly `
                -ParameterFilter { $PesterBoundParameters.FailureThresholdPercentage -eq 0.25 }
            Should -Invoke Start-AzPolicyRemediation -Times 1 -Exactly `
                -ParameterFilter { $PesterBoundParameters.Name -like 'bfu-remediation-*' }
        }

        It 'Reports Already compliant and creates no task when nothing is outstanding' {
            Mock Get-AzPolicyState {
                @(
                    [pscustomobject]@{
                        ResourceId = '/subscriptions/sub-1/resourceGroups/rg-app/providers/Microsoft.Compute' +
                            '/virtualMachines/vm-app-1'
                        PolicyAssignmentId = $assignmentId
                        ComplianceState = 'Compliant'
                        PolicyDefinitionAction = 'deployIfNotExists'
                        Timestamp = (Get-Date).ToUniversalTime().AddHours(-1)
                    }
                )
            }

            $PolicyAssignmentId = $assignmentId
            $SubscriptionId = ''
            $ResourceCount = 500
            $ParallelDeploymentCount = 10
            $FailureThresholdPercentage = 100

            $out = Main *>&1
            $text = $out | Out-String

            $text | Should -Match '\[\+\] Non-compliant resources: 0'
            $text | Should -Match "\[\+\] Already compliant: no non-compliant resources for '$assignmentId'"
            $text | Should -Not -Match '\[!\]'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            Should -Invoke Start-AzPolicyRemediation -Times 0 -Exactly
        }

        It 'Refuses an assignment whose effect is not deployIfNotExists or modify' {
            Mock Get-AzPolicyState {
                @(
                    [pscustomobject]@{
                        ResourceId = '/subscriptions/sub-1/resourceGroups/rg-db/providers/Microsoft.Storage' +
                            '/storageAccounts/stg-db-1'
                        PolicyAssignmentId = $assignmentId
                        ComplianceState = 'NonCompliant'
                        PolicyDefinitionAction = 'audit'
                        Timestamp = (Get-Date).ToUniversalTime().AddHours(-1)
                    }
                    [pscustomobject]@{
                        ResourceId = '/subscriptions/sub-1/resourceGroups/rg-db/providers/Microsoft.Storage' +
                            '/storageAccounts/stg-db-2'
                        PolicyAssignmentId = $assignmentId
                        ComplianceState = 'NonCompliant'
                        PolicyDefinitionAction = 'deny'
                        Timestamp = (Get-Date).ToUniversalTime().AddHours(-1)
                    }
                )
            }

            $PolicyAssignmentId = $assignmentId
            $SubscriptionId = ''
            $ResourceCount = 500
            $ParallelDeploymentCount = 10
            $FailureThresholdPercentage = 100

            $out = Main *>&1
            $text = $out | Out-String

            $text | Should -Match "\[!\] Assignment '$assignmentId' uses effect\(s\) audit, deny\."
            $text | Should -Match "only supported for 'deployIfNotExists' and 'modify'"
            ($out | Where-Object { $_ -is [int] }) | Should -Be 2
            Should -Invoke Start-AzPolicyRemediation -Times 0 -Exactly
        }

        It 'Creates nothing under -WhatIf and still returns 0' {
            $PolicyAssignmentId = $assignmentId
            $SubscriptionId = ''
            $ResourceCount = 500
            $ParallelDeploymentCount = 10
            $FailureThresholdPercentage = 100

            $out = Main -WhatIf *>&1
            $text = $out | Out-String

            $text | Should -Match '\[\*\] WhatIf: no remediation task was created\.'
            $text | Should -Not -Match '\[\+\] Remediation .* started'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            Should -Invoke Start-AzPolicyRemediation -Times 0 -Exactly
        }

        It 'Returns 1 with [-] output when the policy states cannot be read' {
            Mock Get-AzPolicyState { throw 'PolicyInsights is unavailable' }

            $PolicyAssignmentId = $assignmentId
            $SubscriptionId = ''
            $ResourceCount = 500
            $ParallelDeploymentCount = 10
            $FailureThresholdPercentage = 100

            $out = Main *>&1
            $text = $out | Out-String

            $text | Should -Match '\[-\] Error: PolicyInsights is unavailable'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
            Should -Invoke Start-AzPolicyRemediation -Times 0 -Exactly
        }

        It 'Returns 1 with [-] output when -PolicyAssignmentId is not a policy assignment resource ID' {
            $PolicyAssignmentId = 'deploy-diag'
            $SubscriptionId = ''
            $ResourceCount = 500
            $ParallelDeploymentCount = 10
            $FailureThresholdPercentage = 100

            $out = Main *>&1
            $text = $out | Out-String

            $text | Should -Match '\[-\] Error: PolicyAssignmentId ''deploy-diag'' is not a policy'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
            Should -Invoke Get-AzPolicyState -Times 0 -Exactly
            Should -Invoke Start-AzPolicyRemediation -Times 0 -Exactly
        }

        It 'Returns 1 with [-] output when not connected to Azure' {
            Mock Get-AzContext { $null }

            $PolicyAssignmentId = $assignmentId
            $SubscriptionId = ''
            $ResourceCount = 500
            $ParallelDeploymentCount = 10
            $FailureThresholdPercentage = 100

            $out = Main *>&1
            $text = $out | Out-String

            $text | Should -Match '\[-\] Error: Not connected to Azure'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
            Should -Invoke Start-AzPolicyRemediation -Times 0 -Exactly
        }
    }
}
