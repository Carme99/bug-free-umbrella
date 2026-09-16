<#
.SYNOPSIS
    Reports Azure Backup compliance: unprotected VMs, stale backups, failed jobs, vaults without soft delete.

.DESCRIPTION
    Read-only Azure Backup compliance report for one Azure subscription or for every subscription the
    signed-in account can read. The report combines the Recovery Services vault inventory
    (Get-AzRecoveryServicesVault), the protected items of each vault (Get-AzRecoveryServicesBackupItem),
    the failed backup jobs of each vault (Get-AzRecoveryServicesBackupJob), the virtual machine
    inventory (Get-AzVM), and the vault soft delete state (Get-AzRecoveryServicesVaultProperty).
    The Azure Backup service these cmdlets drive is described at
    https://learn.microsoft.com/en-us/azure/backup/backup-overview and
    https://learn.microsoft.com/en-us/azure/backup/backup-azure-recovery-services-vault-overview ;
    the reference for the protected-item query is
    https://learn.microsoft.com/en-us/powershell/module/az.recoveryservices/get-azrecoveryservicesbackupitem

    Four finding categories are reported:
    - UnprotectedVM   : a virtual machine in the subscription that is not a protected item in any
      Recovery Services vault the script read;
    - StaleBackup     : a protected item whose last successful backup (LastBackupTime) is older than
      -StaleBackupDays, or that has no successful backup at all;
    - FailedJob       : a backup job reported with status Failed inside the -StaleBackupDays window;
    - SoftDeleteDisabled : a vault whose soft delete state is neither 'Enabled' nor 'AlwaysON'. A vault
      whose soft delete state cannot be read is reported as a warning, not as a finding.

    The script never mutates Azure resources, so re-running it against an unchanged environment produces
    the same report and the same exit code. For -OutputFormat Json or Csv it writes one uniquely named
    report file under -OutputPath.
    Exit codes: 0 = report produced and no findings; 2 = report produced and findings detected;
    1 = error (missing Az module, not signed in, or an unsafe -OutputPath).

.PARAMETER SubscriptionId
    Subscription ID to audit, or '*' to audit every subscription the signed-in account can read.
    Default: '*'.

.PARAMETER ResourceGroupName
    Audit only vaults (and virtual machines) in this resource group, or '*' for every resource group.
    Default: '*'.

.PARAMETER VaultName
    Audit only the vault with this exact name, or '*' for every vault. Default: '*'. When this filter is
    used the UnprotectedVM check is skipped, because a VM protected in a vault that was filtered out
    would otherwise be reported as unprotected.

.PARAMETER StaleBackupDays
    Number of days a protected item may go without a successful backup before it is reported as
    StaleBackup; also the lookback window for failed backup jobs (1-365). Default: 7.

.PARAMETER OutputFormat
    Report format: 'Table' prints the report to the console only, while 'Json' and 'Csv' also write a
    report file under -OutputPath. Default: 'Table'.

.PARAMETER OutputPath
    Local directory that receives the JSON/CSV report file. Must be a local path without '..' traversal.
    Default: MyDocuments\Reports.

.EXAMPLE
    PS C:\> .\Get-AzureBackupComplianceReport.ps1
    Audits every readable subscription with the default 7 day staleness threshold and prints the
    unprotected VMs, stale protected items, failed backup jobs and vaults without soft delete.

