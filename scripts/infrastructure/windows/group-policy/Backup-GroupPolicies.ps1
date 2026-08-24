<#
.SYNOPSIS
    Backs up all Group Policy Objects in the domain to a specified location.

.DESCRIPTION
    This script creates backups of all GPOs in the domain (or a single named GPO), including
    their settings, links, and WMI filter metadata. It writes a timestamped backup folder with
    a CSV backup log, JSON manifest, and HTML report, optionally compresses the folder to a
    ZIP archive, and prunes backup folders/ZIPs older than the retention window. Retention
    deletion is destructive and therefore gated behind -WhatIf/-Confirm support; re-running
    the script is safe because each run creates a fresh unique backup folder.

.PARAMETER BackupPath
    Root local absolute path where GPO backups will be stored. Creates timestamped subdirectories.

.PARAMETER Comment
    Custom comment to add to the backup metadata. Default is "Automated GPO backup".

.PARAMETER RetentionDays
    Number of days to retain old backups. Backups older than this will be deleted. Default is 90 days.

.PARAMETER CompressBackup
    Switch to compress the backup into a ZIP file after creation.

.PARAMETER GPOName
    Optional. Name of a specific GPO to backup. If not specified, all GPOs are backed up.

.EXAMPLE
    PS C:\> .\Backup-GroupPolicies.ps1 -BackupPath "D:\GPO_Backups"
    Backs up all GPOs to D:\GPO_Backups with a timestamped folder.

.EXAMPLE
    PS C:\> .\Backup-GroupPolicies.ps1 -BackupPath "D:\GPO_Backups" -Comment "Pre-migration backup" -CompressBackup
    Backs up all GPOs with a comment and compresses the backup.

.EXAMPLE
    PS C:\> .\Backup-GroupPolicies.ps1 -BackupPath "D:\GPO_Backups" -GPOName "Corporate Security Policy"
    Backs up only the specified GPO.

.NOTES
    File Name: Backup-GroupPolicies.ps1
    Author: Server Management Team
    Prerequisite: PowerShell 7.0
    Version: 1.0.0
    Date: 2026-08-23
#>

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification='Spec 3 requirement')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification='Used in Main scope')]
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$BackupPath,

    [Parameter(Mandatory = $false)]
    [string]$Comment = 'Automated GPO backup',

    [Parameter(Mandatory = $false)]
    [ValidateRange(0, 3650)]
    [int]$RetentionDays = 90,

    [Parameter(Mandatory = $false)]
    [switch]$CompressBackup,

    [Parameter(Mandatory = $false)]
    [string]$GPOName
)

$ErrorActionPreference = 'Stop'

function Assert-SafeLocalPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Label
    )

    if ([string]::IsNullOrWhiteSpace($Path) -or
        $Path -match '(^|[\\/])\.\.([\\/]|$)' -or
        $Path -match '^(\\\\|//)') {
        throw "$Label must be a local absolute path without '..' traversal: '$Path'"
    }

    return [System.IO.Path]::GetFullPath($Path)
}

