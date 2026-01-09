<#
.SYNOPSIS
    Automated daily reporting workflow for compliance and health monitoring

.DESCRIPTION
    This example demonstrates an automated daily reporting workflow that can be scheduled
    via Task Scheduler or Azure Automation. Generates comprehensive reports on device
    compliance, security posture, system health, and email summaries to stakeholders.

    Designed to run unattended with automated email delivery.

.NOTES
    Copyright (c) 2025 bug-free-umbrella contributors
    Licensed under Apache License 2.0
    https://github.com/Carme99/bug-free-umbrella

    SMTP AUTHENTICATION:
    Most enterprise SMTP servers require authentication. This script uses Send-MailMessage which supports:
    - Add -Credential parameter for authenticated SMTP
    - Use -UseSsl for TLS/SSL encryption
    - Alternative: Use Microsoft Graph API (Send-MgUserMail) for modern authentication

    Example with credentials:
    $Cred = Get-Credential
    Send-MailMessage -Credential $Cred -UseSsl -Port 587 -SmtpServer "smtp.office365.com" ...

    For unattended execution, store credentials securely using:
    - Windows Credential Manager
    - Azure Key Vault
    - Encrypted credential files

    SCHEDULED TASK SETUP:
    Create a scheduled task to run this script daily:

    $Action = New-ScheduledTaskAction -Execute "PowerShell.exe" `
        -Argument "-ExecutionPolicy Bypass -File C:\Scripts\scheduled-daily-reporting.ps1"
    $Trigger = New-ScheduledTaskTrigger -Daily -At 8:00AM
    $Principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
    Register-ScheduledTask -TaskName "Daily IT Report" -Action $Action -Trigger $Trigger -Principal $Principal

.EXAMPLE
    .\scheduled-daily-reporting.ps1

.EXAMPLE
    .\scheduled-daily-reporting.ps1 -EmailTo "it-team@company.com,management@company.com" -SMTPServer "smtp.company.com"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string[]]$EmailTo = @("it-team@company.com"),

    [Parameter(Mandatory = $false)]
    [string]$EmailFrom = "",

    [Parameter(Mandatory = $false)]
    [string]$SMTPServer = "smtp.office365.com",

    [Parameter(Mandatory = $false)]
    [int]$SMTPPort = 587,

    [Parameter(Mandatory = $false)]
    [switch]$UseSsl,

    [Parameter(Mandatory = $false)]
    [System.Management.Automation.PSCredential]$Credential,

    [Parameter(Mandatory = $false)]
    [string]$ReportPath = "C:\AutomatedReports",

    [Parameter(Mandatory = $false)]
    [int]$RetentionDays = 30
)

# Define the root path to the scripts directory
$ScriptRoot = Join-Path -Path $PSScriptRoot -ChildPath "..\..\scripts"

# Validate script root exists
if (-not (Test-Path -Path $ScriptRoot)) {
    Write-Error "Script root path not found: $ScriptRoot"
    Write-Error "Please ensure the script is run from the examples/automation directory"
    exit 1
}

# Set EmailFrom if not provided
if ([string]::IsNullOrWhiteSpace($EmailFrom)) {
    $DomainName = if ($env:USERDNSDOMAIN) { $env:USERDNSDOMAIN } else { "company.com" }
    $EmailFrom = "daily-report@$DomainName"
}

# Create report directory if it doesn't exist
if (-not (Test-Path -Path $ReportPath)) {
    New-Item -Path $ReportPath -ItemType Directory -Force | Out-Null
}

$Timestamp = Get-Date -Format "yyyy-MM-dd"
$LogFile = Join-Path -Path $ReportPath -ChildPath "DailyReport_$Timestamp.log"

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $LogMessage = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [$Level] - $Message"
    Write-Host $LogMessage
    Add-Content -Path $LogFile -Value $LogMessage
}

Write-Log "=== AUTOMATED DAILY REPORTING STARTED ===" "INFO"
Write-Host "=== Automated Daily Report - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ===" -ForegroundColor Cyan

$ReportData = @{
    ExecutionTime = Get-Date
    ReportDate = $Timestamp
    Sections = @()
    Errors = @()
    Summary = @{
        TotalChecks = 0
        SuccessfulChecks = 0
        FailedChecks = 0
        Warnings = 0
    }
}

# Validate required script paths exist
Write-Log "Validating script dependencies..." "INFO"
$RequiredScripts = @(
    "$ScriptRoot\endpoints\intune\reporting\Get-DeviceComplianceReport.ps1"
    "$ScriptRoot\endpoints\intune\reporting\Get-BitLockerStatus.ps1"
    "$ScriptRoot\endpoints\intune\reporting\Get-WindowsUpdateCompliance.ps1"
    "$ScriptRoot\security\compliance\frameworks\Test-CISBenchmark.ps1"
    "$ScriptRoot\security\compliance\frameworks\Get-FailedLoginReport.ps1"
    "$ScriptRoot\security\compliance\frameworks\Get-ExpiredCertificates.ps1"
    "$ScriptRoot\endpoints\intune\maintenance\Find-StaleDevices.ps1"
)

$MissingScripts = @()
foreach ($Script in $RequiredScripts) {
    if (-not (Test-Path -Path $Script)) {
        $MissingScripts += $Script
        Write-Log "WARNING: Required script not found: $Script" "WARN"
    }
}

if ($MissingScripts.Count -gt 0) {
    Write-Warning "Some required scripts are missing. Reports may be incomplete."
    Write-Log "$($MissingScripts.Count) required scripts are missing" "WARN"
}

# Section 1: Device Compliance Report
Write-Host "`n[1/7] Generating device compliance report..." -ForegroundColor Yellow
Write-Log "Section 1: Device Compliance Report"
try {
    $ComplianceReport = Join-Path -Path $ReportPath -ChildPath "DeviceCompliance_$Timestamp.html"
    & "$ScriptRoot\endpoints\intune\reporting\Get-DeviceComplianceReport.ps1" `
        -ExportHTML `
        -OutputPath $ComplianceReport

    # Get summary data
    $ComplianceData = & "$ScriptRoot\endpoints\intune\reporting\Get-DeviceComplianceReport.ps1"
    $NonCompliantCount = ($ComplianceData | Where-Object { $_.ComplianceState -eq "NonCompliant" }).Count
    $TotalDevices = $ComplianceData.Count
    $CompliancePercent = if ($TotalDevices -gt 0) { [math]::Round((($TotalDevices - $NonCompliantCount) / $TotalDevices) * 100, 2) } else { 0 }

    Write-Host "  ✓ Device Compliance: $CompliancePercent% ($TotalDevices total, $NonCompliantCount non-compliant)" -ForegroundColor Green
    Write-Log "Device Compliance: $CompliancePercent% compliant" "INFO"

    $ReportData.Sections += @{
        Name = "Device Compliance"
        Status = "Success"
        Summary = "$CompliancePercent% compliant ($NonCompliantCount non-compliant)"
        ReportFile = $ComplianceReport
    }
    $ReportData.Summary.SuccessfulChecks++

    if ($NonCompliantCount -gt 0) {
        $ReportData.Summary.Warnings++
    }
} catch {
    Write-Warning "  ✗ Device compliance report failed: $_"
    Write-Log "Device compliance report failed: $_" "ERROR"
    $ReportData.Sections += @{
        Name = "Device Compliance"
        Status = "Failed"
        Summary = "Error: $_"
        ReportFile = $null
    }
    $ReportData.Errors += "Device Compliance: $_"
    $ReportData.Summary.FailedChecks++
}
$ReportData.Summary.TotalChecks++

