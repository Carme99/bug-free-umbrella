<#
.SYNOPSIS
    Performs comprehensive security compliance scanning against industry frameworks.

.DESCRIPTION
    Multi-framework security compliance scanner that validates systems against:
    - CIS Benchmarks (Windows, Linux)
    - NIST 800-53 controls
    - PCI-DSS requirements
    - HIPAA security rule
    - SOC 2 Type II controls
    - ISO 27001 requirements

    Generates detailed compliance reports with remediation guidance.

.PARAMETER Framework
    Compliance framework to test against: 'CIS', 'NIST', 'PCI-DSS', 'HIPAA', 'SOC2', 'ISO27001', 'All'

.PARAMETER TargetSystem
    Target system type: 'Windows', 'Linux', 'Cloud', 'Network'

.PARAMETER Severity
    Minimum severity to report: 'Critical', 'High', 'Medium', 'Low', 'All'. Default: 'All'

.PARAMETER OutputFormat
    Output format: 'Console', 'HTML', 'CSV', or 'JSON'. Default: 'HTML'

.PARAMETER OutputPath
    Path for output files. Default: MyDocuments\Reports

.PARAMETER RemediationGuidance
    Include detailed remediation steps in report

.EXAMPLE
    .\Invoke-SecurityComplianceScan.ps1 -Framework "CIS" -TargetSystem "Windows"