.EXAMPLE
    PS C:\> .\Get-AzureBackupComplianceReport.ps1 -SubscriptionId "*" -VaultName "rsv-prod" `
        -StaleBackupDays 14 -OutputFormat Json -OutputPath C:\Reports
    Audits only the vault named rsv-prod, treats a backup older than 14 days as stale, and writes a
    timestamped JSON report to C:\Reports.

.NOTES
    File Name   : Get-AzureBackupComplianceReport.ps1
    Author      : Bug-Free Umbrella
    Prerequisite: PowerShell 7.0
    Version     : 2.0.0
    Date        : 2026-09-16

    Soft delete semantics of the SoftDeleteDisabled check:
    https://learn.microsoft.com/en-us/azure/backup/secure-by-default
    Vault soft delete state is read with Get-AzRecoveryServicesVaultProperty:
    https://learn.microsoft.com/en-us/powershell/module/az.recoveryservices/get-azrecoveryservicesvaultproperty
    Failed backup jobs are queried exactly as documented for Get-AzRecoveryServicesBackupJob:
    https://learn.microsoft.com/en-us/powershell/module/az.recoveryservices/get-azrecoveryservicesbackupjob
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
    [ValidateNotNullOrEmpty()]
    [string]$VaultName = '*',

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 365)]
    [int]$StaleBackupDays = 7,

    [Parameter(Mandatory = $false)]
    [ValidateSet('Table', 'Json', 'Csv')]
    [string]$OutputFormat = 'Table',

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$OutputPath = (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Reports')
)

$ErrorActionPreference = 'Stop'

function Test-BackupItemMatchesVm {
    <#
    .SYNOPSIS
        Returns $true when a protected backup item is the protected item of the given VM name.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$VmName,
        [Parameter(Mandatory = $true)][AllowNull()][object]$Item
    )

    if ([string]$Item.FriendlyName -eq $VmName) { return $true }
    $containerName = [string]$Item.ContainerName
    if (-not [string]::IsNullOrWhiteSpace($containerName) -and
        $containerName -match "[;/]$([regex]::Escape($VmName))$") {
        return $true
    }
    return $false
}

function Get-StaleBackupAgeDays {
    <#
    .SYNOPSIS
        Returns the age in whole days of a protected item's last successful backup, or -1 when none.
    #>
    param(
        [Parameter(Mandatory = $true)][AllowNull()][object]$LastBackupTime
    )

    if ($null -eq $LastBackupTime) { return -1 }
    $lastBackup = [datetime]$LastBackupTime
    return [int](((Get-Date).ToUniversalTime() - $lastBackup.ToUniversalTime()).TotalDays)
}

function Main {
    <#
    .SYNOPSIS
        Runs the Azure Backup compliance report and returns the documented exit code.
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
        Import-Module Az.RecoveryServices -ErrorAction Stop
        Import-Module Az.Compute -ErrorAction Stop
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

        $filterResourceGroup = (-not [string]::IsNullOrWhiteSpace($ResourceGroupName)) -and
            ($ResourceGroupName -ne '*')
        $filterVaultName = (-not [string]::IsNullOrWhiteSpace($VaultName)) -and ($VaultName -ne '*')

        $findings = @()
        $vaultReports = @()
        $protectedItemCount = 0

        foreach ($subscription in $subscriptions) {
            Write-Host "[*] Auditing subscription: $($subscription.Name)" -ForegroundColor Cyan
            Set-AzContext -SubscriptionId $subscription.Id -ErrorAction Stop | Out-Null

            try {
                if ($filterResourceGroup) {
                    $vaults = @(Get-AzRecoveryServicesVault -ResourceGroupName $ResourceGroupName `
                            -ErrorAction Stop)
                }
                else {
                    $vaults = @(Get-AzRecoveryServicesVault -ErrorAction Stop)
                }
            }
            catch {
                Write-Host "[!] Failed to list Recovery Services vaults: $($_.Exception.Message)" `
                    -ForegroundColor Yellow
                $vaults = @()
            }

            if ($filterVaultName) {
                $vaults = @($vaults | Where-Object { [string]$_.Name -eq $VaultName })
            }

            if ($vaults.Count -eq 0) {
                Write-Host "[!] No Recovery Services vault matched the filters in '$($subscription.Name)'." `
                    -ForegroundColor Yellow
            }

            $vms = @()
            if ($filterVaultName) {
                $unprotectedCheckSkipped = 'the UnprotectedVM check is skipped because only one vault is audited.'
                Write-Host "[!] Vault filter active: $unprotectedCheckSkipped" -ForegroundColor Yellow
            }
            else {
                try {
                    if ($filterResourceGroup) {
                        $vms = @(Get-AzVM -ResourceGroupName $ResourceGroupName -ErrorAction Stop)
                    }
                    else {
                        $vms = @(Get-AzVM -ErrorAction Stop)
                    }
                }
                catch {
                    Write-Host "[!] Failed to list virtual machines: $($_.Exception.Message)" `
                        -ForegroundColor Yellow
                    $vms = @()
                }
            }

            $subscriptionItems = @()

            foreach ($vault in $vaults) {
                Write-Host "[*]   Vault: $($vault.Name)" -ForegroundColor Gray

                $softDeleteState = ''
                try {
                    $vaultProperty = Get-AzRecoveryServicesVaultProperty -VaultId $vault.Id -ErrorAction Stop
                    $softDeleteState = [string]$vaultProperty.SoftDeleteFeatureState
                }
                catch {
                    Write-Host "[!]   Could not read the soft delete state of '$($vault.Name)':" `
                        "$($_.Exception.Message)" -ForegroundColor Yellow
                }

                if ((-not [string]::IsNullOrWhiteSpace($softDeleteState)) -and
                    ($softDeleteState -notin @('Enabled', 'AlwaysON'))) {
                    $findings += [pscustomobject]@{
                        Category     = 'SoftDeleteDisabled'
                        Subscription = [string]$subscription.Name
                        Vault        = [string]$vault.Name
                        Target       = [string]$vault.Name
                        Detail       = "Vault soft delete state is '$softDeleteState'."
                    }
                }

                $vaultReports += [pscustomobject]@{
                    Subscription    = [string]$subscription.Name
                    Vault           = [string]$vault.Name
                    ResourceGroup   = [string]$vault.ResourceGroupName
                    SoftDeleteState = $softDeleteState
                }

                try {
                    $items = @(Get-AzRecoveryServicesBackupItem -VaultId $vault.Id `
                            -BackupManagementType AzureVM -WorkloadType AzureVM -ErrorAction Stop)
                }
                catch {
                    Write-Host "[!]   Failed to list backup items for '$($vault.Name)':" `
                        "$($_.Exception.Message)" -ForegroundColor Yellow
                    $items = @()
                }

                foreach ($item in $items) {
                    $protectedItemCount = $protectedItemCount + 1
                    $subscriptionItems += $item

                    $ageDays = Get-StaleBackupAgeDays -LastBackupTime $item.LastBackupTime
                    if (($ageDays -lt 0) -or ($ageDays -gt $StaleBackupDays)) {
                        $ageText = 'no successful backup'
                        if ($ageDays -ge 0) { $ageText = "$ageDays day(s) old" }
                        $findings += [pscustomobject]@{
                            Category     = 'StaleBackup'
                            Subscription = [string]$subscription.Name
                            Vault        = [string]$vault.Name
                            Target       = [string]$item.FriendlyName
                            Detail       = "Last successful backup is $ageText (threshold $StaleBackupDays day(s))."
                        }
                    }
                }

                try {
                    $jobFrom = (Get-Date).AddDays(-1 * $StaleBackupDays).ToUniversalTime()
                    $failedJobs = @(Get-AzRecoveryServicesBackupJob -VaultId $vault.Id -Status Failed `
                            -From $jobFrom -ErrorAction Stop)
                }
                catch {
                    Write-Host "[!]   Failed to list backup jobs for '$($vault.Name)':" `
                        "$($_.Exception.Message)" -ForegroundColor Yellow
                    $failedJobs = @()
                }

                foreach ($job in $failedJobs) {
                    $findings += [pscustomobject]@{
                        Category     = 'FailedJob'
                        Subscription = [string]$subscription.Name
                        Vault        = [string]$vault.Name
                        Target       = [string]$job.JobId
                        Detail       = "Backup job for '$($job.WorkloadName)' has status 'Failed'."
                    }
                }
            }

            foreach ($vm in $vms) {
                $isProtected = $false
                foreach ($item in $subscriptionItems) {
                    if (Test-BackupItemMatchesVm -VmName ([string]$vm.Name) -Item $item) {
                        $isProtected = $true
                        break
                    }
                }
                if (-not $isProtected) {
                    $findings += [pscustomobject]@{
                        Category     = 'UnprotectedVM'
                        Subscription = [string]$subscription.Name
                        Vault        = ''
                        Target       = [string]$vm.Name
                        Detail       = "Virtual machine '$($vm.Name)' has no protected item in any vault."
                    }
                }
            }
        }

        $unprotectedVms = @($findings | Where-Object { $_.Category -eq 'UnprotectedVM' })
        $staleBackups = @($findings | Where-Object { $_.Category -eq 'StaleBackup' })
        $failedJobs = @($findings | Where-Object { $_.Category -eq 'FailedJob' })
        $softDeleteDisabled = @($findings | Where-Object { $_.Category -eq 'SoftDeleteDisabled' })

        Write-Host ''
        Write-Host '=== Azure Backup compliance report ===' -ForegroundColor Cyan
        Write-Host "Subscriptions  : $($subscriptions.Count)"
        Write-Host "Vaults audited : $($vaultReports.Count)"
        Write-Host "Protected items: $protectedItemCount"
        Write-Host "Stale threshold: $StaleBackupDays day(s)"

        if ($unprotectedVms.Count -gt 0) {
            Write-Host "[!] $($unprotectedVms.Count) virtual machine(s) have no backup protection." `
                -ForegroundColor Yellow
        }
        if ($staleBackups.Count -gt 0) {
            Write-Host "[!] $($staleBackups.Count) protected item(s) are older than $StaleBackupDays day(s)." `
                -ForegroundColor Yellow
        }
        if ($failedJobs.Count -gt 0) {
            Write-Host "[!] $($failedJobs.Count) backup job(s) failed in the last $StaleBackupDays day(s)." `
                -ForegroundColor Yellow
        }
        if ($softDeleteDisabled.Count -gt 0) {
            Write-Host "[!] $($softDeleteDisabled.Count) vault(s) do not have soft delete enabled." `
                -ForegroundColor Yellow
        }

        if ($OutputFormat -ne 'Table') {
            if (-not (Test-Path -LiteralPath $resolvedOutputPath -PathType Container)) {
                New-Item -ItemType Directory -Path $resolvedOutputPath -Force -ErrorAction Stop | Out-Null
            }
            $timestamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
            $report = [pscustomobject]@{
                GeneratedAt        = (Get-Date).ToString('o')
                SubscriptionId     = $SubscriptionId
                StaleBackupDays    = $StaleBackupDays
                ProtectedItemCount = $protectedItemCount
                Vaults             = $vaultReports
                Findings           = $findings
            }

            if ($OutputFormat -eq 'Json') {
                $reportPath = Join-Path -Path $resolvedOutputPath `
                    -ChildPath "AzureBackupCompliance-$timestamp.json"
                $report | ConvertTo-Json -Depth 6 |
                    Set-Content -LiteralPath $reportPath -Encoding utf8 -ErrorAction Stop
            }
            else {
                $reportPath = Join-Path -Path $resolvedOutputPath `
                    -ChildPath "AzureBackupCompliance-$timestamp.csv"
                if ($findings.Count -gt 0) {
                    $findings | Export-Csv -LiteralPath $reportPath -NoTypeInformation -Encoding utf8 `
                        -ErrorAction Stop
                }
                else {
                    Set-Content -LiteralPath $reportPath -Encoding utf8 -ErrorAction Stop `
                        -Value 'Category,Subscription,Vault,Target,Detail'
                }
            }
            Write-Host "[+] Report written to: $reportPath" -ForegroundColor Green
        }

        if ($findings.Count -gt 0) {
            Write-Host "[!] $($findings.Count) backup compliance finding(s) detected." -ForegroundColor Yellow
            return 2
        }

        Write-Host '[+] No backup compliance findings detected.' -ForegroundColor Green
        return 0
    }
    catch {
        Write-Host "[-] Error: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