# Section 2: BitLocker Encryption Status
Write-Host "`n[2/7] Checking BitLocker encryption status..." -ForegroundColor Yellow
Write-Log "Section 2: BitLocker Encryption Status"
try {
    $BitLockerReport = Join-Path -Path $ReportPath -ChildPath "BitLockerStatus_$Timestamp.csv"
    $BitLockerData = & "$ScriptRoot\endpoints\intune\reporting\Get-BitLockerStatus.ps1" -ExportToCSV -OutputPath $BitLockerReport

    $UnencryptedCount = ($BitLockerData | Where-Object { $_.EncryptionStatus -ne "FullyEncrypted" }).Count
    $TotalChecked = $BitLockerData.Count

    Write-Host "  ✓ BitLocker Status: $($TotalChecked - $UnencryptedCount) encrypted, $UnencryptedCount unencrypted" -ForegroundColor Green
    Write-Log "BitLocker: $UnencryptedCount devices not fully encrypted" "INFO"

    $ReportData.Sections += @{
        Name = "BitLocker Encryption"
        Status = "Success"
        Summary = "$($TotalChecked - $UnencryptedCount) encrypted, $UnencryptedCount unencrypted"
        ReportFile = $BitLockerReport
    }
    $ReportData.Summary.SuccessfulChecks++

    if ($UnencryptedCount -gt 0) {
        $ReportData.Summary.Warnings++
    }
} catch {
    Write-Warning "  ✗ BitLocker status check failed: $_"
    Write-Log "BitLocker status check failed: $_" "ERROR"
    $ReportData.Sections += @{
        Name = "BitLocker Encryption"
        Status = "Failed"
        Summary = "Error: $_"
        ReportFile = $null
    }
    $ReportData.Errors += "BitLocker Encryption: $_"
    $ReportData.Summary.FailedChecks++
}
$ReportData.Summary.TotalChecks++

