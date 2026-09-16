<#
.SYNOPSIS
    Reports Azure Policy compliance per assignment and per initiative, and lists non-compliant resources.

.DESCRIPTION
    Read-only Azure Policy compliance report for one subscription or for every subscription the signed-in
    account can read. The report is built from the Microsoft.PolicyInsights policy state records:

    - Get-AzPolicyState supplies the latest policy state record of every evaluated resource. Those records
      are rolled up here into compliant and non-compliant counts per policy assignment and per initiative
      (policy set definition), and into the list of non-compliant resource IDs:
      https://learn.microsoft.com/en-us/powershell/module/az.policyinsights/get-azpolicystate . The
      compliance states and the scope semantics are documented at
      https://learn.microsoft.com/en-us/azure/governance/policy/how-to/get-compliance-data . The -All
      switch is deliberately not used: it requests every state transition instead of the latest state.
    - Get-AzPolicyStateSummary supplies the service-side non-compliant totals for the same scope and is
      printed as a cross-check:
      https://learn.microsoft.com/en-us/powershell/module/az.policyinsights/get-azpolicystatesummary

    Azure Policy reevaluates each assignment automatically once every 24 hours (the standard compliance
    evaluation cycle documented on the get-compliance-data page), so every assignment whose newest state
    record is older than that cycle is reported with a [!] warning.

    With -TriggerScan the script also starts an on-demand evaluation through Start-AzPolicyComplianceScan
    (https://learn.microsoft.com/en-us/powershell/module/az.policyinsights/start-azpolicycompliancescan).
    That scan is asynchronous, so it returns immediately and the report still reflects the states that were
    recorded before the scan started.

    The script never mutates Azure resources; the only side effect is the report file written for
    -OutputFormat Json or Csv. Re-running it against an unchanged environment reports the same counts and
    the same exit code. Exit codes: 0 = compliant (no non-compliant resources), 2 = non-compliant resources
    were found, 1 = error (missing Az module, not signed in, unsafe -OutputPath, or the subscription could
    not be read).

.PARAMETER SubscriptionId
    Subscription ID to report on, or '*' to report on every subscription the signed-in account can read.
    Default: '*'.

.PARAMETER PolicyAssignmentId
    Optional policy assignment resource ID used to filter the report, for example
    '/subscriptions/<subscriptionId>/providers/Microsoft.Authorization/policyAssignments/<assignmentName>'.
    The value is sent as the 'PolicyAssignmentId eq ...' OData filter that the get-compliance-data page
    documents. Default: empty (every assignment).

.PARAMETER ResourceGroupName
    Resource group name used to filter the policy states and the compliance summary. Use '*' to include
    every resource group. Default: '*'.

.PARAMETER TriggerScan
    Starts an on-demand compliance evaluation with Start-AzPolicyComplianceScan before the report is built.
    The scan is asynchronous, so the report still reflects the previously recorded policy states.

.PARAMETER OutputFormat
    Report format: 'Table' prints the report to the console only, while 'Json' and 'Csv' also write a
    report file under -OutputPath. Default: 'Table'.

.PARAMETER OutputPath
    Local directory that receives the JSON/CSV report file. Must be a local path without '..' traversal.
    Default: MyDocuments\Reports.

.EXAMPLE
    PS C:\> .\Get-AzurePolicyComplianceReport.ps1
    Reports the compliance rollup of every readable subscription, prints the non-compliant resource IDs and
    the assignments that have not been evaluated for more than 24 hours, and exits 2 when any non-compliant
    resource is present.

.EXAMPLE
    PS C:\> .\Get-AzurePolicyComplianceReport.ps1 -SubscriptionId "00000000-0000-0000-0000-000000000001"
        -ResourceGroupName "rg-production" -OutputFormat Json -OutputPath C:\Reports
    Writes a timestamped JSON report for the resource group and exits with the documented compliance code.

.EXAMPLE
    PS C:\> .\Get-AzurePolicyComplianceReport.ps1 -PolicyAssignmentId $assignmentId -TriggerScan
    Starts an on-demand evaluation scan and reports the compliance rollup of that single assignment.
    Populate $assignmentId from Get-AzPolicyAssignment, for example
    "/subscriptions/<subscriptionId>/providers/Microsoft.Authorization/policyAssignments/deny-public-ip".

.NOTES
    File Name   : Get-AzurePolicyComplianceReport.ps1
    Author      : Bug-Free Umbrella
    Prerequisite: PowerShell 7.0
    Version     : 2.0.0
    Date        : 2026-09-16

    Policy state records carry an ISO 8601 Timestamp property, which is compared against the 24-hour cycle
    in UTC. Get-AzPolicyStateSummary returns the ISummary model
    (https://learn.microsoft.com/en-us/dotnet/api/microsoft.azure.powershell.cmdlets.policyinsights.models.isummary),
    which reports the non-compliant totals as ResultNonCompliantResource and ResultNonCompliantPolicy; the
    script also accepts the older NonCompliantResources and NonCompliantPolicies property names.
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
    Justification = 'The script spec mandates Write-Host status output with [+]/[!]/[-]/[*] prefixes.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '',
    Justification = 'Script parameters are consumed by Main through the caller scope; see the help.')]
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$SubscriptionId = '*',

    [Parameter(Mandatory = $false)]
    [string]$PolicyAssignmentId = '',

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$ResourceGroupName = '*',

    [Parameter(Mandatory = $false)]
    [switch]$TriggerScan,

    [Parameter(Mandatory = $false)]
    [ValidateSet('Table', 'Json', 'Csv')]
    [string]$OutputFormat = 'Table',

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$OutputPath = (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Reports')
)

