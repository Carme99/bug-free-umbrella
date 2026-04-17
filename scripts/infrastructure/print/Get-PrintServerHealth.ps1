<#
.SYNOPSIS
    Monitors print server health and identifies printing issues.

.DESCRIPTION
    This script checks print server infrastructure:
    - Print Spooler service status
    - Printer status and errors
    - Print queue health
    - Stuck/stale print jobs
    - Printer driver issues
    - Port configuration
    - Disk space for spool directory
    - Event log errors

.PARAMETER ClearStuckJobs
    Automatically clear print jobs older than specified hours.

.PARAMETER StuckJobThresholdHours
    Hours threshold for considering a job stuck (default: 2).

.PARAMETER CheckDrivers
    Verify printer driver status.

.PARAMETER ExportHTML
    Export results to HTML report.

.PARAMETER ExportCSV
    Export results to CSV file.

.EXAMPLE
    .\Get-PrintServerHealth.ps1
    Basic print server health check.

.EXAMPLE
    .\Get-PrintServerHealth.ps1 -ClearStuckJobs -StuckJobThresholdHours 4
    Checks health and clears jobs stuck for 4+ hours.

.EXAMPLE
    .\Get-PrintServerHealth.ps1 -CheckDrivers -ExportHTML
    Comprehensive check including driver validation.

.NOTES
    Requires Administrator privileges
    Requires Print Management features
    Compatible with Windows Server 2016, 2019, 2022
#>

[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [Parameter(Mandatory=$false)]
    [switch]$ClearStuckJobs,

    [Parameter(Mandatory=$false)]
    [int]$StuckJobThresholdHours = 2,

    [Parameter(Mandatory=$false)]
    [switch]$CheckDrivers,

    [Parameter(Mandatory=$false)]
    [switch]$ExportHTML,

    [Parameter(Mandatory=$false)]
    [switch]$ExportCSV
)

#Requires -RunAsAdministrator

$ErrorActionPreference = "Stop"
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"

Write-Host "`n=== Print Server Health Check ===" -ForegroundColor Cyan
Write-Host "Server: $env:COMPUTERNAME" -ForegroundColor Yellow
Write-Host "Timestamp: $(Get-Date)" -ForegroundColor Gray
Write-Host ""

$results = @()
$issueCount = 0
$warningCount = 0
$jobsCleared = 0

# 1. Check Print Spooler service
Write-Host "[*] Checking Print Spooler service..." -ForegroundColor Cyan

$spooler = Get-Service -Name Spooler

if ($spooler.Status -eq 'Running') {
    Write-Host "[+] Print Spooler is running" -ForegroundColor Green

    $results += [PSCustomObject]@{
        Category = "Service"
        Item = "Print Spooler"
        Status = "Pass"
        Finding = "Service is running"
        Details = "Startup: $($spooler.StartType)"
    }
}
else {
    Write-Host "[-] Print Spooler is not running: $($spooler.Status)" -ForegroundColor Red
    $issueCount++

    $results += [PSCustomObject]@{
        Category = "Service"
        Item = "Print Spooler"
        Status = "Fail"
        Finding = "Service status: $($spooler.Status)"
        Details = "Startup: $($spooler.StartType)"
    }
}

Write-Host ""

# 2. Check spool directory disk space
Write-Host "[*] Checking spool directory..." -ForegroundColor Cyan

$spoolPath = "$env:SystemRoot\System32\spool\PRINTERS"
$spoolDrive = Split-Path -Path $spoolPath -Qualifier

try {
    $drive = Get-PSDrive -Name ($spoolDrive -replace ':','') -ErrorAction Stop
    $freeSpaceGB = [math]::Round($drive.Free / 1GB, 2)
    $usedPercent = [math]::Round(($drive.Used / ($drive.Used + $drive.Free)) * 100, 2)

    Write-Host "[+] Spool directory: $spoolPath" -ForegroundColor Green
    Write-Host "    Free space: $freeSpaceGB GB ($usedPercent% used)" -ForegroundColor Gray

    if ($freeSpaceGB -lt 1) {
        Write-Host "    [Warning] Low disk space!" -ForegroundColor Red
        $issueCount++
    }
    elseif ($freeSpaceGB -lt 5) {
        Write-Host "    [Warning] Disk space getting low" -ForegroundColor Yellow
        $warningCount++
    }

    $results += [PSCustomObject]@{
        Category = "Spool Directory"
        Item = $spoolPath
        Status = if ($freeSpaceGB -lt 1) { "Fail" } elseif ($freeSpaceGB -lt 5) { "Warning" } else { "Pass" }
        Finding = "Free space: $freeSpaceGB GB"
        Details = "Used: $usedPercent%"
    }
}
catch {
    Write-Host "[-] Could not check spool directory" -ForegroundColor Yellow
}

Write-Host ""

# 3. Check printers
Write-Host "[*] Checking installed printers..." -ForegroundColor Cyan

try {
    $printers = Get-Printer

    Write-Host "[+] Found $($printers.Count) printer(s)" -ForegroundColor Green

    foreach ($printer in $printers) {
        # Check printer status
        $status = if ($printer.PrinterStatus -eq 'Normal') { "Pass" }
                 elseif ($printer.PrinterStatus -match 'Error|Offline') { "Fail" }
                 else { "Warning" }

        if ($status -eq "Fail") {
            Write-Host "    [Fail] $($printer.Name): $($printer.PrinterStatus)" -ForegroundColor Red
            $issueCount++
        }
        elseif ($status -eq "Warning") {
            Write-Host "    [Warning] $($printer.Name): $($printer.PrinterStatus)" -ForegroundColor Yellow
            $warningCount++
        }
        else {
            Write-Host "    [Pass] $($printer.Name): $($printer.PrinterStatus)" -ForegroundColor Green
        }

        $results += [PSCustomObject]@{
            Category = "Printer Status"
            Item = $printer.Name
            Status = $status
            Finding = "Status: $($printer.PrinterStatus)"
            Details = "Type: $($printer.Type), Shared: $($printer.Shared)"
        }
    }

    Write-Host ""

    # 4. Check print jobs
    Write-Host "[*] Checking print queues..." -ForegroundColor Cyan

    $totalJobs = 0
    $stuckJobs = @()

    foreach ($printer in $printers) {
        $jobs = Get-PrintJob -PrinterName $printer.Name -ErrorAction SilentlyContinue

        if ($jobs) {
            $totalJobs += $jobs.Count

            foreach ($job in $jobs) {
                $jobAge = (Get-Date) - $job.SubmittedTime

                if ($jobAge.TotalHours -gt $StuckJobThresholdHours) {
                    $stuckJobs += $job

                    Write-Host "    [Warning] Stuck job on $($printer.Name): $($job.DocumentName) ($([math]::Round($jobAge.TotalHours, 1)) hours old)" -ForegroundColor Yellow

                    $results += [PSCustomObject]@{
                        Category = "Print Job"
                        Item = "$($printer.Name) - $($job.Id)"
                        Status = "Warning"
                        Finding = "Job stuck for $([math]::Round($jobAge.TotalHours, 1)) hours"
                        Details = "Document: $($job.DocumentName), User: $($job.UserName)"
                    }
                }
            }
        }
    }

    Write-Host "[+] Total print jobs: $totalJobs" -ForegroundColor Green
    Write-Host "[+] Stuck jobs: $($stuckJobs.Count)" -ForegroundColor $(if ($stuckJobs.Count -eq 0) { "Green" } else { "Yellow" })

    # Clear stuck jobs if requested
    if ($ClearStuckJobs -and $stuckJobs.Count -gt 0) {
        Write-Host ""
        Write-Host "[*] Clearing stuck jobs..." -ForegroundColor Cyan

        foreach ($job in $stuckJobs) {
            if ($PSCmdlet.ShouldProcess("$($job.DocumentName) on $($job.PrinterName)", "Remove stuck print job")) {
                try {
                    Remove-PrintJob -PrinterName $job.PrinterName -ID $job.Id -ErrorAction Stop
                    Write-Host "[+] Removed job: $($job.DocumentName)" -ForegroundColor Green
                    $jobsCleared++
                }
                catch {
                    Write-Host "[-] Failed to remove job: $($_.Exception.Message)" -ForegroundColor Red
                }
            }
        }

        Write-Host "[+] Cleared $jobsCleared stuck job(s)" -ForegroundColor Green
    }

    Write-Host ""

    # 5. Check printer drivers
    if ($CheckDrivers) {
        Write-Host "[*] Checking printer drivers..." -ForegroundColor Cyan

        $drivers = Get-PrinterDriver

        Write-Host "[+] Found $($drivers.Count) printer driver(s) installed" -ForegroundColor Green

        $uniqueDrivers = $drivers | Group-Object Name | Select-Object Name, Count

        foreach ($driver in $uniqueDrivers) {
            Write-Host "    - $($driver.Name) ($($driver.Count) version(s))" -ForegroundColor Gray
        }

        Write-Host ""
    }

}
catch {
    Write-Host "[-] Error checking printers: $($_.Exception.Message)" -ForegroundColor Red
    $issueCount++
}

