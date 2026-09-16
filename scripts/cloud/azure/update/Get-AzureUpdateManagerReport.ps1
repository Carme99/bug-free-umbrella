<#
.SYNOPSIS
    Reports Azure Update Manager compliance: assessments, pending patches, and maintenance schedules.

.DESCRIPTION
    Read-only Azure Update Manager compliance report for one subscription or every subscription the
    signed-in account can read. It combines the Azure Update Manager cmdlet surface with the Azure
    Resource Graph tables that Update Manager writes its results to:

    - machines (Azure VMs and Azure Arc-enabled servers) and their update assessment summaries come
      from the Resource Graph tables patchassessmentresources and resources, cross-checked against the
      maintenance configuration assignments recorded in maintenanceresources. The table layouts are
      documented at https://learn.microsoft.com/en-us/azure/update-manager/query-logs with ready-made
      queries at https://learn.microsoft.com/en-us/azure/update-manager/sample-query-logs ;
    - maintenance configurations are enumerated with Get-AzMaintenanceConfiguration
      (https://learn.microsoft.com/en-us/powershell/module/az.maintenance/get-azmaintenanceconfiguration).
      Per-resource assignments can also be listed with Get-AzConfigurationAssignment
      (https://learn.microsoft.com/en-us/powershell/module/az.maintenance/get-azconfigurationassignment),
      but that cmdlet is machine-scoped, so the report reads the Resource Graph assignment records
      instead of calling it once per machine.

    Azure Update Manager itself is described at
    https://learn.microsoft.com/en-us/azure/update-manager/overview . The "manage updates" material
    now lives at https://learn.microsoft.com/en-us/azure/update-manager/view-updates ; the former
    /azure/update-manager/manage-updates path returns HTTP 404.

    The report lists machines with no update assessment result, machines with pending critical or
    security updates, machines with no maintenance configuration assigned, and maintenance
    configurations with no machines assigned.

    The script is read-only: it never mutates Azure resources or triggers an assessment, so re-running
    it against an unchanged environment returns the same report and the same exit code. For
    -OutputFormat Json or Csv it writes one uniquely named report file under -OutputPath. Exit codes:
    0 = compliant (no findings); 2 = findings were detected; 1 = error (missing Az module, not signed
    in, unsafe -OutputPath, or the machine inventory could not be read for any subscription).

.PARAMETER SubscriptionId
    Subscription ID to report on, or '*' to report on every subscription the signed-in account can read.
    Default: '*'.

.PARAMETER ResourceGroupName
    Resource group name used to filter machines and maintenance configurations. Use '*' to include every
    resource group. Default: '*'.

.PARAMETER OutputFormat
    Report format: 'Table' prints the report to the console only, while 'Json' and 'Csv' also write a
    report file under -OutputPath. Default: 'Table'.

.PARAMETER OutputPath
    Local directory that receives the JSON/CSV report file. Must be a local path without '..' traversal.
    Default: MyDocuments\Reports.

.EXAMPLE
    PS C:\> .\Get-AzureUpdateManagerReport.ps1
    Reports update assessment coverage, pending critical/security updates, and maintenance configuration
    coverage for every readable subscription, printing the findings to the console.

.EXAMPLE
    PS C:\> .\Get-AzureUpdateManagerReport.ps1 -SubscriptionId "00000000-0000-0000-0000-000000000001" `
        -ResourceGroupName "rg-production" -OutputFormat Json -OutputPath C:\Reports
    Writes a timestamped JSON report for the machines and maintenance configurations of rg-production,
    and exits 2 when any compliance finding is present.

.NOTES
    File Name   : Get-AzureUpdateManagerReport.ps1
    Author      : Bug-Free Umbrella
    Prerequisite: PowerShell 7.0
    Version     : 2.0.0
    Date        : 2026-09-16

    Azure Resource Graph queries are issued through Search-AzGraph
    (https://learn.microsoft.com/en-us/powershell/module/az.resourcegraph/search-azgraph) and are paged
    with its skip token. Resource Graph keeps Update Manager assessment history for the last 7 days and
    installation history for the last 30 days, so "no assessment" means "no assessment result within the
    Resource Graph retention window".
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
    [ValidateNotNullOrEmpty()]
    [string]$ResourceGroupName = '*',

    [Parameter(Mandatory = $false)]
    [ValidateSet('Table', 'Json', 'Csv')]
    [string]$OutputFormat = 'Table',

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$OutputPath = (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Reports')
)

$ErrorActionPreference = 'Stop'

function Get-DynamicProperty {
    <#
    .SYNOPSIS
        Reads a property from a Resource Graph row, whether it is an object or a JSON string.
    #>
    param(
        [Parameter(Mandatory = $false)][AllowNull()][object]$InputObject,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $false)][AllowNull()][object]$Default
    )

    if ($null -eq $InputObject) { return $Default }
    $container = $InputObject
    if ($container -is [string]) {
        if ([string]::IsNullOrWhiteSpace($container)) { return $Default }
        $container = ConvertFrom-Json -InputObject $container
    }

    $value = $container.$Name
    if ($null -eq $value) { return $Default }
    return $value
}

function ConvertTo-IntOrDefault {
    <#
    .SYNOPSIS
        Converts a Resource Graph count to an integer, falling back to a default.
    #>
    param(
        [Parameter(Mandatory = $false)][AllowNull()][object]$Value,
        [Parameter(Mandatory = $false)][int]$Default = 0
    )

    if ($null -eq $Value) { return $Default }
    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text)) { return $Default }

    $parsed = 0
    if ([int]::TryParse($text, [ref]$parsed)) { return $parsed }
    return $Default
}

function Get-ResourceIdSegment {
    <#
    .SYNOPSIS
        Returns one segment value of an Azure resource ID, or an empty string.
    #>
    param(
        [Parameter(Mandatory = $false)][AllowNull()][string]$ResourceId,
        [Parameter(Mandatory = $true)][string]$Segment
    )

    if ([string]::IsNullOrWhiteSpace($ResourceId)) { return '' }
    $match = [regex]::Match($ResourceId, "/$Segment/([^/]+)", 'IgnoreCase')
    if ($match.Success) { return $match.Groups[1].Value }
    return ''
}

function Get-MachineResourceId {
    <#
    .SYNOPSIS
        Strips the assessment suffix from a patch assessment result ID to get the machine ID.
    #>
    param(
        [Parameter(Mandatory = $false)][AllowNull()][string]$AssessmentId
    )

    if ([string]::IsNullOrWhiteSpace($AssessmentId)) { return '' }
    $index = $AssessmentId.IndexOf('/patchAssessmentResults/', [System.StringComparison]::OrdinalIgnoreCase)
    if ($index -lt 0) { return $AssessmentId }
    return $AssessmentId.Substring(0, $index)
}

function Get-ResourceGraphRow {
    <#
    .SYNOPSIS
        Runs an Azure Resource Graph query and pages through the results with the skip token.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Query,
        [Parameter(Mandatory = $true)][string]$TargetSubscriptionId
    )

    $rows = @()
    $skipToken = ''
    do {
        $arguments = @{
            Query        = $Query
            Subscription = $TargetSubscriptionId
            First        = 1000
            ErrorAction  = 'Stop'
        }
        if ($skipToken) { $arguments['SkipToken'] = $skipToken }

        $page = @(Search-AzGraph @arguments)
        $rows += $page

        $skipToken = ''
        foreach ($item in $page) {
            if ($item.PSObject.Properties['SkipToken']) { $skipToken = [string]$item.SkipToken }
        }
    } while ($skipToken)

    return $rows
}

function Main {
    <#
    .SYNOPSIS
        Runs the Azure Update Manager compliance report and returns the documented exit code.
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
        Import-Module Az.ResourceGraph -ErrorAction Stop
        Import-Module Az.Maintenance -ErrorAction Stop
        $context = Get-AzContext -ErrorAction Stop
        if (-not $context) {
            throw "Not connected to Azure. Run: Connect-AzAccount"
        }
        Write-Host "[+] Connected to: $($context.Subscription.Name)" -ForegroundColor Green

        $subscriptions = if ($SubscriptionId -eq '*') {
            @(Get-AzSubscription -ErrorAction Stop)
        }
        else {
            @(Get-AzSubscription -SubscriptionId $SubscriptionId -ErrorAction Stop)
        }
        if ($subscriptions.Count -eq 0) {
            throw "No readable subscriptions found for '$SubscriptionId'."
        }

        $subscriptionNames = @{}
        foreach ($subscription in $subscriptions) {
            if ($subscription.Id) { $subscriptionNames[$subscription.Id.ToLowerInvariant()] = $subscription.Name }
        }

        $machineQuery = "resources | where type =~ 'microsoft.compute/virtualmachines' " +
            "or type =~ 'microsoft.hybridcompute/machines' " +
            "| project id, name, resourceGroup, subscriptionId"
        $assessmentQuery = "patchassessmentresources | where type !has 'softwarepatches' " +
            "| extend prop = parse_json(properties) " +
            "| project id, criticalCount = prop.availablePatchCountByClassification.critical, " +
            "securityCount = prop.availablePatchCountByClassification.security"
        $assignmentQuery = "maintenanceresources " +
            "| where type =~ 'microsoft.maintenance/configurationassignments' " +
            "| project id, resourceId = tostring(properties.resourceId), " +
            "maintenanceConfigurationId = tostring(properties.maintenanceConfigurationId)"

        $findings = @()
        $configurations = @()
        $usedConfigurationKeys = @{}
        $machineCount = 0
        $assessmentCount = 0
        $assignmentCount = 0
        $machineQueryFailures = 0

        foreach ($subscription in $subscriptions) {
            Write-Host "[*] Analysing subscription: $($subscription.Name)" -ForegroundColor Cyan
            Set-AzContext -SubscriptionId $subscription.Id -ErrorAction Stop | Out-Null

            try {
                if ($ResourceGroupName -eq '*') {
                    $configurations += @(Get-AzMaintenanceConfiguration -ErrorAction Stop)
                }
                else {
                    $configurations += @(Get-AzMaintenanceConfiguration -ResourceGroupName $ResourceGroupName `
                            -ErrorAction Stop)
                }
            }
            catch {
                Write-Host "[!] Failed to retrieve maintenance configurations: $($_.Exception.Message)" `
                    -ForegroundColor Yellow
            }

            try {
                $machineRows = @(Get-ResourceGraphRow -Query $machineQuery `
                        -TargetSubscriptionId $subscription.Id)
            }
            catch {
                $machineQueryFailures = $machineQueryFailures + 1
                $machineRows = @()
                Write-Host "[!] Failed to enumerate machines: $($_.Exception.Message)" -ForegroundColor Yellow
            }

            try {
                $assessmentRows = @(Get-ResourceGraphRow -Query $assessmentQuery `
                        -TargetSubscriptionId $subscription.Id)
            }
            catch {
                $assessmentRows = @()
                Write-Host "[!] Failed to read update assessments: $($_.Exception.Message)" `
                    -ForegroundColor Yellow
            }

            try {
                $assignmentRows = @(Get-ResourceGraphRow -Query $assignmentQuery `
                        -TargetSubscriptionId $subscription.Id)
            }
            catch {
                $assignmentRows = @()
                Write-Host "[!] Failed to read assignments: $($_.Exception.Message)" `
                    -ForegroundColor Yellow
            }

            $assessmentCount = $assessmentCount + $assessmentRows.Count
            $assignmentCount = $assignmentCount + $assignmentRows.Count

            $machineByKey = @{}
            foreach ($machine in $machineRows) {
                $machineId = [string](Get-DynamicProperty -InputObject $machine -Name 'id' -Default '')
                if ([string]::IsNullOrWhiteSpace($machineId)) { continue }

                $resourceGroup = [string](Get-DynamicProperty -InputObject $machine `
                        -Name 'resourceGroup' -Default '')
                if ($ResourceGroupName -ne '*' -and $resourceGroup -ne $ResourceGroupName) { continue }

                $machineByKey[$machineId.ToLowerInvariant()] = [pscustomobject]@{
                    Name          = [string](Get-DynamicProperty -InputObject $machine -Name 'name' `
                            -Default $machineId)
                    ResourceGroup = $resourceGroup
                }
            }
            $machineCount = $machineCount + $machineByKey.Count

            $assessedKeys = @{}
            $pendingByKey = @{}
            foreach ($assessment in $assessmentRows) {
                $assessmentId = [string](Get-DynamicProperty -InputObject $assessment -Name 'id' -Default '')
                $machineId = Get-MachineResourceId -AssessmentId $assessmentId
                if ([string]::IsNullOrWhiteSpace($machineId)) { continue }

                $key = $machineId.ToLowerInvariant()
                $assessedKeys[$key] = $true

                $criticalCount = ConvertTo-IntOrDefault -Value (
                    Get-DynamicProperty -InputObject $assessment -Name 'criticalCount' -Default 0)
                $securityCount = ConvertTo-IntOrDefault -Value (
                    Get-DynamicProperty -InputObject $assessment -Name 'securityCount' -Default 0)
                $totalCount = $criticalCount + $securityCount
                if ($totalCount -le 0) { continue }

                $currentCount = 0
                if ($pendingByKey.ContainsKey($key)) { $currentCount = $pendingByKey[$key].Total }
                if ($totalCount -gt $currentCount) {
                    $pendingByKey[$key] = [pscustomobject]@{
                        Total    = $totalCount
                        Critical = $criticalCount
                        Security = $securityCount
                    }
                }
            }

            $assignedKeys = @{}
            foreach ($assignment in $assignmentRows) {
                $resourceId = [string](Get-DynamicProperty -InputObject $assignment `
                        -Name 'resourceId' -Default '')
                if ([string]::IsNullOrWhiteSpace($resourceId)) { continue }
                $assignedKeys[$resourceId.ToLowerInvariant()] = $true

                $configurationId = [string](Get-DynamicProperty -InputObject $assignment `
                        -Name 'maintenanceConfigurationId' -Default '')
                if (-not [string]::IsNullOrWhiteSpace($configurationId)) {
                    $usedConfigurationKeys[$configurationId.ToLowerInvariant()] = $true
                }
            }

            foreach ($key in $machineByKey.Keys) {
                $machine = $machineByKey[$key]
                if (-not $assessedKeys.ContainsKey($key)) {
                    $findings += [pscustomobject]@{
                        Category      = 'NoUpdateAssessment'
                        Subscription  = $subscription.Name
                        Name          = $machine.Name
                        ResourceGroup = $machine.ResourceGroup
                        Detail        = 'No update assessment result found for this machine.'
                    }
                }
                if (-not $assignedKeys.ContainsKey($key)) {
                    $findings += [pscustomobject]@{
                        Category      = 'NoMaintenanceConfiguration'
                        Subscription  = $subscription.Name
                        Name          = $machine.Name
                        ResourceGroup = $machine.ResourceGroup
                        Detail        = 'No maintenance configuration is assigned; patching is unscheduled.'
                    }
                }
            }

            foreach ($key in $pendingByKey.Keys) {
                if (-not $machineByKey.ContainsKey($key)) { continue }
                $pending = $pendingByKey[$key]
                $findings += [pscustomobject]@{
                    Category      = 'PendingCriticalSecurityUpdates'
                    Subscription  = $subscription.Name
                    Name          = $machineByKey[$key].Name
                    ResourceGroup = $machineByKey[$key].ResourceGroup
                    Detail        = "Pending updates: $($pending.Critical) critical, $($pending.Security) security."
                }
            }
        }

        if ($subscriptions.Count -gt 0 -and $machineQueryFailures -ge $subscriptions.Count) {
            throw 'The machine inventory could not be read for any subscription.'
        }

        foreach ($configuration in $configurations) {
            $configurationId = [string](Get-DynamicProperty -InputObject $configuration -Name 'Id' -Default '')
            if ([string]::IsNullOrWhiteSpace($configurationId)) { continue }
            if ($usedConfigurationKeys.ContainsKey($configurationId.ToLowerInvariant())) { continue }

            $configurationSubscriptionId = Get-ResourceIdSegment -ResourceId $configurationId `
                -Segment 'subscriptions'
            $configurationSubscription = $configurationSubscriptionId
            if ($subscriptionNames.ContainsKey($configurationSubscriptionId.ToLowerInvariant())) {
                $configurationSubscription = $subscriptionNames[$configurationSubscriptionId.ToLowerInvariant()]
            }

            $findings += [pscustomobject]@{
                Category      = 'UnusedMaintenanceConfiguration'
                Subscription  = $configurationSubscription
                Name          = [string](Get-DynamicProperty -InputObject $configuration -Name 'Name' `
                        -Default $configurationId)
                ResourceGroup = Get-ResourceIdSegment -ResourceId $configurationId -Segment 'resourceGroups'
                Detail        = 'Maintenance configuration has no machines assigned; nothing is patched.'
            }
        }

        $summary = "[+] Found $machineCount machine(s), $assessmentCount assessment result(s), " +
            "$($configurations.Count) maintenance configuration(s), $assignmentCount assignment(s)"

        $noAssessment = @($findings | Where-Object { $_.Category -eq 'NoUpdateAssessment' })
        $pendingUpdates = @($findings | Where-Object { $_.Category -eq 'PendingCriticalSecurityUpdates' })
        $unassigned = @($findings | Where-Object { $_.Category -eq 'NoMaintenanceConfiguration' })
        $unusedConfigurations = @($findings | Where-Object { $_.Category -eq 'UnusedMaintenanceConfiguration' })

        Write-Host ''
        Write-Host '=== Azure Update Manager report ===' -ForegroundColor Cyan
        Write-Host $summary
        Write-Host "Resource group filter: $ResourceGroupName"
        Write-Host "Assessment window    : Resource Graph retention (last 7 days)"

        if ($noAssessment.Count -gt 0) {
            Write-Host "[!] $($noAssessment.Count) machine(s) have no update assessment result." `
                -ForegroundColor Yellow
        }
        if ($pendingUpdates.Count -gt 0) {
            Write-Host "[!] $($pendingUpdates.Count) machine(s) have pending critical/security updates." `
                -ForegroundColor Yellow
        }
        if ($unassigned.Count -gt 0) {
            Write-Host "[!] $($unassigned.Count) machine(s) have no maintenance configuration assigned." `
                -ForegroundColor Yellow
        }
        if ($unusedConfigurations.Count -gt 0) {
            Write-Host "[!] $($unusedConfigurations.Count) maintenance configuration(s) have no machines assigned." `
                -ForegroundColor Yellow
        }

        if ($findings.Count -gt 0) {
            $table = $findings | Format-Table -Property Category, Name, ResourceGroup -AutoSize | Out-String
            Write-Host $table.TrimEnd()
        }

        if ($OutputFormat -ne 'Table') {
            if (-not (Test-Path -LiteralPath $resolvedOutputPath -PathType Container)) {
                New-Item -ItemType Directory -Path $resolvedOutputPath -Force -ErrorAction Stop | Out-Null
            }
            $timestamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
            $report = [pscustomobject]@{
                GeneratedAt                   = (Get-Date).ToString('o')
                SubscriptionId                = $SubscriptionId
                ResourceGroupName             = $ResourceGroupName
                MachineCount                  = $machineCount
                AssessmentResultCount         = $assessmentCount
                MaintenanceConfigurationCount = $configurations.Count
                AssignmentCount               = $assignmentCount
                Findings                      = $findings
            }

            if ($OutputFormat -eq 'Json') {
                $reportPath = Join-Path -Path $resolvedOutputPath -ChildPath "AzureUpdateManager-$timestamp.json"
                $report | ConvertTo-Json -Depth 6 |
                    Set-Content -LiteralPath $reportPath -Encoding utf8 -ErrorAction Stop
            }
            else {
                $reportPath = Join-Path -Path $resolvedOutputPath -ChildPath "AzureUpdateManager-$timestamp.csv"
                if ($findings.Count -gt 0) {
                    $findings | Export-Csv -LiteralPath $reportPath -NoTypeInformation -Encoding utf8 `
                        -ErrorAction Stop
                }
                else {
                    Set-Content -LiteralPath $reportPath -Encoding utf8 -ErrorAction Stop `
                        -Value 'Category,Subscription,Name,ResourceGroup,Detail'
                }
            }
            Write-Host "[+] Report written to: $reportPath" -ForegroundColor Green
        }

        if ($findings.Count -gt 0) {
            Write-Host "[!] $($findings.Count) finding(s) detected." -ForegroundColor Yellow
            return 2
        }

        Write-Host '[+] All machines are assessed and assigned to a maintenance configuration.' `
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
