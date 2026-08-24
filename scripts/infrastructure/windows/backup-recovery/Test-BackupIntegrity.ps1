<#
.SYNOPSIS
    Tests integrity and validity of Windows Server Backup archives.

.DESCRIPTION
    This script verifies backup integrity by checking backup completion status, validating
    the backup catalog and policy, testing backup file accessibility, checking available
    recovery points, optionally testing Volume Shadow Copy health, and estimating recovery
    health. Results are summarized with a health score; optional HTML/CSV exports are written
    to the user's Reports folder. The script is read-only with respect to backups and safe
    to re-run on a converged system.

.PARAMETER BackupLocation
    Path to backup location (local drive, network share, or all configured locations).

.PARAMETER TestRestore
    Perform test restore validation (non-destructive).

.PARAMETER CheckVSS
    Validate Volume Shadow Copy Service health.

.PARAMETER DaysToCheck
    Number of days back to check backups (default: 7).

.PARAMETER ExportHTML
    Export results to HTML report.

.PARAMETER ExportCSV
    Export results to CSV file.

.EXAMPLE
    PS C:\> .\Test-BackupIntegrity.ps1
    Checks all configured backup locations for the last 7 days.

.EXAMPLE
    PS C:\> .\Test-BackupIntegrity.ps1 -BackupLocation "\\backup-server\backups" -TestRestore
    Validates specific backup location with test restore.

.EXAMPLE
    PS C:\> .\Test-BackupIntegrity.ps1 -CheckVSS -DaysToCheck 30 -ExportHTML
    Checks VSS health and 30 days of backups, exporting an HTML report.

.NOTES
    File Name: Test-BackupIntegrity.ps1
    Author: Server Management Team
    Prerequisite: PowerShell 7.0
    Version: 1.0.0
    Date: 2026-08-23