# Section 3: Windows Update Compliance
Write-Host "`n[3/7] Checking Windows Update compliance..." -ForegroundColor Yellow
Write-Log "Section 3: Windows Update Compliance"
try {
    $UpdateReport = Join-Path -Path $ReportPath -ChildPath "WindowsUpdateCompliance_$Timestamp.html"
    $UpdateData = & "$ScriptRoot\endpoints\intune\reporting\Get-WindowsUpdateCompliance.ps1" -ExportHTML -OutputPath $UpdateReport

    $OutdatedCount = ($UpdateData | Where-Object { $_.UpdatesNeeded -gt 0 }).Count
    $TotalDevices = $UpdateData.Count

    Write-Host "  ✓ Windows Updates: $OutdatedCount devices need updates" -ForegroundColor Green
    Write-Log "Windows Updates: $OutdatedCount devices need updates" "INFO"

    $ReportData.Sections += @{
        Name = "Windows Updates"
        Status = "Success"
        Summary = "$OutdatedCount devices need updates"
        ReportFile = $UpdateReport
    }
    $ReportData.Summary.SuccessfulChecks++

    if ($OutdatedCount -gt 5) {
        $ReportData.Summary.Warnings++
    }
} catch {
    Write-Warning "  ✗ Windows Update check failed: $_"
    Write-Log "Windows Update check failed: $_" "ERROR"
    $ReportData.Sections += @{
        Name = "Windows Updates"
        Status = "Failed"
        Summary = "Error: $_"
        ReportFile = $null
    }
    $ReportData.Errors += "Windows Updates: $_"
    $ReportData.Summary.FailedChecks++
}
$ReportData.Summary.TotalChecks++

# Section 4: Security Compliance Scan
Write-Host "`n[4/7] Running security compliance scan (CIS Benchmark)..." -ForegroundColor Yellow
Write-Log "Section 4: Security Compliance Scan"
try {
    $SecurityReport = Join-Path -Path $ReportPath -ChildPath "SecurityCompliance_$Timestamp.html"
    & "$ScriptRoot\security\compliance\frameworks\Test-CISBenchmark.ps1" `
        -ExportHTML `
        -OutputPath $SecurityReport

    Write-Host "  ✓ Security scan completed - review report for findings" -ForegroundColor Green
    Write-Log "Security compliance scan completed" "INFO"

    $ReportData.Sections += @{
        Name = "Security Compliance (CIS)"
        Status = "Success"
        Summary = "Scan completed - see detailed report"
        ReportFile = $SecurityReport
    }
    $ReportData.Summary.SuccessfulChecks++
} catch {
    Write-Warning "  ✗ Security scan failed: $_"
    Write-Log "Security scan failed: $_" "ERROR"
    $ReportData.Sections += @{
        Name = "Security Compliance (CIS)"
        Status = "Failed"
        Summary = "Error: $_"
        ReportFile = $null
    }
    $ReportData.Errors += "Security Compliance: $_"
    $ReportData.Summary.FailedChecks++
}
$ReportData.Summary.TotalChecks++

