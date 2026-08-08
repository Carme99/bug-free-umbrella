<#
.SYNOPSIS
    Verifies Windows Server Backup status and configuration.

.DESCRIPTION
    This script checks Windows Server Backup configuration, backup schedules,
    recent backup history, and validates backup integrity. Provides comprehensive
    reporting on backup health and identifies potential issues.

.PARAMETER CheckDays
    Number of days to check for backup history. Default is 30 days.

.PARAMETER OutputPath
    Path where the report will be saved.

.PARAMETER ValidateBackups
    Switch to perform integrity validation on recent backups (slower).

.PARAMETER AlertIfNoBackup
    Switch to alert if no backups found within specified days.

.PARAMETER EmailReport
    Switch to email the report (requires email configuration).

.PARAMETER EmailTo
    Email address to send report to (requires -EmailReport).

.PARAMETER SMTPServer
    SMTP server for sending email reports.

.EXAMPLE
    .\Get-BackupStatus.ps1 -OutputPath "C:\Reports"
    Checks backup status for the last 30 days.

.EXAMPLE
    .\Get-BackupStatus.ps1 -CheckDays 7 -AlertIfNoBackup -ValidateBackups
    Checks last 7 days, alerts if no backups, and validates backup integrity.

.NOTES
    Author: Server Management Team
    Requires: Windows Server Backup feature installed, Administrator privileges
    Version: 1.0
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [int]$CheckDays = 30,

    [Parameter(Mandatory = $false)]
    [string]$OutputPath = "$env:TEMP\BackupStatus_$(Get-Date -Format 'yyyyMMdd_HHmmss')",

    [Parameter(Mandatory = $false)]
    [switch]$ValidateBackups,

    [Parameter(Mandatory = $false)]
    [switch]$AlertIfNoBackup,

    [Parameter(Mandatory = $false)]
    [switch]$EmailReport,

    [Parameter(Mandatory = $false)]
    [string]$EmailTo,

    [Parameter(Mandatory = $false)]
    [string]$SMTPServer
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

Write-Host "`n=== Windows Server Backup Status Report ===" -ForegroundColor Cyan
Write-Host "Start Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray
Write-Host "Server: $env:COMPUTERNAME" -ForegroundColor Cyan

# Check if Windows Server Backup is installed
try {
    $wsbFeature = Get-WindowsFeature -Name Windows-Server-Backup -ErrorAction Stop
    if (-not $wsbFeature.Installed) {
        Write-Host "`nERROR: Windows Server Backup feature is not installed" -ForegroundColor Red
        Write-Host "Install with: Install-WindowsFeature Windows-Server-Backup" -ForegroundColor Yellow
        exit 1
    }
}
catch {
    Write-Warning "Could not verify Windows Server Backup feature. Continuing anyway..."
}

# Import backup module
try {
    Import-Module WindowsServerBackup -ErrorAction Stop
}
catch {
    Write-Error "Failed to load Windows Server Backup module: $_"
    exit 1
}

# Create output directory
if (-not (Test-Path -Path $OutputPath)) {
    New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
}

$report = @{
    ServerName = $env:COMPUTERNAME
    ReportTime = Get-Date
    BackupPolicy = $null
    RecentBackups = @()
    BackupTargets = @()
    Issues = @()
    Status = "Unknown"
}

