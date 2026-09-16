<#
.SYNOPSIS
    Audits Azure NSG rules, subnets, NICs, and public IP exposure read-only.

.DESCRIPTION
    Read-only Azure network exposure audit. For every selected subscription the
    script inventories network security groups, virtual networks, network
    interfaces, and public IP addresses, then reports four classes of finding:

    - an NSG security rule that allows inbound traffic from the Internet (or a
      wildcard source) to any port, which Azure evaluates ahead of the
      DenyAllInbound default rule
    - a subnet with no network security group associated
    - a network interface with no network security group associated; a subnet
      level NSG may still cover it, so this is reported at medium severity
    - a public IP address attached directly to a virtual machine NIC

    The script is read-only and idempotent: it never mutates Azure state, so
    re-running it makes no changes. Exit codes: 0 = no findings; 2 = findings
    present; 1 = error (no Azure context, Az modules unavailable, unsafe
    -OutputPath, or an inventory query failed so the audit is incomplete).

    NSG rule evaluation order and the default security rules are documented at
    https://learn.microsoft.com/azure/virtual-network/network-security-group-how-it-works
    and https://learn.microsoft.com/azure/virtual-network/network-security-groups-overview

.PARAMETER SubscriptionId
    Subscription ID to audit. Use '*' (the default) to audit every accessible
    subscription.

.PARAMETER ResourceGroupName
    Optional resource group name filter applied to every inventory query.

.PARAMETER OutputFormat
    Report format: 'Table' (console list), 'Json', or 'Csv'. Default: 'Table'.

.PARAMETER OutputPath
    Optional directory for the Json or Csv report. Must be a local absolute
    path without '..' traversal. When omitted, Json and Csv output is written
    to the console instead.

.EXAMPLE
    PS C:\> .\Get-AzureNetworkSecurityAudit.ps1 -SubscriptionId '*'
    Audits every accessible subscription and prints the finding table.