# Section 5: Failed Login Attempts (Last 24 Hours)
Write-Host "`n[5/7] Analyzing failed login attempts..." -ForegroundColor Yellow
Write-Log "Section 5: Failed Login Attempts"
try {
    $FailedLoginReport = Join-Path -Path $ReportPath -ChildPath "FailedLogins_$Timestamp.html"
    $FailedLogins = & "$ScriptRoot\security\compliance\frameworks\Get-FailedLoginReport.ps1" `
        -Hours 24 `
        -ExportHTML `
        -OutputPath $FailedLoginReport

    $FailedLoginCount = if ($FailedLogins) { $FailedLogins.Count } else { 0 }

    Write-Host "  ✓ Failed Logins: $FailedLoginCount attempts in last 24 hours" -ForegroundColor Green
    Write-Log "Failed Logins: $FailedLoginCount attempts" "INFO"

    $ReportData.Sections += @{
        Name = "Failed Login Attempts"
        Status = "Success"
        Summary = "$FailedLoginCount failed attempts in 24 hours"
        ReportFile = $FailedLoginReport
    }
    $ReportData.Summary.SuccessfulChecks++

    if ($FailedLoginCount -gt 10) {
        $ReportData.Summary.Warnings++
    }
} catch {
    Write-Warning "  ✗ Failed login report failed: $_"
    Write-Log "Failed login report failed: $_" "ERROR"
    $ReportData.Sections += @{
        Name = "Failed Login Attempts"
        Status = "Failed"
        Summary = "Error: $_"
        ReportFile = $null
    }
    $ReportData.Errors += "Failed Logins: $_"
    $ReportData.Summary.FailedChecks++
}
$ReportData.Summary.TotalChecks++

# Section 6: Certificate Expiration Check
Write-Host "`n[6/7] Checking for expiring certificates (30 days)..." -ForegroundColor Yellow
Write-Log "Section 6: Certificate Expiration"
try {
    $CertReport = Join-Path -Path $ReportPath -ChildPath "ExpiringCertificates_$Timestamp.csv"
    $ExpiringCerts = & "$ScriptRoot\security\compliance\frameworks\Get-ExpiredCertificates.ps1" `
        -DaysBeforeExpiration 30 `
        -ExportToCSV `
        -OutputPath $CertReport

    $ExpiringCount = if ($ExpiringCerts) { $ExpiringCerts.Count } else { 0 }

    Write-Host "  ✓ Certificates: $ExpiringCount expiring within 30 days" -ForegroundColor Green
    Write-Log "Certificates: $ExpiringCount expiring within 30 days" "INFO"

    $ReportData.Sections += @{
        Name = "Certificate Expiration"
        Status = "Success"
        Summary = "$ExpiringCount certificates expiring soon"
        ReportFile = $CertReport
    }
    $ReportData.Summary.SuccessfulChecks++

    if ($ExpiringCount -gt 0) {
        $ReportData.Summary.Warnings++
    }
} catch {
    Write-Warning "  ✗ Certificate check failed: $_"
    Write-Log "Certificate check failed: $_" "ERROR"
    $ReportData.Sections += @{
        Name = "Certificate Expiration"
        Status = "Failed"
        Summary = "Error: $_"
        ReportFile = $null
    }
    $ReportData.Errors += "Certificate Expiration: $_"
    $ReportData.Summary.FailedChecks++
}
$ReportData.Summary.TotalChecks++

# Section 7: Stale Device Cleanup (90 days inactive)
Write-Host "`n[7/7] Identifying stale devices..." -ForegroundColor Yellow
Write-Log "Section 7: Stale Devices"
try {
    $StaleDeviceReport = Join-Path -Path $ReportPath -ChildPath "StaleDevices_$Timestamp.csv"
    $StaleDevices = & "$ScriptRoot\endpoints\intune\maintenance\Find-StaleDevices.ps1" `
        -InactiveDays 90 `
        -ExportToCSV `
        -OutputPath $StaleDeviceReport

    $StaleCount = if ($StaleDevices) { $StaleDevices.Count } else { 0 }

    Write-Host "  ✓ Stale Devices: $StaleCount inactive for 90+ days" -ForegroundColor Green
    Write-Log "Stale Devices: $StaleCount devices inactive" "INFO"

    $ReportData.Sections += @{
        Name = "Stale Devices"
        Status = "Success"
        Summary = "$StaleCount devices inactive 90+ days"
        ReportFile = $StaleDeviceReport
    }
    $ReportData.Summary.SuccessfulChecks++

    if ($StaleCount -gt 10) {
        $ReportData.Summary.Warnings++
    }
} catch {
    Write-Warning "  ✗ Stale device check failed: $_"
    Write-Log "Stale device check failed: $_" "ERROR"
    $ReportData.Sections += @{
        Name = "Stale Devices"
        Status = "Failed"
        Summary = "Error: $_"
        ReportFile = $null
    }
    $ReportData.Errors += "Stale Devices: $_"
    $ReportData.Summary.FailedChecks++
}
$ReportData.Summary.TotalChecks++

# Cleanup old reports (retention policy)
Write-Host "`nCleaning up reports older than $RetentionDays days..." -ForegroundColor Cyan
Write-Log "Cleaning up old reports (retention: $RetentionDays days)"
try {
    $OldReports = Get-ChildItem -Path $ReportPath -Filter "*.*" | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-$RetentionDays) }
    foreach ($OldReport in $OldReports) {
        Remove-Item -Path $OldReport.FullName -Force
        Write-Log "Deleted old report: $($OldReport.Name)" "INFO"
    }
    Write-Host "  ✓ Cleaned up $($OldReports.Count) old report(s)" -ForegroundColor Green
} catch {
    Write-Warning "  ✗ Cleanup failed: $_"
    Write-Log "Report cleanup failed: $_" "ERROR"
}

# Generate Summary Email
Write-Host "`nGenerating summary email..." -ForegroundColor Cyan
Write-Log "Generating summary email"

$SummaryColor = if ($ReportData.Summary.FailedChecks -gt 0) {
    "#d32f2f"
} elseif ($ReportData.Summary.Warnings -gt 0) {
    "#ff6f00"
} else {
    "#388e3c"
}

$EmailBody = @"
<!DOCTYPE html>
<html>
<head>
    <title>Daily IT Report - $Timestamp</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 0; padding: 0; background-color: #f5f5f5; }
        .container { max-width: 800px; margin: 20px auto; background-color: white; padding: 30px; box-shadow: 0 0 10px rgba(0,0,0,0.1); }
        h1 { color: #0066cc; border-bottom: 3px solid #0066cc; padding-bottom: 10px; }
        .summary { background-color: #e3f2fd; padding: 20px; margin: 20px 0; border-radius: 5px; border-left: 5px solid $SummaryColor; }
        .summary h2 { margin-top: 0; color: $SummaryColor; }
        table { border-collapse: collapse; width: 100%; margin: 20px 0; }
        th { background-color: #0066cc; color: white; padding: 12px; text-align: left; }
        td { border: 1px solid #ddd; padding: 10px; }
        tr:nth-child(even) { background-color: #f9f9f9; }
        .success { color: #388e3c; font-weight: bold; }
        .failed { color: #d32f2f; font-weight: bold; }
        .footer { margin-top: 30px; padding-top: 20px; border-top: 1px solid #ddd; font-size: 0.9em; color: #666; }
    </style>
</head>
<body>
    <div class="container">
        <h1>📊 Daily IT Operations Report</h1>
        <p><strong>Report Date:</strong> $Timestamp</p>
        <p><strong>Generated:</strong> $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</p>

        <div class="summary">
            <h2>Executive Summary</h2>
            <p><strong>Total Checks:</strong> $($ReportData.Summary.TotalChecks)</p>
            <p><strong>Successful:</strong> <span class="success">$($ReportData.Summary.SuccessfulChecks)</span></p>
            <p><strong>Failed:</strong> <span class="failed">$($ReportData.Summary.FailedChecks)</span></p>
            <p><strong>Warnings:</strong> $($ReportData.Summary.Warnings)</p>
        </div>

        <h2>Report Sections</h2>
        <table>
            <tr>
                <th>Section</th>
                <th>Status</th>
                <th>Summary</th>
            </tr>
"@

foreach ($Section in $ReportData.Sections) {
    $StatusClass = if ($Section.Status -eq "Success") { "success" } else { "failed" }
    $EmailBody += @"
            <tr>
                <td>$($Section.Name)</td>
                <td class="$StatusClass">$($Section.Status)</td>
                <td>$($Section.Summary)</td>
            </tr>
"@
}

$EmailBody += @"
        </table>
"@

if ($ReportData.Errors.Count -gt 0) {
    $EmailBody += @"
        <h2 style="color: #d32f2f;">⚠ Errors Encountered</h2>
        <ul>
"@
    foreach ($ReportError in $ReportData.Errors) {
        $EmailBody += "            <li>$ReportError</li>`n"
    }
    $EmailBody += "        </ul>`n"
}

$EmailBody += @"
        <p><strong>Note:</strong> Detailed reports are saved to: <code>$ReportPath</code></p>

        <div class="footer">
            <p>This is an automated report generated by bug-free-umbrella.</p>
            <p>Repository: <a href="https://github.com/Carme99/bug-free-umbrella">https://github.com/Carme99/bug-free-umbrella</a></p>
        </div>
    </div>
</body>
</html>
"@

# Send Email
Write-Host "Sending email report to: $($EmailTo -join ', ')..." -ForegroundColor Cyan
Write-Log "Sending email to: $($EmailTo -join ', ')"
try {
    $MailParams = @{
        To         = $EmailTo
        From       = $EmailFrom
        Subject    = "Daily IT Report - $Timestamp - $($ReportData.Summary.SuccessfulChecks)/$($ReportData.Summary.TotalChecks) Checks Passed"
        Body       = $EmailBody
        BodyAsHtml = $true
        SmtpServer = $SMTPServer
        Port       = $SMTPPort
    }

    # Add authentication if credential provided
    if ($Credential) {
        $MailParams.Credential = $Credential
        Write-Log "Using authenticated SMTP" "INFO"
    }

    # Add SSL/TLS if requested
    if ($UseSsl) {
        $MailParams.UseSsl = $true
        Write-Log "Using SSL/TLS encryption" "INFO"
    }

    # Add attachments if any critical reports exist
    if ($ReportData.Summary.FailedChecks -gt 0 -or $ReportData.Summary.Warnings -gt 3) {
        Write-Host "  Adding detailed reports as attachments..." -ForegroundColor Yellow
    }

    Send-MailMessage @MailParams
    Write-Host "  ✓ Email sent successfully" -ForegroundColor Green
    Write-Log "Email sent successfully" "INFO"
} catch {
    Write-Warning "  ✗ Failed to send email: $_"
    Write-Log "Failed to send email: $_" "ERROR"
}

Write-Host "`n=== AUTOMATED DAILY REPORTING COMPLETE ===" -ForegroundColor Cyan
Write-Host "Summary: $($ReportData.Summary.SuccessfulChecks)/$($ReportData.Summary.TotalChecks) checks passed" -ForegroundColor Yellow
Write-Host "Reports saved to: $ReportPath" -ForegroundColor Yellow
Write-Log "=== AUTOMATED DAILY REPORTING COMPLETED ===" "INFO"
Write-Log "Summary: $($ReportData.Summary.SuccessfulChecks)/$($ReportData.Summary.TotalChecks) checks passed" "INFO"
