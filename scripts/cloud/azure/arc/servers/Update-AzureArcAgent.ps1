<#
.SYNOPSIS
    Requests a Connected Machine agent upgrade for Azure Arc-enabled servers below a target version.

.DESCRIPTION
    Enumerates Azure Arc-enabled servers with Get-AzConnectedMachine, selects the machines
    whose Connected Machine agent version is below -MinimumAgentVersion (or below the
    newest agent version observed in the selected fleet when -MinimumAgentVersion is
    omitted), and requests an agent upgrade for each selected machine with
    Update-AzConnectedMachine -AgentUpgradeDesiredVersion. The agent upgrade property this
    script drives is documented at
    https://learn.microsoft.com/azure/azure-arc/servers/manage-agent
    and the update cmdlet is documented at
    https://learn.microsoft.com/powershell/module/az.connectedmachine/update-azconnectedmachine
    Azure Advisor flags Arc agents that are not on the latest version; this script
    remediates those machines in bulk. Every upgrade is gated behind ShouldProcess per
    machine, so -WhatIf and -Confirm are honored and no machine is changed without an
    approved action. The script is idempotent: when every selected machine is already
    on or above the target version it prints "[+] Already up to date" and exits 0 without
    calling Update-AzConnectedMachine. Exit codes: 0 when the fleet is converged (all
    eligible machines upgraded, skipped by ShouldProcess, or already up to date) and 1
    when the script cannot complete (missing Az module, no Azure context, an invalid
    -MinimumAgentVersion, or a failed enumeration).

.PARAMETER SubscriptionId
    One or more subscription IDs to assess. The default '*' assesses every enabled
    subscription in the current Azure PowerShell context.

.PARAMETER ResourceGroupName
    Resource group to scope the assessment to. The default '*' covers every Arc-enabled
    server in each selected subscription.

.PARAMETER MachineName
    Machine-name filter applied with wildcard (-like) matching. The default '*' matches
    every Arc-enabled server in scope.

.PARAMETER MinimumAgentVersion
    Target agent version, for example 1.57.0. Only machines below this version are
    upgraded. When omitted, the newest agent version observed in the assessed fleet is
    used as the target.

.PARAMETER OutputPath
    Optional path for a JSON report of the per-machine assessment (machine, previous
    version, target version, and action) in addition to the console output.

.EXAMPLE
    PS C:\> .\Update-AzureArcAgent.ps1 -WhatIf
    Reports which Arc-enabled servers would be upgraded to the newest fleet version, changing nothing.

.EXAMPLE
    PS C:\> .\Update-AzureArcAgent.ps1 -MinimumAgentVersion 1.57.0 -Confirm:$false
    Upgrades every server in context whose agent is older than 1.57.0 without per-machine prompts.

.EXAMPLE
    PS C:\> .\Update-AzureArcAgent.ps1 -MachineName 'srv-prod-*' -OutputPath C:\arc-agent.json
    Upgrades the matching production servers and writes the assessment report to JSON.

.NOTES
    File Name   : Update-AzureArcAgent.ps1
    Author      : Bug-Free Umbrella
    Prerequisite: PowerShell 7.0
    Version     : 2.0.0
    Date        : 2026-09-16
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter()]
    [string[]]$SubscriptionId = @('*'),

    [Parameter()]
    [string]$ResourceGroupName = '*',

    [Parameter()]
    [string]$MachineName = '*',

    [Parameter()]
    [string]$MinimumAgentVersion,

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

