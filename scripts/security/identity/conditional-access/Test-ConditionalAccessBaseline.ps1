<#
.SYNOPSIS
    Audits Microsoft Entra Conditional Access policies against baseline design guidance.

.DESCRIPTION
    Reads every Conditional Access policy in the tenant through the Microsoft Graph
    conditionalAccessPolicy API and compares the result with the documented baseline: the
    240-policy tenant limit that counts policies in every state (including report-only), the
    number of report-only policies, policies whose includeApplications collection is empty,
    All-resources policies that do not exclude the nominated emergency-access group, and
    policies that target no user or no application.
    Read-only: no policy is created, updated, or deleted, and re-running the script is safe.
    A report file is written only when -OutputPath is supplied.
    Exit codes: 0 = baseline passes, 2 = findings present, 1 = error (missing module, Microsoft
    Graph failure, or unsafe -OutputPath).
    Baseline guidance (Microsoft Learn):
    https://learn.microsoft.com/entra/identity/conditional-access/plan-conditional-access
    API family (Microsoft Learn):
    https://learn.microsoft.com/graph/api/conditionalaccessroot-list-policies

.PARAMETER TenantId
    Microsoft Entra tenant ID to sign in to. When omitted, the current Microsoft Graph session
    is reused and no sign-in is attempted.

.PARAMETER EmergencyAccessGroupId
    Object ID of the security group that holds the emergency access (break-glass) accounts. When
    supplied, All-resources policies that do not exclude this group are reported as findings.

.PARAMETER IncludeReportOnly
    Extends the policy-level findings to policies in report-only state. The 240-policy limit and
    the report-only counter always cover every policy state.

.PARAMETER OutputFormat
    Report format: Table (colored console summary, the default), Json, or Csv.

.PARAMETER OutputPath
    File to write the report to. When omitted, Json and Csv reports are written to the pipeline
    and Table output stays on the console.

.EXAMPLE
    PS C:\> .\Test-ConditionalAccessBaseline.ps1 -TenantId 'contoso.onmicrosoft.com'
    Audits every policy in the tenant with table output and exits 2 when findings exist.

.EXAMPLE
    PS C:\> $groupId = 'd1f2b0f6-11aa-4c33-9c8d-5a2f7e61c004'
    PS C:\> .\Test-ConditionalAccessBaseline.ps1 -EmergencyAccessGroupId $groupId -IncludeReportOnly
    Includes report-only policies in the findings and checks All-resources policies for the
    emergency access group exclusion.

.NOTES
    File Name   : Test-ConditionalAccessBaseline.ps1
    Author      : Bug-Free Umbrella
    Prerequisite: PowerShell 7.0
    Version     : 2.0.0
    Date        : 2026-09-16
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$TenantId,

    [Parameter()]
    [string]$EmergencyAccessGroupId,

    [Parameter()]
    [switch]$IncludeReportOnly,

    [Parameter()]
    [ValidateSet('Table', 'Json', 'Csv')]
    [string]$OutputFormat = 'Table',

    [Parameter()]
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'

# PSSA note: Write-Host is mandated for the colorized [+]/[!]/[-]/[*] console status prefixes
# (RELAUNCH-SPEC section 3); PSAvoidUsingWriteHost warnings are accepted by design.

$PolicyLimit = 240
$EnabledState = 'enabled'
$ReportOnlyState = 'enabledForReportingButNotEnforced'
$AllResourcesToken = 'All'
$GraphScopes = @('Policy.Read.All')
$PolicyUri = 'https://graph.microsoft.com/v1.0/identity/conditionalAccess/policies'

function Get-GraphProperty {
    [CmdletBinding()]
    param(
        [Parameter()]
        [object]$InputObject,

        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    if ($null -eq $InputObject) { return $null }
    if ($InputObject -is [System.Collections.IDictionary]) {
        if ($InputObject.Contains($Name)) { return $InputObject[$Name] }
        return $null
    }
    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Get-GraphCollection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Uri
    )

    $items = New-Object System.Collections.ArrayList
    $nextLink = $Uri
    while (-not [string]::IsNullOrWhiteSpace($nextLink)) {
        $response = Invoke-MgGraphRequest -Method GET -Uri $nextLink -ErrorAction Stop
        $page = Get-GraphProperty -InputObject $response -Name 'value'
        if ($page) {
            foreach ($item in $page) { [void]$items.Add($item) }
        }
        $nextLink = Get-GraphProperty -InputObject $response -Name '@odata.nextLink'
    }
    return $items.ToArray()
}

