<#
.SYNOPSIS
    Weekly server and workstation health check workflow

.DESCRIPTION
    This example demonstrates a comprehensive weekly health check routine that can be
    scheduled to run automatically. Includes server health, disk space, security checks,
    and automated reporting.

.NOTES
    Copyright (c) 2025 bug-free-umbrella contributors
    Licensed under Apache License 2.0
    https://github.com/Carme99/bug-free-umbrella

.EXAMPLE
    .\weekly-health-check.ps1 -EmailReport -SMTPServer "smtp.company.com" -To "it-team@company.com"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string[]]$ComputerName = @($env:COMPUTERNAME),

    [Parameter(Mandatory = $false)]
    [string]$ReportPath = "C:\HealthCheckReports",

    [Parameter(Mandatory = $false)]
    [switch]$EmailReport,

    [Parameter(Mandatory = $false)]
    [string]$SMTPServer,

    [Parameter(Mandatory = $false)]
    [string]$To
)

# Define the root path to the scripts directory
$ScriptRoot = Join-Path -Path $PSScriptRoot -ChildPath "..\..\scripts"

# Create report directory if it doesn't exist
if (-not (Test-Path -Path $ReportPath)) {
    New-Item -Path $ReportPath -ItemType Directory -Force | Out-Null
}

$Timestamp = Get-Date -Format "yyyy-MM-dd_HHmmss"
$ReportFile = Join-Path -Path $ReportPath -ChildPath "WeeklyHealthCheck_$Timestamp.html"

Write-Host "=== Weekly Health Check - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ===" -ForegroundColor Cyan
Write-Host "Targets: $($ComputerName -join ', ')" -ForegroundColor Yellow
Write-Host ""

$Results = @()

