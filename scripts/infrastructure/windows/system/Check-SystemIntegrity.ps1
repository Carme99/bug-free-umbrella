<#
.SYNOPSIS
    Performs comprehensive system integrity checks on Windows Server 2016-2022.

.DESCRIPTION
    This script runs multiple system integrity verification tools:
    - System File Checker (SFC)
    - Deployment Image Servicing and Management (DISM)
    - Check Disk (CHKDSK) analysis
    - Windows Component Store verification
    - Event log analysis for critical errors

.PARAMETER QuickScan
    Performs only SFC and basic DISM checks (faster).

.PARAMETER AutoRepair
    Automatically attempts to repair detected issues.

.PARAMETER GenerateReport
    Creates a detailed HTML report of findings.

.EXAMPLE
    .\Check-SystemIntegrity.ps1
    Performs a standard integrity check.

.EXAMPLE
    .\Check-SystemIntegrity.ps1 -AutoRepair -GenerateReport
    Checks integrity, repairs issues, and generates a report.

.NOTES
    Requires Administrator privileges
    Compatible with Windows Server 2016, 2019, and 2022
    May take 15-30 minutes to complete full scan
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [switch]$QuickScan,

    [Parameter(Mandatory=$false)]
    [switch]$AutoRepair,

    [Parameter(Mandatory=$false)]
    [switch]$GenerateReport
)

#Requires -RunAsAdministrator

$script:results = @{
    ServerName = $env:COMPUTERNAME
    ScanDate = Get-Date
    OSVersion = (Get-WmiObject Win32_OperatingSystem).Caption
    SFCResult = ""
    DISMResult = ""
    CHKDSKResult = ""
    EventLogErrors = @()
    OverallStatus = "UNKNOWN"
}

