<#
.SYNOPSIS
    Monthly compliance audit workflow

.DESCRIPTION
    This example demonstrates a comprehensive monthly compliance audit covering
    multiple frameworks (CIS, NIST, PCI-DSS, HIPAA) with automated reporting.

.NOTES
    Copyright (c) 2025 bug-free-umbrella contributors
    Licensed under Apache License 2.0
    https://github.com/Carme99/bug-free-umbrella

.EXAMPLE
    .\monthly-compliance-audit.ps1 -Frameworks CIS,NIST,PCI-DSS -ExportPath "C:\ComplianceReports"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [ValidateSet("CIS", "NIST", "PCI-DSS", "HIPAA", "SOC2", "ISO27001", "All")]
    [string[]]$Frameworks = @("CIS", "NIST"),

    [Parameter(Mandatory = $false)]
    [string]$ExportPath = "C:\ComplianceReports",

    [Parameter(Mandatory = $false)]
    [switch]$EmailReport,

    [Parameter(Mandatory = $false)]
    [string]$SMTPServer,

    [Parameter(Mandatory = $false)]
    [string]$To
)

# Define the root path to the scripts directory
$ScriptRoot = Join-Path -Path $PSScriptRoot -ChildPath "..\..\scripts"

# Create export directory if it doesn't exist
if (-not (Test-Path -Path $ExportPath)) {
    New-Item -Path $ExportPath -ItemType Directory -Force | Out-Null
}

$Timestamp = Get-Date -Format "yyyy-MM"
$AuditDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

Write-Host "=== Monthly Compliance Audit ===" -ForegroundColor Cyan
Write-Host "Date: $AuditDate" -ForegroundColor Yellow
Write-Host "Frameworks: $($Frameworks -join ', ')" -ForegroundColor Yellow
Write-Host ""

$AuditResults = @()