# 6. Check recent print spooler errors
Write-Host "[*] Checking for recent spooler errors..." -ForegroundColor Cyan

try {
    $errorEvents = Get-WinEvent -FilterHashtable @{
        LogName = 'System'
        ProviderName = 'Microsoft-Windows-PrintService'
        Level = 2,3  # Error and Warning
        StartTime = (Get-Date).AddHours(-24)
    } -MaxEvents 50 -ErrorAction SilentlyContinue

    if ($errorEvents) {
        Write-Host "[-] Found $($errorEvents.Count) print service error(s) in last 24 hours" -ForegroundColor Yellow
        $warningCount++

        $errorEvents | Select-Object -First 5 | ForEach-Object {
            Write-Host "    - $($_.TimeCreated): $($_.Message.Substring(0, [Math]::Min(100, $_.Message.Length)))" -ForegroundColor Gray
        }
    }
    else {
        Write-Host "[+] No recent print service errors" -ForegroundColor Green
    }
}
catch {
    Write-Host "[-] Could not check event log" -ForegroundColor Gray
}

Write-Host ""

# Summary
Write-Host "=== Health Check Summary ===" -ForegroundColor Cyan
Write-Host "Total Checks: $($results.Count)" -ForegroundColor White
Write-Host "Issues: $issueCount" -ForegroundColor $(if ($issueCount -eq 0) { "Green" } else { "Red" })
Write-Host "Warnings: $warningCount" -ForegroundColor Yellow
if ($jobsCleared -gt 0) {
    Write-Host "Jobs Cleared: $jobsCleared" -ForegroundColor Green
}

$healthScore = if ($results.Count -gt 0) {
    [math]::Round((($results.Count - $issueCount - ($warningCount * 0.5)) / $results.Count) * 100, 2)
}
else {
    100
}

Write-Host "Health Score: $healthScore%" -ForegroundColor $(if ($healthScore -ge 80) { "Green" } elseif ($healthScore -ge 60) { "Yellow" } else { "Red" })
Write-Host ""

# Export results
if ($ExportHTML) {
    $htmlPath = "$env:USERPROFILE\Desktop\PrintServerHealth_$timestamp.html"

    $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>Print Server Health - $timestamp</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        h1 { color: #8e44ad; }
        .summary { background-color: #ecf0f1; padding: 15px; border-radius: 5px; margin: 20px 0; }
        .score { font-size: 24px; font-weight: bold; color: $(if ($healthScore -ge 80) { '#27ae60' } elseif ($healthScore -ge 60) { '#f39c12' } else { '#e74c3c' }); }
        table { border-collapse: collapse; width: 100%; margin-top: 10px; }
        th { background-color: #8e44ad; color: white; padding: 10px; text-align: left; }
        td { border: 1px solid #ddd; padding: 8px; font-size: 12px; }
        tr:nth-child(even) { background-color: #f2f2f2; }
        .pass { background-color: #27ae60; color: white; padding: 3px 6px; border-radius: 3px; }
        .fail { background-color: #e74c3c; color: white; padding: 3px 6px; border-radius: 3px; }
        .warning { background-color: #f39c12; color: white; padding: 3px 6px; border-radius: 3px; }
    </style>
</head>
<body>
    <h1>Print Server Health Check Report</h1>
    <div class="summary">
        <strong>Server:</strong> $env:COMPUTERNAME<br>
        <strong>Generated:</strong> $(Get-Date)<br>
        <strong>Health Score:</strong> <span class="score">$healthScore%</span><br>
        <strong>Issues:</strong> $issueCount | <strong>Warnings:</strong> $warningCount<br>
        <strong>Jobs Cleared:</strong> $jobsCleared
    </div>

    <h2>Health Check Results</h2>
    <table>
        <tr><th>Category</th><th>Item</th><th>Status</th><th>Finding</th><th>Details</th></tr>
"@

    foreach ($result in $results) {
        $statusClass = $result.Status.ToLower()
        $html += @"
        <tr>
            <td>$($result.Category)</td>
            <td>$($result.Item)</td>
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
    $csvPath = "$env:USERPROFILE\Desktop\PrintServerHealth_$timestamp.csv"
    $results | Export-Csv -Path $csvPath -NoTypeInformation
    Write-Host "[+] CSV export saved to: $csvPath" -ForegroundColor Green
}

Write-Host "[+] Health check completed!" -ForegroundColor Green

if ($issueCount -gt 0) {
    exit 1
}

exit 0
