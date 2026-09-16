<#
.SYNOPSIS
    Inventories Azure Arc-enabled servers and reports agent, heartbeat, and extension findings.

.DESCRIPTION
    Enumerates Azure Arc-enabled servers with Get-AzConnectedMachine and reports the
    Connected Machine agent version, connection status, last status change, OS and SKU,
    location, tags, and installed Arc extensions for every machine in scope. Extensions
    are read per machine with Get-AzConnectedMachineExtension so the inventory matches the
    hybrid, multicloud, and edge model described at
    https://learn.microsoft.com/azure/azure-arc/servers/organize-inventory-servers
    Findings are raised for machines that are not Connected, for heartbeats older than
    -AgentStaleDays, for agents behind the newest agent version observed in the fleet
    (Azure Advisor flags Arc agents that are not on the latest version, see
    https://learn.microsoft.com/azure/azure-arc/servers/manage-agent), and for machines
    missing the AzureMonitorAgent extension. The machine list is produced by the cmdlet
    documented at
    https://learn.microsoft.com/powershell/module/az.connectedmachine/get-azconnectedmachine
    Exit codes: 0 when the fleet is healthy, 2 when one or more findings are present, and
    1 when the script cannot complete (missing Az module, no Azure context, or a failed
    enumeration). The script is read-only and idempotent: it never mutates Arc resources
    and repeated runs return the same exit code.

.PARAMETER SubscriptionId
    One or more subscription IDs to inventory. The default '*' inventories every enabled
    subscription in the current Azure PowerShell context.

.PARAMETER ResourceGroupName
    Resource group to scope the inventory to. The default '*' lists every Arc-enabled
    server in each selected subscription.

.PARAMETER AgentStaleDays
    Number of days after which a machine's last status change counts as a stale heartbeat.
    Valid range 1-365; the default is 30.

.PARAMETER OutputFormat
    Report format used for both the console report and -OutputPath: Table, Json, or Csv.
    The default is Table.

.PARAMETER OutputPath
    Optional file path. When supplied, the fleet inventory is written to that file in the
    selected -OutputFormat in addition to the console report.

.EXAMPLE
    PS C:\> .\Get-AzureArcServerFleet.ps1
    Inventories every Arc-enabled server in the current context and reports findings.

.EXAMPLE
    PS C:\> .\Get-AzureArcServerFleet.ps1 -SubscriptionId '*' -AgentStaleDays 7
    Inventories all enabled subscriptions in context and flags heartbeats older than 7 days.

.EXAMPLE
    PS C:\> .\Get-AzureArcServerFleet.ps1 -ResourceGroupName rg-hybrid -OutputFormat Csv -OutputPath C:\arc-fleet.csv
    Inventories one resource group and writes the CSV inventory to C:\arc-fleet.csv.

.NOTES
    File Name   : Get-AzureArcServerFleet.ps1
    Author      : Bug-Free Umbrella
    Prerequisite: PowerShell 7.0
    Version     : 2.0.0
    Date        : 2026-09-16
#>
[CmdletBinding()]
param(
    [Parameter()]
    [string[]]$SubscriptionId = @('*'),

    [Parameter()]
    [string]$ResourceGroupName = '*',

    [Parameter()]
    [ValidateRange(1, 365)]
    [int]$AgentStaleDays = 30,

    [Parameter()]
    [ValidateSet('Table', 'Json', 'Csv')]
    [string]$OutputFormat = 'Table',

    [Parameter()]
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'

function ConvertTo-AgentVersion {
    param([string]$VersionText)

    if ([string]::IsNullOrWhiteSpace($VersionText)) { return $null }
    try {
        return [version]$VersionText
    }
    catch {
        return $null
    }
}

function Resolve-FleetSubscription {
    param([string[]]$Requested)

    $wanted = @($Requested | ForEach-Object { "$_".Trim() } | Where-Object { $_ -ne '' })
    if ($wanted.Count -eq 0) { $wanted = @('*') }

    if (-not ($wanted -contains '*')) { return $wanted }

    $enabled = @()
    try {
        $enabled = @(Get-AzSubscription -ErrorAction Stop |
            Where-Object { $_.State -eq 'Enabled' } | ForEach-Object { $_.Id })
    }
    catch {
        $enabled = @()
    }
    if ($enabled.Count -gt 0) { return $enabled }

    $context = Get-AzContext -ErrorAction Stop
    if (-not $context) { throw "Not connected to Azure. Run: Connect-AzAccount" }
    return @($context.Subscription.Id)
}

function Get-MachineResourceGroup {
    param([string]$MachineId)

    if ("$MachineId" -match '/resourceGroups/([^/]+)') { return $Matches[1] }
    return ''
}

function Get-MachineTagList {
    param($Machine)

    $tagTable = $null
    foreach ($candidate in @('Tag', 'Tags')) {
        $property = $Machine.PSObject.Properties[$candidate]
        if ($property -and $property.Value) {
            $tagTable = $property.Value
            break
        }
    }
    if (-not $tagTable) { return @() }

    $keys = @($tagTable.Keys | Sort-Object)
    return @($keys | ForEach-Object { "$_=$($tagTable[$_])" })
}

function Get-ArcServerRecord {
    param(
        [Parameter(Mandatory = $true)]$Machine,
        [string]$SubscriptionId = '',
        [string]$FallbackResourceGroup = ''
    )

    $resourceGroup = Get-MachineResourceGroup -MachineId "$($Machine.Id)"
    if (-not $resourceGroup) { $resourceGroup = $FallbackResourceGroup }

    $extensionNames = @()
    try {
        $extensionNames = @(Get-AzConnectedMachineExtension -ResourceGroupName $resourceGroup `
                -MachineName $Machine.Name -SubscriptionId $SubscriptionId -ErrorAction Stop |
            ForEach-Object { $_.Name })
    }
    catch {
        Write-Host "[!] Could not read extensions for $($Machine.Name): $($_.Exception.Message)" `
            -ForegroundColor Yellow
    }

    return [pscustomobject]@{
        Name             = "$($Machine.Name)"
        SubscriptionId   = $SubscriptionId
        ResourceGroup    = $resourceGroup
        Location         = "$($Machine.Location)"
        Status           = "$($Machine.Status)"
        AgentVersion     = "$($Machine.AgentVersion)"
        LastStatusChange = $Machine.LastStatusChange
        OSName           = "$($Machine.OSName)"
        OSSku            = "$($Machine.OSSku)"
        Tags             = @(Get-MachineTagList -Machine $Machine)
        Extensions       = @($extensionNames)
    }
}

function Get-FleetReportText {
    param(
        [object[]]$Records = @(),
        [string]$Format = 'Table'
    )

    if ($Format -eq 'Json') {
        $json = @($Records) | ConvertTo-Json -Depth 6
        if (-not $json) { $json = '[]' }
        return [string]$json
    }

    if ($Format -eq 'Csv') {
        $columns = @('Name', 'SubscriptionId', 'ResourceGroup', 'Location', 'Status',
            'AgentVersion', 'LastStatusChange', 'OSName', 'OSSku', 'Tags', 'Extensions')
        $rows = @($Records | Select-Object $columns | ConvertTo-Csv -NoTypeInformation)
        return [string]($rows -join "`r`n")
    }

    $lines = @()
    foreach ($record in $Records) {
        $lastChange = 'never'
        if ($record.LastStatusChange) {
            $lastChange = ([datetime]$record.LastStatusChange).ToString('s')
        }
        $tagText = 'none'
        if (@($record.Tags).Count -gt 0) { $tagText = @($record.Tags) -join '; ' }
        $extensionText = 'none'
        if (@($record.Extensions).Count -gt 0) { $extensionText = @($record.Extensions) -join ', ' }

        $lines += ("  {0} [{1}] status={2} agent={3} lastChange={4} os={5}/{6} location={7}" -f `
            $record.Name, $record.ResourceGroup, $record.Status, $record.AgentVersion, `
            $lastChange, $record.OSName, $record.OSSku, $record.Location)
        $lines += "    tags: $tagText"
        $lines += "    extensions: $extensionText"
    }
    return [string]($lines -join "`r`n")
}

function Main {
    try {
        Write-Host "[*] Checking Azure connection..." -ForegroundColor Cyan

        # Throw before doing work when a precondition fails.
        if (-not (Get-Command Get-AzContext -ErrorAction SilentlyContinue)) {
            throw "Az.Accounts is not available. Install-Module Az.Accounts"
        }
        Import-Module Az.Accounts -ErrorAction Stop
        Import-Module Az.ConnectedMachine -ErrorAction Stop

        $context = Get-AzContext -ErrorAction Stop
        if (-not $context) {
            throw "Not connected to Azure. Run: Connect-AzAccount"
        }
        Write-Host "[+] Connected to: $($context.Subscription.Name)" -ForegroundColor Green

        $subscriptions = @(Resolve-FleetSubscription -Requested $SubscriptionId)
        Write-Host "[*] Subscriptions in scope: $($subscriptions -join ', ')" -ForegroundColor Cyan

        $scopedResourceGroup = ''
        if ($ResourceGroupName -and $ResourceGroupName -ne '*') {
            $scopedResourceGroup = $ResourceGroupName
        }

        $records = @()
        foreach ($subscription in $subscriptions) {
            $machineParams = @{ ErrorAction = 'Stop' }
            if ($subscription) { $machineParams['SubscriptionId'] = $subscription }
            if ($scopedResourceGroup) { $machineParams['ResourceGroupName'] = $scopedResourceGroup }

            try {
                $found = @(Get-AzConnectedMachine @machineParams)
            }
            catch {
                throw "Failed to enumerate Arc-enabled servers in '$subscription': $($_.Exception.Message)"
            }
            Write-Host "[+] Found $($found.Count) Arc-enabled servers in '$subscription'" -ForegroundColor Green

            foreach ($machine in $found) {
                $records += Get-ArcServerRecord -Machine $machine -SubscriptionId $subscription `
                    -FallbackResourceGroup $scopedResourceGroup
            }
        }

        $machineVersions = @{}
        $newestVersion = $null
        foreach ($record in $records) {
            $parsed = ConvertTo-AgentVersion -VersionText $record.AgentVersion
            if (-not $parsed) { continue }
            if (-not $machineVersions.ContainsKey($record.Name)) {
                $machineVersions[$record.Name] = $parsed
            }
            if (($null -eq $newestVersion) -or ($parsed -gt $newestVersion)) {
                $newestVersion = $parsed
            }
        }

        $staleBefore = (Get-Date).AddDays(-1 * $AgentStaleDays)
        $findings = @()
        foreach ($record in $records) {
            if ($record.Status -ne 'Connected') {
                $findings += [pscustomobject]@{
                    Machine = $record.Name
                    Finding = "Status is '$($record.Status)'"
                }
            }
            if ($record.LastStatusChange) {
                $lastChange = [datetime]$record.LastStatusChange
                if ($lastChange -lt $staleBefore) {
                    $findings += [pscustomobject]@{
                        Machine = $record.Name
                        Finding = "Stale heartbeat, last status change $($lastChange.ToString('s'))"
                    }
                }
            }
            $parsed = $machineVersions[$record.Name]
            if (($null -ne $newestVersion) -and $parsed -and ($parsed -lt $newestVersion)) {
                $findings += [pscustomobject]@{
                    Machine = $record.Name
                    Finding = "Agent version $($record.AgentVersion) is behind fleet maximum $newestVersion"
                }
            }
            if (-not (@($record.Extensions) -contains 'AzureMonitorAgent')) {
                $findings += [pscustomobject]@{
                    Machine = $record.Name
                    Finding = 'AzureMonitorAgent extension is not installed'
                }
            }
        }

        Write-Host ""
        Write-Host "=== Azure Arc server fleet ===" -ForegroundColor Cyan
        $reportText = Get-FleetReportText -Records $records -Format $OutputFormat
        if ($reportText) { Write-Host $reportText }

        foreach ($finding in $findings) {
            Write-Host "[!] $($finding.Machine): $($finding.Finding)" -ForegroundColor Yellow
        }

        if ($OutputPath) {
            Set-Content -LiteralPath $OutputPath -Value $reportText -Encoding UTF8 -ErrorAction Stop
            Write-Host "[+] Report written to: $OutputPath" -ForegroundColor Green
        }

        if ($findings.Count -eq 0) {
            Write-Host "[+] Fleet healthy: $($records.Count) Arc-enabled servers, no findings" -ForegroundColor Green
            return 0
        }

        Write-Host ("[!] $($findings.Count) findings across " +
            "$($records.Count) Arc-enabled servers") -ForegroundColor Yellow
        return 2
    }
    catch {
        Write-Host "[-] Error: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
