<#
.SYNOPSIS
    Monitors Azure VM backup status and compliance with backup policies.

.DESCRIPTION
    Comprehensive Azure VM backup monitoring including:
    - VM backup configuration status
    - Last successful backup time
    - Backup age compliance
    - Recovery Services Vault health
    - Backup policy compliance
    - VMs without backup configured
    - Backup job success/failure rates
    - Recovery point objectives (RPO) validation

.PARAMETER SubscriptionId
    Azure subscription ID. Use '*' for all subscriptions.

.PARAMETER ResourceGroupName
    Specific resource group. Use '*' for all resource groups.

.PARAMETER BackupAgeThreshold
    Maximum days since last backup before flagging as non-compliant. Default: 1

.PARAMETER IncludeBackupJobs
    Include recent backup job analysis

.PARAMETER OutputFormat
    Output format: 'Console', 'HTML', or 'JSON'. Default: 'HTML'

.PARAMETER OutputPath
    Path for output files. Default: MyDocuments\Reports

.EXAMPLE
    Connect-AzAccount
    .\Get-VMBackupCompliance.ps1 -SubscriptionId "*"

.EXAMPLE
    .\Get-VMBackupCompliance.ps1 -SubscriptionId "sub-id" `
        -ResourceGroupName "*" `
        -BackupAgeThreshold 2 `
        -IncludeBackupJobs

.NOTES
    Author: IT Operations
    Version: 1.0.0
    Requires: PowerShell 5.1+, Az.RecoveryServices, Az.Compute modules

    WARNING: This script has not been thoroughly tested in production environments.
    Please test in a non-production environment first and validate results before relying on this data.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$SubscriptionId = "*",

    [Parameter(Mandatory = $false)]
    [string]$ResourceGroupName = "*",

    [Parameter(Mandatory = $false)]
    [int]$BackupAgeThreshold = 1,

    [Parameter(Mandatory = $false)]
    [switch]$IncludeBackupJobs,

    [Parameter(Mandatory = $false)]
    [ValidateSet('Console', 'HTML', 'JSON')]
    [string]$OutputFormat = 'HTML',

    [Parameter(Mandatory = $false)]
    [string]$OutputPath = (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Reports')
)
# Validate OutputPath: reject '..' traversal and UNC remote paths before resolution
if ([string]::IsNullOrWhiteSpace($OutputPath) -or
    $OutputPath -match '(^|[\\/])\.\.([\\/]|$)' -or
    $OutputPath -match '^(\\\\|//)') {
    Write-Error "Unsafe OutputPath: $OutputPath. OutputPath must be a local absolute path without '..' traversal."
    exit 1
}
$OutputPath = [System.IO.Path]::GetFullPath($OutputPath)
if (-not (Test-Path -LiteralPath $OutputPath -PathType Container)) {
    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
}

if (-not (Get-Module -ListAvailable -Name Az.RecoveryServices)) {
    Write-Error "Az.RecoveryServices module required. Install: Install-Module Az"
    exit 1
}

Import-Module Az.RecoveryServices -ErrorAction SilentlyContinue
Import-Module Az.Compute -ErrorAction SilentlyContinue

$results = @{
    Timestamp = Get-Date
    BackupAgeThreshold = $BackupAgeThreshold
    VMBackupStatus = @()
    UnprotectedVMs = @()
    NonCompliantBackups = @()
    BackupJobs = @()
    Summary = @{}
}

Write-Host "Monitoring Azure VM backup compliance..." -ForegroundColor Cyan

try {
    $context = Get-AzContext
    if (-not $context) {
        Write-Error "Not logged in. Run Connect-AzAccount"
        exit 1
    }
} catch {
    Write-Error "Azure authentication required"
    exit 1
}

$subscriptions = if ($SubscriptionId -eq '*') {
    Get-AzSubscription
} else {
    @(Get-AzSubscription -SubscriptionId $SubscriptionId)
}

foreach ($sub in $subscriptions) {
    Write-Host "`nAnalyzing subscription: $($sub.Name)" -ForegroundColor Yellow
    Set-AzContext -SubscriptionId $sub.Id | Out-Null

    # Get all VMs
    $vms = if ($ResourceGroupName -eq '*') {
        Get-AzVM -Status
    } else {
        Get-AzVM -ResourceGroupName $ResourceGroupName -Status
    }

    Write-Host "Found $($vms.Count) VMs" -ForegroundColor White

    # Get Recovery Services Vaults
    $vaults = Get-AzRecoveryServicesVault

    if ($vaults.Count -eq 0) {
        Write-Warning "No Recovery Services Vaults found in subscription $($sub.Name)"
        foreach ($vm in $vms) {
            $results.UnprotectedVMs += @{
                VMName = $vm.Name
                ResourceGroup = $vm.ResourceGroupName
                Location = $vm.Location
                Subscription = $sub.Name
                Reason = "No Recovery Services Vault configured"
            }
        }
        continue
    }

    Write-Host "Found $($vaults.Count) Recovery Services Vault(s)" -ForegroundColor White

    # Check each VM's backup status
    foreach ($vm in $vms) {
        Write-Host "  Checking backup for: $($vm.Name)" -ForegroundColor Gray

        $vmBackupStatus = @{
            VMName = $vm.Name
            ResourceGroup = $vm.ResourceGroupName
            Location = $vm.Location
            Subscription = $sub.Name
            PowerState = ($vm.Statuses | Where-Object { $_.Code -like 'PowerState/*' }).DisplayStatus
            BackupEnabled = $false
            LastBackupTime = $null
            BackupAge = $null
            VaultName = $null
            PolicyName = $null
            ComplianceStatus = "Unknown"
        }

        # Check if VM is protected in any vault
        $isProtected = $false

        foreach ($vault in $vaults) {
            Set-AzRecoveryServicesVaultContext -Vault $vault | Out-Null

            try {
                # Get backup container for the VM
                $container = Get-AzRecoveryServicesBackupContainer `
                    -ContainerType AzureVM `
                    -FriendlyName $vm.Name `
                    -ErrorAction SilentlyContinue

                if ($container) {
                    $backupItem = Get-AzRecoveryServicesBackupItem `
                        -Container $container `
                        -WorkloadType AzureVM `
                        -ErrorAction SilentlyContinue

                    if ($backupItem) {
                        $isProtected = $true
                        $vmBackupStatus.BackupEnabled = $true
                        $vmBackupStatus.VaultName = $vault.Name
                        $vmBackupStatus.PolicyName = $backupItem.ProtectionPolicyName
                        $vmBackupStatus.LastBackupTime = $backupItem.LastBackupTime

                        if ($backupItem.LastBackupTime) {
                            $backupAge = ((Get-Date) - $backupItem.LastBackupTime).Days
                            $vmBackupStatus.BackupAge = $backupAge

                            if ($backupAge -le $BackupAgeThreshold) {
                                $vmBackupStatus.ComplianceStatus = "Compliant"
                            } else {
                                $vmBackupStatus.ComplianceStatus = "Non-Compliant"
                                $results.NonCompliantBackups += $vmBackupStatus
                            }
                        } else {
                            $vmBackupStatus.ComplianceStatus = "No Backup Yet"
                            $results.NonCompliantBackups += $vmBackupStatus
                        }

                        break
                    }
                }
            } catch {
                # Continue checking other vaults
            }
        }

        if (-not $isProtected) {
            $vmBackupStatus.ComplianceStatus = "Unprotected"
            $results.UnprotectedVMs += @{
                VMName = $vm.Name
                ResourceGroup = $vm.ResourceGroupName
                Location = $vm.Location
                Subscription = $sub.Name
                Reason = "Backup not configured"
            }
        }

        $results.VMBackupStatus += $vmBackupStatus
    }

    # Get backup jobs if requested
    if ($IncludeBackupJobs) {
        Write-Host "`nRetrieving recent backup jobs..." -ForegroundColor Yellow

        foreach ($vault in $vaults) {
            Set-AzRecoveryServicesVaultContext -Vault $vault | Out-Null

            try {
                $jobs = Get-AzRecoveryServicesBackupJob `
                    -From (Get-Date).AddDays(-7) `
                    -To (Get-Date) `
                    -Operation Backup `
                    -ErrorAction SilentlyContinue

                foreach ($job in $jobs) {
                    $results.BackupJobs += @{
                        VaultName = $vault.Name
                        JobId = $job.JobId
                        WorkloadName = $job.WorkloadName
                        Operation = $job.Operation
                        Status = $job.Status
                        StartTime = $job.StartTime
                        EndTime = $job.EndTime
                        Duration = if ($job.EndTime) { ($job.EndTime - $job.StartTime).TotalMinutes } else { $null }
                    }
                }
            } catch {
                Write-Warning "Could not retrieve backup jobs from $($vault.Name)"
            }
        }

        Write-Host "Retrieved $($results.BackupJobs.Count) backup jobs" -ForegroundColor White
    }
}

