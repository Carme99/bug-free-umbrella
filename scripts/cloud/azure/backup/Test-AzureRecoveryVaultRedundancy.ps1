<#
.SYNOPSIS
    Audits Recovery Services vault storage redundancy and cross-region-restore state.

.DESCRIPTION
    Read-only audit of every Recovery Services vault in one Azure subscription, or in every subscription
    the signed-in account can read. For each vault the script reads the backup storage redundancy type
    and the cross-region-restore setting with Get-AzRecoveryServicesBackupProperty, the cmdlet documented
    at
    https://learn.microsoft.com/en-us/powershell/module/az.recoveryservices/get-azrecoveryservicesbackupproperty
    and compares the reported redundancy against -MinimumRedundancy.

    Redundancy tiers are ranked by the outage scenarios they survive, as tabulated under "Durability and
    availability by outage scenario" at
    https://learn.microsoft.com/en-us/azure/storage/common/storage-redundancy :
    LocallyRedundant (1) < ZoneRedundant (2) < GeoRedundant (3) < GeoZoneRedundant (4).
    Recovery Services vaults report LocallyRedundant, ZoneRedundant or GeoRedundant; GeoZoneRedundant is
    accepted here so the same threshold can be applied to geo-zone-redundant backup storage. A vault that
    reports a type the script does not recognise is treated as below the minimum, because compliance
    cannot be proven. The vault redundancy and cross-region-restore settings audited here are described at
    https://learn.microsoft.com/en-us/azure/backup/backup-azure-recovery-services-vault-overview and
    https://learn.microsoft.com/en-us/azure/backup/backup-create-recovery-services-vault .

    With -IncludeCrossRegionRestore the audit additionally reports geo-redundant vaults whose
    CrossRegionRestore setting is off: cross-region restore is supported only on geo-redundant vaults and
    enables restore in the Azure paired region for audit and disaster-recovery drills.

    The script never mutates Azure resources, so re-running it against an unchanged environment produces
    the same report and the same exit code. For -OutputFormat Json or Csv it writes one uniquely named
    report file under -OutputPath.
    Exit codes: 0 = every audited vault meets the minimum redundancy; 2 = findings detected;
    1 = error (missing Az module, not signed in, or an unsafe -OutputPath).

.PARAMETER SubscriptionId
    Subscription ID to audit, or '*' to audit every subscription the signed-in account can read.
    Default: '*'.

.PARAMETER MinimumRedundancy
    Lowest storage redundancy tier a vault may use: 'LocallyRedundant', 'ZoneRedundant', 'GeoRedundant' or
    'GeoZoneRedundant'. Default: 'GeoRedundant'.

.PARAMETER IncludeCrossRegionRestore
    Also flag geo-redundant vaults that do not have cross-region restore enabled.

.PARAMETER OutputFormat
    Report format: 'Table' prints the report to the console only, while 'Json' and 'Csv' also write a
    report file under -OutputPath. Default: 'Table'.

.PARAMETER OutputPath
    Local directory that receives the JSON/CSV report file. Must be a local path without '..' traversal.
    Default: MyDocuments\Reports.

.EXAMPLE
    PS C:\> .\Test-AzureRecoveryVaultRedundancy.ps1
    Reports the storage redundancy of every vault in every readable subscription and flags any vault that
    is not geo-redundant.