function Main {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    try {
        Write-Host '[*] Starting Group Policy backup...' -ForegroundColor Cyan

        # Validate BackupPath: reject '..' traversal and UNC remote paths before resolution
        $BackupPath = Assert-SafeLocalPath -Path $BackupPath -Label 'BackupPath'

        $RunTimestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $RunId = [Guid]::NewGuid().ToString('N').Substring(0, 8)

        Write-Host ''
        Write-Host '=== Group Policy Backup Utility ===' -ForegroundColor Cyan
        Write-Host "Start Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray

        # Create backup directory structure
        $backupFolder = Join-Path -Path $BackupPath -ChildPath "GPO_Backup_${RunTimestamp}_${RunId}"

        if (-not (Test-Path -Path $BackupPath)) {
            Write-Host "[*] Creating backup root directory: $BackupPath" -ForegroundColor Yellow
            New-Item -Path $BackupPath -ItemType Directory -Force -ErrorAction Stop | Out-Null
        }

        Write-Host "[*] Creating backup folder: $backupFolder" -ForegroundColor Yellow
        New-Item -Path $backupFolder -ItemType Directory -Force -ErrorAction Stop | Out-Null
        Write-Host '[+] Backup folder created successfully' -ForegroundColor Green

        # Get domain information
        $domain = Get-ADDomain -ErrorAction Stop
        $domainName = $domain.DNSRoot
        Write-Host "Domain: $domainName" -ForegroundColor Cyan

        # Get GPOs to backup
        if ($GPOName) {
            Write-Host "[*] Backing up specific GPO: $GPOName" -ForegroundColor Yellow
            try {
                $gposToBackup = @(Get-GPO -Name $GPOName -Domain $domainName -ErrorAction Stop)
            }
            catch {
                Write-Host "[-] GPO '$GPOName' not found: $_" -ForegroundColor Red
                return 1
            }
        }
        else {
            Write-Host '[*] Retrieving all GPOs...' -ForegroundColor Yellow
            $gposToBackup = @(Get-GPO -All -Domain $domainName)
        }

        $totalGPOs = @($gposToBackup).Count
        Write-Host "[+] Found $totalGPOs GPO(s) to backup" -ForegroundColor Green

        # Initialize backup log
        $backupLog = @()
        $successCount = 0
        $failCount = 0
        $counter = 0

        # Backup each GPO
        foreach ($gpo in $gposToBackup) {
            $counter++
            $percentComplete = [math]::Round(($counter / $totalGPOs) * 100)
            $progressStatus = "Backing up: $($gpo.DisplayName) ($counter of $totalGPOs)"
            Write-Progress -Activity 'Backing up GPOs' -Status $progressStatus -PercentComplete $percentComplete

            try {
                # Backup the GPO
                $backupInfo = Backup-GPO -Guid $gpo.Id -Path $backupFolder -Comment $Comment -ErrorAction Stop

                # Get additional GPO information
                $gpoReport = [xml](Get-GPOReport -Guid $gpo.Id -ReportType XML -ErrorAction Stop)
                $links = $gpoReport.GPO.LinksTo
                $linkCount = if ($links) { @($links).Count } else { 0 }

                # Get WMI filter info
                $wmiFilter = if ($gpo.WmiFilter) { $gpo.WmiFilter.Name } else { 'None' }

                # Create detailed backup record
                $backupLog += [PSCustomObject]@{
                    GPOName        = $gpo.DisplayName
                    GUID           = $gpo.Id
                    BackupTime     = Get-Date
                    BackupID       = $backupInfo.Id
                    Status         = 'Success'
                    GpoStatus      = $gpo.GpoStatus
                    Created        = $gpo.CreationTime
                    Modified       = $gpo.ModificationTime
                    LinkCount      = $linkCount
                    WMIFilter      = $wmiFilter
                    Owner          = $gpo.Owner
                    ComputerEnabled = $gpo.Computer.Enabled
                    UserEnabled    = $gpo.User.Enabled
                    Error          = ''
                }

                $successCount++
                Write-Host "  [+] $($gpo.DisplayName)" -ForegroundColor Green
            }
            catch {
                $failCount++
                Write-Host "  [-] $($gpo.DisplayName): $($_.Exception.Message)" -ForegroundColor Red

                $backupLog += [PSCustomObject]@{
                    GPOName         = $gpo.DisplayName
                    GUID            = $gpo.Id
                    BackupTime      = Get-Date
                    BackupID        = 'N/A'
                    Status          = 'Failed'
                    GpoStatus       = $gpo.GpoStatus
                    Created         = $gpo.CreationTime
                    Modified        = $gpo.ModificationTime
                    LinkCount       = 0
                    WMIFilter       = ''
                    Owner           = $gpo.Owner
                    ComputerEnabled = $false
                    UserEnabled     = $false
                    Error           = $_.Exception.Message
                }
            }
        }

        Write-Progress -Activity 'Backing up GPOs' -Completed

        # Export backup log
        $logPath = Join-Path -Path $backupFolder -ChildPath 'BackupLog.csv'
        $backupLog | Export-Csv -Path $logPath -NoTypeInformation -ErrorAction Stop
        Write-Host "[+] Backup log saved to: $logPath" -ForegroundColor Cyan

        # Create backup manifest
        $manifest = @{
            BackupDate       = Get-Date
            Domain           = $domainName
            TotalGPOs        = $totalGPOs
            SuccessfulBackups = $successCount
            FailedBackups    = $failCount
            BackupPath       = $backupFolder
            Comment          = $Comment
            BackupBy         = "$env:USERDOMAIN\$env:USERNAME"
        }

        $manifestPath = Join-Path -Path $backupFolder -ChildPath 'BackupManifest.json'
        $manifest | ConvertTo-Json -Depth 3 | Out-File -FilePath $manifestPath -Encoding UTF8 -ErrorAction Stop
        Write-Host "[+] Backup manifest saved to: $manifestPath" -ForegroundColor Cyan

        # Create HTML report
        $reportPath = Join-Path -Path $backupFolder -ChildPath 'BackupReport.html'
        $htmlHead = @"
<!DOCTYPE html>
<html>
<head>
    <title>GPO Backup Report - $([System.Net.WebUtility]::HtmlEncode("$domainName"))</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background-color: #f5f5f5; }
        h1 { color: #0066cc; }
        h2 { color: #0099cc; margin-top: 30px; }
        table { border-collapse: collapse; width: 100%; background-color: white;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1); margin: 20px 0; }
        th { background-color: #0066cc; color: white; padding: 12px; text-align: left; }
        td { padding: 10px; border-bottom: 1px solid #ddd; }
        tr:hover { background-color: #f0f0f0; }
        .success { color: #009900; font-weight: bold; }
        .failed { color: #cc0000; font-weight: bold; }
        .info { background-color: #e6f3ff; padding: 15px; border-left: 4px solid #0066cc; margin: 20px 0; }
    </style>
</head>
<body>
    <h1>Group Policy Backup Report</h1>
    <div class="info">
        <strong>Domain:</strong> $([System.Net.WebUtility]::HtmlEncode("$domainName"))<br>
        <strong>Backup Date:</strong> $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | <strong>Run ID:</strong> $RunId<br>
        <strong>Backup Location:</strong> $([System.Net.WebUtility]::HtmlEncode("$backupFolder"))<br>
        <strong>Performed By:</strong> $([System.Net.WebUtility]::HtmlEncode("$env:USERDOMAIN\$env:USERNAME"))<br>
        <strong>Comment:</strong> $([System.Net.WebUtility]::HtmlEncode("$Comment"))
    </div>

    <h2>Backup Summary</h2>
    <table>
        <tr><td><strong>Total GPOs</strong></td><td>$totalGPOs</td></tr>
        <tr><td><strong>Successful Backups</strong></td><td class="success">$successCount</td></tr>
        <tr><td><strong>Failed Backups</strong></td>
            <td class="$(if ($failCount -gt 0) { 'failed' } else { 'success' })">$failCount</td></tr>
    </table>

    <h2>Backed Up GPOs</h2>
    <table>
        <tr>
            <th>GPO Name</th>
            <th>Status</th>
            <th>Backup ID</th>
            <th>Modified Date</th>
            <th>Links</th>
        </tr>
"@

        $htmlRows = ''
        foreach ($entry in $backupLog | Sort-Object -Property GPOName) {
            $statusClass = if ($entry.Status -eq 'Success') { 'success' } else { 'failed' }
            $htmlRows += @"
        <tr>
            <td>$([System.Net.WebUtility]::HtmlEncode("$($entry.GPOName)"))</td>
            <td class="$statusClass">$([System.Net.WebUtility]::HtmlEncode("$($entry.Status)"))</td>
            <td>$([System.Net.WebUtility]::HtmlEncode("$($entry.BackupID)"))</td>
            <td>$($entry.Modified.ToString('yyyy-MM-dd HH:mm'))</td>
            <td>$($entry.LinkCount)</td>
        </tr>
"@
        }

        $html = "$htmlHead$htmlRows    </table>`n</body>`n</html>"

        $html | Out-File -FilePath $reportPath -Encoding UTF8 -ErrorAction Stop
        Write-Host "[+] HTML report saved to: $reportPath" -ForegroundColor Cyan

        # Compress backup if requested
        if ($CompressBackup) {
            Write-Host '[*] Compressing backup...' -ForegroundColor Yellow
            $zipPath = "$backupFolder.zip"

            Add-Type -AssemblyName System.IO.Compression.FileSystem
            [System.IO.Compression.ZipFile]::CreateFromDirectory($backupFolder, $zipPath)

            Write-Host "[+] Backup compressed to: $zipPath" -ForegroundColor Green
            $backupSize = [math]::Round((Get-Item $zipPath).Length / 1MB, 2)
            Write-Host "Compressed size: $backupSize MB" -ForegroundColor Cyan
        }

        # Clean up old backups (destructive: gated behind ShouldProcess)
        if ($RetentionDays -gt 0) {
            Write-Host "[*] Cleaning up old backups (retention: $RetentionDays days)..." -ForegroundColor Yellow
            $cutoffDate = (Get-Date).AddDays(-$RetentionDays)

            $oldBackups = @(Get-ChildItem -Path $BackupPath -Directory -Filter 'GPO_Backup_*' |
                    Where-Object { $_.CreationTime -lt $cutoffDate })

            $oldZips = @(Get-ChildItem -Path $BackupPath -File -Filter 'GPO_Backup_*.zip' |
                    Where-Object { $_.CreationTime -lt $cutoffDate })

            $deletedCount = 0

            foreach ($oldBackup in $oldBackups) {
                if ($PSCmdlet.ShouldProcess($oldBackup.FullName, 'Delete old GPO backup directory')) {
                    Remove-Item -Path $oldBackup.FullName -Recurse -Force -ErrorAction Stop
                    Write-Host "  Deleted: $($oldBackup.Name)" -ForegroundColor Gray
                    $deletedCount++
                }
            }

            foreach ($oldZip in $oldZips) {
                if ($PSCmdlet.ShouldProcess($oldZip.FullName, 'Delete old GPO backup ZIP')) {
                    Remove-Item -Path $oldZip.FullName -Force -ErrorAction Stop
                    Write-Host "  Deleted: $($oldZip.Name)" -ForegroundColor Gray
                    $deletedCount++
                }
            }

            if ($deletedCount -gt 0) {
                Write-Host "[+] Deleted $deletedCount old backup(s)" -ForegroundColor Green
            }
            else {
                # Idempotent: retention already converged.
                Write-Host '[+] No old backups to delete' -ForegroundColor Green
            }
        }

        # Display summary
        Write-Host '[+] Backup Complete' -ForegroundColor Green
        Write-Host "Successful: $successCount" -ForegroundColor Green
        if ($failCount -gt 0) {
            Write-Host "Failed: $failCount" -ForegroundColor Red
        }
        Write-Host "Backup Location: $backupFolder" -ForegroundColor Cyan
        Write-Host "End Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray

        return 0
    }
    catch {
        Write-Host "[-] Backup operation failed: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