# 1. Run Security Compliance Scans
Write-Host "[1/5] Running compliance scans..." -ForegroundColor Green
foreach ($Framework in $Frameworks) {
    Write-Host "  - Scanning: $Framework" -ForegroundColor Yellow
    try {
        $ScanOutput = Join-Path -Path $ExportPath -ChildPath "${Timestamp}_${Framework}_Scan.html"
        & "$ScriptRoot\security\compliance\frameworks\Invoke-SecurityComplianceScan.ps1" `
            -Framework $Framework `
            -ExportHTML `
            -OutputPath $ScanOutput
        $AuditResults += @{ Framework = $Framework; Status = "Completed"; Report = $ScanOutput }
        Write-Host "    ✓ Scan completed" -ForegroundColor Green
    } catch {
        $AuditResults += @{ Framework = $Framework; Status = "Failed"; Error = $_ }
        Write-Warning "    ✗ Scan failed: $_"
    }
}

# 2. BitLocker Compliance Check
Write-Host "`n[2/5] BitLocker compliance verification..." -ForegroundColor Green
try {
    $BitLockerReport = Join-Path -Path $ExportPath -ChildPath "${Timestamp}_BitLocker_Status.csv"
    & "$ScriptRoot\endpoints\intune\reporting\Get-BitLockerStatus.ps1" `
        -ExportCSV `
        -OutputPath $BitLockerReport
    $AuditResults += @{ Framework = "BitLocker"; Status = "Completed"; Report = $BitLockerReport }
    Write-Host "  ✓ BitLocker status verified" -ForegroundColor Green
} catch {
    $AuditResults += @{ Framework = "BitLocker"; Status = "Failed"; Error = $_ }
    Write-Warning "  ✗ BitLocker check failed: $_"
}

# 3. Security Baseline Check
Write-Host "`n[3/5] Security baseline verification..." -ForegroundColor Green
try {
    $SecurityReport = Join-Path -Path $ExportPath -ChildPath "${Timestamp}_Security_Baseline.html"
    & "$ScriptRoot\security\compliance\frameworks\Get-SecurityBaseline.ps1" `
        -ExportHTML `
        -OutputPath $SecurityReport
    $AuditResults += @{ Framework = "Security Baseline"; Status = "Completed"; Report = $SecurityReport }
    Write-Host "  ✓ Security baseline check completed" -ForegroundColor Green
} catch {
    $AuditResults += @{ Framework = "Security Baseline"; Status = "Failed"; Error = $_ }
    Write-Warning "  ✗ Security baseline check failed: $_"
}

# 4. System Health and Security Monitoring
Write-Host "`n[4/5] System health and security monitoring..." -ForegroundColor Green
try {
    $HealthReport = Join-Path -Path $ExportPath -ChildPath "${Timestamp}_System_Health.html"
    & "$ScriptRoot\infrastructure\windows\monitoring\Monitor-ServerHealth.ps1" `
        -SecurityAudit `
        -CheckCertificates `
        -DaysBeforeExpiration 60 `
        -ExportHTML `
        -OutputPath $HealthReport
    $AuditResults += @{ Framework = "System Health"; Status = "Completed"; Report = $HealthReport }
    Write-Host "  ✓ Health monitoring completed" -ForegroundColor Green
} catch {
    $AuditResults += @{ Framework = "System Health"; Status = "Failed"; Error = $_ }
    Write-Warning "  ✗ Health monitoring failed: $_"
}

# 5. Generate Executive Summary
Write-Host "`n[5/5] Generating executive summary..." -ForegroundColor Green

$SummaryReport = Join-Path -Path $ExportPath -ChildPath "${Timestamp}_Executive_Summary.html"

$PassedScans = ($AuditResults | Where-Object { $_.Status -eq "Completed" }).Count
$FailedScans = ($AuditResults | Where-Object { $_.Status -eq "Failed" }).Count
$TotalScans = $AuditResults.Count

$HtmlSummary = @"
<!DOCTYPE html>
<html>
<head>
    <title>Monthly Compliance Audit - Executive Summary</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background-color: #f5f5f5; }
        .container { max-width: 1200px; margin: 0 auto; background-color: white; padding: 30px; box-shadow: 0 0 10px rgba(0,0,0,0.1); }
        h1 { color: #0066cc; border-bottom: 3px solid #0066cc; padding-bottom: 10px; }
        h2 { color: #333; margin-top: 30px; }
        .summary-box { background-color: #f0f8ff; border-left: 4px solid #0066cc; padding: 15px; margin: 20px 0; }
        .metrics { display: flex; justify-content: space-around; margin: 20px 0; }
        .metric { text-align: center; padding: 20px; background-color: #f9f9f9; border-radius: 5px; flex: 1; margin: 0 10px; }
        .metric-value { font-size: 2.5em; font-weight: bold; color: #0066cc; }
        .metric-label { font-size: 0.9em; color: #666; margin-top: 5px; }
        table { border-collapse: collapse; width: 100%; margin-top: 20px; }
        th { background-color: #0066cc; color: white; padding: 12px; text-align: left; }
        td { border: 1px solid #ddd; padding: 10px; }
        tr:nth-child(even) { background-color: #f9f9f9; }
        .status-completed { color: green; font-weight: bold; }
        .status-failed { color: red; font-weight: bold; }
        .recommendations { background-color: #fff3cd; border-left: 4px solid #ffc107; padding: 15px; margin: 20px 0; }
        .footer { margin-top: 40px; padding-top: 20px; border-top: 1px solid #ddd; font-size: 0.9em; color: #666; text-align: center; }
    </style>
</head>
<body>
    <div class="container">
        <h1>Monthly Compliance Audit - Executive Summary</h1>

        <div class="summary-box">
            <strong>Audit Period:</strong> $Timestamp<br>
            <strong>Generated:</strong> $AuditDate<br>
            <strong>Frameworks Assessed:</strong> $($Frameworks -join ', ')<br>
        </div>

        <h2>Audit Metrics</h2>
        <div class="metrics">
            <div class="metric">
                <div class="metric-value">$TotalScans</div>
                <div class="metric-label">Total Audits</div>
            </div>
            <div class="metric">
                <div class="metric-value" style="color: green;">$PassedScans</div>
                <div class="metric-label">Completed</div>
            </div>
            <div class="metric">
                <div class="metric-value" style="color: red;">$FailedScans</div>
                <div class="metric-label">Failed</div>
            </div>
        </div>

        <h2>Audit Results</h2>
        <table>
            <tr>
                <th>Framework/Component</th>
                <th>Status</th>
                <th>Report</th>
                <th>Notes</th>
            </tr>
"@

foreach ($Result in $AuditResults) {
    $StatusClass = if ($Result.Status -eq "Completed") { "status-completed" } else { "status-failed" }
    $ReportLink = if ($Result.Report) { "<a href='file:///$($Result.Report)'>View Report</a>" } else { "-" }
    $Notes = if ($Result.Error) { $Result.Error } else { "No issues" }

    $HtmlSummary += @"
            <tr>
                <td>$($Result.Framework)</td>
                <td class="$StatusClass">$($Result.Status)</td>
                <td>$ReportLink</td>
                <td>$Notes</td>
            </tr>
"@
}

$HtmlSummary += @"
        </table>

        <h2>Key Findings</h2>
        <div class="recommendations">
            <strong>Action Items:</strong>
            <ul>
                <li>Review all failed compliance scans and initiate remediation</li>
                <li>Verify BitLocker encryption is enabled on all required systems</li>
                <li>Address any certificate expiration warnings (60-day threshold)</li>
                <li>Review security posture findings and implement recommendations</li>
                <li>Schedule follow-up assessment for critical findings</li>
            </ul>
        </div>

        <h2>Compliance Trend</h2>
        <p>Compare this month's results with previous audits to identify trends:</p>
        <ul>
            <li>Track improvement in compliance scores over time</li>
            <li>Monitor recurring issues across frameworks</li>
            <li>Measure effectiveness of remediation efforts</li>
        </ul>

        <h2>Next Steps</h2>
        <ol>
            <li>Distribute detailed reports to relevant stakeholders</li>
            <li>Create remediation tickets for failed items</li>
            <li>Schedule review meeting with security team</li>
            <li>Update compliance dashboard with current results</li>
            <li>Plan next month's audit schedule</li>
        </ol>

        <div class="footer">
            <p>Generated by bug-free-umbrella automation</p>
            <p><a href="https://github.com/Carme99/bug-free-umbrella">https://github.com/Carme99/bug-free-umbrella</a></p>
        </div>
    </div>
</body>
</html>
"@

$HtmlSummary | Out-File -FilePath $SummaryReport -Encoding UTF8
Write-Host "✓ Executive summary saved: $SummaryReport" -ForegroundColor Green

# Email Report (if requested)
if ($EmailReport -and $SMTPServer -and $To) {
    Write-Host "`nSending compliance audit summary..." -ForegroundColor Green
    try {
        $MailParams = @{
            To         = $To
            From       = "compliance@$env:USERDNSDOMAIN"
            Subject    = "Monthly Compliance Audit Summary - $Timestamp"
            Body       = $HtmlSummary
            BodyAsHtml = $true
            SmtpServer = $SMTPServer
        }
        Send-MailMessage @MailParams
        Write-Host "✓ Email sent successfully" -ForegroundColor Green
    } catch {
        Write-Warning "Failed to send email: $_"
    }
}

Write-Host "`n=== Compliance Audit Complete ===" -ForegroundColor Cyan
Write-Host "Summary Report: $SummaryReport" -ForegroundColor Yellow
Write-Host "All reports saved to: $ExportPath" -ForegroundColor Yellow
