<#
.SYNOPSIS
    Reports Azure cost optimisation findings: top cost drivers, month-to-date spend, and idle resources.

.DESCRIPTION
    Read-only cost optimisation report for one Azure subscription or for every subscription the
    signed-in account can read. Cost data is read from the Microsoft Cost Management Query API
    (POST <scope>/providers/Microsoft.CostManagement/query) through Invoke-AzRestMethod, documented at
    https://learn.microsoft.com/en-us/powershell/module/az.accounts/invoke-azrestmethod and
    https://learn.microsoft.com/en-us/rest/api/cost-management/query/usage .

    This script deliberately does NOT use the Consumption Usage Details API or its Az.Billing wrapper
    Get-AzConsumptionUsageDetail: that API is deprecated and Microsoft recommends moving reporting
    pipelines to the Cost Details API or to cost exports. See:
    https://learn.microsoft.com/en-us/azure/cost-management-billing/automate/migrate-consumption-usage-details-api
    The Cost Analysis figures the report mirrors (month-to-date spend and top cost contributors) are
    described at https://learn.microsoft.com/en-us/azure/cost-management-billing/costs/quick-acm-cost-analysis .

    The report contains the month-to-date spend per subscription, the top cost drivers by service and by
    resource group over the lookback window, and resources that keep billing while idle:
    - virtual machines in the "VM stopped" (allocated) power state. A deallocated VM releases its compute
      allocation and stops billing, while a stopped-but-allocated VM keeps billing, so only the latter is
      flagged;
    - managed disks that are not attached to a VM (an empty ManagedBy) and keep billing;
    - public IP addresses with no IP configuration and no NAT gateway attached.

    The script is read-only: it never mutates Azure resources, so re-running it against an unchanged
    environment produces the same report and the same exit code. For -OutputFormat Json or Csv it writes
    one uniquely named report file under -OutputPath. Exit codes: 0 = report produced and no optimisation
    findings; 2 = report produced and optimisation findings were detected; 1 = error (missing Az module,
    not signed in, unsafe -OutputPath, or every Cost Management query failed).

.PARAMETER SubscriptionId
    Subscription ID to report on, or '*' to report on every subscription the signed-in account can read.
    Default: '*'.

.PARAMETER LookbackDays
    Number of days of cost data aggregated for the top cost drivers and for the lookback window (1-90).
    Default: 30.

.PARAMETER TopN
    Maximum number of cost drivers reported per dimension: top services and top resource groups (1-100).
    Default: 10.

.PARAMETER OutputFormat
    Report format: 'Table' prints the report to the console only, while 'Json' and 'Csv' also write a
    report file under -OutputPath. Default: 'Table'.

.PARAMETER OutputPath
    Local directory that receives the JSON/CSV report file. Must be a local path without '..' traversal.
    Default: MyDocuments\Reports.

.EXAMPLE
    PS C:\> .\Get-AzureCostOptimizationReport.ps1
    Prints month-to-date spend plus the top 10 cost drivers by service and by resource group for every
    readable subscription over the last 30 days, and flags stopped-but-allocated VMs, unattached managed
    disks and idle public IPs.