try {
    # Get backup policy
    Write-Host "`nChecking backup policy..." -ForegroundColor Yellow
    $policy = Get-WBPolicy -ErrorAction SilentlyContinue

    if ($policy) {
        Write-Host "Backup policy found" -ForegroundColor Green

        $report.BackupPolicy = @{
            Schedule = $policy.Schedule
            BackupTargets = @($policy.BackupTargets | ForEach-Object {
                    @{
                        TargetType = $_.TargetType
                        TargetPath = $_.TargetPath
                    }
                })
            VolumesToBackup = @($policy.VolumesToBackup)
            BMREnabled = $policy.BMRBackupEnabled
            SystemStateEnabled = $policy.SystemStateBackupEnabled
        }

        Write-Host "  Backup Schedule: $($policy.Schedule)" -ForegroundColor Cyan
        Write-Host "  System State: $(if ($policy.SystemStateBackupEnabled) { 'Enabled' } else { 'Disabled' })" -ForegroundColor Cyan
        Write-Host "  Bare Metal Recovery: $(if ($policy.BMRBackupEnabled) { 'Enabled' } else { 'Disabled' })" -ForegroundColor Cyan
    }
    else {
        Write-Host "No backup policy configured" -ForegroundColor Yellow
        $report.Issues += "No backup policy configured on this server"
    }

    # Get backup targets
    Write-Host "`nChecking backup targets..." -ForegroundColor Yellow
    $targets = Get-WBBackupTarget -ErrorAction SilentlyContinue

    if ($targets) {
        foreach ($target in $targets) {
            $targetInfo = @{
                Type = $target.TargetType
                Path = $target.TargetPath
                Available = Test-Path -Path $target.TargetPath -ErrorAction SilentlyContinue
            }

            $report.BackupTargets += $targetInfo

            Write-Host "  Target: $($target.TargetPath)" -ForegroundColor Cyan
            Write-Host "  Type: $($target.TargetType)" -ForegroundColor Cyan
            Write-Host "  Available: $(if ($targetInfo.Available) { 'Yes' } else { 'No' })" -ForegroundColor $(if ($targetInfo.Available) { 'Green' } else { 'Red' })

            if (-not $targetInfo.Available) {
                $report.Issues += "Backup target not available: $($target.TargetPath)"
            }
        }
    }
    else {
        Write-Host "No backup targets found" -ForegroundColor Yellow
    }

    # Get backup history
    Write-Host "`nRetrieving backup history (last $CheckDays days)..." -ForegroundColor Yellow
    $cutoffDate = (Get-Date).AddDays(-$CheckDays)

    try {
        $backups = Get-WBBackupSet -ErrorAction Stop | Where-Object {
            $_.BackupTime -gt $cutoffDate
        } | Sort-Object -Property BackupTime -Descending

        # WBBackupSet objects do not document a ResultHR property; derive the latest
        # run result from Get-WBSummary (LastBackupResultHR, 0 = success) instead.
        try {
            $wbSummary = Get-WBSummary -ErrorAction Stop
            if ($wbSummary -and $null -ne $wbSummary.LastBackupResultHR) {
                $latestResultHR = $wbSummary.LastBackupResultHR
                $latestTime = $wbSummary.LastBackupTime

                if ($latestResultHR -ne 0) {
                    $report.Issues += "Latest backup run failed on ${latestTime}: Error 0x$($latestResultHR.ToString('X'))"
                }

                Write-Host "`n  Latest run: $latestTime" -ForegroundColor Cyan
                Write-Host "  Latest run status: $(if ($latestResultHR -eq 0) { 'Success' } else { "Failed (0x$($latestResultHR.ToString('X')))" })" -ForegroundColor $(if ($latestResultHR -eq 0) { 'Green' } else { 'Red' })
            }
        }
        catch {
            Write-Warning "Could not retrieve backup summary: $_"
        }

        if ($backups) {
            Write-Host "Found $($backups.Count) backup(s)" -ForegroundColor Green

            foreach ($backup in $backups) {
                # Get-WBBackupSet does not document a ResultHR property; guard it so a
                # $null value is not treated as a failure. 0 = success when present.
                $backupResultHR = $backup.ResultHR
                $backupSucceeded = if ($null -ne $backupResultHR) { $backupResultHR -eq 0 } else { $null }

                $backupInfo = @{
                    BackupTime = $backup.BackupTime
                    BackupTarget = $backup.BackupTarget
                    VersionId = $backup.VersionId
                    SnapshotId = $backup.SnapshotId
                    Success = $backupSucceeded
                    ResultCode = $backupResultHR
                    Components = @($backup.Component)
                }

                $report.RecentBackups += $backupInfo

                $statusColor = if ($backupSucceeded -eq $true) { 'Green' } elseif ($backupSucceeded -eq $false) { 'Red' } else { 'Yellow' }
                $statusText = if ($backupSucceeded -eq $true) { 'Success' } elseif ($backupSucceeded -eq $false) { "Failed (0x$($backupResultHR.ToString('X')))" } else { 'Unknown' }

                Write-Host "`n  Backup: $($backup.BackupTime)" -ForegroundColor Cyan
                Write-Host "  Status: $statusText" -ForegroundColor $statusColor
                Write-Host "  Target: $($backup.BackupTarget)" -ForegroundColor Gray

                if ($backupSucceeded -eq $false) {
                    $report.Issues += "Backup failed on $($backup.BackupTime): Error 0x$($backupResultHR.ToString('X'))"
                }
            }

            # Check for recent successful backup
            $lastSuccessfulBackup = $backups | Where-Object { $null -ne $_.ResultHR -and $_.ResultHR -eq 0 } | Select-Object -First 1

            if ($lastSuccessfulBackup) {
                $daysSinceBackup = ((Get-Date) - $lastSuccessfulBackup.BackupTime).Days

                Write-Host "`nLast Successful Backup: $($lastSuccessfulBackup.BackupTime)" -ForegroundColor Green
                Write-Host "Days Since Last Backup: $daysSinceBackup" -ForegroundColor $(if ($daysSinceBackup -le 1) { 'Green' } elseif ($daysSinceBackup -le 7) { 'Yellow' } else { 'Red' })

                if ($daysSinceBackup -gt 7) {
                    $report.Issues += "Last successful backup was $daysSinceBackup days ago"
                }

                $report.Status = "OK"
            }
            else {
                Write-Host "`nWARNING: No successful backups in the last $CheckDays days" -ForegroundColor Red
                $report.Issues += "No successful backups in the last $CheckDays days"
                $report.Status = "Warning"
            }
        }
        else {
            Write-Host "No backups found in the last $CheckDays days" -ForegroundColor Yellow
            $report.Issues += "No backups found in the last $CheckDays days"
            $report.Status = "Warning"

            if ($AlertIfNoBackup) {
                Write-Host "`nALERT: No backups found!" -ForegroundColor Red -BackgroundColor Yellow
            }
        }
    }
    catch {
        Write-Warning "Could not retrieve backup history: $_"
        $report.Issues += "Failed to retrieve backup history: $_"
    }

    # Validate backups if requested
    if ($ValidateBackups -and $backups) {
        Write-Host "`nValidating backup integrity..." -ForegroundColor Yellow

        foreach ($backup in $backups | Select-Object -First 3) {
            try {
                Write-Host "  Validating backup from $($backup.BackupTime)..." -ForegroundColor Gray

                # Basic validation - check if backup files exist
                $backupPath = $backup.BackupTarget
                if (Test-Path -Path $backupPath) {
                    Write-Host "    ✓ Backup files accessible" -ForegroundColor Green
                }
                else {
                    Write-Host "    ✗ Backup files not accessible" -ForegroundColor Red
                    $report.Issues += "Backup files not accessible: $backupPath"
                }
            }
            catch {
                Write-Host "    ✗ Validation failed: $_" -ForegroundColor Red
                $report.Issues += "Backup validation failed for $($backup.BackupTime): $_"
            }
        }
    }

    # Generate summary
    Write-Host "`n=== Backup Status Summary ===" -ForegroundColor Cyan
    Write-Host "Server: $env:COMPUTERNAME" -ForegroundColor White
    Write-Host "Policy Configured: $(if ($policy) { 'Yes' } else { 'No' })" -ForegroundColor $(if ($policy) { 'Green' } else { 'Yellow' })
    Write-Host "Backups Found: $($backups.Count)" -ForegroundColor Cyan
    Write-Host "Issues Detected: $($report.Issues.Count)" -ForegroundColor $(if ($report.Issues.Count -eq 0) { 'Green' } else { 'Red' })

    if ($report.Issues.Count -gt 0) {
        Write-Host "`nIssues:" -ForegroundColor Yellow
        foreach ($issue in $report.Issues) {
            Write-Host "  • $issue" -ForegroundColor Yellow
        }
    }

    # Export report
    $jsonPath = Join-Path -Path $OutputPath -ChildPath "BackupStatus.json"
    $report | ConvertTo-Json -Depth 5 | Out-File -FilePath $jsonPath -Encoding UTF8
    Write-Host "`nReport saved to: $jsonPath" -ForegroundColor Green

    # Generate HTML report
    $htmlPath = Join-Path -Path $OutputPath -ChildPath "BackupStatusReport.html"

    $issuesHtml = if ($report.Issues.Count -gt 0) {
        "<h2>Issues Detected</h2><ul>"
        foreach ($issue in $report.Issues) {
            $issuesHtml += "<li>$([System.Net.WebUtility]::HtmlEncode("$issue"))</li>"
        }
        $issuesHtml += "</ul>"
    }
    else {
        "<p style='color: green;'><strong>No issues detected</strong></p>"
    }

    $backupsTableHtml = ""
    if ($report.RecentBackups.Count -gt 0) {
        $backupsTableHtml = "<h2>Recent Backups</h2><table><tr><th>Backup Time</th><th>Status</th><th>Target</th></tr>"
        foreach ($bk in $report.RecentBackups) {
            $statusClass = if ($bk.Success) { "success" } else { "failed" }
            $statusText = if ($bk.Success) { "Success" } else { "Failed" }
            $backupsTableHtml += "<tr><td>$($bk.BackupTime)</td><td class='$statusClass'>$statusText</td><td>$([System.Net.WebUtility]::HtmlEncode("$($bk.BackupTarget)"))</td></tr>"
        }
        $backupsTableHtml += "</table>"
    }

    $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>Backup Status Report - $([System.Net.WebUtility]::HtmlEncode("$env:COMPUTERNAME"))</title>
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
        .warning { background-color: #fff3cd; padding: 15px; border-left: 4px solid #ffc107; margin: 20px 0; }
        ul { line-height: 1.8; }
    </style>
</head>
<body>
    <h1>Windows Server Backup Status</h1>
    <div class="info">
        <strong>Server:</strong> $([System.Net.WebUtility]::HtmlEncode("$env:COMPUTERNAME"))<br>
        <strong>Report Time:</strong> $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')<br>
        <strong>Status:</strong> $([System.Net.WebUtility]::HtmlEncode("$($report.Status)"))
    </div>

    <h2>Configuration</h2>
    <table>
        <tr><td><strong>Backup Policy Configured</strong></td><td>$(if ($policy) { 'Yes' } else { 'No' })</td></tr>
        <tr><td><strong>System State Backup</strong></td><td>$(if ($policy.SystemStateBackupEnabled) { 'Enabled' } else { 'Disabled' })</td></tr>
        <tr><td><strong>Bare Metal Recovery</strong></td><td>$(if ($policy.BMRBackupEnabled) { 'Enabled' } else { 'Disabled' })</td></tr>
        <tr><td><strong>Backups Found</strong></td><td>$($report.RecentBackups.Count)</td></tr>
        <tr><td><strong>Issues Detected</strong></td><td>$($report.Issues.Count)</td></tr>
    </table>

    $backupsTableHtml

    $issuesHtml

</body>
</html>
"@

    $html | Out-File -FilePath $htmlPath -Encoding UTF8
    Write-Host "HTML report saved to: $htmlPath" -ForegroundColor Green

    # Email report if requested
    if ($EmailReport -and $EmailTo -and $SMTPServer) {
        try {
            $emailSubject = "Backup Status Report - $($env:COMPUTERNAME) - $($report.Status)"
            $emailBody = Get-Content -Path $htmlPath -Raw

            # Send-MailMessage is obsolete; use System.Net.Mail.SmtpClient instead.
            # The existing call used the SmtpClient defaults (port 25, no SSL).
            $smtpClient = New-Object System.Net.Mail.SmtpClient($SMTPServer)
            $mailMessage = New-Object System.Net.Mail.MailMessage
            $mailMessage.From = (New-Object System.Net.Mail.MailAddress("backup-report@$env:USERDNSDOMAIN"))
            $mailMessage.To.Add($EmailTo)
            $mailMessage.Subject = $emailSubject
            $mailMessage.Body = $emailBody
            $mailMessage.IsBodyHtml = $true

            $smtpClient.Send($mailMessage)
            $mailMessage.Dispose()
            $smtpClient.Dispose()

            Write-Host "`nEmail sent to: $EmailTo" -ForegroundColor Green
        }
        catch {
            Write-Warning "Failed to send email: $_"
        }
    }

}
catch {
    Write-Error "Error checking backup status: $_"
    Write-Error $_.ScriptStackTrace
    exit 1
}

Write-Host "`nEnd Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray
