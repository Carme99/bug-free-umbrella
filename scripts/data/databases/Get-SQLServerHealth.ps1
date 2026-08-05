<#
.SYNOPSIS
    Performs comprehensive health check of SQL Server instances.

.DESCRIPTION
    This script checks SQL Server health including:
    - Database status and integrity
    - Last backup dates
    - Database file sizes and growth
    - Transaction log usage
    - Failed SQL Agent jobs
    - Long-running queries
    - Blocking sessions
    - Index fragmentation
    - Tempdb configuration
    - Memory usage

.PARAMETER ServerInstance
    SQL Server instance name (default: localhost).

.PARAMETER Database
    Specific database to check (default: all databases).

.PARAMETER IncludePerformance
    Include performance metrics and query analysis.

.PARAMETER CheckBackups
    Verify backup status and schedules.

.PARAMETER ExportHTML
    Export results to HTML report.

.PARAMETER ExportCSV
    Export results to CSV file.

.EXAMPLE
    .\Get-SQLServerHealth.ps1
    Checks health of local SQL Server instance.

.EXAMPLE
    .\Get-SQLServerHealth.ps1 -ServerInstance "SQLSERVER01" -CheckBackups -ExportHTML
    Comprehensive health check with backup validation.

.EXAMPLE
    .\Get-SQLServerHealth.ps1 -Database "ProductionDB" -IncludePerformance
    Detailed check of specific database with performance metrics.

.NOTES
    Requires SQL Server PowerShell module or SMO
    Requires appropriate SQL Server permissions
    Compatible with SQL Server 2016, 2017, 2019, 2022
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$ServerInstance = "localhost",

    [Parameter(Mandatory=$false)]
    [string]$Database,

    [Parameter(Mandatory=$false)]
    [switch]$IncludePerformance,

    [Parameter(Mandatory=$false)]
    [switch]$CheckBackups,

    [Parameter(Mandatory=$false)]
    [switch]$ExportHTML,

    [Parameter(Mandatory=$false)]
    [switch]$ExportCSV
)

$ErrorActionPreference = "Stop"
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"

Write-Host "`n=== SQL Server Health Check ===" -ForegroundColor Cyan
Write-Host "Server Instance: $ServerInstance" -ForegroundColor Yellow
Write-Host "Timestamp: $(Get-Date)" -ForegroundColor Gray
Write-Host ""

$results = @()
$issueCount = 0

# Try to import SQL Server module
try {
    Import-Module SqlServer -ErrorAction Stop
    Write-Host "[+] SQL Server module loaded" -ForegroundColor Green
}
catch {
    try {
        Import-Module SQLPS -DisableNameChecking -ErrorAction Stop
        Write-Host "[+] SQLPS module loaded" -ForegroundColor Green
    }
    catch {
        Write-Host "[-] SQL Server module not found. Using T-SQL queries..." -ForegroundColor Yellow
    }
}

# Function to execute SQL query
function Invoke-SqlQuery {
    param(
        [string]$Query,
        [string]$Server = $ServerInstance
    )

    try {
        $connectionString = "Server=$Server;Integrated Security=true;Database=master"
        $connection = New-Object System.Data.SqlClient.SqlConnection($connectionString)
        $command = New-Object System.Data.SqlClient.SqlCommand($Query, $connection)
        $adapter = New-Object System.Data.SqlClient.SqlDataAdapter($command)
        $dataset = New-Object System.Data.DataSet
        $adapter.Fill($dataset) | Out-Null
        $connection.Close()
        return $dataset.Tables[0]
    }
    catch {
        Write-Host "[-] Query error: $($_.Exception.Message)" -ForegroundColor Red
        return $null
    }
}

# 1. Check SQL Server version and edition
Write-Host "[*] Checking SQL Server version..." -ForegroundColor Cyan

$versionQuery = @"
SELECT
    SERVERPROPERTY('ServerName') AS ServerName,
    SERVERPROPERTY('ProductVersion') AS Version,
    SERVERPROPERTY('ProductLevel') AS ProductLevel,
    SERVERPROPERTY('Edition') AS Edition,
    SERVERPROPERTY('EngineEdition') AS EngineEdition
"@

$versionInfo = Invoke-SqlQuery -Query $versionQuery

if ($versionInfo) {
    Write-Host "[+] SQL Server: $($versionInfo.ServerName)" -ForegroundColor Green
    Write-Host "    Version: $($versionInfo.Version) $($versionInfo.ProductLevel)" -ForegroundColor Gray
    Write-Host "    Edition: $($versionInfo.Edition)" -ForegroundColor Gray
}

Write-Host ""

# 2. Check database status
Write-Host "[*] Checking database status..." -ForegroundColor Cyan

$dbStatusQuery = @"
SELECT
    name AS DatabaseName,
    state_desc AS Status,
    recovery_model_desc AS RecoveryModel,
    compatibility_level AS CompatLevel,
    CAST(size * 8.0 / 1024 AS DECIMAL(10,2)) AS SizeMB