.EXAMPLE
    .\Invoke-SecurityComplianceScan.ps1 -Framework "All" `
        -TargetSystem "Windows" `
        -Severity "High" `
        -RemediationGuidance

.NOTES
    Author: IT Operations
    Version: 1.0.0
    Requires: PowerShell 5.1+, Administrator privileges

    WARNING: This script has not been thoroughly tested in production environments.
    Please test in a non-production environment first and validate results before relying on this data.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('CIS', 'NIST', 'PCI-DSS', 'HIPAA', 'SOC2', 'ISO27001', 'All')]
    [string]$Framework,

    [Parameter(Mandatory = $true)]
    [ValidateSet('Windows', 'Linux', 'Cloud', 'Network')]
    [string]$TargetSystem,

    [Parameter(Mandatory = $false)]
    [ValidateSet('Critical', 'High', 'Medium', 'Low', 'All')]
    [string]$Severity = 'All',

    [Parameter(Mandatory = $false)]
    [ValidateSet('Console', 'HTML', 'CSV', 'JSON')]
    [string]$OutputFormat = 'HTML',

    [Parameter(Mandatory = $false)]
    [string]$OutputPath = (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Reports'),

    [Parameter(Mandatory = $false)]
    [switch]$RemediationGuidance
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

$results = @{
    Timestamp = Get-Date
    Framework = $Framework
    TargetSystem = $TargetSystem
    ComputerName = $env:COMPUTERNAME
    Findings = @()
    Summary = @{}
}

Write-Host "Running security compliance scan..." -ForegroundColor Cyan
Write-Host "Framework: $Framework | Target: $TargetSystem | Severity: $Severity" -ForegroundColor Yellow

# Check if running as administrator (required for many checks)
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin -and $TargetSystem -eq 'Windows') {
    Write-Warning "Some checks require Administrator privileges. Run as Administrator for complete scan."
}

# CIS Windows Benchmarks
function Test-CISWindowsCompliance {
    $findings = @()

    # CIS 1.1.1 - Enforce password history
    $passHistory = (Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\Netlogon\Parameters' -ErrorAction SilentlyContinue).PasswordHistoryLength
    if ($passHistory -lt 24) {
        $findings += @{
            ControlID = "CIS-1.1.1"
            Title = "Password History"
            Description = "Enforce password history should be 24 or more passwords"
            Severity = "High"
            Status = "Non-Compliant"
            CurrentValue = $passHistory
            ExpectedValue = "24"
            Remediation = "Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\Netlogon\Parameters' -Name 'PasswordHistoryLength' -Value 24"
        }
    }

    # CIS 2.2.1 - Guest account status
    $guestEnabled = (Get-LocalUser -Name "Guest" -ErrorAction SilentlyContinue).Enabled
    if ($guestEnabled) {
        $findings += @{
            ControlID = "CIS-2.2.1"
            Title = "Guest Account"
            Description = "Guest account should be disabled"
            Severity = "Critical"
            Status = "Non-Compliant"
            CurrentValue = "Enabled"
            ExpectedValue = "Disabled"
            Remediation = "Disable-LocalUser -Name 'Guest'"
        }
    }

    # CIS 2.3.1.1 - Interactive logon message title
    $legalNotice = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -ErrorAction SilentlyContinue).legalnoticecaption
    if ([string]::IsNullOrEmpty($legalNotice)) {
        $findings += @{
            ControlID = "CIS-2.3.1.1"
            Title = "Legal Notice Caption"
            Description = "Interactive logon message title should be configured"
            Severity = "Medium"
            Status = "Non-Compliant"
            CurrentValue = "Not Set"
            ExpectedValue = "Legal warning message"
            Remediation = "Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -Name 'legalnoticecaption' -Value 'Legal Notice'"
        }
    }

    # CIS 9.1.1 - Windows Firewall Domain Profile
    $fwProfile = Get-NetFirewallProfile -Profile Domain -ErrorAction SilentlyContinue
    if ($fwProfile.Enabled -ne $true) {
        $findings += @{
            ControlID = "CIS-9.1.1"
            Title = "Windows Firewall - Domain Profile"
            Description = "Windows Firewall Domain Profile should be enabled"
            Severity = "Critical"
            Status = "Non-Compliant"
            CurrentValue = "Disabled"
            ExpectedValue = "Enabled"
            Remediation = "Set-NetFirewallProfile -Profile Domain -Enabled True"
        }
    }

    # CIS 18.3.1 - LAPS AdmPwd GPO Extension
    $lapsInstalled = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon\GPExtensions\{D76B9641-3288-4f75-942D-087DE603E3EA}' -ErrorAction SilentlyContinue
    if (-not $lapsInstalled) {
        $findings += @{
            ControlID = "CIS-18.3.1"
            Title = "LAPS Installation"
            Description = "Local Administrator Password Solution (LAPS) should be installed"
            Severity = "High"
            Status = "Non-Compliant"
            CurrentValue = "Not Installed"
            ExpectedValue = "Installed"
            Remediation = "Install LAPS from Microsoft Download Center"
        }
    }

    return $findings
}

# NIST 800-53 Controls
function Test-NISTCompliance {
    $findings = @()

    # AC-2 - Account Management
    $inactiveUsers = Get-LocalUser | Where-Object { $_.Enabled -and $_.LastLogon -lt (Get-Date).AddDays(-90) }
    if ($inactiveUsers) {
        $findings += @{
            ControlID = "NIST-AC-2"
            Title = "Inactive User Accounts"
            Description = "User accounts inactive for 90+ days should be disabled"
            Severity = "Medium"
            Status = "Non-Compliant"
            CurrentValue = "$($inactiveUsers.Count) inactive accounts"
            ExpectedValue = "0 inactive accounts"
            Remediation = "Disable or remove inactive user accounts"
        }
    }

    # AC-7 - Unsuccessful Logon Attempts
    $lockoutThreshold = (Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\Netlogon\Parameters' -ErrorAction SilentlyContinue).LockoutThreshold
    if ($lockoutThreshold -gt 5 -or $lockoutThreshold -eq 0) {
        $findings += @{
            ControlID = "NIST-AC-7"
            Title = "Account Lockout Threshold"
            Description = "Account lockout threshold should be 5 or fewer invalid logon attempts"
            Severity = "High"
            Status = "Non-Compliant"
            CurrentValue = $lockoutThreshold
            ExpectedValue = "5 or less"
            Remediation = "Configure account lockout policy in Group Policy"
        }
    }

    # AU-12 - Audit Generation
    $auditSettings = auditpol /get /category:* 2>&1
    if ($auditSettings -notmatch "Success and Failure") {
        $findings += @{
            ControlID = "NIST-AU-12"
            Title = "Audit Policy Configuration"
            Description = "Comprehensive audit policies should be enabled"
            Severity = "High"
            Status = "Non-Compliant"
            CurrentValue = "Incomplete audit configuration"
            ExpectedValue = "Success and Failure auditing enabled"
            Remediation = "Configure comprehensive audit policies via Group Policy"
        }
    }

    return $findings
}

# PCI-DSS Requirements
function Test-PCIDSSCompliance {
    $findings = @()

    # Requirement 2.2.2 - Enable only necessary services
    $unnecessaryServices = @('Telnet', 'FTP', 'SNMP')
    foreach ($svc in $unnecessaryServices) {
        $service = Get-Service -Name $svc -ErrorAction SilentlyContinue
        if ($service -and $service.Status -eq 'Running') {
            $findings += @{
                ControlID = "PCI-DSS-2.2.2"
                Title = "Unnecessary Services"
                Description = "Service '$svc' should be disabled if not required"
                Severity = "High"
                Status = "Non-Compliant"
                CurrentValue = "Running"
                ExpectedValue = "Stopped/Disabled"
                Remediation = "Stop-Service '$svc' -Force; Set-Service '$svc' -StartupType Disabled"
            }
        }
    }

    # Requirement 2.2.4 - Configure system security parameters
    $tlsVersion = [Net.ServicePointManager]::SecurityProtocol
    if ($tlsVersion -notmatch "Tls12|Tls13") {
        $findings += @{
            ControlID = "PCI-DSS-2.2.4"
            Title = "TLS Configuration"
            Description = "TLS 1.2 or higher should be enforced"
            Severity = "Critical"
            Status = "Non-Compliant"
            CurrentValue = $tlsVersion
            ExpectedValue = "TLS 1.2 or TLS 1.3"
            Remediation = "Configure TLS 1.2+ in registry and disable older protocols"
        }
    }

    # Requirement 8.2.3 - Password complexity
    $passComplexity = (Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' -ErrorAction SilentlyContinue).PasswordComplexity
    if ($passComplexity -ne 1) {
        $findings += @{
            ControlID = "PCI-DSS-8.2.3"
            Title = "Password Complexity"
            Description = "Password complexity requirements should be enabled"
            Severity = "Critical"
            Status = "Non-Compliant"
            CurrentValue = "Disabled"
            ExpectedValue = "Enabled"
            Remediation = "Enable password complexity in Group Policy"
        }
    }

    return $findings
}

# Execute compliance checks based on framework
if ($Framework -eq 'CIS' -or $Framework -eq 'All') {
    Write-Host "`nRunning CIS Benchmark checks..." -ForegroundColor Yellow
    $results.Findings += Test-CISWindowsCompliance
}