.EXAMPLE
    PS C:\> .\Test-AzureRecoveryVaultRedundancy.ps1 -SubscriptionId "00000000-0000-0000-0000-000000000000" `
        -MinimumRedundancy ZoneRedundant -IncludeCrossRegionRestore -OutputFormat Csv -OutputPath C:\Reports
    Requires at least zone-redundant storage, also flags geo-redundant vaults without cross-region
    restore, and writes a timestamped CSV report to C:\Reports.

.NOTES
    File Name   : Test-AzureRecoveryVaultRedundancy.ps1
    Author      : Bug-Free Umbrella
    Prerequisite: PowerShell 7.0
    Version     : 2.0.0
    Date        : 2026-09-16

    The redundancy and cross-region-restore settings are read with Get-AzRecoveryServicesBackupProperty,
    which returns BackupStorageRedundancy and CrossRegionRestore:
    https://learn.microsoft.com/en-us/powershell/module/az.recoveryservices/get-azrecoveryservicesbackupproperty
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
    Justification = 'The script spec mandates Write-Host status output with [+]/[!]/[-]/[*] prefixes.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '',
    Justification = 'Script parameters are consumed by Main through the caller scope; see the help.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
    Justification = 'Only creates fresh timestamped report files; never mutates Azure state.')]
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$SubscriptionId = '*',

    [Parameter(Mandatory = $false)]
    [ValidateSet('GeoRedundant', 'ZoneRedundant', 'LocallyRedundant', 'GeoZoneRedundant')]
    [string]$MinimumRedundancy = 'GeoRedundant',

    [Parameter(Mandatory = $false)]
    [switch]$IncludeCrossRegionRestore,

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

function Get-RedundancyRank {
    <#
    .SYNOPSIS
        Returns the durability rank of a backup storage redundancy type, or 0 when it is unrecognised.
    #>
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Redundancy
    )

    switch ($Redundancy) {
        'LocallyRedundant' { return 1 }
        'ZoneRedundant' { return 2 }
        'GeoRedundant' { return 3 }
        'GeoZoneRedundant' { return 4 }
        default { return 0 }
    }
}

function ConvertTo-CrossRegionRestoreState {
    <#
    .SYNOPSIS
        Normalises a vault CrossRegionRestore setting into a boolean.
    #>
    param(
        [Parameter(Mandatory = $false)][AllowNull()][object]$Value
    )

    if ($null -eq $Value) { return $false }
    if ($Value -is [bool]) { return [bool]$Value }
    return ([string]$Value -in @('Enabled', 'True', 'true', '1'))
}

function Main {
    <#
    .SYNOPSIS
        Runs the vault redundancy audit and returns the documented exit code.
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

        $minimumRank = Get-RedundancyRank -Redundancy $MinimumRedundancy
        $vaultReports = @()
        $findings = @()

        foreach ($subscription in $subscriptions) {
            Write-Host "[*] Auditing subscription: $($subscription.Name)" -ForegroundColor Cyan
            Set-AzContext -SubscriptionId $subscription.Id -ErrorAction Stop | Out-Null

            try {
                $vaults = @(Get-AzRecoveryServicesVault -ErrorAction Stop)
            }
            catch {
                Write-Host "[!] Failed to list Recovery Services vaults: $($_.Exception.Message)" `
                    -ForegroundColor Yellow
                $vaults = @()
            }

            if ($vaults.Count -eq 0) {
                Write-Host "[!] No Recovery Services vaults found in '$($subscription.Name)'." `
                    -ForegroundColor Yellow
            }

            foreach ($vault in $vaults) {
                try {
                    $property = Get-AzRecoveryServicesBackupProperty -Vault $vault -ErrorAction Stop
                }
                catch {
                    Write-Host "[!] Failed to read the backup properties of '$($vault.Name)':" `
                        "$($_.Exception.Message)" -ForegroundColor Yellow
                    continue
                }

                $redundancy = [string]$property.BackupStorageRedundancy
                $crossRegionRestore = ConvertTo-CrossRegionRestoreState -Value $property.CrossRegionRestore
                $rank = Get-RedundancyRank -Redundancy $redundancy
                $meetsMinimum = ($rank -gt 0) -and ($rank -ge $minimumRank)

                if (-not $meetsMinimum) {
                    $detail = "Storage redundancy '$redundancy' is below the minimum '$MinimumRedundancy'."
                    if ($rank -eq 0) {
                        $detail = "Storage redundancy '$redundancy' is not recognised, so compliance" +
                            ' cannot be proven.'
                    }
                    $findings += [pscustomobject]@{
                        Category     = 'BelowMinimumRedundancy'
                        Subscription = [string]$subscription.Name
                        Vault        = [string]$vault.Name
                        Redundancy   = $redundancy
                        Detail       = $detail
                    }
                }

                $isGeoRedundant = $redundancy -in @('GeoRedundant', 'GeoZoneRedundant')
                if ($IncludeCrossRegionRestore -and $isGeoRedundant -and (-not $crossRegionRestore)) {
                    $findings += [pscustomobject]@{
                        Category     = 'CrossRegionRestoreDisabled'
                        Subscription = [string]$subscription.Name
                        Vault        = [string]$vault.Name
                        Redundancy   = $redundancy
                        Detail       = 'Cross-region restore is not enabled on this geo-redundant vault.'
                    }
                }

                $crossRegionText = 'Disabled'
                if ($crossRegionRestore) { $crossRegionText = 'Enabled' }

                $vaultReports += [pscustomobject]@{
                    Subscription       = [string]$subscription.Name
                    Vault              = [string]$vault.Name
                    ResourceGroup      = [string]$vault.ResourceGroupName
                    Redundancy         = $redundancy
                    CrossRegionRestore = $crossRegionText
                    MeetsMinimum       = $meetsMinimum
                }

                Write-Host ("[*]   " + $vault.Name + " : " + $redundancy +
                    " (cross-region restore: " + $crossRegionText + ")") -ForegroundColor Gray
            }
        }

        $belowMinimum = @($findings | Where-Object { $_.Category -eq 'BelowMinimumRedundancy' })
        $crrDisabled = @($findings | Where-Object { $_.Category -eq 'CrossRegionRestoreDisabled' })

        Write-Host ''
        Write-Host '=== Azure Recovery Services vault redundancy report ===' -ForegroundColor Cyan
        Write-Host "Subscriptions     : $($subscriptions.Count)"
        Write-Host "Vaults audited    : $($vaultReports.Count)"
        Write-Host "Minimum redundancy: $MinimumRedundancy"

        if ($belowMinimum.Count -gt 0) {
            $belowMinimumCount = $belowMinimum.Count
            $belowMinimumNotice = "[!] $belowMinimumCount vault(s) are below the minimum '$MinimumRedundancy'."
            Write-Host $belowMinimumNotice -ForegroundColor Yellow
        }
        if ($crrDisabled.Count -gt 0) {
            Write-Host "[!] $($crrDisabled.Count) vault(s) do not have cross-region restore enabled." `
                -ForegroundColor Yellow
        }

        if ($OutputFormat -ne 'Table') {
            if (-not (Test-Path -LiteralPath $resolvedOutputPath -PathType Container)) {
                New-Item -ItemType Directory -Path $resolvedOutputPath -Force -ErrorAction Stop | Out-Null
            }
            $timestamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
            $report = [pscustomobject]@{
                GeneratedAt       = (Get-Date).ToString('o')
                SubscriptionId    = $SubscriptionId
                MinimumRedundancy = $MinimumRedundancy
                Vaults            = $vaultReports
                Findings          = $findings
            }

            if ($OutputFormat -eq 'Json') {
                $reportPath = Join-Path -Path $resolvedOutputPath `
                    -ChildPath "AzureVaultRedundancy-$timestamp.json"
                $report | ConvertTo-Json -Depth 6 |
                    Set-Content -LiteralPath $reportPath -Encoding utf8 -ErrorAction Stop
            }
            else {
                $reportPath = Join-Path -Path $resolvedOutputPath `
                    -ChildPath "AzureVaultRedundancy-$timestamp.csv"
                if ($vaultReports.Count -gt 0) {
                    $vaultReports | Export-Csv -LiteralPath $reportPath -NoTypeInformation -Encoding utf8 `
                        -ErrorAction Stop
                }
                else {
                    Set-Content -LiteralPath $reportPath -Encoding utf8 -ErrorAction Stop `
                        -Value 'Subscription,Vault,ResourceGroup,Redundancy,CrossRegionRestore,MeetsMinimum'
                }
            }
            Write-Host "[+] Report written to: $reportPath" -ForegroundColor Green
        }

        if ($findings.Count -gt 0) {
            Write-Host "[!] $($findings.Count) redundancy finding(s) detected." -ForegroundColor Yellow
            return 2
        }

        Write-Host "[+] All vaults meet the minimum redundancy of $MinimumRedundancy." -ForegroundColor Green
        return 0
    }
    catch {
        Write-Host "[-] Error: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