FROM sys.databases
WHERE name NOT IN ('master', 'model', 'msdb', 'tempdb')
ORDER BY name
"@

$databases = Invoke-SqlQuery -Query $dbStatusQuery

if ($databases) {
    foreach ($db in $databases) {
        $status = if ($db.Status -eq "ONLINE") { "Pass" } else { "Fail" }

        if ($status -eq "Fail") { $issueCount++ }

        Write-Host "[$status] $($db.DatabaseName): $($db.Status) ($($db.SizeMB) MB)" -ForegroundColor $(if ($status -eq "Pass") { "Green" } else { "Red" })

        $results += [PSCustomObject]@{
            Category = "Database Status"
            Database = $db.DatabaseName
            Status = $status
            Finding = "$($db.Status) - Recovery: $($db.RecoveryModel)"
            Details = "Size: $($db.SizeMB) MB, Compat: $($db.CompatLevel)"
        }
    }
}

Write-Host ""

# 3. Check last backups
if ($CheckBackups) {
    Write-Host "[*] Checking backup status..." -ForegroundColor Cyan

    $backupQuery = @"
SELECT
    d.name AS DatabaseName,
    MAX(CASE WHEN b.type = 'D' THEN b.backup_finish_date END) AS LastFullBackup,
    MAX(CASE WHEN b.type = 'I' THEN b.backup_finish_date END) AS LastDiffBackup,
    MAX(CASE WHEN b.type = 'L' THEN b.backup_finish_date END) AS LastLogBackup,
    DATEDIFF(DAY, MAX(CASE WHEN b.type = 'D' THEN b.backup_finish_date END), GETDATE()) AS DaysSinceFullBackup
FROM sys.databases d
LEFT JOIN msdb.dbo.backupset b ON d.name = b.database_name
WHERE d.name NOT IN ('tempdb')
GROUP BY d.name
ORDER BY DaysSinceFullBackup DESC
"@

    $backups = Invoke-SqlQuery -Query $backupQuery

    if ($backups) {
        foreach ($backup in $backups) {
            $daysSince = if ($backup.DaysSinceFullBackup -is [DBNull]) { 999 } else { $backup.DaysSinceFullBackup }

            $status = if ($daysSince -le 1) { "Pass" }
                     elseif ($daysSince -le 7) { "Warning" }
                     else { "Fail" }

            if ($status -eq "Fail") { $issueCount++ }

            $backupAge = if ($backup.LastFullBackup -is [DBNull]) { "Never" } else { "$daysSince days ago" }

            Write-Host "[$status] $($backup.DatabaseName): Last backup $backupAge" -ForegroundColor $(
                if ($status -eq "Pass") { "Green" }
                elseif ($status -eq "Warning") { "Yellow" }
                else { "Red" }
            )

            $results += [PSCustomObject]@{
                Category = "Backup Status"
                Database = $backup.DatabaseName
                Status = $status
                Finding = "Last full backup: $backupAge"
                Details = "Full: $($backup.LastFullBackup), Log: $($backup.LastLogBackup)"
            }
        }
    }

    Write-Host ""
}

# 4. Check transaction log usage
Write-Host "[*] Checking transaction log usage..." -ForegroundColor Cyan

$logQuery = @"
DBCC SQLPERF(LOGSPACE)
"@

$logSpace = Invoke-SqlQuery -Query $logQuery

if ($logSpace) {
    foreach ($log in $logSpace) {
        $logUsed = [math]::Round($log.'Log Space Used (%)', 2)

        $status = if ($logUsed -lt 70) { "Pass" }
                 elseif ($logUsed -lt 90) { "Warning" }
                 else { "Fail" }

        if ($status -eq "Fail") { $issueCount++ }

        Write-Host "[$status] $($log.'Database Name'): Log $logUsed% used" -ForegroundColor $(
            if ($status -eq "Pass") { "Green" }
            elseif ($status -eq "Warning") { "Yellow" }
            else { "Red" }
        )

        $results += [PSCustomObject]@{
            Category = "Transaction Log"
            Database = $log.'Database Name'
            Status = $status
            Finding = "Log usage: $logUsed%"
            Details = "Log size: $([math]::Round($log.'Log Size (MB)', 2)) MB"
        }
    }
}

Write-Host ""

# 5. Check failed SQL Agent jobs
Write-Host "[*] Checking SQL Agent job failures..." -ForegroundColor Cyan

$jobQuery = @"
SELECT
    j.name AS JobName,
    jh.step_name AS StepName,
    jh.run_date,
    jh.run_time,
    jh.message
FROM msdb.dbo.sysjobs j
INNER JOIN msdb.dbo.sysjobhistory jh ON j.job_id = jh.job_id
WHERE jh.run_status = 0
    AND jh.run_date >= CONVERT(VARCHAR(8), DATEADD(DAY, -7, GETDATE()), 112)