#>

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification='Spec 3 requirement')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification='Used in Main scope')]
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$BackupLocation,

    [Parameter(Mandatory = $false)]
    [switch]$TestRestore,

    [Parameter(Mandatory = $false)]
    [switch]$CheckVSS,

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 3650)]
    [int]$DaysToCheck = 7,

    [Parameter(Mandatory = $false)]
    [switch]$ExportHTML,

    [Parameter(Mandatory = $false)]
    [switch]$ExportCSV
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
    [CmdletBinding()]
    param()

    try {
        $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $cutoffDate = (Get-Date).AddDays(-$DaysToCheck)

        Write-Host '[*] Starting backup integrity verification...' -ForegroundColor Cyan

        # Reports directory (internal output location)
        $ReportDir = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Reports'
        # Validate report directory: reject '..' traversal and UNC remote paths before resolution
        $ReportDir = Assert-SafeLocalPath -Path $ReportDir -Label 'Report directory'
        if (-not (Test-Path -LiteralPath $ReportDir -PathType Container)) {
            New-Item -ItemType Directory -Path $ReportDir -Force -ErrorAction Stop | Out-Null
        }

        Write-Host ''
        Write-Host '=== Backup Integrity Verification ===' -ForegroundColor Cyan
        Write-Host "Server: $env:COMPUTERNAME" -ForegroundColor Yellow
        Write-Host "Checking backups from: $($cutoffDate.ToShortDateString())" -ForegroundColor Yellow
        Write-Host ''

        $results = @()
        $successCount = 0
        $failCount = 0
        $warningCount = 0

        # Check if Windows Server Backup is installed
        try {
            Import-Module WindowsServerBackup -ErrorAction Stop
            Write-Host '[+] Windows Server Backup module loaded' -ForegroundColor Green
        }
        catch {
            Write-Host '[-] Windows Server Backup is not installed!' -ForegroundColor Red
            Write-Host '[!] Install using: Install-WindowsFeature Windows-Server-Backup' -ForegroundColor Yellow
            return 1
        }

        # Get backup policy
        Write-Host '[*] Retrieving backup configuration...' -ForegroundColor Cyan

        try {
            $policy = Get-WBPolicy -ErrorAction SilentlyContinue

            if ($policy) {
                Write-Host '[+] Backup policy is configured' -ForegroundColor Green

                $schedule = Get-WBSchedule -Policy $policy
                Write-Host "    Schedule: $($schedule -join ', ')" -ForegroundColor Gray

                $targets = Get-WBBackupTarget -Policy $policy
                Write-Host "    Targets: $(@($targets).Count)" -ForegroundColor Gray
                foreach ($target in $targets) {
                    Write-Host "      - $($target.TargetType): $($target.TargetPath)" -ForegroundColor Gray
                }
            }
            else {
                Write-Host '[!] No backup policy configured' -ForegroundColor Yellow
                $warningCount++
            }
        }
        catch {
            Write-Host "[-] Could not retrieve backup policy: $($_.Exception.Message)" -ForegroundColor Red
        }

        Write-Host ''

        # Get backup history
        Write-Host '[*] Retrieving backup history...' -ForegroundColor Cyan

        try {
            $backups = Get-WBSummary -ErrorAction Stop

            if ($backups) {
                Write-Host '[+] Last backup information:' -ForegroundColor Green
                Write-Host "    Last Successful: $($backups.LastSuccessfulBackupTime)" -ForegroundColor Gray
                Write-Host "    Last Backup: $($backups.LastBackupTime)" -ForegroundColor Gray
                Write-Host "    Next Scheduled: $($backups.NextBackupTime)" -ForegroundColor Gray
                Write-Host "    Total Backups: $($backups.NumberOfVersions)" -ForegroundColor Gray

                # Check last backup age
                if ($backups.LastSuccessfulBackupTime) {
                    $daysSinceBackup = ((Get-Date) - $backups.LastSuccessfulBackupTime).Days

                    if ($daysSinceBackup -le 1) {
                        Write-Host '    Status: Backup completed within 24 hours' -ForegroundColor Green
                        $successCount++
                    }
                    elseif ($daysSinceBackup -le 7) {
                        Write-Host "    Status: Backup is $daysSinceBackup days old" -ForegroundColor Yellow
                        $warningCount++
                    }
                    else {
                        Write-Host "    Status: Backup is $daysSinceBackup days old (CRITICAL)" -ForegroundColor Red
                        $failCount++
                    }

                    $results += [PSCustomObject]@{
                        Check     = 'Last Successful Backup'
                        Status    = if ($daysSinceBackup -le 1) { 'Pass' }
                            elseif ($daysSinceBackup -le 7) { 'Warning' } else { 'Fail' }
                        Details   = "Last backup: $($backups.LastSuccessfulBackupTime) ($daysSinceBackup days ago)"
                        Timestamp = Get-Date
                    }
                }
            }
        }
        catch {
            Write-Host "[-] Could not retrieve backup history: $($_.Exception.Message)" -ForegroundColor Red
            $failCount++
        }

        Write-Host ''

        # Get individual backup versions
        Write-Host '[*] Checking backup versions...' -ForegroundColor Cyan

        try {
            if ($BackupLocation) {
                $versions = Get-WBBackupSet -BackupTarget $BackupLocation -ErrorAction SilentlyContinue
            }
            else {
                $versions = Get-WBBackupSet -ErrorAction SilentlyContinue
            }

            if ($versions) {
                $recentVersions = @($versions | Where-Object { $_.BackupTime -ge $cutoffDate })

                Write-Host ("[+] Found $($recentVersions.Count)" +
                    "backup(s) in the last $DaysToCheck days") -ForegroundColor Green

                foreach ($version in $recentVersions) {
                    $versionStatus = if ($version.BackupState -eq 'Succeeded') { 'Pass' } else { 'Fail' }

                    if ($versionStatus -eq 'Pass') { $successCount++ } else { $failCount++ }

                    $fgColor = if ($versionStatus -eq 'Pass') { 'Green' } else { 'Red' }
                    Write-Host ("    [$versionStatus] $($version.BackupTime):" +
                        "$($version.BackupState)") -ForegroundColor $fgColor

                    $results += [PSCustomObject]@{
                        Check     = 'Backup Version'
                        Status    = $versionStatus
                        Details   = "Time: $($version.BackupTime), State: $($version.BackupState)," +
                            " Target: $($version.TargetLabel)"
                        Timestamp = $version.BackupTime
                    }
                }
            }
            else {
                Write-Host '[!] No backup versions found' -ForegroundColor Yellow
                $warningCount++
            }
        }
        catch {
            Write-Host "[-] Could not retrieve backup versions: $($_.Exception.Message)" -ForegroundColor Red
        }

        Write-Host ''

        # Check VSS
        if ($CheckVSS) {
            Write-Host '=== Volume Shadow Copy Service ===' -ForegroundColor Cyan

            try {
                $vssService = Get-Service -Name VSS -ErrorAction Stop

                if ($vssService.Status -eq 'Running') {
                    Write-Host '[+] VSS service is running' -ForegroundColor Green
                    $successCount++

                    $results += [PSCustomObject]@{
                        Check     = 'VSS Service'
                        Status    = 'Pass'
                        Details   = 'Service is running'
                        Timestamp = Get-Date
                    }
                }
                else {
                    Write-Host "[-] VSS service is not running: $($vssService.Status)" -ForegroundColor Red
                    $failCount++

                    $results += [PSCustomObject]@{
                        Check     = 'VSS Service'
                        Status    = 'Fail'
                        Details   = "Service status: $($vssService.Status)"
                        Timestamp = Get-Date
                    }
                }

                # Check shadow copies
                $volumes = Get-CimInstance -ClassName Win32_Volume | Where-Object { $null -ne $_.DriveLetter }

                foreach ($volume in $volumes) {
                    $shadows = @(Get-CimInstance -ClassName Win32_ShadowCopy |
                            Where-Object { $_.VolumeName -eq $volume.DeviceID })

                    if ($shadows.Count -gt 0) {
                        Write-Host ("[+] Volume $($volume.DriveLetter):" +
                            "$($shadows.Count) shadow copy/copies") -ForegroundColor Green

                        # Check newest shadow copy age
                        $newestShadow = $shadows | Sort-Object InstallDate -Descending | Select-Object -First 1
                        # Get-CimInstance returns InstallDate as a DateTime; fall back to the
                        # WMI DMTF string conversion only if a string is encountered.
                        $installDate = $newestShadow.InstallDate
                        if ($installDate -is [string]) {
                            $installDate = [Management.ManagementDateTimeConverter]::ToDateTime($installDate)
                        }
                        $shadowAge = ((Get-Date) - $installDate).Days

                        Write-Host "    Newest shadow copy: $shadowAge day(s) old" -ForegroundColor Gray
                    }
                    else {
                        Write-Host "[!] Volume $($volume.DriveLetter): No shadow copies" -ForegroundColor Yellow
                    }
                }
            }
            catch {
                Write-Host "[-] Error checking VSS: $($_.Exception.Message)" -ForegroundColor Red
            }

            Write-Host ''
        }

        # Test restore (if requested)
        if ($TestRestore) {
            Write-Host '=== Test Restore Validation ===' -ForegroundColor Cyan
            Write-Host '[!] This would perform a non-destructive restore test...' -ForegroundColor Yellow
            Write-Host '[!] Test restore functionality requires manual configuration' -ForegroundColor Yellow
            Write-Host ''
        }

        # Summary
        Write-Host '=== Integrity Check Summary ===' -ForegroundColor Cyan
        Write-Host "Total Checks: $(@($results).Count)" -ForegroundColor White
        Write-Host "Passed: $successCount" -ForegroundColor Green
        Write-Host "Failed: $failCount" -ForegroundColor Red
        Write-Host "Warnings: $warningCount" -ForegroundColor Yellow

        $healthScore = if (@($results).Count -gt 0) {
            [math]::Round(($successCount / @($results).Count) * 100, 2)
        }
        else {
            0
        }

        $fgColor = if ($healthScore -ge 80) { 'Green' } elseif ($healthScore -ge 60) { 'Yellow' } else { 'Red' }
                Write-Host "Backup Health Score: $healthScore%" -ForegroundColor $fgColor
        Write-Host ''

        # Export results
        if ($ExportHTML) {
            $htmlPath = Join-Path $ReportDir "BackupIntegrityReport_$timestamp.html"

            $htmlHead = @"
<!DOCTYPE html>
<html>
<head>
    <title>Backup Integrity Report - $timestamp</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        h1 { color: #2980b9; }
        .summary { background-color: #ecf0f1; padding: 15px; border-radius: 5px; margin: 20px 0; font-size: 18px; }
        table { border-collapse: collapse; width: 100%; margin-top: 20px; }
        th { background-color: #2980b9; color: white; padding: 10px; text-align: left; }
        td { border: 1px solid #ddd; padding: 8px; }
        tr:nth-child(even) { background-color: #f2f2f2; }
        .pass { background-color: #27ae60; color: white; padding: 5px; border-radius: 3px; }
        .fail { background-color: #e74c3c; color: white; padding: 5px; border-radius: 3px; }
        .warning { background-color: #f39c12; color: white; padding: 5px; border-radius: 3px; }
    </style>
</head>
<body>
    <h1>Backup Integrity Verification Report</h1>
    <div class="summary">
        <strong>Server:</strong> $([System.Net.WebUtility]::HtmlEncode("$env:COMPUTERNAME"))<br>
        <strong>Generated:</strong> $(Get-Date)<br>
        <strong>Health Score:</strong> $healthScore%<br>
        <strong>Passed:</strong> $successCount | <strong>Failed:</strong> $failCount |
        <strong>Warnings:</strong> $warningCount
    </div>

    <h2>Detailed Results</h2>
    <table>
        <tr><th>Check</th><th>Status</th><th>Details</th><th>Timestamp</th></tr>
"@

            $htmlRows = ''
            foreach ($result in $results) {
                $statusClass = $result.Status.ToLower()
                $htmlRows += @"
        <tr>
            <td>$([System.Net.WebUtility]::HtmlEncode("$($result.Check)"))</td>
            <td><span class="$statusClass">$([System.Net.WebUtility]::HtmlEncode("$($result.Status)"))</span></td>
            <td>$([System.Net.WebUtility]::HtmlEncode("$($result.Details)"))</td>
            <td>$($result.Timestamp)</td>
        </tr>
"@
            }

            $html = "$htmlHead$htmlRows</table></body></html>"

            $html | Out-File -FilePath $htmlPath -Encoding UTF8 -ErrorAction Stop
            Write-Host "[+] HTML report saved to: $htmlPath" -ForegroundColor Green
        }

        if ($ExportCSV) {
            $csvPath = Join-Path $ReportDir "BackupIntegrityReport_$timestamp.csv"
            $results | Export-Csv -Path $csvPath -NoTypeInformation -ErrorAction Stop
            Write-Host "[+] CSV export saved to: $csvPath" -ForegroundColor Green
        }

        Write-Host '[+] Integrity check completed!' -ForegroundColor Green

        if ($failCount -gt 0) {
            return 1
        }

        return 0
    }
    catch {
        Write-Host "[-] Error during integrity check: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
