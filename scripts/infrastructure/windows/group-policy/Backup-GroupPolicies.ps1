<#
.SYNOPSIS
    Backs up all Group Policy Objects in the domain to a specified location.

.DESCRIPTION
    This script creates backups of all GPOs in the domain, including their settings,
    permissions, WMI filters, and links. Can be scheduled for regular backups and
    supports incremental backups with version history.

.PARAMETER BackupPath
    Root path where GPO backups will be stored. Creates timestamped subdirectories.

.PARAMETER IncludeComments
    Switch to include comments in the backup metadata.

.PARAMETER Comment
    Custom comment to add to the backup metadata.

.PARAMETER RetentionDays
    Number of days to retain old backups. Backups older than this will be deleted. Default is 90 days.

.PARAMETER CompressBackup
    Switch to compress the backup into a ZIP file after creation.

.PARAMETER GPOName
    Optional. Name of a specific GPO to backup. If not specified, all GPOs are backed up.

.EXAMPLE
    .\Backup-GroupPolicies.ps1 -BackupPath "D:\GPO_Backups"
    Backs up all GPOs to D:\GPO_Backups with a timestamped folder.

.EXAMPLE
    .\Backup-GroupPolicies.ps1 -BackupPath "D:\GPO_Backups" -Comment "Pre-migration backup" -CompressBackup
    Backs up all GPOs with a comment and compresses the backup.

.EXAMPLE
    .\Backup-GroupPolicies.ps1 -BackupPath "D:\GPO_Backups" -GPOName "Corporate Security Policy"
    Backs up only the specified GPO.

.NOTES
    Author: Server Management Team
    Requires: GroupPolicy PowerShell module, Domain Admin or equivalent permissions
    Version: 1.0
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$BackupPath,

    [Parameter(Mandatory = $false)]
    [string]$Comment = "Automated GPO backup",

    [Parameter(Mandatory = $false)]
    [int]$RetentionDays = 90,

    [Parameter(Mandatory = $false)]
    [switch]$CompressBackup,

    [Parameter(Mandatory = $false)]
    [string]$GPOName
)

#Requires -Module GroupPolicy

Write-Host "`n=== Group Policy Backup Utility ===" -ForegroundColor Cyan
Write-Host "Start Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray

# Create backup directory structure
$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$backupFolder = Join-Path -Path $BackupPath -ChildPath "GPO_Backup_$timestamp"

