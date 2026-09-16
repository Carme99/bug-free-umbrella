<#
.SYNOPSIS
    Reports Azure Storage blob lifecycle policy coverage per storage account.

.DESCRIPTION
    Read-only Azure Storage lifecycle report. For every selected subscription the script
    inventories storage accounts with Get-AzStorageAccount, reads each account's blob
    lifecycle management policy with Get-AzStorageAccountManagementPolicy, and reports,
    per account: whether a policy exists, how many rules it holds, how many of those
    rules are enabled, and which blob types and actions the rules cover.

    An account with no lifecycle policy is recorded as a gap, because lifecycle rules
    are what transition or expire blobs and keep storage cost and retention under
    control. Get-AzStorageAccountManagementPolicy surfaces a policy-less account as a
    not-found error rather than an empty result, so that error is classified as a gap
    and every other failure is reported as an incomplete run. The script is read-only
    and idempotent: it never mutates Azure state.
    Exit codes: 0 = every storage account has a lifecycle policy; 2 = one or more
    accounts have no lifecycle policy; 1 = error (no Azure context, Az modules
    unavailable, unsafe -OutputPath, or a query failed so the report is incomplete).

    Policy structure and rule semantics are documented at
    https://learn.microsoft.com/azure/storage/blobs/lifecycle-management-overview

.PARAMETER SubscriptionId
    Subscription ID to report on. Use '*' (the default) to cover every accessible
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
    PS C:\> .\Get-AzureStorageLifecycleReport.ps1 -SubscriptionId '*'
    Reports lifecycle coverage for every storage account in every subscription.

.EXAMPLE
    PS C:\> .\Get-AzureStorageLifecycleReport.ps1 -SubscriptionId '00000000-0000-0000-0000-000000000001' `
        -ResourceGroupName 'rg-prod' -OutputFormat Csv -OutputPath 'C:\Reports'
    Writes a CSV of the lifecycle coverage for one resource group into C:\Reports.

.NOTES
    File Name   : Get-AzureStorageLifecycleReport.ps1
    Author      : Bug-Free Umbrella
    Prerequisite: PowerShell 7.0
    Version     : 2.0.0
    Date        : 2026-09-16

    Cmdlet reference pages:
    https://learn.microsoft.com/powershell/module/az.storage/get-azstorageaccount
    https://learn.microsoft.com/powershell/module/az.storage/get-azstorageaccountmanagementpolicy
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

function ConvertTo-LifecycleRuleList {
    param([object]$Policy)

    if (-not $Policy) {
        return @()
    }
    $rules = $Policy.Rules
    if ($null -eq $rules) {
        return @()
    }
    if ($rules -is [string]) {
        if ([string]::IsNullOrWhiteSpace($rules)) {
            return @()
        }
        $rules = ConvertFrom-Json -InputObject $rules -ErrorAction Stop
    }
    return @($rules)
}

function Get-RuleBlobTypes {
    param([object]$Rule)

    if (-not $Rule -or -not $Rule.Definition -or -not $Rule.Definition.Filters) {
        return @()
    }
    return @($Rule.Definition.Filters.BlobTypes)
}

function Get-RuleActions {
    param([object]$Rule)

    $actions = @()
    if (-not $Rule -or -not $Rule.Definition -or -not $Rule.Definition.Actions) {
        return $actions
    }
    foreach ($scope in @('BaseBlob', 'Snapshot', 'Version')) {
        $scopeNode = $Rule.Definition.Actions.$scope
        if (-not $scopeNode) {
            continue
        }
        foreach ($property in $scopeNode.PSObject.Properties) {
            if ($null -ne $property.Value) {
                $actions += "$scope/$($property.Name)"
            }
        }
    }
    return $actions
}

function Get-LifecycleErrorText {
    param([object]$ErrorRecord)

    $text = "$($ErrorRecord.Exception.Message)"
    $body = $ErrorRecord.Exception.Body
    if ($body -and $body.Code) {
        $text = "$text $($body.Code)"
    }
    $response = $ErrorRecord.Exception.Response
    if ($response -and $response.StatusCode) {
        $text = "$text $($response.StatusCode)"
    }
    return $text
}

function Test-MissingPolicyError {
    param([string]$ErrorText)

    if ([string]::IsNullOrWhiteSpace($ErrorText)) {
        return $false
    }
    return ($ErrorText -match '(?i)ManagementPolicyNotFound|not found|404|NotFoundException')
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
        Write-Host "[*] Reporting on $($subscriptions.Count) subscription(s)..." -ForegroundColor Cyan

        $queryArgs = @{}
        if ($ResourceGroupName) {
            $queryArgs['ResourceGroupName'] = $ResourceGroupName
        }

        $rows = @()
        $findings = @()
        $accountCount = 0
        $coveredCount = 0
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

                $policy = $null
                $policyMissing = $false
                try {
                    $policy = Get-AzStorageAccountManagementPolicy `
                        -ResourceGroupName $account.ResourceGroupName `
                        -StorageAccountName $name -ErrorAction Stop
                }
                catch {
                    $errorText = Get-LifecycleErrorText -ErrorRecord $_
                    if (Test-MissingPolicyError -ErrorText $errorText) {
                        $policyMissing = $true
                    }
                    else {
                        Write-Host "[!] Failed to read lifecycle policy for ${resource}: $errorText" `
                            -ForegroundColor Yellow
                        $incomplete = $true
                        continue
                    }
                }

                if ($policyMissing -or -not $policy) {
                    $findings += [pscustomobject]@{
                        Severity     = 'Medium'
                        Category     = 'MissingLifecyclePolicy'
                        Resource     = $resource
                        Details      = 'Storage account has no blob lifecycle management policy'
                        Subscription = $sub.Name
                    }
                    Write-Host "[!] ${resource}: no lifecycle policy" -ForegroundColor Yellow
                    continue
                }

                $rules = @()
                try {
                    $rules = ConvertTo-LifecycleRuleList -Policy $policy
                }
                catch {
                    Write-Host "[!] Failed to parse lifecycle policy for ${resource}: $($_.Exception.Message)" `
                        -ForegroundColor Yellow
                    $incomplete = $true
                    continue
                }

                $blobTypes = @()
                $actions = @()
                $enabledRules = 0
                foreach ($rule in $rules) {
                    if ($rule.Enabled -eq $true) {
                        $enabledRules++
                    }
                    $blobTypes += @(Get-RuleBlobTypes -Rule $rule)
                    $actions += @(Get-RuleActions -Rule $rule)
                }
                $blobTypeList = @($blobTypes | Where-Object { $_ } | Sort-Object -Unique)
                $actionList = @($actions | Sort-Object -Unique)
                $coveredCount++

                $typeText = '(none)'
                if ($blobTypeList.Count -gt 0) {
                    $typeText = $blobTypeList -join ', '
                }
                $actionText = '(none)'
                if ($actionList.Count -gt 0) {
                    $actionText = $actionList -join ', '
                }

                $rows += [pscustomobject]@{
                    Subscription      = $sub.Name
                    ResourceGroup     = $account.ResourceGroupName
                    Account           = $name
                    Resource          = $resource
                    PolicyId          = $policy.Id
                    Rules             = $rules.Count
                    EnabledRules      = $enabledRules
                    BlobTypes         = ($blobTypeList -join ';')
                    Actions           = ($actionList -join ';')
                }

                Write-Host ("[+] {0}: {1} rule(s), {2} enabled" -f $resource, $rules.Count, $enabledRules) `
                    -ForegroundColor Green
                Write-Host "    blob types: $typeText"
                Write-Host "    actions: $actionText"
            }
        }

        Write-Host ""
        Write-Host "=== Azure Storage Lifecycle Report ===" -ForegroundColor Cyan
        Write-Host "Subscriptions reported: $($subscriptions.Count)" -ForegroundColor White
        Write-Host "Storage accounts audited: $accountCount" -ForegroundColor White
        Write-Host "Accounts with a lifecycle policy: $coveredCount" -ForegroundColor White
        Write-Host "Gaps: $($findings.Count)" -ForegroundColor White

        $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'

        switch ($OutputFormat) {
            'Table' {
                foreach ($finding in $findings) {
                    Write-Host ("  [{0}] {1}" -f $finding.Severity, $finding.Category) -ForegroundColor Gray
                    Write-Host ("      {0}: {1}" -f $finding.Resource, $finding.Details)
                }
            }
            'Json' {
                $report = [pscustomobject]@{
                    GeneratedAt        = (Get-Date).ToString('s')
                    Subscriptions      = @($subscriptions | ForEach-Object { $_.Name })
                    AccountsAudited    = $accountCount
                    AccountsWithPolicy = $coveredCount
                    Coverage           = @($rows)
                    Findings           = @($findings)
                }
                $json = ConvertTo-Json -InputObject $report -Depth 5
                if ($OutputPath) {
                    $jsonFile = Join-Path $OutputPath "Azure-StorageLifecycleReport_$stamp.json"
                    Set-Content -LiteralPath $jsonFile -Value $json -Encoding utf8
                    Write-Host "[+] JSON report written: $jsonFile" -ForegroundColor Green
                }
                else {
                    Write-Host $json
                }
            }
            'Csv' {
                if ($rows.Count -eq 0) {
                    Write-Host "[+] No lifecycle coverage rows to export." -ForegroundColor Green
                }
                elseif ($OutputPath) {
                    $csvFile = Join-Path $OutputPath "Azure-StorageLifecycleReport_$stamp.csv"
                    $rows | Export-Csv -LiteralPath $csvFile -NoTypeInformation -Encoding utf8
                    Write-Host "[+] CSV report written: $csvFile" -ForegroundColor Green
                }
                else {
                    $rows | ConvertTo-Csv -NoTypeInformation | ForEach-Object { Write-Host $_ }
                }
            }
        }

        if ($incomplete) {
            Write-Host "[!] Report incomplete: one or more lifecycle queries failed." -ForegroundColor Yellow
            return 1
        }
        if ($findings.Count -gt 0) {
            Write-Host "[!] Lifecycle gaps: $($findings.Count) storage account(s) have no policy." `
                -ForegroundColor Yellow
            return 2
        }

        Write-Host "[+] Lifecycle coverage: every storage account has a lifecycle policy." -ForegroundColor Green
        return 0
    }
    catch {
        Write-Host "[-] Error: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
