<#
.SYNOPSIS
    Starts an Azure Policy remediation task for a deployIfNotExists or modify policy assignment.

.DESCRIPTION
    Mutating script: it creates and starts an Azure Policy remediation task with Start-AzPolicyRemediation
    (https://learn.microsoft.com/en-us/powershell/module/az.policyinsights/start-azpolicyremediation) so
    that resources that are non-compliant to the given assignment are put into a compliant state. The
    remediation model, its managed identity requirements and the remediation task settings are documented
    at https://learn.microsoft.com/en-us/azure/governance/policy/how-to/remediate-resources .

    Remediation is only supported for the 'deployIfNotExists' and 'modify' effects. The script therefore
    reads the latest policy states of the assignment with Get-AzPolicyState
    (https://learn.microsoft.com/en-us/powershell/module/az.policyinsights/get-azpolicystate) - the
    compliance states are documented at
    https://learn.microsoft.com/en-us/azure/governance/policy/how-to/get-compliance-data - and refuses the
    run with a [!] line when any non-compliant resource was evaluated by another effect. The effect of each
    non-compliant record is read from its PolicyDefinitionAction property.

    The remediation task is created only after ShouldProcess approval, so -WhatIf and -Confirm behave as
    documented: -WhatIf creates nothing and still exits 0. The script is idempotent: when the assignment has
    no non-compliant resources it prints '[+] Already compliant: ...' and exits 0 without calling
    Start-AzPolicyRemediation.

    The -FailureThresholdPercentage, -ResourceCount and -ParallelDeploymentCount parameters map onto the
    cmdlet's -FailureThresholdPercentage (a value between 0.0 and 1.0), -ResourceCount (up to 50,000) and
    -ParallelDeployment (1 to 30 resources at a time) parameters.

    Exit codes: 0 = nothing outstanding, or the remediation task was started (or was suppressed by -WhatIf);
    2 = refused because the assignment's effect is not deployIfNotExists or modify; 1 = error (missing Az
    module, not signed in, malformed -PolicyAssignmentId, or the policy states could not be read).

.PARAMETER PolicyAssignmentId
    Resource ID of the policy assignment to remediate, for example
    '/subscriptions/<subscriptionId>/providers/Microsoft.Authorization/policyAssignments/<assignmentName>'.
    Mandatory; subscription, resource group and management group assignment scopes are accepted.

.PARAMETER SubscriptionId
    Subscription ID used for the policy state query and the remediation. Omit it to use the subscription of
    the current Az context. Default: empty.

.PARAMETER ResourceCount
    Maximum number of non-compliant resources the remediation task may remediate, from 1 to 50,000.
    Default: 500.

.PARAMETER ParallelDeploymentCount
    Number of resources that are remediated at the same time, from 1 to 30. Default: 10.

.PARAMETER FailureThresholdPercentage
    Failure threshold as a percentage from 0 to 100; the remediation fails when the percentage of failed
    deployments exceeds it. The value is divided by 100 before it is passed to the cmdlet, which expects a
    value between 0.0 and 1.0. Default: 100.

.EXAMPLE
    PS C:\> .\Start-AzurePolicyRemediation.ps1 -PolicyAssignmentId $assignmentId
    Starts a remediation task for the non-compliant resources of the assignment, using the documented
    defaults: 500 resources, 10 parallel deployments and a failure threshold of 100%.

.EXAMPLE
    PS C:\> .\Start-AzurePolicyRemediation.ps1 -PolicyAssignmentId $assignmentId -ResourceCount 10000 `
        -ParallelDeploymentCount 30 -FailureThresholdPercentage 25 -WhatIf
    Shows what would be remediated without creating a remediation task, and exits 0.

.EXAMPLE
    PS C:\> .\Start-AzurePolicyRemediation.ps1 -PolicyAssignmentId $assignmentId -Confirm:$false
    Starts the remediation task without an interactive confirmation prompt.

.NOTES
    File Name   : Start-AzurePolicyRemediation.ps1
    Author      : Bug-Free Umbrella
    Prerequisite: PowerShell 7.0
    Version     : 2.0.0
    Date        : 2026-09-16

    The cmdlet reference documents -ParallelDeployment as the parameter name and ParallelDeploymentCount as
    its alias; the remediate-resources page uses the alias form. The cmdlet also requires -Name, which this
    script generates as bfu-remediation-<yyyyMMdd-HHmmss> in UTC.
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
    Justification = 'The script spec mandates Write-Host status output with [+]/[!]/[-]/[*] prefixes.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '',
    Justification = 'Script parameters are consumed by Main through the caller scope; see the help.')]
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$PolicyAssignmentId,

    [Parameter(Mandatory = $false)]
    [string]$SubscriptionId = '',

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 50000)]
    [int]$ResourceCount = 500,

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 30)]
    [int]$ParallelDeploymentCount = 10,

    [Parameter(Mandatory = $false)]
    [ValidateRange(0, 100)]
    [int]$FailureThresholdPercentage = 100
)

$ErrorActionPreference = 'Stop'

$policyAssignmentIdPattern = '^/(subscriptions/[^/]+|subscriptions/[^/]+/resourceGroups/[^/]+|' +
    'providers/Microsoft\.Management/managementGroups/[^/]+)' +
    '/providers/Microsoft\.Authorization/policyAssignments/[^/]+$'

function Get-ObjectProperty {
    <#
    .SYNOPSIS
        Reads a property of a policy state or remediation object, returning a default when it is absent.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)][AllowNull()][object]$InputObject,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $false)][AllowNull()][object]$Default
    )

    if ($null -eq $InputObject) { return $Default }
    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $property) { return $Default }
    if ($null -eq $property.Value) { return $Default }
    return $property.Value
}

function Get-RemediationTarget {
    <#
    .SYNOPSIS
        Splits the policy states of an assignment into remediation targets and unsupported effects.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)][AllowNull()][object[]]$State
    )

    $supportedEffects = @('deployIfNotExists', 'modify')
    $targets = @()
    $unsupported = @{}
    $remediationEffect = ''

    foreach ($record in @($State)) {
        $complianceState = [string](Get-ObjectProperty -InputObject $record `
                -Name 'ComplianceState' -Default 'Unknown')
        if ($complianceState -ne 'NonCompliant') { continue }

        $effect = [string](Get-ObjectProperty -InputObject $record `
                -Name 'PolicyDefinitionAction' -Default 'unknown')
        if ($effect -notin $supportedEffects) {
            $unsupported[$effect] = $true
            continue
        }

        $targets += $record
        if (-not $remediationEffect) { $remediationEffect = $effect }
    }

    return [pscustomobject]@{
        Targets = $targets
        UnsupportedEffects = @($unsupported.Keys | Sort-Object)
        Effect = $remediationEffect
    }
}

function Main {
    <#
    .SYNOPSIS
        Starts the Azure Policy remediation task and returns the documented exit code.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param()

    try {
        $assignmentId = [string]$PolicyAssignmentId
        if ($assignmentId -notmatch $policyAssignmentIdPattern) {
            throw "PolicyAssignmentId '$assignmentId' is not a policy assignment resource ID."
        }

        Write-Host "[*] Checking Azure connection..." -ForegroundColor Cyan
        Import-Module Az.Accounts -ErrorAction Stop
        Import-Module Az.PolicyInsights -ErrorAction Stop
        $context = Get-AzContext -ErrorAction Stop
        if (-not $context) {
            throw "Not connected to Azure. Run: Connect-AzAccount"
        }
        Write-Host "[+] Connected to: $($context.Subscription.Name)" -ForegroundColor Green

        $stateArguments = @{ Filter = "PolicyAssignmentId eq '$assignmentId'"; ErrorAction = 'Stop' }
        if ($SubscriptionId) { $stateArguments['SubscriptionId'] = $SubscriptionId }
        $states = @(Get-AzPolicyState @stateArguments)

        $resolution = Get-RemediationTarget -State $states
        Write-Host "[+] Policy state records for the assignment: $($states.Count)" -ForegroundColor Green
        Write-Host "[+] Non-compliant resources: $($resolution.Targets.Count)" -ForegroundColor Green

        if ($resolution.Targets.Count -eq 0 -and $resolution.UnsupportedEffects.Count -eq 0) {
            $line = "[+] Already compliant: no non-compliant resources for '$assignmentId'."
            Write-Host $line -ForegroundColor Green
            return 0
        }

        if ($resolution.UnsupportedEffects.Count -gt 0) {
            $effects = $resolution.UnsupportedEffects -join ', '
            $line = "[!] Assignment '$assignmentId' uses effect(s) $effects. Remediation is only" +
                " supported for 'deployIfNotExists' and 'modify'."
            Write-Host $line -ForegroundColor Yellow
            return 2
        }

        $remediationName = 'bfu-remediation-' + (Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmss')
        $remediationArguments = @{
            Name                       = $remediationName
            PolicyAssignmentId         = $assignmentId
            ResourceCount              = $ResourceCount
            ParallelDeployment         = $ParallelDeploymentCount
            FailureThresholdPercentage = ([single]$FailureThresholdPercentage / 100)
            ErrorAction                = 'Stop'
        }
        if ($SubscriptionId) { $remediationArguments['SubscriptionId'] = $SubscriptionId }

        $action = "Start remediation task '$remediationName'"
        if ($PSCmdlet.ShouldProcess($assignmentId, $action)) {
            $line = "[*] Starting remediation '$remediationName' for $($resolution.Targets.Count)" +
                " non-compliant resource(s) using effect '$($resolution.Effect)'..."
            Write-Host $line -ForegroundColor Cyan

            $remediation = Start-AzPolicyRemediation @remediationArguments
            $startedName = [string](Get-ObjectProperty -InputObject $remediation -Name 'Name' `
                    -Default $remediationName)
            $line = "[+] Remediation '$startedName' started for $($resolution.Targets.Count)" +
                " non-compliant resource(s)."
            Write-Host $line -ForegroundColor Green
        }
        else {
            Write-Host "[*] WhatIf: no remediation task was created." -ForegroundColor Cyan
        }

        return 0
    }
    catch {
        Write-Host "[-] Error: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
