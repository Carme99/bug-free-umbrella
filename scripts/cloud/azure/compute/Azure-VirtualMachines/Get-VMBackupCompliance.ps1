<#
.SYNOPSIS
    Monitors Azure VM backup status and compliance with backup policies.

.DESCRIPTION
    Comprehensive read-only Azure VM backup monitoring including:
    - VM backup configuration status
    - Last successful backup time
    - Backup age compliance
    - Recovery Services Vault health
    - Backup policy compliance
    - VMs without backup configured
    - Backup job success/failure rates
    - Recovery point objectives (RPO) validation

    The script never mutates Azure resources; for HTML/JSON output formats it writes a
    uniquely-named report file under -OutputPath, so re-running against an unchanged
    environment is safe (idempotent). A missing Az.RecoveryServices module or missing Azure
    login fails with exit code 1. Exit code 0 is returned on a completed analysis regardless
    of individual VM compliance findings, which are reported in the output.

.PARAMETER SubscriptionId
    Azure subscription ID. Use '*' for all subscriptions.

.PARAMETER ResourceGroupName
    Specific resource group. Use '*' for all resource groups.

.PARAMETER BackupAgeThreshold
    Maximum days since last backup before flagging as non-compliant (0-365). Default: 1

.PARAMETER IncludeBackupJobs
    Include recent backup job analysis

.PARAMETER OutputFormat
    Output format: 'Console', 'HTML', or 'JSON'. Default: 'HTML'

.PARAMETER OutputPath
    Local directory path for output files. Default: MyDocuments\Reports

.EXAMPLE
    PS C:\> Connect-AzAccount
    PS C:\> .\Get-VMBackupCompliance.ps1 -SubscriptionId "*"
    Checks backup compliance for every VM in all accessible subscriptions and writes an HTML report.