.EXAMPLE
    PS C:\> .\Get-AzureNetworkSecurityAudit.ps1 -SubscriptionId '00000000-0000-0000-0000-000000000001' `
        -ResourceGroupName 'rg-prod' -OutputFormat Json -OutputPath 'C:\Reports'
    Audits one resource group and writes a JSON report into C:\Reports.

.NOTES
    File Name   : Get-AzureNetworkSecurityAudit.ps1
    Author      : Bug-Free Umbrella
    Prerequisite: PowerShell 7.0
    Version     : 2.0.0
    Date        : 2026-09-16

    Cmdlet reference pages:
    https://learn.microsoft.com/powershell/module/az.network/get-aznetworksecuritygroup
    https://learn.microsoft.com/powershell/module/az.network/get-azvirtualnetwork
    https://learn.microsoft.com/powershell/module/az.network/get-aznetworkinterface
    https://learn.microsoft.com/powershell/module/az.network/get-azpublicipaddress
#>
[CmdletBinding()]
param(
    [Parameter()][string]$SubscriptionId = '*',
    [Parameter()][string]$ResourceGroupName,
    [Parameter()][ValidateSet('Table', 'Json', 'Csv')][string]$OutputFormat = 'Table',
    [Parameter()][string]$OutputPath
)

$ErrorActionPreference = 'Stop'

function Get-ResourceNameFromId {
    param([string]$Id)

    if ([string]::IsNullOrWhiteSpace($Id)) {
        return $null
    }
    $segments = $Id.TrimEnd('/').Split('/')
    return $segments[$segments.Count - 1]
}

function Test-PermissiveSource {
    param([object]$Rule)

    $sources = @()
    if ($Rule.SourceAddressPrefix) {
        $sources += $Rule.SourceAddressPrefix
    }
    if ($Rule.SourceAddressPrefixes) {
        $sources += $Rule.SourceAddressPrefixes
    }
    foreach ($source in $sources) {
        if ($source -in @('Internet', 'Any', '*', '0.0.0.0/0', '::/0')) {
            return $true
        }
    }
    return $false
}

function Test-PermissivePort {
    param([object]$Rule)

    $ports = @()
    if ($Rule.DestinationPortRange) {
        $ports += $Rule.DestinationPortRange
    }
    if ($Rule.DestinationPortRanges) {
        $ports += $Rule.DestinationPortRanges
    }
    foreach ($port in $ports) {
        if ($port -in @('*', 'Any', '0-65535')) {
            return $true
        }
    }
    return $false
}

function Main {
    try {
        if (-not (Get-Command Get-AzContext -ErrorAction SilentlyContinue)) {
            throw "Az.Accounts is not available. Install-Module Az.Accounts"
        }

        Write-Host "[*] Checking Azure connection..." -ForegroundColor Cyan
        Import-Module Az.Accounts -ErrorAction Stop
        Import-Module Az.Network -ErrorAction Stop

        $context = Get-AzContext -ErrorAction Stop
        if (-not $context) {
            throw "Not connected to Azure. Run: Connect-AzAccount"
        }
        Write-Host "[+] Azure context: $($context.Subscription.Name)" -ForegroundColor Green

        if ($OutputPath) {
            if ($OutputPath -match '(^|[\\/])\.\.([\\/]|$)' -or $OutputPath -match '^(\\\\|//)') {
                Write-Host "[-] Unsafe OutputPath: $OutputPath." -ForegroundColor Red
                Write-Host "    Use a local absolute path without '..' traversal." -ForegroundColor Red
                return 1
            }
            if (-not (Test-Path -LiteralPath $OutputPath -PathType Container)) {
                New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
            }
        }

        if ($SubscriptionId -eq '*') {
            $subscriptions = @(Get-AzSubscription -ErrorAction Stop)
        }
        else {
            $subscriptions = @(Get-AzSubscription -SubscriptionId $SubscriptionId -ErrorAction Stop)
        }
        if ($subscriptions.Count -eq 0) {
            throw "No accessible Azure subscription matched '$SubscriptionId'."
        }
        Write-Host "[*] Auditing $($subscriptions.Count) subscription(s)..." -ForegroundColor Cyan

        $queryArgs = @{}
        if ($ResourceGroupName) {
            $queryArgs['ResourceGroupName'] = $ResourceGroupName
        }

        $findings = @()
        $incomplete = $false

        foreach ($sub in $subscriptions) {
            Set-AzContext -SubscriptionId $sub.Id -ErrorAction Stop | Out-Null
            Write-Host "[*] Auditing subscription: $($sub.Name)" -ForegroundColor Cyan

            $nsgs = @()
            $vnets = @()
            $nics = @()
            $pips = @()

            try {
                $nsgs = @(Get-AzNetworkSecurityGroup @queryArgs -ErrorAction Stop)
            }
            catch {
                Write-Host "[!] Failed to read NSGs: $($_.Exception.Message)" -ForegroundColor Yellow
                $incomplete = $true
            }
            try {
                $vnets = @(Get-AzVirtualNetwork @queryArgs -ErrorAction Stop)
            }
            catch {
                Write-Host "[!] Failed to read VNets: $($_.Exception.Message)" -ForegroundColor Yellow
                $incomplete = $true
            }
            try {
                $nics = @(Get-AzNetworkInterface @queryArgs -ErrorAction Stop)
            }
            catch {
                Write-Host "[!] Failed to read NICs: $($_.Exception.Message)" -ForegroundColor Yellow
                $incomplete = $true
            }
            try {
                $pips = @(Get-AzPublicIpAddress @queryArgs -ErrorAction Stop)
            }
            catch {
                Write-Host "[!] Failed to read public IPs: $($_.Exception.Message)" -ForegroundColor Yellow
                $incomplete = $true
            }

            Write-Host ("[+] Inventory: {0} NSGs, {1} VNets, {2} NICs, {3} public IPs" -f `
                $nsgs.Count, $vnets.Count, $nics.Count, $pips.Count) -ForegroundColor Green

            foreach ($nsg in $nsgs) {
                foreach ($rule in @($nsg.SecurityRules)) {
                    if ($rule.Direction -ne 'Inbound' -or $rule.Access -ne 'Allow') {
                        continue
                    }
                    if (-not (Test-PermissiveSource -Rule $rule)) {
                        continue
                    }
                    if (-not (Test-PermissivePort -Rule $rule)) {
                        continue
                    }
                    $findings += [pscustomobject]@{
                        Severity     = 'High'
                        Category     = 'PermissiveInboundRule'
                        Resource     = "$($nsg.Name)/$($rule.Name)"
                        Details      = "Inbound allow from Internet on any port (protocol $($rule.Protocol))"
                        Subscription = $sub.Name
                    }
                }
            }

            foreach ($vnet in $vnets) {
                foreach ($subnet in @($vnet.Subnets)) {
                    $subnetNsgId = $null
                    if ($subnet.NetworkSecurityGroup) {
                        $subnetNsgId = $subnet.NetworkSecurityGroup.Id
                    }
                    if ($subnetNsgId) {
                        continue
                    }
                    $findings += [pscustomobject]@{
                        Severity     = 'High'
                        Category     = 'SubnetWithoutNsg'
                        Resource     = "$($vnet.Name)/$($subnet.Name)"
                        Details      = "Subnet '$($subnet.Name)' has no network security group associated"
                        Subscription = $sub.Name
                    }
                }
            }

            $nicsByName = @{}
            foreach ($nic in $nics) {
                if ($nic.Name) {
                    $nicsByName[$nic.Name] = $nic
                }
            }
            foreach ($nic in $nics) {
                $nicNsgId = $null
                if ($nic.NetworkSecurityGroup) {
                    $nicNsgId = $nic.NetworkSecurityGroup.Id
                }
                if ($nicNsgId) {
                    continue
                }
                $findings += [pscustomobject]@{
                    Severity     = 'Medium'
                    Category     = 'NicWithoutNsg'
                    Resource     = "$($nic.Name)"
                    Details      = "Network interface has no NSG; a subnet level NSG may still cover it"
                    Subscription = $sub.Name
                }
            }

            foreach ($pip in $pips) {
                $configId = $null
                if ($pip.IpConfiguration) {
                    $configId = $pip.IpConfiguration.Id
                }
                if (-not $configId) {
                    continue
                }
                if ($configId -notmatch '(?i)/networkInterfaces/([^/]+)') {
                    continue
                }
                $nicName = $Matches[1]
                if (-not $nicsByName.ContainsKey($nicName)) {
                    continue
                }
                $nic = $nicsByName[$nicName]
                if (-not $nic.VirtualMachine) {
                    continue
                }
                $vmName = Get-ResourceNameFromId -Id $nic.VirtualMachine.Id
                $findings += [pscustomobject]@{
                    Severity     = 'High'
                    Category     = 'PublicIpOnVmNic'
                    Resource     = "$($pip.Name) -> $nicName"
                    Details      = "Public IP attached directly to NIC '$nicName' of VM '$vmName'"
                    Subscription = $sub.Name
                }
            }
        }

        Write-Host ""
        Write-Host "=== Azure Network Security Audit ===" -ForegroundColor Cyan
        Write-Host "Subscriptions audited: $($subscriptions.Count)" -ForegroundColor White
        Write-Host "Findings: $($findings.Count)" -ForegroundColor White

        $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'

        switch ($OutputFormat) {
            'Table' {
                if ($findings.Count -eq 0) {
                    Write-Host "[+] No findings to list." -ForegroundColor Green
                }
                foreach ($finding in $findings) {
                    Write-Host ("  [{0}] {1}" -f $finding.Severity, $finding.Category) -ForegroundColor Gray
                    Write-Host ("      {0}: {1}" -f $finding.Resource, $finding.Details)
                }
            }
            'Json' {
                $report = [pscustomobject]@{
                    GeneratedAt   = (Get-Date).ToString('s')
                    Subscriptions = @($subscriptions | ForEach-Object { $_.Name })
                    Findings      = @($findings)
                }
                $json = ConvertTo-Json -InputObject $report -Depth 5
                if ($OutputPath) {
                    $jsonFile = Join-Path $OutputPath "Azure-NetworkSecurityAudit_$stamp.json"
                    Set-Content -LiteralPath $jsonFile -Value $json -Encoding utf8
                    Write-Host "[+] JSON report written: $jsonFile" -ForegroundColor Green
                }
                else {
                    Write-Host $json
                }
            }
            'Csv' {
                if ($findings.Count -eq 0) {
                    Write-Host "[+] No findings to export." -ForegroundColor Green
                }
                elseif ($OutputPath) {
                    $csvFile = Join-Path $OutputPath "Azure-NetworkSecurityAudit_$stamp.csv"
                    $findings | Export-Csv -LiteralPath $csvFile -NoTypeInformation -Encoding utf8
                    Write-Host "[+] CSV report written: $csvFile" -ForegroundColor Green
                }
                else {
                    $findings | ConvertTo-Csv -NoTypeInformation | ForEach-Object { Write-Host $_ }
                }
            }
        }

        if ($incomplete) {
            Write-Host "[!] Audit incomplete: one or more inventory queries failed." -ForegroundColor Yellow
            return 1
        }
        if ($findings.Count -gt 0) {
            Write-Host "[!] Audit complete: $($findings.Count) finding(s) require review." -ForegroundColor Yellow
            return 2
        }

        Write-Host "[+] Audit complete: no findings." -ForegroundColor Green
        return 0
    }
    catch {
        Write-Host "[-] Error: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