foreach ($Computer in $ComputerName) {
    Write-Host "Processing: $Computer" -ForegroundColor Green

    # 1. Comprehensive Health Check
    Write-Host "  [1/7] Server health monitoring..." -ForegroundColor Yellow
    try {
        $HealthCheck = & "$ScriptRoot\infrastructure\windows\monitoring\Monitor-ServerHealth.ps1" `
            -ComputerName $Computer `
            -CheckAll `
            -Verbose:$false
        $Results += @{ Computer = $Computer; Check = "Health"; Status = "Pass" }
    } catch {
        $Results += @{ Computer = $Computer; Check = "Health"; Status = "Fail"; Error = $_ }
        Write-Warning "Health check failed: $_"
    }

    # 2. Disk Space Check (using WMI/CIM directly)
    Write-Host "  [2/7] Disk space analysis..." -ForegroundColor Yellow
    try {
        $Disks = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DriveType=3" -ComputerName $Computer
        foreach ($Disk in $Disks) {
            $PercentFree = ($Disk.FreeSpace / $Disk.Size) * 100
            if ($PercentFree -lt 20) {
                Write-Warning "$($Disk.DeviceID) has only $([math]::Round($PercentFree,2))% free space"
            }
        }
        $Results += @{ Computer = $Computer; Check = "Disk Space"; Status = "Pass" }
    } catch {
        $Results += @{ Computer = $Computer; Check = "Disk Space"; Status = "Fail"; Error = $_ }
        Write-Warning "Disk space check failed: $_"
    }

    # 3. Event Log Errors (Last 7 Days - using Get-WinEvent directly)
    Write-Host "  [3/7] Event log analysis..." -ForegroundColor Yellow
    try {
        $StartTime = (Get-Date).AddHours(-168)
        $Errors = Get-WinEvent -FilterHashtable @{
            LogName = 'System', 'Application'
            Level = 1,2  # Critical and Error
            StartTime = $StartTime
        } -ComputerName $Computer -ErrorAction SilentlyContinue | Select-Object -First 10
        if ($Errors.Count -gt 0) {
            Write-Warning "Found $($Errors.Count) critical/error events in the last 7 days"
        }
        $Results += @{ Computer = $Computer; Check = "Event Logs"; Status = "Pass" }
    } catch {
        $Results += @{ Computer = $Computer; Check = "Event Logs"; Status = "Fail"; Error = $_ }
        Write-Warning "Event log check failed: $_"
    }

    # 4. Security Compliance Scan
    Write-Host "  [4/7] Security compliance scan..." -ForegroundColor Yellow
    try {
        & "$ScriptRoot\security\compliance\frameworks\Invoke-SecurityComplianceScan.ps1" `
            -Framework CIS `
            -ComputerName $Computer
        $Results += @{ Computer = $Computer; Check = "Security"; Status = "Pass" }
    } catch {
        $Results += @{ Computer = $Computer; Check = "Security"; Status = "Fail"; Error = $_ }
        Write-Warning "Security scan failed: $_"
    }

    # 5. BitLocker Status
    Write-Host "  [5/7] BitLocker encryption check..." -ForegroundColor Yellow
    try {
        & "$ScriptRoot\endpoints\intune\reporting\Get-BitLockerStatus.ps1" `
            -ComputerName $Computer
        $Results += @{ Computer = $Computer; Check = "BitLocker"; Status = "Pass" }
    } catch {
        $Results += @{ Computer = $Computer; Check = "BitLocker"; Status = "Fail"; Error = $_ }
        Write-Warning "BitLocker check failed: $_"
    }

    # 6. Certificate Expiration (30 days)
    Write-Host "  [6/7] Certificate expiration check..." -ForegroundColor Yellow
    try {
        & "$ScriptRoot\infrastructure\windows\monitoring\Monitor-ServerHealth.ps1" `
            -ComputerName $Computer `
            -CheckCertificates `
            -DaysBeforeExpiration 30
        $Results += @{ Computer = $Computer; Check = "Certificates"; Status = "Pass" }
    } catch {
        $Results += @{ Computer = $Computer; Check = "Certificates"; Status = "Fail"; Error = $_ }
        Write-Warning "Certificate check failed: $_"
    }

    # 7. Windows Update Status
    Write-Host "  [7/7] Windows Update status..." -ForegroundColor Yellow
    try {
        & "$ScriptRoot\infrastructure\windows\monitoring\Monitor-ServerHealth.ps1" `
            -ComputerName $Computer `
            -CheckWindowsUpdate
        $Results += @{ Computer = $Computer; Check = "Updates"; Status = "Pass" }
    } catch {
        $Results += @{ Computer = $Computer; Check = "Updates"; Status = "Fail"; Error = $_ }
        Write-Warning "Update check failed: $_"
    }

    Write-Host ""
}

# Generate HTML Report
Write-Host "Generating health check report..." -ForegroundColor Green
$HtmlReport = @"
<!DOCTYPE html>
<html>
<head>
    <title>Weekly Health Check Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        h1 { color: #0066cc; }
        table { border-collapse: collapse; width: 100%; margin-top: 20px; }
        th { background-color: #0066cc; color: white; padding: 10px; text-align: left; }
        td { border: 1px solid #ddd; padding: 8px; }
        tr:nth-child(even) { background-color: #f2f2f2; }
        .pass { color: green; font-weight: bold; }
        .fail { color: red; font-weight: bold; }
    </style>
</head>
<body>
    <h1>Weekly Health Check Report</h1>
    <p><strong>Generated:</strong> $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")</p>
    <p><strong>Systems Checked:</strong> $($ComputerName.Count)</p>

    <h2>Results Summary</h2>
    <table>
        <tr>
            <th>Computer</th>
            <th>Check Type</th>
            <th>Status</th>
            <th>Details</th>
        </tr>
"@

foreach ($Result in $Results) {
    $StatusClass = if ($Result.Status -eq "Pass") { "pass" } else { "fail" }
    $ErrorMsg = if ($Result.Error) { $Result.Error } else { "-" }
    $HtmlReport += @"
        <tr>
            <td>$($Result.Computer)</td>
            <td>$($Result.Check)</td>
            <td class="$StatusClass">$($Result.Status)</td>
            <td>$ErrorMsg</td>
        </tr>
"@
}

$HtmlReport += @"
    </table>

    <h2>Recommendations</h2>
    <ul>
        <li>Review any failed checks and take corrective action</li>
        <li>Verify all critical security updates are installed</li>
        <li>Monitor disk space on systems approaching threshold</li>
        <li>Review expiring certificates and renew as needed</li>
    </ul>

    <hr>
    <p style="font-size: 0.9em; color: #666;">
        Generated by bug-free-umbrella automation<br>
        <a href="https://github.com/Carme99/bug-free-umbrella">https://github.com/Carme99/bug-free-umbrella</a>
    </p>
</body>
</html>
"@

$HtmlReport | Out-File -FilePath $ReportFile -Encoding UTF8
Write-Host "✓ Report saved: $ReportFile" -ForegroundColor Green

# Email Report (if requested)
if ($EmailReport -and $SMTPServer -and $To) {
    Write-Host "Sending email report..." -ForegroundColor Green
    try {
        $MailParams = @{
            To         = $To
            From       = "healthcheck@$env:USERDNSDOMAIN"
            Subject    = "Weekly Health Check Report - $(Get-Date -Format 'yyyy-MM-dd')"
            Body       = $HtmlReport
            BodyAsHtml = $true
            SmtpServer = $SMTPServer
        }
        Send-MailMessage @MailParams
        Write-Host "✓ Email sent successfully" -ForegroundColor Green
    } catch {
        Write-Warning "Failed to send email: $_"
    }
}

Write-Host "`n=== Health Check Complete ===" -ForegroundColor Cyan
Write-Host "Review the report and address any issues identified." -ForegroundColor Yellow