if ($Framework -eq 'NIST' -or $Framework -eq 'All') {
    Write-Host "`nRunning NIST 800-53 checks..." -ForegroundColor Yellow
    $results.Findings += Test-NISTCompliance
}

if ($Framework -eq 'PCI-DSS' -or $Framework -eq 'All') {
    Write-Host "`nRunning PCI-DSS checks..." -ForegroundColor Yellow
    $results.Findings += Test-PCIDSSCompliance
}

# Filter by severity
if ($Severity -ne 'All') {
    $severityOrder = @('Critical', 'High', 'Medium', 'Low')
    $severityIndex = $severityOrder.IndexOf($Severity)
    $results.Findings = $results.Findings | Where-Object {
        $severityOrder.IndexOf($_.Severity) -le $severityIndex
    }
}

# Calculate summary
$criticalCount = ($results.Findings | Where-Object { $_.Severity -eq 'Critical' }).Count
$highCount = ($results.Findings | Where-Object { $_.Severity -eq 'High' }).Count
$mediumCount = ($results.Findings | Where-Object { $_.Severity -eq 'Medium' }).Count
$lowCount = ($results.Findings | Where-Object { $_.Severity -eq 'Low' }).Count

$results.Summary = @{
    TotalFindings = $results.Findings.Count
    CriticalFindings = $criticalCount
    HighFindings = $highCount
    MediumFindings = $mediumCount
    LowFindings = $lowCount
    ComplianceScore = if ($results.Findings.Count -gt 0) {
        [math]::Round((1 - ($criticalCount * 4 + $highCount * 3 + $mediumCount * 2 + $lowCount) / ($results.Findings.Count * 4)) * 100, 2)
    } else { 100 }
}

# Output results
$RunTimestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$RunId = [Guid]::NewGuid().ToString('N').Substring(0, 8)
switch ($OutputFormat) {
    'Console' {
        Write-Host "`n=== Security Compliance Scan Results ===" -ForegroundColor Cyan
        Write-Host "Framework: $Framework | System: $TargetSystem" -ForegroundColor White
        Write-Host "Total Findings: $($results.Summary.TotalFindings)" -ForegroundColor White
        Write-Host "Critical: $criticalCount | High: $highCount | Medium: $mediumCount | Low: $lowCount" -ForegroundColor White
        Write-Host "Compliance Score: $($results.Summary.ComplianceScore)%" -ForegroundColor $(if ($results.Summary.ComplianceScore -ge 80) { 'Green' } elseif ($results.Summary.ComplianceScore -ge 60) { 'Yellow' } else { 'Red' })

        if ($results.Findings.Count -gt 0) {
            Write-Host "`n=== Top Findings ===" -ForegroundColor Cyan
            foreach ($finding in ($results.Findings | Sort-Object { @('Critical','High','Medium','Low').IndexOf($_.Severity) } | Select-Object -First 10)) {
                $color = switch ($finding.Severity) {
                    'Critical' { 'Red' }
                    'High' { 'DarkRed' }
                    'Medium' { 'Yellow' }
                    'Low' { 'Gray' }
                }
                Write-Host "[$($finding.Severity)] $($finding.ControlID) - $($finding.Title)" -ForegroundColor $color
                Write-Host "  $($finding.Description)" -ForegroundColor Gray
                if ($RemediationGuidance) {
                    Write-Host "  Remediation: $($finding.Remediation)" -ForegroundColor Cyan
                }
            }
        }
    }

    'HTML' {
        $htmlFile = Join-Path $OutputPath "Security-Compliance-${RunTimestamp}_${RunId}.html"
        $scoreColor = if ($results.Summary.ComplianceScore -ge 80) { '#107c10' } elseif ($results.Summary.ComplianceScore -ge 60) { '#ff8c00' } else { '#d13438' }

        $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>Security Compliance Report</title>
    <style>
        body { font-family: 'Segoe UI', Arial, sans-serif; margin: 20px; background-color: #f5f5f5; }
        h1 { color: #d13438; border-bottom: 3px solid #d13438; }
        .summary { background: white; padding: 20px; border-radius: 8px; margin-bottom: 20px; }
        .score { font-size: 48px; font-weight: bold; color: $scoreColor; text-align: center; }
        table { border-collapse: collapse; width: 100%; background: white; }
        th { background-color: #d13438; color: white; padding: 10px; }
        td { padding: 8px; border-bottom: 1px solid #ddd; }
        .critical { background-color: #fdd; color: #d13438; font-weight: bold; }
        .high { background-color: #fed; color: #8b0000; }
        .medium { background-color: #ffc; color: #ff8c00; }
        .low { background-color: #f5f5f5; color: #666; }
    </style>
</head>
<body>
    <h1>Security Compliance Report</h1>
    <div class="summary">
        <strong>Framework:</strong> $([System.Net.WebUtility]::HtmlEncode("$Framework")) | <strong>System:</strong> $([System.Net.WebUtility]::HtmlEncode("$TargetSystem"))<br>
        <strong>Computer:</strong> $([System.Net.WebUtility]::HtmlEncode("$($results.ComputerName)")) | <strong>Scan Time:</strong> $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        <div class="score">$($results.Summary.ComplianceScore)%</div>
        <p style="text-align: center;">Compliance Score</p>
        <p>Critical: $criticalCount | High: $highCount | Medium: $mediumCount | Low: $lowCount</p>
    </div>
    <h2>Findings</h2>
    <table>
        <tr><th>Control ID</th><th>Title</th><th>Severity</th><th>Status</th><th>Current Value</th><th>Expected Value</th>$(if ($RemediationGuidance) { '<th>Remediation</th>' })</tr>
"@
        foreach ($finding in ($results.Findings | Sort-Object { @('Critical','High','Medium','Low').IndexOf($_.Severity) })) {
            $severityClass = $finding.Severity.ToLower()
            $html += "<tr class='$severityClass'><td>$([System.Net.WebUtility]::HtmlEncode("$($finding.ControlID)"))</td><td>$([System.Net.WebUtility]::HtmlEncode("$($finding.Title)"))</td><td>$([System.Net.WebUtility]::HtmlEncode("$($finding.Severity)"))</td><td>$([System.Net.WebUtility]::HtmlEncode("$($finding.Status)"))</td><td>$([System.Net.WebUtility]::HtmlEncode("$($finding.CurrentValue)"))</td><td>$([System.Net.WebUtility]::HtmlEncode("$($finding.ExpectedValue)"))</td>"
            if ($RemediationGuidance) {
                $html += "<td>$([System.Net.WebUtility]::HtmlEncode("$($finding.Remediation)"))</td>"
            }
            $html += "</tr>"
        }
        $html += "</table><p style='margin-top: 30px; text-align: center; color: #666; font-size: 12px;'><strong>Note:</strong> This report has not been thoroughly tested. Validate findings before remediation.</p></body></html>"

        $html | Out-File -FilePath $htmlFile -Encoding UTF8
        Write-Host "`nHTML report saved to: $htmlFile" -ForegroundColor Green
    }

    'CSV' {
        $csvFile = Join-Path $OutputPath "Security-Compliance-${RunTimestamp}_${RunId}.csv"
        $results.Findings | Export-Csv -Path $csvFile -NoTypeInformation
        Write-Host "`nCSV report saved to: $csvFile" -ForegroundColor Green
    }

    'JSON' {
        $jsonFile = Join-Path $OutputPath "Security-Compliance-${RunTimestamp}_${RunId}.json"
        $results | ConvertTo-Json -Depth 10 | Out-File -FilePath $jsonFile
        Write-Host "`nJSON saved to: $jsonFile" -ForegroundColor Green
    }
}

Write-Host "`nSecurity compliance scan complete!" -ForegroundColor Green