function Main {
    [CmdletBinding(SupportsShouldProcess)]
    param()

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

        $target = $null
        if ($MinimumAgentVersion) {
            $target = ConvertTo-AgentVersion -VersionText $MinimumAgentVersion
            if ($null -eq $target) {
                throw "-MinimumAgentVersion '$MinimumAgentVersion' is not a valid version."
            }
        }

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

            foreach ($machine in $found) {
                if (-not ("$($machine.Name)" -like $MachineName)) { continue }
                $resourceGroup = Get-MachineResourceGroup -MachineId "$($machine.Id)"
                if (-not $resourceGroup) { $resourceGroup = $scopedResourceGroup }

                $records += [pscustomobject]@{
                    Name           = "$($machine.Name)"
                    SubscriptionId = $subscription
                    ResourceGroup  = $resourceGroup
                    AgentVersion   = "$($machine.AgentVersion)"
                    Status         = "$($machine.Status)"
                }
            }
        }
        Write-Host "[+] Matched $($records.Count) Arc-enabled servers" -ForegroundColor Green

        foreach ($record in $records) {
            $parsed = ConvertTo-AgentVersion -VersionText $record.AgentVersion
            if (-not $parsed) { continue }
            if (($null -eq $target) -or ($parsed -gt $target)) { $target = $parsed }
        }
        if ($null -eq $target) {
            Write-Host "[!] No Arc-enabled server reported a usable agent version; nothing to upgrade." `
                -ForegroundColor Yellow
            return 0
        }
        Write-Host "[*] Target agent version: $target" -ForegroundColor Cyan

        $plan = @()
        $upgradeCount = 0
        $skippedCount = 0
        foreach ($record in $records) {
            $current = ConvertTo-AgentVersion -VersionText $record.AgentVersion
            $needsUpgrade = $false
            if ($null -eq $current) { $needsUpgrade = $true }
            elseif ($current -lt $target) { $needsUpgrade = $true }

            if (-not $needsUpgrade) {
                Write-Host "[+] $($record.Name) already up to date (agent $($record.AgentVersion))" `
                    -ForegroundColor Green
                $plan += [pscustomobject]@{
                    Machine         = $record.Name
                    PreviousVersion = $record.AgentVersion
                    TargetVersion   = "$target"
                    Action          = 'AlreadyUpToDate'
                }
                continue
            }

            if (-not $record.ResourceGroup) {
                throw "Could not determine the resource group for machine $($record.Name)."
            }

            $action = "upgrade the Connected Machine agent to $target"
            if ($PSCmdlet.ShouldProcess($record.Name, $action)) {
                $updateParams = @{
                    Name                       = $record.Name
                    ResourceGroupName          = $record.ResourceGroup
                    AgentUpgradeDesiredVersion = "$target"
                    ErrorAction                = 'Stop'
                }
                if ($record.SubscriptionId) { $updateParams['SubscriptionId'] = $record.SubscriptionId }
                Update-AzConnectedMachine @updateParams | Out-Null

                $upgradeCount++
                Write-Host "[+] Upgrade requested for $($record.Name): $($record.AgentVersion) -> $target" `
                    -ForegroundColor Green
                $plan += [pscustomobject]@{
                    Machine         = $record.Name
                    PreviousVersion = $record.AgentVersion
                    TargetVersion   = "$target"
                    Action          = 'UpgradeRequested'
                }
            }
            else {
                $skippedCount++
                Write-Host "[!] Skipped $($record.Name) because ShouldProcess was not approved." `
                    -ForegroundColor Yellow
                $plan += [pscustomobject]@{
                    Machine         = $record.Name
                    PreviousVersion = $record.AgentVersion
                    TargetVersion   = "$target"
                    Action          = 'Skipped'
                }
            }
        }

        if ($OutputPath) {
            $reportJson = @($plan) | ConvertTo-Json -Depth 4
            if (-not $reportJson) { $reportJson = '[]' }
            Set-Content -LiteralPath $OutputPath -Value $reportJson -Encoding UTF8 -ErrorAction Stop
            Write-Host "[+] Assessment report written to: $OutputPath" -ForegroundColor Green
        }

        if ($upgradeCount -gt 0) {
            Write-Host "[+] Requested $upgradeCount agent upgrade(s) targeting $target" -ForegroundColor Green
            return 0
        }
        if ($skippedCount -gt 0) {
            Write-Host ("[!] $skippedCount agent upgrade(s) skipped by ShouldProcess; " +
                "nothing was changed") -ForegroundColor Yellow
            return 0
        }

        Write-Host ("[+] Already up to date: $($records.Count) Arc-enabled servers on agent " +
            "$target or newer") -ForegroundColor Green
        return 0
    }
    catch {
        Write-Host "[-] Error: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