try {
    if (-not (Test-Path -Path $BackupPath)) {
        Write-Host "`nCreating backup root directory: $BackupPath" -ForegroundColor Yellow
        New-Item -Path $BackupPath -ItemType Directory -Force | Out-Null
    }

    Write-Host "`nCreating backup folder: $backupFolder" -ForegroundColor Yellow
    New-Item -Path $backupFolder -ItemType Directory -Force | Out-Null
    Write-Host "Backup folder created successfully" -ForegroundColor Green

    # Get domain information
    $domain = Get-ADDomain
    $domainName = $domain.DNSRoot
    Write-Host "`nDomain: $domainName" -ForegroundColor Cyan

    # Get GPOs to backup
    if ($GPOName) {
        Write-Host "`nBacking up specific GPO: $GPOName" -ForegroundColor Yellow
        try {
            $gposToBackup = @(Get-GPO -Name $GPOName -Domain $domainName)
        }
        catch {
            Write-Error "GPO '$GPOName' not found: $_"
            exit 1
        }
    }
    else {
        Write-Host "`nRetrieving all GPOs..." -ForegroundColor Yellow
        $gposToBackup = Get-GPO -All -Domain $domainName
    }

    $totalGPOs = $gposToBackup.Count
    Write-Host "Found $totalGPOs GPO(s) to backup" -ForegroundColor Green

    # Initialize backup log
    $backupLog = @()
    $successCount = 0
    $failCount = 0
    $counter = 0

    # Backup each GPO
    foreach ($gpo in $gposToBackup) {
        $counter++
        $percentComplete = [math]::Round(($counter / $totalGPOs) * 100)
        Write-Progress -Activity "Backing up GPOs" -Status "Backing up: $($gpo.DisplayName) ($counter of $totalGPOs)" -PercentComplete $percentComplete

        try {
            # Backup the GPO
            $backupInfo = Backup-GPO -Guid $gpo.Id -Path $backupFolder -Comment $Comment -ErrorAction Stop

            # Get additional GPO information
            $gpoReport = [xml](Get-GPOReport -Guid $gpo.Id -ReportType XML)
            $links = $gpoReport.GPO.LinksTo
            $linkCount = if ($links) { @($links).Count } else { 0 }

            # Get WMI filter info
            $wmiFilter = if ($gpo.WmiFilter) { $gpo.WmiFilter.Name } else { "None" }

            # Create detailed backup record
            $backupLog += [PSCustomObject]@{
                GPOName           = $gpo.DisplayName
                GUID              = $gpo.Id
                BackupTime        = Get-Date
                BackupID          = $backupInfo.Id
                Status            = "Success"
                GpoStatus         = $gpo.GpoStatus
                Created           = $gpo.CreationTime
                Modified          = $gpo.ModificationTime
                LinkCount         = $linkCount
                WMIFilter         = $wmiFilter
                Owner             = $gpo.Owner
                ComputerEnabled   = $gpo.Computer.Enabled
                UserEnabled       = $gpo.User.Enabled
                Error             = ""
            }

            $successCount++
            Write-Host "  ✓ $($gpo.DisplayName)" -ForegroundColor Green
        }
        catch {
            $failCount++
            Write-Host "  ✗ $($gpo.DisplayName): $($_.Exception.Message)" -ForegroundColor Red

            $backupLog += [PSCustomObject]@{
                GPOName           = $gpo.DisplayName
                GUID              = $gpo.Id
                BackupTime        = Get-Date
                BackupID          = "N/A"
                Status            = "Failed"
                GpoStatus         = $gpo.GpoStatus
                Created           = $gpo.CreationTime
                Modified          = $gpo.ModificationTime
                LinkCount         = 0
                WMIFilter         = ""
                Owner             = $gpo.Owner
                ComputerEnabled   = $false
                UserEnabled       = $false
                Error             = $_.Exception.Message
            }
        }
    }

    Write-Progress -Activity "Backing up GPOs" -Completed

    # Export backup log
    $logPath = Join-Path -Path $backupFolder -ChildPath "BackupLog.csv"
    $backupLog | Export-Csv -Path $logPath -NoTypeInformation
    Write-Host "`nBackup log saved to: $logPath" -ForegroundColor Cyan

    # Create backup manifest
    $manifest = @{
        BackupDate        = Get-Date
        Domain            = $domainName
        TotalGPOs         = $totalGPOs
        SuccessfulBackups = $successCount
        FailedBackups     = $failCount
        BackupPath        = $backupFolder
        Comment           = $Comment
        BackupBy          = "$env:USERDOMAIN\$env:USERNAME"
    }

    $manifestPath = Join-Path -Path $backupFolder -ChildPath "BackupManifest.json"
    $manifest | ConvertTo-Json -Depth 3 | Out-File -FilePath $manifestPath -Encoding UTF8
    Write-Host "Backup manifest saved to: $manifestPath" -ForegroundColor Cyan

    # Create HTML report
    $reportPath = Join-Path -Path $backupFolder -ChildPath "BackupReport.html"
    $htmlReport = @"
<!DOCTYPE html>
<html>
<head>
    <title>GPO Backup Report - $domainName</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background-color: #f5f5f5; }
        h1 { color: #0066cc; }
        h2 { color: #0099cc; margin-top: 30px; }
        table { border-collapse: collapse; width: 100%; background-color: white; box-shadow: 0 2px 4px rgba(0,0,0,0.1); margin: 20px 0; }
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
        <strong>Domain:</strong> $domainName<br>
        <strong>Backup Date:</strong> $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')<br>
        <strong>Backup Location:</strong> $backupFolder<br>
        <strong>Performed By:</strong> $env:USERDOMAIN\$env:USERNAME<br>
        <strong>Comment:</strong> $Comment
    </div>

    <h2>Backup Summary</h2>
    <table>
        <tr><td><strong>Total GPOs</strong></td><td>$totalGPOs</td></tr>
        <tr><td><strong>Successful Backups</strong></td><td class="success">$successCount</td></tr>
        <tr><td><strong>Failed Backups</strong></td><td class="$(if ($failCount -gt 0) { 'failed' } else { 'success' })">$failCount</td></tr>
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

    foreach ($entry in $backupLog | Sort-Object -Property GPOName) {
        $statusClass = if ($entry.Status -eq "Success") { "success" } else { "failed" }
        $htmlReport += @"
        <tr>
            <td>$($entry.GPOName)</td>
            <td class="$statusClass">$($entry.Status)</td>
            <td>$($entry.BackupID)</td>
            <td>$($entry.Modified.ToString('yyyy-MM-dd HH:mm'))</td>
            <td>$($entry.LinkCount)</td>
        </tr>
"@
    }

    $htmlReport += @"
    </table>
</body>
</html>
"@

    $htmlReport | Out-File -FilePath $reportPath -Encoding UTF8
    Write-Host "HTML report saved to: $reportPath" -ForegroundColor Cyan

    # Compress backup if requested
    if ($CompressBackup) {
        Write-Host "`nCompressing backup..." -ForegroundColor Yellow
        $zipPath = "$backupFolder.zip"

        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::CreateFromDirectory($backupFolder, $zipPath)

        Write-Host "Backup compressed to: $zipPath" -ForegroundColor Green
        $backupSize = [math]::Round((Get-Item $zipPath).Length / 1MB, 2)
        Write-Host "Compressed size: $backupSize MB" -ForegroundColor Cyan
    }

    # Clean up old backups
    if ($RetentionDays -gt 0) {
        Write-Host "`nCleaning up old backups (retention: $RetentionDays days)..." -ForegroundColor Yellow
        $cutoffDate = (Get-Date).AddDays(-$RetentionDays)

        $oldBackups = Get-ChildItem -Path $BackupPath -Directory -Filter "GPO_Backup_*" |
            Where-Object { $_.CreationTime -lt $cutoffDate }

        $oldZips = Get-ChildItem -Path $BackupPath -File -Filter "GPO_Backup_*.zip" |
            Where-Object { $_.CreationTime -lt $cutoffDate }

        $deletedCount = 0

        foreach ($oldBackup in $oldBackups) {
            Remove-Item -Path $oldBackup.FullName -Recurse -Force
            Write-Host "  Deleted: $($oldBackup.Name)" -ForegroundColor Gray
            $deletedCount++
        }

        foreach ($oldZip in $oldZips) {
            Remove-Item -Path $oldZip.FullName -Force
            Write-Host "  Deleted: $($oldZip.Name)" -ForegroundColor Gray
            $deletedCount++
        }

        if ($deletedCount -gt 0) {
            Write-Host "Deleted $deletedCount old backup(s)" -ForegroundColor Green
        }
        else {
            Write-Host "No old backups to delete" -ForegroundColor Green
        }
    }

    # Display summary
    Write-Host "`n=== Backup Complete ===" -ForegroundColor Green
    Write-Host "Successful: $successCount" -ForegroundColor Green
    if ($failCount -gt 0) {
        Write-Host "Failed: $failCount" -ForegroundColor Red
    }
    Write-Host "`nBackup Location: $backupFolder" -ForegroundColor Cyan

    # Open report
    Start-Process $reportPath

}
catch {
    Write-Error "Backup operation failed: $_"
    Write-Error $_.ScriptStackTrace
    exit 1
}

Write-Host "`nEnd Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray
