<#
.SYNOPSIS
    Security incident investigation and response workflow

.DESCRIPTION
    This example demonstrates a comprehensive security incident response workflow that includes
    threat detection, user activity audit, suspicious login investigation, compromised account
    isolation, and incident reporting. Use this when responding to potential security breaches.

.NOTES
    Copyright (c) 2025 bug-free-umbrella contributors
    Licensed under Apache License 2.0
    https://github.com/Carme99/bug-free-umbrella

.EXAMPLE
    .\security-incident-response.ps1 -SuspiciousUser "compromised@company.com" -IncidentId "INC-2025-001"

.EXAMPLE
    .\security-incident-response.ps1 -SuspiciousUser "user@company.com" -IsolateAccount -EmailReport -To "soc@company.com"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SuspiciousUser,

    [Parameter(Mandatory = $false)]
    [string]$IncidentId = "INC-$(Get-Date -Format 'yyyyMMdd-HHmmss')",

    [Parameter(Mandatory = $false)]
    [string]$ReportPath = "C:\IncidentReports",

    [Parameter(Mandatory = $false)]
    [switch]$IsolateAccount,

    [Parameter(Mandatory = $false)]
    [switch]$EmailReport,

    [Parameter(Mandatory = $false)]
    [string]$SMTPServer,

    [Parameter(Mandatory = $false)]
    [int]$SMTPPort = 587,

    [Parameter(Mandatory = $false)]
    [switch]$UseSsl,

    [Parameter(Mandatory = $false)]
    [System.Management.Automation.PSCredential]$Credential,

    [Parameter(Mandatory = $false)]
    [string]$To
)

# Define the root path to the scripts directory
$ScriptRoot = Join-Path -Path $PSScriptRoot -ChildPath "..\..\scripts"

# Validate script root exists
if (-not (Test-Path -Path $ScriptRoot)) {
    Write-Error "Script root path not found: $ScriptRoot"
    Write-Error "Please ensure the script is run from the examples/incident-response directory"
    exit 1
}

# Create report directory if it doesn't exist
if (-not (Test-Path -Path $ReportPath)) {
    New-Item -Path $ReportPath -ItemType Directory -Force | Out-Null
}

$Timestamp = Get-Date -Format "yyyy-MM-dd_HHmmss"
$ReportFile = Join-Path -Path $ReportPath -ChildPath "SecurityIncident_${IncidentId}_$Timestamp.html"
$LogFile = Join-Path -Path $ReportPath -ChildPath "SecurityIncident_${IncidentId}_$Timestamp.log"

function Write-Log {
    param([string]$Message)
    $LogMessage = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $Message"
    Write-Host $LogMessage
    Add-Content -Path $LogFile -Value $LogMessage
}

Write-Host "=== SECURITY INCIDENT RESPONSE ===" -ForegroundColor Red
Write-Host "Incident ID: $IncidentId" -ForegroundColor Yellow
Write-Host "Suspicious User: $SuspiciousUser" -ForegroundColor Yellow
Write-Host "Response Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Yellow
Write-Host ""

Write-Log "=== SECURITY INCIDENT RESPONSE INITIATED ==="
Write-Log "Incident ID: $IncidentId"
Write-Log "Target User: $SuspiciousUser"

$Findings = @()

# Step 1: Get comprehensive user information
Write-Host "[1/8] Gathering user account information..." -ForegroundColor Cyan
Write-Log "Step 1: Gathering user account information"
try {
    $UserInfo = & "$ScriptRoot\collaboration\microsoft365\Get-M365UserInfo.ps1" -UserPrincipalName $SuspiciousUser
    $Findings += @{
        Category = "User Information"
        Status = "Collected"
        Details = "User account details retrieved"
    }
    Write-Host "✓ User information collected" -ForegroundColor Green
    Write-Log "SUCCESS: User information collected"
} catch {
    $Findings += @{
        Category = "User Information"
        Status = "Failed"
        Details = "Error: $_"
    }
    Write-Warning "Failed to retrieve user info: $_"
    Write-Log "ERROR: Failed to retrieve user info: $_"
}

# Step 2: Check for failed login attempts
Write-Host "`n[2/8] Analyzing failed login attempts (last 48 hours)..." -ForegroundColor Cyan
Write-Log "Step 2: Analyzing failed login attempts"
try {
    $FailedLogins = & "$ScriptRoot\security\compliance\frameworks\Get-FailedLoginReport.ps1" `
        -Hours 48 `
        -UserName $SuspiciousUser

    if ($FailedLogins) {
        Write-Warning "Found $($FailedLogins.Count) failed login attempts"
        Write-Log "WARNING: Found $($FailedLogins.Count) failed login attempts"
        $Findings += @{
            Category = "Failed Logins"
            Status = "Found"
            Details = "$($FailedLogins.Count) failed attempts in last 48 hours"
        }
    } else {
        Write-Host "✓ No unusual failed login attempts" -ForegroundColor Green
        Write-Log "INFO: No unusual failed login attempts"
        $Findings += @{
            Category = "Failed Logins"
            Status = "Clean"
            Details = "No suspicious failed logins"
        }
    }
} catch {
    Write-Warning "Failed login check error: $_"
    Write-Log "ERROR: Failed login check: $_"
    $Findings += @{
        Category = "Failed Logins"
        Status = "Failed"
        Details = "Error: $_"
    }
}

# Step 3: Check for suspicious mail rules
Write-Host "`n[3/8] Checking for suspicious mail rules..." -ForegroundColor Cyan
Write-Log "Step 3: Checking for suspicious mail rules"
try {
    $MailRules = & "$ScriptRoot\collaboration\microsoft365\exchange-online\Get-UserMailRules.ps1" `
        -UserPrincipalName $SuspiciousUser `
        -CheckForSuspicious

    if ($MailRules | Where-Object { $_.IsSuspicious -eq $true }) {
        Write-Warning "Found suspicious mail forwarding or deletion rules"
        Write-Log "CRITICAL: Suspicious mail rules detected"
        $Findings += @{
            Category = "Mail Rules"
            Status = "Suspicious"
            Details = "Potential data exfiltration rules found"
        }
    } else {
        Write-Host "✓ No suspicious mail rules detected" -ForegroundColor Green
        Write-Log "INFO: No suspicious mail rules"
        $Findings += @{
            Category = "Mail Rules"
            Status = "Clean"
            Details = "No suspicious mail rules"
        }
    }
} catch {
    Write-Warning "Mail rule check failed: $_"
    Write-Log "ERROR: Mail rule check failed: $_"
    $Findings += @{
        Category = "Mail Rules"
        Status = "Failed"
        Details = "Error: $_"
    }
}

# Step 4: Check mailbox permissions
Write-Host "`n[4/8] Auditing mailbox permissions..." -ForegroundColor Cyan
Write-Log "Step 4: Auditing mailbox permissions"
try {
    $Permissions = & "$ScriptRoot\collaboration\microsoft365\exchange-online\Get-UserMailboxPermissions.ps1" `
        -UserPrincipalName $SuspiciousUser

    $DelegateCount = ($Permissions | Where-Object { $_.AccessRights -match "FullAccess|SendAs" }).Count
    if ($DelegateCount -gt 0) {
        Write-Warning "Found $DelegateCount delegate permissions - review for unauthorized access"
        Write-Log "WARNING: Found $DelegateCount delegate permissions"
        $Findings += @{
            Category = "Mailbox Permissions"
            Status = "Review Required"
            Details = "$DelegateCount users with elevated permissions"
        }
    } else {
        Write-Host "✓ No suspicious mailbox delegations" -ForegroundColor Green
        Write-Log "INFO: No suspicious mailbox delegations"
        $Findings += @{
            Category = "Mailbox Permissions"
            Status = "Clean"
            Details = "No elevated permissions granted"
        }
    }
} catch {
    Write-Warning "Permission audit failed: $_"
    Write-Log "ERROR: Permission audit failed: $_"
    $Findings += @{
        Category = "Mailbox Permissions"
        Status = "Failed"
        Details = "Error: $_"
    }
}

# Step 5: Check for recent threat detections
Write-Host "`n[5/8] Checking Defender for Office 365 threat detections..." -ForegroundColor Cyan
Write-Log "Step 5: Checking threat detections"
try {
    $Threats = & "$ScriptRoot\collaboration\microsoft365\defender-office365\Get-DefenderO365ThreatReport.ps1" `
        -Days 7 `
        -UserPrincipalName $SuspiciousUser

    if ($Threats) {
        Write-Warning "Found $($Threats.Count) threat detections in last 7 days"
        Write-Log "CRITICAL: Found $($Threats.Count) threat detections"
        $Findings += @{
            Category = "Threat Detection"
            Status = "Threats Found"
            Details = "$($Threats.Count) threats detected"
        }
    } else {
        Write-Host "✓ No recent threats detected" -ForegroundColor Green
        Write-Log "INFO: No recent threats detected"
        $Findings += @{
            Category = "Threat Detection"
            Status = "Clean"
            Details = "No threats in last 7 days"
        }
    }
} catch {
    Write-Warning "Threat check failed: $_"
    Write-Log "ERROR: Threat check failed: $_"
    $Findings += @{
        Category = "Threat Detection"
        Status = "Failed"
        Details = "Error: $_"
    }
}

# Step 6: Check if user's devices are compliant
Write-Host "`n[6/8] Checking device compliance status..." -ForegroundColor Cyan
Write-Log "Step 6: Checking device compliance"
try {
    $DeviceCompliance = & "$ScriptRoot\endpoints\intune\reporting\Get-DeviceComplianceReport.ps1" `
        -UserPrincipalName $SuspiciousUser

    $NonCompliantDevices = $DeviceCompliance | Where-Object { $_.ComplianceState -eq "NonCompliant" }
    if ($NonCompliantDevices) {
        Write-Warning "Found $($NonCompliantDevices.Count) non-compliant devices"
        Write-Log "WARNING: Found $($NonCompliantDevices.Count) non-compliant devices"
        $Findings += @{
            Category = "Device Compliance"
            Status = "Non-Compliant"
            Details = "$($NonCompliantDevices.Count) devices need attention"
        }
    } else {
        Write-Host "✓ All devices compliant" -ForegroundColor Green
        Write-Log "INFO: All devices compliant"
        $Findings += @{
            Category = "Device Compliance"
            Status = "Compliant"
            Details = "All devices meet policy requirements"
        }
    }
} catch {
    Write-Warning "Device compliance check failed: $_"
    Write-Log "ERROR: Device compliance check failed: $_"
    $Findings += @{
        Category = "Device Compliance"
        Status = "Failed"
        Details = "Error: $_"
    }
}

# Step 7: Check mail flow patterns
Write-Host "`n[7/8] Analyzing mail flow patterns..." -ForegroundColor Cyan
Write-Log "Step 7: Analyzing mail flow patterns"
try {
    $MailFlow = & "$ScriptRoot\collaboration\microsoft365\exchange-online\Get-MailFlowAnalysis.ps1" `
        -UserPrincipalName $SuspiciousUser `
        -Days 7

    Write-Host "✓ Mail flow analysis completed - review for anomalies" -ForegroundColor Green
    Write-Log "INFO: Mail flow analysis completed"
    $Findings += @{
        Category = "Mail Flow"
        Status = "Analyzed"
        Details = "7-day mail flow pattern collected"
    }
} catch {
    Write-Warning "Mail flow analysis failed: $_"
    Write-Log "ERROR: Mail flow analysis failed: $_"
    $Findings += @{
        Category = "Mail Flow"
        Status = "Failed"
        Details = "Error: $_"
    }
}

# Step 8: Account isolation (if requested)
Write-Host "`n[8/8] Account isolation..." -ForegroundColor Cyan
Write-Log "Step 8: Account isolation"
if ($IsolateAccount) {
    Write-Host "⚠ WARNING: Account isolation is a destructive operation!" -ForegroundColor Red -BackgroundColor Yellow
    Write-Host "  This will:" -ForegroundColor Yellow
    Write-Host "    - Revoke all active sessions" -ForegroundColor Yellow
    Write-Host "    - Disable the account" -ForegroundColor Yellow
    Write-Host "    - Block sign-in" -ForegroundColor Yellow
    Write-Host ""

    $Confirmation = Read-Host "Type 'ISOLATE' to confirm account isolation for $SuspiciousUser"

    if ($Confirmation -ne 'ISOLATE') {
        Write-Host "Account isolation cancelled by user" -ForegroundColor Yellow
        Write-Log "Account isolation cancelled by user"
        $Findings += @{
            Category = "Response Action"
            Status = "Cancelled"
            Details = "Account isolation was cancelled by administrator"
        }
    } else {
        Write-Host "⚠ ISOLATING ACCOUNT - User will be signed out and blocked" -ForegroundColor Red
        Write-Log "CRITICAL: Account isolation initiated"

        # In production, this would:
        # - Revoke all active sessions
        # - Disable the account
        # - Reset password
        # - Remove from groups
        # - Block sign-in

        Write-Host "  [!] Revoking active sessions..." -ForegroundColor Yellow
        Write-Host "  [!] Disabling account..." -ForegroundColor Yellow
        Write-Host "  [!] Blocking sign-in..." -ForegroundColor Yellow
        Write-Host "  [!] Notifying security team..." -ForegroundColor Yellow

        Write-Log "Account isolation actions would be performed here"
        Write-Warning "Account isolation flag set - manual action required in production"

        $Findings += @{
            Category = "Response Action"
            Status = "Isolation Requested"
            Details = "Account requires manual isolation by administrator"
        }
    }
} else {
    Write-Host "ℹ Account isolation NOT requested - monitoring only" -ForegroundColor Yellow
    Write-Log "INFO: Monitoring mode - no isolation actions taken"
    $Findings += @{
        Category = "Response Action"
        Status = "Monitoring"
        Details = "No isolation actions taken"
    }
}

# Generate HTML Report
Write-Host "`nGenerating incident response report..." -ForegroundColor Cyan
Write-Log "Generating incident response report"

$SeverityColor = if ($Findings | Where-Object { $_.Status -match "Suspicious|Threats Found|Non-Compliant" }) {
    "red"
} else {
    "orange"
}

$HtmlReport = @"
<!DOCTYPE html>
<html>
<head>
    <title>Security Incident Report - $IncidentId</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background-color: #f5f5f5; }
        .container { max-width: 1200px; margin: 0 auto; background-color: white; padding: 30px; box-shadow: 0 0 10px rgba(0,0,0,0.1); }
        h1 { color: #d32f2f; border-bottom: 3px solid #d32f2f; padding-bottom: 10px; }
        h2 { color: #0066cc; margin-top: 30px; }
        .header-info { background-color: #fff3cd; border-left: 5px solid #ffc107; padding: 15px; margin: 20px 0; }
        .critical { background-color: #ffebee; border-left: 5px solid #d32f2f; padding: 10px; margin: 10px 0; }
        .warning { background-color: #fff3cd; border-left: 5px solid #ffc107; padding: 10px; margin: 10px 0; }
        .info { background-color: #e3f2fd; border-left: 5px solid #2196f3; padding: 10px; margin: 10px 0; }
        .success { background-color: #e8f5e9; border-left: 5px solid #4caf50; padding: 10px; margin: 10px 0; }
        table { border-collapse: collapse; width: 100%; margin-top: 20px; }
        th { background-color: #d32f2f; color: white; padding: 12px; text-align: left; }
        td { border: 1px solid #ddd; padding: 10px; }
        tr:nth-child(even) { background-color: #f9f9f9; }
        .status-suspicious { color: #d32f2f; font-weight: bold; }
        .status-warning { color: #ff6f00; font-weight: bold; }
        .status-clean { color: #388e3c; font-weight: bold; }
        .status-failed { color: #666; font-style: italic; }
        .recommendations { background-color: #ffebee; padding: 20px; margin-top: 30px; border-radius: 5px; }
        .footer { margin-top: 40px; padding-top: 20px; border-top: 1px solid #ddd; color: #666; font-size: 0.9em; }
    </style>
</head>
<body>
    <div class="container">
        <h1>🚨 SECURITY INCIDENT RESPONSE REPORT</h1>

        <div class="header-info">
            <p><strong>Incident ID:</strong> $IncidentId</p>
            <p><strong>Suspicious User:</strong> $SuspiciousUser</p>
            <p><strong>Report Generated:</strong> $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")</p>
            <p><strong>Incident Severity:</strong> <span style="color: $SeverityColor; font-weight: bold;">$(if ($SeverityColor -eq 'red') { 'HIGH' } else { 'MEDIUM' })</span></p>
        </div>

        <h2>Investigation Findings</h2>
        <table>
            <tr>
                <th>Category</th>
                <th>Status</th>
                <th>Details</th>
            </tr>
"@

foreach ($Finding in $Findings) {
    $StatusClass = switch -Wildcard ($Finding.Status) {
        "*Suspicious*" { "status-suspicious" }
        "*Threats*" { "status-suspicious" }
        "*Non-Compliant*" { "status-warning" }
        "*Warning*" { "status-warning" }
        "*Review*" { "status-warning" }
        "*Clean*" { "status-clean" }
        "*Compliant*" { "status-clean" }
        "*Failed*" { "status-failed" }
        default { "status-clean" }
    }

    $HtmlReport += @"
            <tr>
                <td>$($Finding.Category)</td>
                <td class="$StatusClass">$($Finding.Status)</td>
                <td>$($Finding.Details)</td>
            </tr>
"@
}

$HtmlReport += @"
        </table>

        <div class="recommendations">
            <h2>🔒 Recommended Actions</h2>
            <ol>
                <li><strong>IMMEDIATE:</strong> Review all findings marked as "Suspicious" or "Threats Found"</li>
                <li><strong>IMMEDIATE:</strong> Remove any suspicious mail forwarding rules</li>
                <li><strong>IMMEDIATE:</strong> Revoke sessions and force password reset if compromise confirmed</li>
                <li><strong>SHORT TERM:</strong> Review mailbox permissions and remove unauthorized access</li>
                <li><strong>SHORT TERM:</strong> Quarantine affected devices if non-compliant</li>
                <li><strong>SHORT TERM:</strong> Monitor mail flow for next 48 hours for anomalies</li>
                <li><strong>FOLLOW-UP:</strong> Schedule security awareness training for the user</li>
                <li><strong>FOLLOW-UP:</strong> Review and update security policies if needed</li>
                <li><strong>DOCUMENTATION:</strong> Log all actions taken in incident management system</li>
            </ol>
        </div>

        <h2>📋 Incident Timeline</h2>
        <div class="info">
            <p>• <strong>Incident Detected:</strong> $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")</p>
            <p>• <strong>Response Initiated:</strong> $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")</p>
            <p>• <strong>Investigation Completed:</strong> $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")</p>
            <p>• <strong>Isolation Status:</strong> $(if ($IsolateAccount) { 'REQUESTED - Manual action required' } else { 'Not requested' })</p>
        </div>

        <h2>📎 Related Evidence</h2>
        <p>Additional logs and evidence stored at: <code>$LogFile</code></p>

        <div class="footer">
            <p><strong>Generated by:</strong> bug-free-umbrella Security Incident Response Workflow</p>
            <p><strong>Repository:</strong> <a href="https://github.com/Carme99/bug-free-umbrella">https://github.com/Carme99/bug-free-umbrella</a></p>
            <p><strong>Report ID:</strong> $IncidentId</p>
        </div>
    </div>
</body>
</html>
"@

$HtmlReport | Out-File -FilePath $ReportFile -Encoding UTF8
Write-Host "✓ Report saved: $ReportFile" -ForegroundColor Green
Write-Host "✓ Log saved: $LogFile" -ForegroundColor Green
Write-Log "Report generated: $ReportFile"

# Email Report (if requested)
if ($EmailReport -and $SMTPServer -and $To) {
    Write-Host "`nSending incident report via email..." -ForegroundColor Cyan
    Write-Log "Sending email report to $To"
    try {
        $DomainName = if ($env:USERDNSDOMAIN) { $env:USERDNSDOMAIN } else { "company.com" }
        $MailParams = @{
            To         = $To
            From       = "security-noreply@$DomainName"
            Subject    = "🚨 SECURITY INCIDENT REPORT - $IncidentId - User: $SuspiciousUser"
            Body       = $HtmlReport
            BodyAsHtml = $true
            SmtpServer = $SMTPServer
            Port       = $SMTPPort
            Priority   = "High"
        }

        # Add authentication if credential provided
        if ($Credential) {
            $MailParams.Credential = $Credential
        }

        # Add SSL/TLS if requested
        if ($UseSsl) {
            $MailParams.UseSsl = $true
        }

        Send-MailMessage @MailParams
        Write-Host "✓ Email sent successfully to $To" -ForegroundColor Green
        Write-Log "Email sent successfully"
    } catch {
        Write-Warning "Failed to send email: $_"
        Write-Log "ERROR: Failed to send email: $_"
    }
}

Write-Host "`n=== INCIDENT RESPONSE COMPLETE ===" -ForegroundColor Red
Write-Host "Incident ID: $IncidentId" -ForegroundColor Yellow
Write-Host "Review the report and take immediate action on any suspicious findings." -ForegroundColor Yellow
Write-Host ""

if ($Findings | Where-Object { $_.Status -match "Suspicious|Threats Found" }) {
    Write-Host "⚠ CRITICAL FINDINGS DETECTED - IMMEDIATE ACTION REQUIRED" -ForegroundColor Red -BackgroundColor Yellow
    Write-Log "CRITICAL: Critical findings detected - immediate action required"
}

Write-Log "=== INCIDENT RESPONSE COMPLETED ==="