$ErrorActionPreference = 'Stop'

function Get-ObjectProperty {
    <#
    .SYNOPSIS
        Reads a property of a policy state or summary object, returning a default when it is absent.
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

function Get-NumericProperty {
    <#
    .SYNOPSIS
        Reads the first present property of a summary object and converts it to an integer.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)][AllowNull()][object]$InputObject,
        [Parameter(Mandatory = $true)][string[]]$Name
    )

    foreach ($candidate in $Name) {
        $value = Get-ObjectProperty -InputObject $InputObject -Name $candidate -Default $null
        if ($null -eq $value) { continue }
        $parsed = 0
        if ([int]::TryParse([string]$value, [ref]$parsed)) { return $parsed }
    }
    return 0
}

function Get-EvaluationTimestamp {
    <#
    .SYNOPSIS
        Converts the Timestamp property of a policy state record to a UTC datetime, or returns $null.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)][AllowNull()][object]$InputObject
    )

    $value = Get-ObjectProperty -InputObject $InputObject -Name 'Timestamp' -Default $null
    if ($null -eq $value) { return $null }
    if ($value -is [datetime]) { return $value.ToUniversalTime() }

    $parsed = [datetime]::MinValue
    $styles = [Globalization.DateTimeStyles]::AdjustToUniversal
    if ([datetime]::TryParse([string]$value, [Globalization.CultureInfo]::InvariantCulture, $styles,
            [ref]$parsed)) {
        return $parsed
    }
    return $null
}

function Add-StateToRollup {
    <#
    .SYNOPSIS
        Adds one policy state record to a compliance rollup keyed by assignment or initiative ID.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][hashtable]$Rollup,
        [Parameter(Mandatory = $true)][string]$Key,
        [Parameter(Mandatory = $true)][string]$ComplianceState,
        [Parameter(Mandatory = $false)][AllowNull()][object]$Timestamp
    )

    if (-not $Rollup.ContainsKey($Key)) {
        $Rollup[$Key] = [pscustomobject]@{
            Key = $Key; Compliant = 0; NonCompliant = 0; Other = 0; Latest = $Timestamp
        }
    }

    $entry = $Rollup[$Key]
    if ($ComplianceState -eq 'Compliant') {
        $entry.Compliant = $entry.Compliant + 1
    }
    elseif ($ComplianceState -eq 'NonCompliant') {
        $entry.NonCompliant = $entry.NonCompliant + 1
    }
    else {
        $entry.Other = $entry.Other + 1
    }

    if ($null -ne $Timestamp -and ($null -eq $entry.Latest -or $Timestamp -gt $entry.Latest)) {
        $entry.Latest = $Timestamp
    }
}