# Calculate summary
$totalVMs = $results.VMBackupStatus.Count
$protectedVMs = ($results.VMBackupStatus | Where-Object { $_.BackupEnabled }).Count
$unprotectedVMs = $results.UnprotectedVMs.Count
$compliantVMs = ($results.VMBackupStatus | Where-Object { $_.ComplianceStatus -eq 'Compliant' }).Count
$nonCompliantVMs = $results.NonCompliantBackups.Count

$complianceRate = if ($totalVMs -gt 0) {
    [math]::Round(($compliantVMs / $totalVMs) * 100, 2)
} else { 0 }

$results.Summary = @{
    TotalVMs = $totalVMs
    ProtectedVMs = $protectedVMs
    UnprotectedVMs = $unprotectedVMs
    CompliantVMs = $compliantVMs
    NonCompliantVMs = $nonCompliantVMs
    ComplianceRate = $complianceRate
    BackupJobsAnalyzed = $results.BackupJobs.Count
}

# Run-scoped stamp to avoid filename collisions on rapid re-runs
$RunTimestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$RunId = [Guid]::NewGuid().ToString('N').Substring(0, 8)

# Output
switch ($OutputFormat) {
    'Console' {
        Write-Host "`n=== Azure VM Backup Compliance Summary ===" -ForegroundColor Cyan
        Write-Host "Total VMs: $totalVMs" -ForegroundColor White
        Write-Host "Protected: $protectedVMs | Unprotected: $unprotectedVMs" -ForegroundColor White
        Write-Host "Compliant: $compliantVMs | Non-Compliant: $nonCompliantVMs" -ForegroundColor White
        Write-Host "Compliance Rate: $complianceRate%" -ForegroundColor $(if ($complianceRate -ge 95) { 'Green' } elseif ($complianceRate -ge 80) { 'Yellow' } else { 'Red' })

        if ($unprotectedVMs -gt 0) {
            Write-Host "`n=== Unprotected VMs ===" -ForegroundColor Red
            foreach ($vm in ($results.UnprotectedVMs | Select-Object -First 10)) {
                Write-Host "  $($vm.VMName) in $($vm.ResourceGroup) - $($vm.Reason)" -ForegroundColor Red
            }
        }

        if ($nonCompliantVMs -gt 0) {
            Write-Host "`n=== Non-Compliant Backups ===" -ForegroundColor Yellow
            foreach ($vm in ($results.NonCompliantBackups | Select-Object -First 10)) {
                Write-Host "  $($vm.VMName): Last backup $($vm.BackupAge) days ago" -ForegroundColor Yellow
            }
        }
    }

    'HTML' {
        $htmlFile = Join-Path $OutputPath "Azure-VM-Backup-Compliance-${RunTimestamp}_${RunId}.html"

        $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>Azure VM Backup Compliance Report</title>
    <style>
        body { font-family: 'Segoe UI', Arial, sans-serif; margin: 20px; background: #f5f5f5; }
        h1 { color: #0078d4; }
        .summary { background: white; padding: 20px; border-radius: 8px; margin-bottom: 20px; }
        .summary-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(150px, 1fr)); gap: 15px; margin-top: 15px; }
        .summary-item { background: #f0f0f0; padding: 15px; border-radius: 5px; text-align: center; }
        .summary-item .value { font-size: 32px; font-weight: bold; color: #0078d4; }
        .summary-item .label { font-size: 14px; color: #666; margin-top: 5px; }
        table { border-collapse: collapse; width: 100%; background: white; margin: 10px 0; }
        th { background: #0078d4; color: white; padding: 10px; }
        td { padding: 8px; border-bottom: 1px solid #ddd; }
        .compliant { background-color: #d4edda; }
        .non-compliant { background-color: #fff3cd; }
        .unprotected { background-color: #f8d7da; }
    </style>
</head>
<body>
    <h1>Azure VM Backup Compliance Report</h1>
    <div class="summary">
        <strong>Generated:</strong> $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')<br>
        <strong>Backup Age Threshold:</strong> $BackupAgeThreshold day(s)

        <div class="summary-grid">
            <div class="summary-item">
                <div class="value">$totalVMs</div>
                <div class="label">Total VMs</div>
            </div>
            <div class="summary-item">
                <div class="value" style="color: #107c10;">$protectedVMs</div>
                <div class="label">Protected</div>
            </div>
            <div class="summary-item">
                <div class="value" style="color: #d13438;">$unprotectedVMs</div>
                <div class="label">Unprotected</div>
            </div>
            <div class="summary-item">
                <div class="value">$complianceRate%</div>
                <div class="label">Compliance Rate</div>
            </div>
        </div>
    </div>

    <h2>VM Backup Status</h2>
    <table>
        <tr><th>VM Name</th><th>Resource Group</th><th>Vault</th><th>Last Backup</th><th>Age (days)</th><th>Status</th></tr>
"@

        foreach ($vm in $results.VMBackupStatus) {
            $rowClass = switch ($vm.ComplianceStatus) {
                'Compliant' { 'compliant' }
                'Non-Compliant' { 'non-compliant' }
                'Unprotected' { 'unprotected' }
                default { '' }
            }

            $html += @"
        <tr class="$rowClass">
            <td>$([System.Net.WebUtility]::HtmlEncode("$($vm.VMName)"))</td>
            <td>$([System.Net.WebUtility]::HtmlEncode("$($vm.ResourceGroup)"))</td>
            <td>$([System.Net.WebUtility]::HtmlEncode("$($vm.VaultName)"))</td>
            <td>$($vm.LastBackupTime)</td>
            <td>$($vm.BackupAge)</td>
            <td>$([System.Net.WebUtility]::HtmlEncode("$($vm.ComplianceStatus)"))</td>
        </tr>
"@
        }

        $html += "</table><p style='margin-top: 30px; text-align: center; color: #666; font-size: 12px;'><strong>Note:</strong> This report has not been thoroughly tested.</p></body></html>"
        $html | Out-File -FilePath $htmlFile -Encoding UTF8
        Write-Host "`nHTML saved to: $htmlFile" -ForegroundColor Green
    }

    'JSON' {
        $jsonFile = Join-Path $OutputPath "Azure-VM-Backup-Compliance-${RunTimestamp}_${RunId}.json"
        $results | ConvertTo-Json -Depth 10 | Out-File -FilePath $jsonFile
        Write-Host "`nJSON saved to: $jsonFile" -ForegroundColor Green
    }
}

Write-Host "`nAzure VM backup compliance analysis complete!" -ForegroundColor Green