function Write-Log {
    param([string]$Message, [string]$Type = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $color = switch($Type) {
        "ERROR" { "Red" }
        "SUCCESS" { "Green" }
        "WARNING" { "Yellow" }
        default { "White" }
    }
    Write-Host "[$timestamp] [$Type] $Message" -ForegroundColor $color
}

function Test-SystemFileChecker {
    Write-Log "Running System File Checker (SFC)..." "INFO"
    Write-Log "This may take several minutes..." "WARNING"

    try {
        $sfcLog = "$env:windir\Logs\CBS\CBS.log"
        $output = & sfc /scannow 2>&1

        Start-Sleep -Seconds 5

        if (Test-Path $sfcLog) {
            $logContent = Get-Content $sfcLog -Tail 50 | Out-String

            if ($logContent -match "Windows Resource Protection did not find any integrity violations") {
                Write-Log "SFC: No integrity violations found" "SUCCESS"
                $script:results.SFCResult = "PASSED"
                return $true
            }
            elseif ($logContent -match "Windows Resource Protection found corrupt files and successfully repaired them") {
                Write-Log "SFC: Found and repaired corrupt files" "SUCCESS"
                $script:results.SFCResult = "REPAIRED"
                return $true
            }
            elseif ($logContent -match "Windows Resource Protection found corrupt files but was unable to fix some of them") {
                Write-Log "SFC: Found corrupt files that could not be repaired" "ERROR"
                $script:results.SFCResult = "FAILED - Manual intervention required"
                return $false
            }
        }

        Write-Log "SFC: Scan completed - Check CBS.log for details" "WARNING"
        $script:results.SFCResult = "COMPLETED - Review logs"
        return $true
    }
    catch {
        Write-Log "SFC: Error during scan - $($_.Exception.Message)" "ERROR"
        $script:results.SFCResult = "ERROR"
        return $false
    }
}

function Test-DISM {
    param([bool]$Repair = $false)

    Write-Log "Running DISM Component Store verification..." "INFO"

    try {
        # Check Component Store health
        Write-Log "Checking component store health..." "INFO"
        $dismCheck = & DISM /Online /Cleanup-Image /CheckHealth 2>&1 | Out-String

        if ($dismCheck -match "No component store corruption detected") {
            Write-Log "DISM CheckHealth: No corruption detected" "SUCCESS"
            $script:results.DISMResult = "PASSED"
            return $true
        }

        # Scan for corruption
        Write-Log "Scanning for component store corruption..." "INFO"
        $dismScan = & DISM /Online /Cleanup-Image /ScanHealth 2>&1 | Out-String

        if ($dismScan -match "No component store corruption detected") {
            Write-Log "DISM ScanHealth: No corruption detected" "SUCCESS"
            $script:results.DISMResult = "PASSED"
            return $true
        }

        if ($Repair -or $AutoRepair) {
            Write-Log "Attempting to repair component store..." "WARNING"
            Write-Log "This may take 10-15 minutes..." "WARNING"
            $dismRepair = & DISM /Online /Cleanup-Image /RestoreHealth 2>&1 | Out-String

            if ($dismRepair -match "The restore operation completed successfully" -or
                $dismRepair -match "No component store corruption detected") {
                Write-Log "DISM RestoreHealth: Repair completed successfully" "SUCCESS"
                $script:results.DISMResult = "REPAIRED"
                return $true
            }
            else {
                Write-Log "DISM RestoreHealth: Repair failed" "ERROR"
                $script:results.DISMResult = "FAILED"
                return $false
            }
        }
        else {
            Write-Log "DISM: Corruption detected - Run with -AutoRepair to fix" "WARNING"
            $script:results.DISMResult = "CORRUPTION DETECTED"
            return $false
        }
    }
    catch {
        Write-Log "DISM: Error during scan - $($_.Exception.Message)" "ERROR"
        $script:results.DISMResult = "ERROR"
        return $false
    }
}

function Test-DiskHealth {
    Write-Log "Analyzing disk health..." "INFO"

    try {
        $volumes = Get-Volume | Where-Object {$_.DriveLetter -ne $null -and $_.FileSystem -eq "NTFS"}

        foreach ($volume in $volumes) {
            $driveLetter = $volume.DriveLetter
            Write-Log "Checking drive $driveLetter..." "INFO"

            # Check for dirty bit
            $dirtyBit = & fsutil dirty query "$($driveLetter):" 2>&1

            if ($dirtyBit -match "NOT set") {
                Write-Log "Drive ${driveLetter}: File system is clean" "SUCCESS"
            }
            else {
                Write-Log "Drive ${driveLetter}: Disk check scheduled on next reboot" "WARNING"
                $script:results.CHKDSKResult += "Drive ${driveLetter}: Requires check on reboot`n"
            }
        }

        if ([string]::IsNullOrEmpty($script:results.CHKDSKResult)) {
            $script:results.CHKDSKResult = "All drives healthy"
        }

        return $true
    }
    catch {
        Write-Log "Disk Health: Error during check - $($_.Exception.Message)" "ERROR"
        $script:results.CHKDSKResult = "ERROR"
        return $false
    }
}

function Get-CriticalEventLogErrors {
    Write-Log "Checking Event Logs for critical errors (last 24 hours)..." "INFO"

    try {
        $startTime = (Get-Date).AddDays(-1)
        $logs = @("System", "Application")

        foreach ($logName in $logs) {
            $errors = Get-WinEvent -FilterHashtable @{
                LogName = $logName
                Level = 1,2  # Critical and Error
                StartTime = $startTime
            } -ErrorAction SilentlyContinue | Select-Object -First 10

            if ($errors) {
                foreach ($error in $errors) {
                    $errorInfo = [PSCustomObject]@{
                        Time = $error.TimeCreated
                        Log = $logName
                        Source = $error.ProviderName
                        EventID = $error.Id
                        Message = $error.Message.Substring(0, [Math]::Min(200, $error.Message.Length))
                    }
                    $script:results.EventLogErrors += $errorInfo
                }
            }
        }

        if ($script:results.EventLogErrors.Count -gt 0) {
            Write-Log "Found $($script:results.EventLogErrors.Count) critical errors in event logs" "WARNING"
        }
        else {
            Write-Log "No critical errors found in event logs" "SUCCESS"
        }

        return $true
    }
    catch {
        Write-Log "Event Log: Error during check - $($_.Exception.Message)" "WARNING"
        return $false
    }
}

function New-IntegrityReport {
    $reportPath = "$env:USERPROFILE\Desktop\SystemIntegrityReport_$($env:COMPUTERNAME)_$(Get-Date -Format 'yyyyMMdd_HHmmss').html"

    $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>System Integrity Report - $($script:results.ServerName)</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background-color: #f5f5f5; }
        .container { background-color: white; padding: 20px; border-radius: 5px; box-shadow: 0 2px 5px rgba(0,0,0,0.1); }
        h1 { color: #333; border-bottom: 2px solid #0078d4; padding-bottom: 10px; }
        h2 { color: #0078d4; margin-top: 20px; }
        .info-table { width: 100%; border-collapse: collapse; margin: 20px 0; }
        .info-table th, .info-table td { padding: 10px; text-align: left; border-bottom: 1px solid #ddd; }
        .info-table th { background-color: #0078d4; color: white; }
        .passed { color: green; font-weight: bold; }
        .failed { color: red; font-weight: bold; }
        .warning { color: orange; font-weight: bold; }
        .event-log { font-size: 12px; }
    </style>
</head>
<body>
    <div class="container">
        <h1>System Integrity Report</h1>
        <table class="info-table">
            <tr><th>Server Name</th><td>$($script:results.ServerName)</td></tr>
            <tr><th>Scan Date</th><td>$($script:results.ScanDate)</td></tr>
            <tr><th>OS Version</th><td>$($script:results.OSVersion)</td></tr>
        </table>

        <h2>Integrity Check Results</h2>
        <table class="info-table">
            <tr><th>Check Type</th><th>Result</th></tr>
            <tr><td>System File Checker (SFC)</td><td class="$(if($script:results.SFCResult -match 'PASSED|REPAIRED'){'passed'}elseif($script:results.SFCResult -match 'FAILED'){'failed'}else{'warning'})">$($script:results.SFCResult)</td></tr>
            <tr><td>DISM Component Store</td><td class="$(if($script:results.DISMResult -match 'PASSED|REPAIRED'){'passed'}elseif($script:results.DISMResult -match 'FAILED'){'failed'}else{'warning'})">$($script:results.DISMResult)</td></tr>
            <tr><td>Disk Health</td><td class="$(if($script:results.CHKDSKResult -match 'healthy'){'passed'}else{'warning'})">$($script:results.CHKDSKResult)</td></tr>
        </table>

        <h2>Critical Event Log Errors (Last 24 Hours)</h2>
        <table class="info-table event-log">
            <tr><th>Time</th><th>Log</th><th>Source</th><th>Event ID</th><th>Message</th></tr>
"@

    if ($script:results.EventLogErrors.Count -gt 0) {
        foreach ($error in $script:results.EventLogErrors) {
            $html += "<tr><td>$($error.Time)</td><td>$($error.Log)</td><td>$($error.Source)</td><td>$($error.EventID)</td><td>$($error.Message)</td></tr>"
        }
    }
    else {
        $html += "<tr><td colspan='5' style='text-align:center;' class='passed'>No critical errors found</td></tr>"
    }

    $html += @"
        </table>
    </div>
</body>
</html>
"@

    $html | Out-File -FilePath $reportPath -Encoding UTF8
    Write-Log "Report generated: $reportPath" "SUCCESS"

    # Open report in default browser
    Start-Process $reportPath
}

# Main execution
Write-Log "=== System Integrity Check Started ===" "INFO"
Write-Log "Server: $($script:results.ServerName) | OS: $($script:results.OSVersion)" "INFO"

$sfcPassed = Test-SystemFileChecker

if (-not $QuickScan) {
    $dismPassed = Test-DISM -Repair $AutoRepair
    $diskPassed = Test-DiskHealth
    $eventLogPassed = Get-CriticalEventLogErrors
}
else {
    Write-Log "Quick scan mode - running SFC only" "INFO"
    $dismPassed = Test-DISM -Repair $false
}

# Determine overall status
if ($sfcPassed -and $dismPassed) {
    $script:results.OverallStatus = "HEALTHY"
    Write-Log "=== Overall Status: HEALTHY ===" "SUCCESS"
}
elseif ($script:results.SFCResult -match "REPAIRED" -or $script:results.DISMResult -match "REPAIRED") {
    $script:results.OverallStatus = "REPAIRED"
    Write-Log "=== Overall Status: ISSUES REPAIRED ===" "SUCCESS"
}
else {
    $script:results.OverallStatus = "ATTENTION REQUIRED"
    Write-Log "=== Overall Status: ATTENTION REQUIRED ===" "WARNING"
}

if ($GenerateReport) {
    New-IntegrityReport
}

Write-Log "=== System Integrity Check Completed ===" "INFO"