function Main {
    <#
    .SYNOPSIS
        Builds the Azure Policy compliance report and returns the documented exit code.
    #>
    [CmdletBinding()]
    param()

    try {
        if ([string]::IsNullOrWhiteSpace($OutputPath) -or
            $OutputPath -match '(^|[\\/])\.\.([\\/]|$)' -or
            $OutputPath -match '^(\\\\|//)') {
            throw "Unsafe OutputPath: '$OutputPath'. Use a local path without '..' traversal."
        }
        $resolvedOutputPath = [System.IO.Path]::GetFullPath($OutputPath)

        Write-Host "[*] Checking Azure connection..." -ForegroundColor Cyan
        Import-Module Az.Accounts -ErrorAction Stop
        Import-Module Az.PolicyInsights -ErrorAction Stop
        $context = Get-AzContext -ErrorAction Stop
        if (-not $context) {
            throw "Not connected to Azure. Run: Connect-AzAccount"
        }
        Write-Host "[+] Connected to: $($context.Subscription.Name)" -ForegroundColor Green

        if ($SubscriptionId -eq '*') {
            $subscriptions = @(Get-AzSubscription -ErrorAction Stop)
        }
        else {
            $subscriptions = @([pscustomobject]@{ Id = $SubscriptionId; Name = $SubscriptionId })
        }
        if ($subscriptions.Count -eq 0) {
            throw "No readable subscriptions found for '$SubscriptionId'."
        }

        $assignmentRollup = @{}
        $initiativeRollup = @{}
        $nonCompliantResources = @{}
        $summaryNonCompliantResources = 0
        $summaryNonCompliantPolicies = 0
        $stateCount = 0
        $nonCompliantCount = 0

        foreach ($subscription in $subscriptions) {
            Write-Host "[*] Analysing subscription: $($subscription.Name)" -ForegroundColor Cyan

            if ($TriggerScan) {
                if ($ResourceGroupName -ne '*') {
                    $scanScope = "resource group '$ResourceGroupName'"
                }
                else {
                    $scanScope = "'$($subscription.Name)'"
                }
                Write-Host "[*] Starting on-demand compliance scan for $scanScope (asynchronous)..." `
                    -ForegroundColor Cyan

                if ($ResourceGroupName -ne '*') {
                    Start-AzPolicyComplianceScan -ResourceGroupName $ResourceGroupName -NoWait `
                        -ErrorAction Stop | Out-Null
                }
                else {
                    Start-AzPolicyComplianceScan -SubscriptionId $subscription.Id -NoWait `
                        -ErrorAction Stop | Out-Null
                }
            }

            $stateArguments = @{ SubscriptionId = $subscription.Id; ErrorAction = 'Stop' }
            if ($ResourceGroupName -ne '*') {
                $stateArguments['ResourceGroupName'] = $ResourceGroupName
            }
            if ($PolicyAssignmentId) {
                $stateArguments['Filter'] = "PolicyAssignmentId eq '$PolicyAssignmentId'"
            }
            $states = @(Get-AzPolicyState @stateArguments)

            $summaryArguments = @{ SubscriptionId = $subscription.Id; ErrorAction = 'Stop' }
            if ($ResourceGroupName -ne '*') {
                $summaryArguments['ResourceGroupName'] = $ResourceGroupName
            }
            $summary = Get-AzPolicyStateSummary @summaryArguments
            if ($summary -is [array]) { $summary = $summary[0] }
            $summaryNonCompliantResources += Get-NumericProperty -InputObject $summary `
                -Name @('ResultNonCompliantResource', 'NonCompliantResources')
            $summaryNonCompliantPolicies += Get-NumericProperty -InputObject $summary `
                -Name @('ResultNonCompliantPolicy', 'NonCompliantPolicies')

            foreach ($state in $states) {
                $stateCount = $stateCount + 1
                $assignmentId = [string](Get-ObjectProperty -InputObject $state `
                        -Name 'PolicyAssignmentId' -Default '(unassigned)')
                $initiativeId = [string](Get-ObjectProperty -InputObject $state `
                        -Name 'PolicySetDefinitionId' -Default '')
                $complianceState = [string](Get-ObjectProperty -InputObject $state `
                        -Name 'ComplianceState' -Default 'Unknown')
                $timestamp = Get-EvaluationTimestamp -InputObject $state

                Add-StateToRollup -Rollup $assignmentRollup -Key $assignmentId `
                    -ComplianceState $complianceState -Timestamp $timestamp
                if ($initiativeId) {
                    Add-StateToRollup -Rollup $initiativeRollup -Key $initiativeId `
                        -ComplianceState $complianceState -Timestamp $timestamp
                }

                if ($complianceState -eq 'NonCompliant') {
                    $nonCompliantCount = $nonCompliantCount + 1
                    $resourceId = [string](Get-ObjectProperty -InputObject $state `
                            -Name 'ResourceId' -Default '')
                    if ($resourceId -and -not $nonCompliantResources.ContainsKey($resourceId)) {
                        $nonCompliantResources[$resourceId] = $true
                    }
                }
            }
        }

        Write-Host "[+] Policy state records read: $stateCount" -ForegroundColor Green
        Write-Host "[+] Assignments with state records: $($assignmentRollup.Count)" -ForegroundColor Green
        Write-Host "[+] Initiatives with state records: $($initiativeRollup.Count)" -ForegroundColor Green
        $summaryLine = "[+] Service summary non-compliant resources: $summaryNonCompliantResources" +
            ", non-compliant policies: $summaryNonCompliantPolicies"
        Write-Host $summaryLine -ForegroundColor Green

        if ($OutputFormat -eq 'Table') {
            Write-Host "[*] Compliance by policy assignment:" -ForegroundColor Cyan
            foreach ($entry in ($assignmentRollup.Values | Sort-Object -Property Key)) {
                $line = "    {0}  compliant={1} non-compliant={2} other={3}" -f `
                    $entry.Key, $entry.Compliant, $entry.NonCompliant, $entry.Other
                Write-Host $line
            }
            if ($initiativeRollup.Count -gt 0) {
                Write-Host "[*] Compliance by initiative:" -ForegroundColor Cyan
                foreach ($entry in ($initiativeRollup.Values | Sort-Object -Property Key)) {
                    $line = "    {0}  compliant={1} non-compliant={2} other={3}" -f `
                        $entry.Key, $entry.Compliant, $entry.NonCompliant, $entry.Other
                    Write-Host $line
                }
            }
        }

        if ($nonCompliantResources.Count -gt 0) {
            $line = "[!] $($nonCompliantResources.Count) non-compliant resource(s) found."
            Write-Host $line -ForegroundColor Yellow
            Write-Host "[*] Non-compliant resource IDs:" -ForegroundColor Cyan
            foreach ($resourceId in ($nonCompliantResources.Keys | Sort-Object)) {
                Write-Host "    $resourceId"
            }
        }

        $evaluationCutoff = [datetime]::UtcNow.AddHours(-24)
        foreach ($entry in ($assignmentRollup.Values | Sort-Object -Property Key)) {
            if ($null -eq $entry.Latest) {
                $line = "[!] Assignment '$($entry.Key)' has no timestamped evaluation record."
                Write-Host $line -ForegroundColor Yellow
            }
            elseif ($entry.Latest -lt $evaluationCutoff) {
                $stale = $entry.Latest.ToString('u')
                $line = "[!] Assignment '$($entry.Key)' was last evaluated at $stale UTC, older than" +
                    " the documented 24-hour automatic evaluation cycle."
                Write-Host $line -ForegroundColor Yellow
            }
        }

        $reportRows = @()
        foreach ($entry in ($assignmentRollup.Values | Sort-Object -Property Key)) {
            $reportRows += [pscustomobject]@{
                Category = 'Assignment'; Name = $entry.Key; Compliant = $entry.Compliant
                NonCompliant = $entry.NonCompliant; Other = $entry.Other
            }
        }
        foreach ($entry in ($initiativeRollup.Values | Sort-Object -Property Key)) {
            $reportRows += [pscustomobject]@{
                Category = 'Initiative'; Name = $entry.Key; Compliant = $entry.Compliant
                NonCompliant = $entry.NonCompliant; Other = $entry.Other
            }
        }
        foreach ($resourceId in ($nonCompliantResources.Keys | Sort-Object)) {
            $reportRows += [pscustomobject]@{
                Category = 'NonCompliantResource'; Name = $resourceId; Compliant = 0
                NonCompliant = 1; Other = 0
            }
        }

        if ($OutputFormat -ne 'Table') {
            if (-not (Test-Path -LiteralPath $resolvedOutputPath)) {
                New-Item -ItemType Directory -Path $resolvedOutputPath -Force | Out-Null
            }
            $stamp = (Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmss')
            if ($OutputFormat -eq 'Json') {
                $reportFile = Join-Path $resolvedOutputPath "AzurePolicyCompliance-$stamp.json"
                $reportRows | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $reportFile -Encoding UTF8
            }
            else {
                $reportFile = Join-Path $resolvedOutputPath "AzurePolicyCompliance-$stamp.csv"
                $reportRows | Export-Csv -LiteralPath $reportFile -NoTypeInformation
            }
            Write-Host "[+] Report written to: $reportFile" -ForegroundColor Green
        }

        if ($nonCompliantCount -gt 0 -or $summaryNonCompliantResources -gt 0) {
            $line = "[!] Non-compliant policy states: $nonCompliantCount ; service summary resources:" +
                " $summaryNonCompliantResources"
            Write-Host $line -ForegroundColor Yellow
            return 2
        }

        Write-Host "[+] Compliant: no non-compliant resources were reported for this scope." `
            -ForegroundColor Green
        return 0
    }
    catch {
        Write-Host "[-] Error: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