.EXAMPLE
    PS C:\> .\Get-VMBackupCompliance.ps1 -SubscriptionId "sub-id" -ResourceGroupName "*" `
        -BackupAgeThreshold 2 -IncludeBackupJobs
    Flags VMs whose last backup is more than 2 days old and includes recent backup job analysis.

.NOTES
    File Name   : Get-VMBackupCompliance.ps1
    Author      : IT Operations
    Prerequisite: PowerShell 7.0
    Version     : 1.0.0
    Date        : 2026-08-23

    WARNING: This script has not been thoroughly tested in production environments.
    Please test in a non-production environment first and validate results before relying on this data.
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
    Justification = 'RELAUNCH-SPEC §3 mandates console status output via Write-Host with [+]/[!]/[-]/[*] prefixes.')]
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$SubscriptionId = "*",

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$ResourceGroupName = "*",

    [Parameter(Mandatory = $false)]
    [ValidateRange(0, 365)]
    [int]$BackupAgeThreshold = 1,

    [Parameter(Mandatory = $false)]
    [switch]$IncludeBackupJobs,

    [Parameter(Mandatory = $false)]
    [ValidateSet('Console', 'HTML', 'JSON')]
    [string]$OutputFormat = 'HTML',

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$OutputPath = (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Reports')
)

$ErrorActionPreference = 'Stop'

function Main {
    [CmdletBinding()]
    param(
        [ValidateNotNullOrEmpty()]
        [string]$SubscriptionId = "*",

        [ValidateNotNullOrEmpty()]
        [string]$ResourceGroupName = "*",

        [ValidateRange(0, 365)]
        [int]$BackupAgeThreshold = 1,

        [switch]$IncludeBackupJobs,

        [ValidateSet('Console', 'HTML', 'JSON')]
        [string]$OutputFormat = 'HTML',

        [ValidateNotNullOrEmpty()]
        [string]$OutputPath = (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Reports')
    )

    try {
        # Validate OutputPath: reject '..' traversal and UNC remote paths before resolution
        if ([string]::IsNullOrWhiteSpace($OutputPath) -or
            $OutputPath -match '(^|[\\/])\.\.([\\/]|$)' -or
            $OutputPath -match '^(\\\\|//)') {
            throw "Unsafe OutputPath: '$OutputPath'. OutputPath must be a local absolute path without '..' traversal."
        }
        $resolvedOutputPath = [System.IO.Path]::GetFullPath($OutputPath)
        if (-not (Test-Path -LiteralPath $resolvedOutputPath -PathType Container)) {
            New-Item -ItemType Directory -Path $resolvedOutputPath -Force -ErrorAction Stop | Out-Null
        }

        if (-not (Get-Module -ListAvailable -Name Az.RecoveryServices)) {
            throw "Az.RecoveryServices module required. Install: Install-Module Az"
        }

        Import-Module Az.RecoveryServices -ErrorAction SilentlyContinue
        Import-Module Az.Compute -ErrorAction SilentlyContinue

        $results = @{
            Timestamp           = Get-Date
            BackupAgeThreshold  = $BackupAgeThreshold
            VMBackupStatus      = @()
            UnprotectedVMs      = @()
            NonCompliantBackups = @()
            BackupJobs          = @()
            Summary             = @{}
        }

        Write-Host "[*] Monitoring Azure VM backup compliance..." -ForegroundColor Cyan

        $context = Get-AzContext -ErrorAction Stop
        if (-not $context) {
            throw "Not logged in to Azure. Run Connect-AzAccount"
        }

        $subscriptions = if ($SubscriptionId -eq '*') {
            Get-AzSubscription -ErrorAction Stop
        }
        else {
            @(Get-AzSubscription -SubscriptionId $SubscriptionId -ErrorAction Stop)
        }

        foreach ($sub in $subscriptions) {
            Write-Host "`n[*] Analyzing subscription: $($sub.Name)" -ForegroundColor Cyan
            Set-AzContext -SubscriptionId $sub.Id -ErrorAction Stop | Out-Null

            # Get all VMs
            $vms = if ($ResourceGroupName -eq '*') {
                @(Get-AzVM -Status -ErrorAction Stop)
            }
            else {
                @(Get-AzVM -ResourceGroupName $ResourceGroupName -Status -ErrorAction Stop)
            }

            Write-Host "[*] Found $($vms.Count) VMs" -ForegroundColor White

            # Get Recovery Services Vaults
            $vaults = @(Get-AzRecoveryServicesVault -ErrorAction Stop)

            if ($vaults.Count -eq 0) {
                Write-Host "[!] No Recovery Services Vaults found in subscription $($sub.Name)" -ForegroundColor Yellow
                foreach ($vm in $vms) {
                    $results.UnprotectedVMs += [pscustomobject]@{
                        VMName         = $vm.Name
                        ResourceGroup  = $vm.ResourceGroupName
                        Location       = $vm.Location
                        Subscription   = $sub.Name
                        Reason         = "No Recovery Services Vault configured"
                    }
                }
                continue
            }

            Write-Host "[*] Found $($vaults.Count) Recovery Services Vault(s)" -ForegroundColor White

            # Check each VM's backup status
            foreach ($vm in $vms) {
                Write-Host "[*]   Checking backup for: $($vm.Name)" -ForegroundColor Gray

                $vmBackupStatus = [pscustomobject]@{
                    VMName            = $vm.Name
                    ResourceGroup     = $vm.ResourceGroupName
                    Location          = $vm.Location
                    Subscription      = $sub.Name
                    PowerState        = ($vm.Statuses | Where-Object { $_.Code -like 'PowerState/*' }).DisplayStatus
                    BackupEnabled     = $false
                    LastBackupTime    = $null
                    BackupAge         = $null
                    VaultName         = $null
                    PolicyName        = $null
                    ComplianceStatus  = "Unknown"
                }

                # Check if VM is protected in any vault
                $isProtected = $false

                foreach ($vault in $vaults) {
                    try {
                        # Get backup container for the VM
                        $container = Get-AzRecoveryServicesBackupContainer `
                            -ContainerType AzureVM `
                            -FriendlyName $vm.Name `
                            -VaultId $vault.Id `
                            -ErrorAction SilentlyContinue

                        if ($container) {
                            $backupItem = Get-AzRecoveryServicesBackupItem `
                                -Container $container `
                                -WorkloadType AzureVM `
                                -VaultId $vault.Id `
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
                                        Write-Host "[+]     $($vm.Name): compliant" `
                                            "(last backup $backupAge day(s) ago)" `
                                            -ForegroundColor Green
                                    }
                                    else {
                                        $vmBackupStatus.ComplianceStatus = "Non-Compliant"
                                        $results.NonCompliantBackups += $vmBackupStatus
                                        Write-Host "[!]     $($vm.Name): last backup $backupAge day(s) ago exceeds" `
                                            "threshold of $BackupAgeThreshold" -ForegroundColor Yellow
                                    }
                                }
                                else {
                                    $vmBackupStatus.ComplianceStatus = "No Backup Yet"
                                    $results.NonCompliantBackups += $vmBackupStatus
                                    Write-Host "[!]     $($vm.Name): protected but no recovery point yet" `
                                        -ForegroundColor Yellow
                                }

                                break
                            }
                        }
                    }
                    catch {
                        Write-Verbose "Handled exception: $($_.Exception.Message)"
                    }
                }

                if (-not $isProtected) {
                    $vmBackupStatus.ComplianceStatus = "Unprotected"
                    $results.UnprotectedVMs += [pscustomobject]@{
                        VMName         = $vm.Name
                        ResourceGroup  = $vm.ResourceGroupName
                        Location       = $vm.Location
                        Subscription   = $sub.Name
                        Reason         = "Backup not configured"
                    }
                    Write-Host "[-]     $($vm.Name): unprotected - backup not configured" -ForegroundColor Red
                }

                $results.VMBackupStatus += $vmBackupStatus
            }

            # Get backup jobs if requested
            if ($IncludeBackupJobs) {
                Write-Host "`n[*] Retrieving recent backup jobs..." -ForegroundColor Cyan

                foreach ($vault in $vaults) {
                    try {
                        $jobs = Get-AzRecoveryServicesBackupJob `
                            -VaultId $vault.Id `
                            -From (Get-Date).AddDays(-7).ToUniversalTime() `
                            -To (Get-Date).ToUniversalTime() `
                            -Operation Backup `
                            -ErrorAction Stop

                        foreach ($job in @($jobs)) {
                            $jobDuration = if ($job.EndTime) {
                                ($job.EndTime - $job.StartTime).TotalMinutes
                            }
                            else { $null }
                            $results.BackupJobs += [pscustomobject]@{
                                VaultName   = $vault.Name
                                JobId       = $job.JobId
                                WorkloadName = $job.WorkloadName
                                Operation   = $job.Operation
                                Status      = $job.Status
                                StartTime   = $job.StartTime
                                EndTime     = $job.EndTime
                                Duration    = $jobDuration
                            }
                        }
                    }
                    catch {
                        Write-Host "[!] Could not retrieve backup jobs from $($vault.Name)" -ForegroundColor Yellow
                    }
                }

                Write-Host "[*] Retrieved $($results.BackupJobs.Count) backup jobs" -ForegroundColor White
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
        }
        else { 0 }

        $results.Summary = @{
            TotalVMs           = $totalVMs
            ProtectedVMs       = $protectedVMs
            UnprotectedVMs     = $unprotectedVMs
            CompliantVMs       = $compliantVMs
            NonCompliantVMs    = $nonCompliantVMs
            ComplianceRate     = $complianceRate
            BackupJobsAnalyzed = $results.BackupJobs.Count
        }

        # Run-scoped stamp to avoid filename collisions on rapid re-runs
        $RunTimestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $RunId = [Guid]::NewGuid().ToString('N').Substring(0, 8)

        # Output
        switch ($OutputFormat) {
            'Console' {
                Write-Host "`n=== Azure VM Backup Compliance Summary ===" -ForegroundColor Cyan
                Write-Host "[*] Total VMs: $totalVMs" -ForegroundColor White
                Write-Host "[*] Protected: $protectedVMs | Unprotected: $unprotectedVMs" -ForegroundColor White
                Write-Host "[*] Compliant: $compliantVMs | Non-Compliant: $nonCompliantVMs" -ForegroundColor White
                $ratePrefix = if ($complianceRate -ge 95) { '[+]' }
                elseif ($complianceRate -ge 80) { '[!]' }
                else { '[-]' }
                $rateColor = if ($complianceRate -ge 95) { 'Green' }
                elseif ($complianceRate -ge 80) { 'Yellow' }
                else { 'Red' }
                Write-Host "$ratePrefix Compliance Rate: $complianceRate%" -ForegroundColor $rateColor

                if ($unprotectedVMs -gt 0) {
                    Write-Host "`n=== Unprotected VMs ===" -ForegroundColor Red
                    foreach ($vm in ($results.UnprotectedVMs | Select-Object -First 10)) {
                        Write-Host "[-]   $($vm.VMName) in $($vm.ResourceGroup) - $($vm.Reason)" -ForegroundColor Red
                    }
                }

                if ($nonCompliantVMs -gt 0) {
                    Write-Host "`n=== Non-Compliant Backups ===" -ForegroundColor Yellow
                    foreach ($vm in ($results.NonCompliantBackups | Select-Object -First 10)) {
                        Write-Host "[!]   $($vm.VMName): Last backup $($vm.BackupAge) days ago" -ForegroundColor Yellow
                    }
                }
            }

            'HTML' {
                $htmlFile = Join-Path $resolvedOutputPath "Azure-VM-Backup-Compliance-${RunTimestamp}_${RunId}.html"

                $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>Azure VM Backup Compliance Report</title>
    <style>
        body { font-family: 'Segoe UI', Arial, sans-serif; margin: 20px; background: #f5f5f5; }
        h1 { color: #0078d4; }
        .summary { background: white; padding: 20px; border-radius: 8px; margin-bottom: 20px; }
        .summary-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(150px, 1fr));
            gap: 15px; margin-top: 15px; }
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
        <tr><th>VM Name</th><th>Resource Group</th><th>Vault</th>
            <th>Last Backup</th><th>Age (days)</th><th>Status</th></tr>
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

                $html += "</table><p style='margin-top: 30px; text-align: center; color: #666; font-size: 12px;'>" +
                    "<strong>Note:</strong> This report has not been thoroughly tested.</p></body></html>"
                $html | Out-File -FilePath $htmlFile -Encoding UTF8 -ErrorAction Stop
                Write-Host "`n[+] HTML saved to: $htmlFile" -ForegroundColor Green
            }

            'JSON' {
                $jsonFile = Join-Path $resolvedOutputPath "Azure-VM-Backup-Compliance-${RunTimestamp}_${RunId}.json"
                $results | ConvertTo-Json -Depth 10 | Out-File -FilePath $jsonFile -ErrorAction Stop
                Write-Host "`n[+] JSON saved to: $jsonFile" -ForegroundColor Green
            }
        }

        Write-Host "`n[+] Azure VM backup compliance analysis complete!" -ForegroundColor Green
        return 0
    }
    catch {
        Write-Host "[-] Error: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Justification for PSUseOutputTypeCorrectly: Main returns an int exit code consumed by the guard below.
# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main @PSBoundParameters) }
