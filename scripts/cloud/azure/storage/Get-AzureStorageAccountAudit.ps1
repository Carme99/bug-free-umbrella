<#
.SYNOPSIS
    Audits Azure Storage account security posture against Microsoft hardening guidance.

.DESCRIPTION
    Read-only Azure Storage security audit. For every selected subscription the script
    inventories storage accounts with Get-AzStorageAccount and reports six classes of
    finding:

    - anonymous public blob access is enabled on the account
    - Shared Key authorization is still permitted
    - the minimum TLS version is below 1.2, or no version is pinned
    - the network rule set does not default to Deny
    - infrastructure (double) encryption is not enabled
    - the account uses Microsoft-managed keys instead of a customer-managed key

    The script is read-only and idempotent: it never mutates Azure state, so re-running
    it makes no changes. Exit codes: 0 = compliant; 2 = findings present; 1 = error
    (no Azure context, Az modules unavailable, unsafe -OutputPath, or an inventory
    query failed so the audit is incomplete).

    The checks follow the Microsoft hardening guidance at
    https://learn.microsoft.com/azure/storage/common/storage-security-guide and
    https://learn.microsoft.com/azure/storage/blobs/security-recommendations

.PARAMETER SubscriptionId
    Subscription ID to audit. Use '*' (the default) to audit every accessible
    subscription.

.PARAMETER ResourceGroupName
    Optional resource group name filter applied to the storage account query.

.PARAMETER OutputFormat
    Report format: 'Table' (console list), 'Json', or 'Csv'. Default: 'Table'.

.PARAMETER OutputPath
    Optional directory for the Json or Csv report. Must be a local absolute path
    without '..' traversal. When omitted, Json and Csv output is written to the
    console instead.

.EXAMPLE
    PS C:\> .\Get-AzureStorageAccountAudit.ps1 -SubscriptionId '*'
    Audits every accessible subscription and prints the finding table.