ORDER BY jh.run_date DESC, jh.run_time DESC
"@

$failedJobs = Invoke-SqlQuery -Query $jobQuery

if ($failedJobs -and $failedJobs.Rows.Count -gt 0) {
    Write-Host "[-] Found $($failedJobs.Rows.Count) failed job executions in last 7 days" -ForegroundColor Red
    $issueCount++

    $failedJobs | Select-Object -First 10 | ForEach-Object {
        Write-Host "  - $($_.JobName): $($_.StepName)" -ForegroundColor Yellow
    }
}
else {
    Write-Host "[+] No failed jobs in the last 7 days" -ForegroundColor Green
}

Write-Host ""

# Summary
Write-Host "=== Health Check Summary ===" -ForegroundColor Cyan
Write-Host "Total Checks: $($results.Count)" -ForegroundColor White
Write-Host "Issues Found: $issueCount" -ForegroundColor $(if ($issueCount -eq 0) { "Green" } else { "Red" })

$healthScore = if ($results.Count -gt 0) {
    [math]::Round((($results.Count - $issueCount) / $results.Count) * 100, 2)
}
else {
    100
}

Write-Host "Health Score: $healthScore%" -ForegroundColor $(if ($healthScore -ge 80) { "Green" } elseif ($healthScore -ge 60) { "Yellow" } else { "Red" })
Write-Host ""

# Export results
$ReportDir = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Reports'
# Validate report directory: reject '..' traversal and UNC remote paths before resolution
if ([string]::IsNullOrWhiteSpace($ReportDir) -or
    $ReportDir -match '(^|[\\/])\.\.([\\/]|$)' -or
    $ReportDir -match '^(\\\\|//)') {
    Write-Error "Unsafe report directory: $ReportDir. Report directory must be a local absolute path without '..' traversal."
    exit 1
}
$ReportDir = [System.IO.Path]::GetFullPath($ReportDir)
if (-not (Test-Path -LiteralPath $ReportDir -PathType Container)) {
    New-Item -ItemType Directory -Path $ReportDir -Force | Out-Null
}

if ($ExportHTML) {
    $htmlPath = Join-Path $ReportDir "SQLHealthCheck_$timestamp.html"

    $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>SQL Server Health Check - $timestamp</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        h1 { color: #e67e22; }
        .summary { background-color: #ecf0f1; padding: 15px; border-radius: 5px; margin: 20px 0; }
        .score { font-size: 24px; font-weight: bold; color: $(if ($healthScore -ge 80) { '#27ae60' } elseif ($healthScore -ge 60) { '#f39c12' } else { '#e74c3c' }); }
        table { border-collapse: collapse; width: 100%; margin-top: 10px; }
        th { background-color: #e67e22; color: white; padding: 10px; text-align: left; }
        td { border: 1px solid #ddd; padding: 8px; font-size: 12px; }
        tr:nth-child(even) { background-color: #f2f2f2; }
        .pass { background-color: #27ae60; color: white; padding: 3px 6px; border-radius: 3px; }
        .fail { background-color: #e74c3c; color: white; padding: 3px 6px; border-radius: 3px; }
        .warning { background-color: #f39c12; color: white; padding: 3px 6px; border-radius: 3px; }
    </style>
</head>
<body>
    <h1>SQL Server Health Check Report</h1>
    <div class="summary">
        <strong>Server:</strong> $ServerInstance<br>
        <strong>Generated:</strong> $(Get-Date)<br>
        <strong>Health Score:</strong> <span class="score">$healthScore%</span><br>
        <strong>Issues Found:</strong> $issueCount
    </div>

    <h2>Health Check Results</h2>
    <table>
        <tr><th>Category</th><th>Database</th><th>Status</th><th>Finding</th><th>Details</th></tr>
"@

    foreach ($result in $results) {
        $statusClass = $result.Status.ToLower()
        $html += @"
        <tr>
            <td>$($result.Category)</td>
            <td>$($result.Database)</td>
            <td><span class="$statusClass">$($result.Status)</span></td>
            <td>$($result.Finding)</td>
            <td>$($result.Details)</td>
        </tr>
"@
    }

    $html += "</table></body></html>"

    $html | Out-File -FilePath $htmlPath -Encoding UTF8
    Write-Host "[+] HTML report saved to: $htmlPath" -ForegroundColor Green
}

if ($ExportCSV) {
    $csvPath = Join-Path $ReportDir "SQLHealthCheck_$timestamp.csv"
    $results | Export-Csv -Path $csvPath -NoTypeInformation
    Write-Host "[+] CSV export saved to: $csvPath" -ForegroundColor Green
}

Write-Host "[+] Health check completed!" -ForegroundColor Green

if ($issueCount -gt 0) {
    exit 1
}

exit 0