function Test-StringInCollection {
    [CmdletBinding()]
    param(
        [Parameter()]
        [object[]]$Collection,

        [Parameter(Mandatory = $true)]
        [string]$Value
    )

    if ($null -eq $Collection) { return $false }
    foreach ($entry in $Collection) {
        if ([string]$entry -eq $Value) { return $true }
    }
    return $false
}

function Main {
    try {
        Write-Host "[*] Auditing Microsoft Entra Conditional Access policies..." -ForegroundColor Cyan

        # Validate the report destination before any Microsoft Graph call is made.
        if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
            if ($OutputPath -match '(^|[\\/])\.\.([\\/]|$)' -or $OutputPath -match '^(\\\\|//)') {
                throw "Unsafe OutputPath: $OutputPath. Use a local path without '..' traversal."
            }
        }

        Import-Module Microsoft.Graph.Authentication -ErrorAction Stop

        if (-not [string]::IsNullOrWhiteSpace($TenantId)) {
            Write-Host "[*] Connecting to Microsoft Graph for tenant $TenantId..." -ForegroundColor Cyan
            Connect-MgGraph -TenantId $TenantId -Scopes $GraphScopes -NoWelcome -ErrorAction Stop
        }
        else {
            Write-Host "[*] Reusing the current Microsoft Graph session." -ForegroundColor Cyan
        }

        $policies = @(Get-GraphCollection -Uri $PolicyUri)
        $countMessage = "[*] Retrieved $($policies.Count) Conditional Access policies " +
            "(tenant limit $PolicyLimit)."
        Write-Host $countMessage -ForegroundColor Cyan

        $includeReportOnlyPolicy = $false
        if ($IncludeReportOnly) { $includeReportOnlyPolicy = $true }

        $emergencyGroupSupplied = -not [string]::IsNullOrWhiteSpace($EmergencyAccessGroupId)
        $emergencyGroupCheckSkipped = $false
        $enabledCount = 0
        $reportOnlyCount = 0
        $disabledCount = 0
        $evaluatedStates = 'enabled'
        if ($includeReportOnlyPolicy) { $evaluatedStates = 'enabled, report-only' }

        $findings = New-Object System.Collections.ArrayList

        if ($policies.Count -ge $PolicyLimit) {
            $limitDetail = "Tenant holds $($policies.Count) Conditional Access policies; the documented " +
                "limit is $PolicyLimit policies in any state."
            [void]$findings.Add([pscustomobject]@{
                    Code   = 'POLICY-LIMIT'
                    Policy = '<tenant>'
                    Detail = $limitDetail
                })
        }

        foreach ($policy in $policies) {
            $state = [string](Get-GraphProperty -InputObject $policy -Name 'state')
            $policyName = [string](Get-GraphProperty -InputObject $policy -Name 'displayName')

            if ($state -eq $EnabledState) { $enabledCount++ }
            elseif ($state -eq $ReportOnlyState) { $reportOnlyCount++ }
            else { $disabledCount++ }

            $evaluate = $false
            if ($state -eq $EnabledState) { $evaluate = $true }
            if ($includeReportOnlyPolicy -and $state -eq $ReportOnlyState) { $evaluate = $true }
            if (-not $evaluate) { continue }

            $conditions = Get-GraphProperty -InputObject $policy -Name 'conditions'
            $applications = Get-GraphProperty -InputObject $conditions -Name 'applications'
            $users = Get-GraphProperty -InputObject $conditions -Name 'users'

            $includeApplications = @(Get-GraphProperty -InputObject $applications -Name 'includeApplications')
            $excludeGroups = @(Get-GraphProperty -InputObject $users -Name 'excludeGroups')
            $includeUsers = @(Get-GraphProperty -InputObject $users -Name 'includeUsers')
            $includeGroups = @(Get-GraphProperty -InputObject $users -Name 'includeGroups')
            $includeRoles = @(Get-GraphProperty -InputObject $users -Name 'includeRoles')

            if ($includeApplications.Count -eq 0) {
                [void]$findings.Add([pscustomobject]@{
                        Code   = 'EMPTY-APP-INCLUDE'
                        Policy = $policyName
                        Detail = 'includeApplications is empty: the policy protects no application.'
                    })
            }
            elseif (Test-StringInCollection -Collection $includeApplications -Value $AllResourcesToken) {
                if ($emergencyGroupSupplied) {
                    $excluded = Test-StringInCollection -Collection $excludeGroups -Value $EmergencyAccessGroupId
                    if (-not $excluded) {
                        $groupDetail = 'Policy covers All resources but does not exclude ' +
                            "emergency access group $EmergencyAccessGroupId."
                        [void]$findings.Add([pscustomobject]@{
                                Code   = 'ALL-APPS-NO-BREAKGLASS'
                                Policy = $policyName
                                Detail = $groupDetail
                            })
                    }
                }
                else {
                    $emergencyGroupCheckSkipped = $true
                }
            }

            if (($includeUsers.Count + $includeGroups.Count + $includeRoles.Count) -eq 0) {
                [void]$findings.Add([pscustomobject]@{
                        Code   = 'EMPTY-USER-INCLUDE'
                        Policy = $policyName
                        Detail = 'No includeUsers, includeGroups, or includeRoles: no user is targeted.'
                    })
            }
        }

        $findingArray = $findings.ToArray()
        $stateMessage = "[*] Enabled: $enabledCount | Report-only: $reportOnlyCount | " +
            "Disabled: $disabledCount"
        Write-Host $stateMessage -ForegroundColor Cyan

        if ($emergencyGroupCheckSkipped) {
            $skipMessage = '[!] -EmergencyAccessGroupId not supplied: the All-resources ' +
                'emergency access exclusion check was skipped.'
            Write-Host $skipMessage -ForegroundColor Yellow
        }

        foreach ($finding in $findingArray) {
            Write-Host "[!] $($finding.Code): $($finding.Policy) - $($finding.Detail)" -ForegroundColor Yellow
        }

        $summary = [ordered]@{
            TenantId               = $TenantId
            GeneratedAtUtc         = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
            PolicyCount            = $policies.Count
            PolicyLimit            = $PolicyLimit
            EnabledCount           = $enabledCount
            ReportOnlyCount        = $reportOnlyCount
            DisabledCount          = $disabledCount
            EvaluatedStates        = $evaluatedStates
            EmergencyAccessGroupId = $EmergencyAccessGroupId
            FindingCount           = $findingArray.Count
            Findings               = $findingArray
        }

        $reportText = ''
        if ($OutputFormat -eq 'Json') {
            $reportText = $summary | ConvertTo-Json -Depth 6
        }
        elseif ($OutputFormat -eq 'Csv') {
            $reportText = (($findingArray | ConvertTo-Csv -NoTypeInformation) -join "`r`n")
        }
        elseif (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
            $tableText = $findingArray | Format-Table -AutoSize | Out-String -Width 200
            $reportText = $tableText.TrimEnd()
        }

        if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
            Set-Content -LiteralPath $OutputPath -Value $reportText -Encoding UTF8 -ErrorAction Stop
            Write-Host "[+] Report written to $OutputPath" -ForegroundColor Green
        }
        elseif ($OutputFormat -ne 'Table') {
            Write-Output $reportText
        }

        if ($findingArray.Count -gt 0) {
            $findingMessage = "[!] Conditional Access baseline findings: $($findingArray.Count)."
            Write-Host $findingMessage -ForegroundColor Yellow
            return 2
        }

        Write-Host "[+] Conditional Access baseline passed." -ForegroundColor Green
        return 0
    }
    catch {
        Write-Host "[-] Error: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