.EXAMPLE
    PS C:\> .\Get-AzureStorageAccountAudit.ps1 -SubscriptionId '00000000-0000-0000-0000-000000000001' `
        -ResourceGroupName 'rg-prod' -OutputFormat Json -OutputPath 'C:\Reports'
    Audits one resource group and writes a JSON report into C:\Reports.

.NOTES
    File Name   : Get-AzureStorageAccountAudit.ps1
    Author      : Bug-Free Umbrella
    Prerequisite: PowerShell 7.0
    Version     : 2.0.0
    Date        : 2026-09-16

    Cmdlet reference page:
    https://learn.microsoft.com/powershell/module/az.storage/get-azstorageaccount
#>
[CmdletBinding()]
param(
    [Parameter()][string]$SubscriptionId = '*',
    [Parameter()][string]$ResourceGroupName,
    [Parameter()][ValidateSet('Table', 'Json', 'Csv')][string]$OutputFormat = 'Table',
    [Parameter()][string]$OutputPath
)

$ErrorActionPreference = 'Stop'

function Get-AccountName {
    param([object]$Account)

    if ($Account.StorageAccountName) {
        return $Account.StorageAccountName
    }
    if ($Account.Id) {
        $segments = $Account.Id.TrimEnd('/').Split('/')
        return $segments[$segments.Count - 1]
    }
    return 'unknown'
}

function Test-WeakTlsVersion {
    param([string]$MinimumTlsVersion)

    if ([string]::IsNullOrWhiteSpace($MinimumTlsVersion)) {
        return $true
    }
    return (@('TLS1_2', 'TLS1_3') -notcontains $MinimumTlsVersion.ToUpperInvariant())
}

function Test-DefaultDenyRuleSet {
    param([object]$NetworkRuleSet)

    if (-not $NetworkRuleSet) {
        return $false
    }
    $action = $NetworkRuleSet.DefaultAction
    if (-not $action) {
        return $false
    }
    return ("$action" -eq 'Deny')
}

function Main {
    try {
        if (-not (Get-Command Get-AzContext -ErrorAction SilentlyContinue)) {
            throw "Az.Accounts is not available. Install-Module Az.Accounts"
        }

        Write-Host "[*] Checking Azure connection..." -ForegroundColor Cyan
        Import-Module Az.Accounts -ErrorAction Stop
        Import-Module Az.Storage -ErrorAction Stop

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
        $accountCount = 0
        $incomplete = $false

        foreach ($sub in $subscriptions) {
            Set-AzContext -SubscriptionId $sub.Id -ErrorAction Stop | Out-Null
            Write-Host "[*] Auditing subscription: $($sub.Name)" -ForegroundColor Cyan

            $accounts = @()
            try {
                $accounts = @(Get-AzStorageAccount @queryArgs -ErrorAction Stop)
            }
            catch {
                Write-Host "[!] Failed to read storage accounts: $($_.Exception.Message)" -ForegroundColor Yellow
                $incomplete = $true
            }

            $accountCount += $accounts.Count
            Write-Host "[+] Inventory: $($accounts.Count) storage account(s)" -ForegroundColor Green

            foreach ($account in $accounts) {
                $name = Get-AccountName -Account $account
                $resource = "$($account.ResourceGroupName)/$name"

                if ($account.AllowBlobPublicAccess -eq $true) {
                    $findings += [pscustomobject]@{
                        Severity     = 'High'
                        Category     = 'PublicBlobAccessEnabled'
                        Resource     = $resource
                        Details      = 'Anonymous public read access to containers and blobs is permitted'
                        Subscription = $sub.Name
                    }
                }

                if ($account.AllowSharedKeyAccess -ne $false) {
                    $findings += [pscustomobject]@{
                        Severity     = 'High'
                        Category     = 'SharedKeyAccessEnabled'
                        Resource     = $resource
                        Details      = 'Shared Key authorization is still permitted; require Microsoft Entra ID'
                        Subscription = $sub.Name
                    }
                }

                if (Test-WeakTlsVersion -MinimumTlsVersion $account.MinimumTlsVersion) {
                    $findings += [pscustomobject]@{
                        Severity     = 'Medium'
                        Category     = 'WeakMinimumTlsVersion'
                        Resource     = $resource
                        Details      = "Minimum TLS version is '$($account.MinimumTlsVersion)'; require 1.2+"
                        Subscription = $sub.Name
                    }
                }

                if (-not (Test-DefaultDenyRuleSet -NetworkRuleSet $account.NetworkRuleSet)) {
                    $findings += [pscustomobject]@{
                        Severity     = 'High'
                        Category     = 'NetworkDefaultAllow'
                        Resource     = $resource
                        Details      = 'Network rule set does not default to Deny; enable firewall rules'
                        Subscription = $sub.Name
                    }
                }

                $keySource = $null
                $infraEncryption = $null
                if ($account.Encryption) {
                    $keySource = $account.Encryption.KeySource
                    $infraEncryption = $account.Encryption.RequireInfrastructureEncryption
                }
                if ($infraEncryption -ne $true) {
                    $findings += [pscustomobject]@{
                        Severity     = 'Medium'
                        Category     = 'MissingInfrastructureEncryption'
                        Resource     = $resource
                        Details      = 'Infrastructure (double) encryption is not enabled'
                        Subscription = $sub.Name
                    }
                }
                if ($keySource -ne 'Microsoft.Keyvault') {
                    $findings += [pscustomobject]@{
                        Severity     = 'Medium'
                        Category     = 'MissingCustomerManagedKey'
                        Resource     = $resource
                        Details      = "Encryption key source is '$keySource'; use a customer-managed key"
                        Subscription = $sub.Name
                    }
                }
            }
        }

        Write-Host ""
        Write-Host "=== Azure Storage Account Audit ===" -ForegroundColor Cyan
        Write-Host "Subscriptions audited: $($subscriptions.Count)" -ForegroundColor White
        Write-Host "Storage accounts audited: $accountCount" -ForegroundColor White
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
                    GeneratedAt     = (Get-Date).ToString('s')
                    Subscriptions   = @($subscriptions | ForEach-Object { $_.Name })
                    AccountsAudited = $accountCount
                    Findings        = @($findings)
                }
                $json = ConvertTo-Json -InputObject $report -Depth 5
                if ($OutputPath) {
                    $jsonFile = Join-Path $OutputPath "Azure-StorageAccountAudit_$stamp.json"
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
                    $csvFile = Join-Path $OutputPath "Azure-StorageAccountAudit_$stamp.csv"
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