.EXAMPLE
    PS C:\> .\Get-AzureCostOptimizationReport.ps1 -SubscriptionId "*" -LookbackDays 90 -TopN 25 `
        -OutputFormat Csv -OutputPath C:\Reports
    Analyses every readable subscription over 90 days and writes the top 25 cost drivers and the
    optimisation findings to a timestamped CSV file in C:\Reports.

.NOTES
    File Name   : Get-AzureCostOptimizationReport.ps1
    Author      : Bug-Free Umbrella
    Prerequisite: PowerShell 7.0
    Version     : 2.0.0
    Date        : 2026-09-16

    Cost Management API version used by the query path: 2026-06-01
    https://learn.microsoft.com/en-us/rest/api/cost-management/query/usage
    The declined alternative, recorded for reference:
    https://learn.microsoft.com/en-us/powershell/module/az.billing/get-azconsumptionusagedetail
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
    [ValidateRange(1, 90)]
    [int]$LookbackDays = 30,

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 100)]
    [int]$TopN = 10,

    [Parameter(Mandatory = $false)]
    [ValidateSet('Table', 'Json', 'Csv')]
    [string]$OutputFormat = 'Table',

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$OutputPath = (Join-Path ($(if ($bfuMyDocs = [Environment]::GetFolderPath('MyDocuments')) { $bfuMyDocs }
            elseif ($env:USERPROFILE) { $env:USERPROFILE }
            elseif ($env:HOME) { $env:HOME }
            else { [IO.Path]::GetTempPath() })) 'Reports')
)

$ErrorActionPreference = 'Stop'

function Get-CostColumnIndex {
    <#
    .SYNOPSIS
        Returns the index of the cost column in a Cost Management query response.
    #>
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Columns
    )

    for ($index = 0; $index -lt $Columns.Count; $index++) {
        if ([string]($Columns[$index].name) -match '^(PreTaxCost|Cost|totalCost)') { return $index }
    }
    for ($index = 0; $index -lt $Columns.Count; $index++) {
        if ([string]($Columns[$index].type) -eq 'Number') { return $index }
    }
    return -1
}

function Get-LabelColumnIndex {
    <#
    .SYNOPSIS
        Returns the index of the grouping label column in a Cost Management query response.
    #>
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Columns
    )

    for ($index = 0; $index -lt $Columns.Count; $index++) {
        $name = [string]($Columns[$index].name)
        if ([string]($Columns[$index].type) -eq 'String' -and $name -notin @('Currency', 'BillingCurrency')) {
            return $index
        }
    }
    return -1
}

function ConvertFrom-CostQueryResponse {
    <#
    .SYNOPSIS
        Converts a Cost Management query HTTP response into Label/Cost/Currency objects.
    #>
    param(
        [Parameter(Mandatory = $false)][AllowNull()][object]$Response
    )

    $converted = @()
    if ($null -eq $Response) { return $converted }
    $content = [string]$Response.Content
    if ([string]::IsNullOrWhiteSpace($content)) { return $converted }

    $body = ConvertFrom-Json -InputObject $content
    if (-not $body.properties) { return $converted }
    if (-not $body.properties.columns -or -not $body.properties.rows) { return $converted }

    $columns = @($body.properties.columns)
    $costIndex = Get-CostColumnIndex -Columns $columns
    if ($costIndex -lt 0) { return $converted }
    $labelIndex = Get-LabelColumnIndex -Columns $columns

    foreach ($row in @($body.properties.rows)) {
        $currency = 'USD'
        for ($index = 0; $index -lt $columns.Count; $index++) {
            if ([string]($columns[$index].name) -eq 'Currency') { $currency = [string]$row[$index] }
        }
        $label = 'Total'
        if ($labelIndex -ge 0) { $label = [string]$row[$labelIndex] }
        $converted += [pscustomobject]@{
            Label    = $label
            Cost     = [double]$row[$costIndex]
            Currency = $currency
        }
    }
    return $converted
}

function Invoke-CostManagementQuery {
    <#
    .SYNOPSIS
        Runs one Cost Management Query API call and returns its Label/Cost/Currency rows.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$TargetSubscriptionId,
        [Parameter(Mandatory = $true)][string]$Timeframe,
        [Parameter(Mandatory = $false)][AllowNull()][string]$Dimension,
        [Parameter(Mandatory = $false)][AllowNull()][string]$From,
        [Parameter(Mandatory = $false)][AllowNull()][string]$To
    )

    $dataset = @{
        granularity = 'None'
        aggregation = @{ totalCost = @{ name = 'PreTaxCost'; function = 'Sum' } }
    }
    if ($Dimension) {
        $dataset['grouping'] = @(@{ type = 'Dimension'; name = $Dimension })
    }

    $body = @{
        type      = 'Usage'
        timeframe = $Timeframe
        dataset   = $dataset
    }
    if ($Timeframe -eq 'Custom') {
        $body['timePeriod'] = @{ from = $From; to = $To }
    }

    $path = "/subscriptions/$TargetSubscriptionId/providers/Microsoft.CostManagement/query?api-version=2026-06-01"
    $payload = $body | ConvertTo-Json -Depth 6 -Compress
    $response = Invoke-AzRestMethod -Method POST -Path $path -Payload $payload -ErrorAction Stop
    return ConvertFrom-CostQueryResponse -Response $response
}

function Get-TopCostDriver {
    <#
    .SYNOPSIS
        Aggregates cost rows by label and returns the highest spending drivers.
    #>
    param(
        [Parameter(Mandatory = $false)][AllowEmptyCollection()][object[]]$Rows,
        [Parameter(Mandatory = $true)][int]$Count
    )

    $totals = @{}
    foreach ($row in @($Rows)) {
        if (-not $row) { continue }
        if ($totals.ContainsKey($row.Label)) {
            $totals[$row.Label] = $totals[$row.Label] + $row.Cost
        }
        else {
            $totals[$row.Label] = $row.Cost
        }
    }

    $drivers = @()
    foreach ($key in $totals.Keys) {
        $drivers += [pscustomobject]@{ Label = $key; Cost = [math]::Round($totals[$key], 2) }
    }
    return @($drivers | Sort-Object -Property Cost -Descending | Select-Object -First $Count)
}

function Main {
    <#
    .SYNOPSIS
        Runs the Azure cost optimisation report and returns the documented exit code.
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
        Import-Module Az.Compute -ErrorAction SilentlyContinue
        Import-Module Az.Network -ErrorAction SilentlyContinue
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

        $to = (Get-Date).ToUniversalTime()
        $from = $to.AddDays(-1 * $LookbackDays)

        $serviceRows = @()
        $resourceGroupRows = @()
        $monthToDate = @()
        $findings = @()
        $costQueryCount = 0
        $costQueryFailures = 0

        foreach ($subscription in $subscriptions) {
            Write-Host "[*] Analysing subscription: $($subscription.Name)" -ForegroundColor Cyan
            Set-AzContext -SubscriptionId $subscription.Id -ErrorAction Stop | Out-Null

            $costQueryCount = $costQueryCount + 3

            try {
                $serviceRows += @(Invoke-CostManagementQuery -TargetSubscriptionId $subscription.Id `
                        -Timeframe 'Custom' -Dimension 'ServiceName' -From $from.ToString('o') -To $to.ToString('o'))
            }
            catch {
                $costQueryFailures = $costQueryFailures + 1
                Write-Host "[!] Service cost query failed: $($_.Exception.Message)" -ForegroundColor Yellow
            }

            try {
                $resourceGroupRows += @(Invoke-CostManagementQuery -TargetSubscriptionId $subscription.Id `
                        -Timeframe 'Custom' -Dimension 'ResourceGroupName' -From $from.ToString('o') `
                        -To $to.ToString('o'))
            }
            catch {
                $costQueryFailures = $costQueryFailures + 1
                Write-Host "[!] Resource group cost query failed: $($_.Exception.Message)" -ForegroundColor Yellow
            }

            try {
                foreach ($row in @(Invoke-CostManagementQuery -TargetSubscriptionId $subscription.Id `
                            -Timeframe 'MonthToDate')) {
                    $monthToDate += [pscustomobject]@{
                        Subscription = $subscription.Name
                        Cost         = $row.Cost
                        Currency     = $row.Currency
                    }
                }
            }
            catch {
                $costQueryFailures = $costQueryFailures + 1
                Write-Host "[!] Month-to-date cost query failed: $($_.Exception.Message)" -ForegroundColor Yellow
            }

            try {
                foreach ($vm in @(Get-AzVM -Status -ErrorAction Stop)) {
                    $powerState = ''
                    $statuses = @($vm.Statuses | Where-Object { $_.Code -like 'PowerState/*' })
                    if ($statuses.Count -gt 0) { $powerState = [string]$statuses[0].DisplayStatus }
                    if ($powerState -eq 'VM stopped') {
                        $findings += [pscustomobject]@{
                            Category      = 'StoppedButBilling'
                            Subscription  = $subscription.Name
                            Name          = [string]$vm.Name
                            ResourceGroup = [string]$vm.ResourceGroupName
                            Detail        = 'VM is stopped but still allocated; deallocate it to stop compute billing.'
                        }
                    }
                }
            }
            catch {
                Write-Host "[!] Failed to retrieve VMs: $($_.Exception.Message)" -ForegroundColor Yellow
            }

            try {
                foreach ($disk in @(Get-AzDisk -ErrorAction Stop)) {
                    if ([string]::IsNullOrWhiteSpace([string]$disk.ManagedBy)) {
                        $findings += [pscustomobject]@{
                            Category      = 'UnattachedDisk'
                            Subscription  = $subscription.Name
                            Name          = [string]$disk.Name
                            ResourceGroup = [string]$disk.ResourceGroupName
                            Detail        = 'Managed disk is not attached to a VM and keeps billing.'
                        }
                    }
                }
            }
            catch {
                Write-Host "[!] Failed to retrieve managed disks: $($_.Exception.Message)" -ForegroundColor Yellow
            }

            try {
                foreach ($publicIp in @(Get-AzPublicIpAddress -ErrorAction Stop)) {
                    if ($null -eq $publicIp.IpConfiguration -and $null -eq $publicIp.NatGateway) {
                        $findings += [pscustomobject]@{
                            Category      = 'IdlePublicIp'
                            Subscription  = $subscription.Name
                            Name          = [string]$publicIp.Name
                            ResourceGroup = [string]$publicIp.ResourceGroupName
                            Detail        = 'Public IP address is not attached to any resource and keeps billing.'
                        }
                    }
                }
            }
            catch {
                Write-Host "[!] Failed to retrieve public IP addresses: $($_.Exception.Message)" `
                    -ForegroundColor Yellow
            }
        }

        if ($costQueryCount -gt 0 -and $costQueryFailures -ge $costQueryCount) {
            throw 'Every Cost Management query failed; no cost data could be retrieved.'
        }

        $topServices = @(Get-TopCostDriver -Rows $serviceRows -Count $TopN)
        $topResourceGroups = @(Get-TopCostDriver -Rows $resourceGroupRows -Count $TopN)
        $stoppedVms = @($findings | Where-Object { $_.Category -eq 'StoppedButBilling' })
        $unattachedDisks = @($findings | Where-Object { $_.Category -eq 'UnattachedDisk' })
        $idlePublicIps = @($findings | Where-Object { $_.Category -eq 'IdlePublicIp' })

        Write-Host ''
        Write-Host '=== Azure cost optimisation report ===' -ForegroundColor Cyan
        Write-Host "Subscriptions : $($subscriptions.Count)"
        Write-Host "Lookback      : $LookbackDays day(s), top $TopN drivers"
        foreach ($entry in $monthToDate) {
            $costText = $entry.Cost.ToString('F2')
            Write-Host ("Month-to-date : " + $entry.Subscription + " = " + $costText + " " + $entry.Currency)
        }

        Write-Host ''
        Write-Host "Top $TopN cost drivers by service:" -ForegroundColor Cyan
        Write-Host (($topServices | Format-Table -Property Label, Cost -AutoSize | Out-String).TrimEnd())
        Write-Host "Top $TopN cost drivers by resource group:" -ForegroundColor Cyan
        Write-Host (($topResourceGroups | Format-Table -Property Label, Cost -AutoSize | Out-String).TrimEnd())

        if ($stoppedVms.Count -gt 0) {
            Write-Host "[!] $($stoppedVms.Count) VM(s) stopped but still allocated (still billing)." `
                -ForegroundColor Yellow
        }
        if ($unattachedDisks.Count -gt 0) {
            Write-Host "[!] $($unattachedDisks.Count) unattached managed disk(s) (still billing)." `
                -ForegroundColor Yellow
        }
        if ($idlePublicIps.Count -gt 0) {
            Write-Host "[!] $($idlePublicIps.Count) idle public IP address(es) (still billing)." `
                -ForegroundColor Yellow
        }

        if ($OutputFormat -ne 'Table') {
            if (-not (Test-Path -LiteralPath $resolvedOutputPath -PathType Container)) {
                New-Item -ItemType Directory -Path $resolvedOutputPath -Force -ErrorAction Stop | Out-Null
            }
            $timestamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
            $report = [pscustomobject]@{
                GeneratedAt          = (Get-Date).ToString('o')
                SubscriptionId       = $SubscriptionId
                LookbackDays         = $LookbackDays
                MonthToDateSpend     = $monthToDate
                TopServices          = $topServices
                TopResourceGroups    = $topResourceGroups
                OptimizationFindings = $findings
            }

            if ($OutputFormat -eq 'Json') {
                $reportPath = Join-Path -Path $resolvedOutputPath -ChildPath "AzureCostOptimization-$timestamp.json"
                $report | ConvertTo-Json -Depth 6 |
                    Set-Content -LiteralPath $reportPath -Encoding utf8 -ErrorAction Stop
            }
            else {
                $reportPath = Join-Path -Path $resolvedOutputPath -ChildPath "AzureCostOptimization-$timestamp.csv"
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
            Write-Host "[!] $($findings.Count) optimisation finding(s) detected." -ForegroundColor Yellow
            return 2
        }

        Write-Host '[+] No optimisation findings detected.' -ForegroundColor Green
        return 0
    }
    catch {
        Write-Host "[-] Error: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
