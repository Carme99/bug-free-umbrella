<#
.SYNOPSIS
    Scan a Windows system for compliance against CIS, NIST, and PCI-DSS frameworks.
.DESCRIPTION
    Multi-framework security compliance scanner that validates Windows systems against:
    - CIS Benchmarks (Windows)
    - NIST 800-53 controls
    - PCI-DSS requirements

    Generates detailed compliance reports with remediation guidance. All checks are read-only
    detectors; remediation text in findings is advice only and is never executed by this script.

    Exit codes: 0 = scan completed (regardless of findings); 1 = invalid input, unsafe output
    path, or a report write failure.
.PARAMETER Framework
    Compliance framework to test against: 'CIS', 'NIST', 'PCI-DSS', 'All'
.PARAMETER TargetSystem
    Target system type: 'Windows' (the implemented checks use Windows-only cmdlets)
.PARAMETER Severity
    Minimum severity to report: 'Critical', 'High', 'Medium', 'Low', 'All'. Default: 'All'
.PARAMETER OutputFormat
    Output format: 'Console', 'HTML', 'CSV', or 'JSON'. Default: 'HTML'
.PARAMETER OutputPath
    Path for output files. Default: MyDocuments\Reports
.PARAMETER RemediationGuidance
    Include detailed remediation steps in report
.EXAMPLE
    PS C:\> .\Invoke-SecurityComplianceScan.ps1 -Framework "CIS" -TargetSystem "Windows"

    Runs the CIS benchmark checks and writes an HTML report.
.EXAMPLE
    PS C:\> .\Invoke-SecurityComplianceScan.ps1 -Framework "All" `
        -TargetSystem "Windows" `
        -Severity "High" `
        -RemediationGuidance

    Runs every framework check, reporting High severity and above with remediation guidance.
.NOTES
    File Name   : Invoke-SecurityComplianceScan.ps1
    Author      : IT Operations
    Prerequisite: PowerShell 5.1+
    Version     : 1.0.0
    Date        : 2026-08-23

    WARNING: This script has not been thoroughly tested in production environments.
    Please test in a non-production environment first and validate results before relying on this data.
#>

# Write-Host is intentional: RELAUNCH-SPEC section 3 mandates prefixed colored console output.
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $false)]
    [ValidateSet('CIS', 'NIST', 'PCI-DSS', 'All')]
    [string]$Framework = 'All',

    [Parameter(Mandatory = $false)]
    [ValidateSet('Windows')]
    [string]$TargetSystem = 'Windows',

    [Parameter(Mandatory = $false)]
    [ValidateSet('Critical', 'High', 'Medium', 'Low', 'All')]
    [string]$Severity = 'All',

    [Parameter(Mandatory = $false)]
    [ValidateSet('Console', 'HTML', 'CSV', 'JSON')]
    [string]$OutputFormat = 'HTML',

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$OutputPath = (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Reports'),

    [Parameter(Mandatory = $false)]
    [switch]$RemediationGuidance
)

$ErrorActionPreference = 'Stop'

# Thin wrapper for the native secedit.exe tool (Pester mock seam).
function Invoke-SeceditExport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ConfigFile
    )

    $null = & secedit.exe /export /cfg $ConfigFile /quiet
    return $LASTEXITCODE
}

# Thin wrapper for the native auditpol.exe tool (Pester mock seam).
function Invoke-AuditPolicyQuery {
    [CmdletBinding()]
    param()

    $output = & auditpol.exe /get /category:* 2>&1
    return [pscustomobject]@{
        Output   = @($output)
        ExitCode = $LASTEXITCODE
    }
}

# Returns $true when the session is elevated; $false otherwise (including non-Windows platforms).
function Test-AdministratorElevation {
    [CmdletBinding()]
    param()

    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = [Security.Principal.WindowsPrincipal]$identity
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch {
        return $false
    }
}

# Helper function to read a value from the exported security policy (secedit INI)
function Get-SecurityPolicyValue {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$Section,
        [string]$Name
    )

    $tempFile = Join-Path ([System.IO.Path]::GetTempPath()) ("secpol_{0}.cfg" -f [Guid]::NewGuid().ToString('N'))

    try {
        $exitCode = Invoke-SeceditExport -ConfigFile $tempFile
        if ($exitCode -ne 0) {
            throw "secedit.exe exited with code $exitCode"
        }

        if (-not (Test-Path -LiteralPath $tempFile)) {
            throw "Failed to export security policy"
        }

        $content = Get-Content -LiteralPath $tempFile -ErrorAction Stop
        $currentSection = ""
        foreach ($line in $content) {
            if ($line -match '^\[(.+)\]$') {
                $currentSection = $matches[1]
            }
            elseif ($line -match '^(.+?)\s*=\s*(.*)$' -and $currentSection -eq $Section) {
                if ($matches[1].Trim() -eq $Name) {
                    return $matches[2].Trim()
                }
            }
        }
        return $null
    }
    catch {
        Write-Verbose "Failed to read security policy value '$Section\$Name': $($_.Exception.Message)"
        return $null
    }
    finally {
        # Cleanup temp file (honors -WhatIf)
        if (Test-Path -LiteralPath $tempFile) {
            if ($PSCmdlet.ShouldProcess($tempFile, "Remove temporary security policy export")) {
                Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

# CIS Windows Benchmarks
function Test-CISWindowsCompliance {
    $findings = @()

    # CIS 1.1.1 - Enforce password history
    $netlogonParams = 'HKLM:\SYSTEM\CurrentControlSet\Services\Netlogon\Parameters'
    $passHistory = (Get-ItemProperty -Path $netlogonParams -ErrorAction SilentlyContinue).PasswordHistoryLength
    if ($passHistory -lt 24) {
        $findings += @{
            ControlID = "CIS-1.1.1"
            Title = "Password History"
            Description = "Enforce password history should be 24 or more passwords"
            Severity = "High"
            Status = "Non-Compliant"
            CurrentValue = $passHistory
            ExpectedValue = "24"
            Remediation = "Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\Netlogon\Parameters' " +
                "-Name 'PasswordHistoryLength' -Value 24"
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
    $policiesSystemPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
    $legalNotice = (Get-ItemProperty -Path $policiesSystemPath -ErrorAction SilentlyContinue).legalnoticecaption
    if ([string]::IsNullOrEmpty($legalNotice)) {
        $findings += @{
            ControlID = "CIS-2.3.1.1"
            Title = "Legal Notice Caption"
            Description = "Interactive logon message title should be configured"
            Severity = "Medium"
            Status = "Non-Compliant"
            CurrentValue = "Not Set"
            ExpectedValue = "Legal warning message"
            Remediation = "Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' " +
                "-Name 'legalnoticecaption' -Value 'Legal Notice'"
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

    # CIS 18.3.1 - LAPS AdmPwd GPO Extension (legacy) / Windows LAPS
    $lapsGpePath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon\' +
        'GPExtensions\{D76B9641-3288-4f75-942D-087DE603E3EA}'
    $legacyLapsInstalled = Get-ItemProperty -Path $lapsGpePath -ErrorAction SilentlyContinue
    $lapsPolicyPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\LAPS'
    $windowsLapsConfigured = Get-ItemProperty -Path $lapsPolicyPath -ErrorAction SilentlyContinue
    if (-not $legacyLapsInstalled -and -not $windowsLapsConfigured) {
        $findings += @{
            ControlID = "CIS-18.3.1"
            Title = "LAPS Installation"
            Description = "Local Administrator Password Solution (LAPS) should be installed and configured"
            Severity = "High"
            Status = "Non-Compliant"
            CurrentValue = "Not Installed"
            ExpectedValue = "Installed"
            Remediation = "Deploy Windows LAPS (built into Windows 10 20H2+/Server 20H2+, enabled via the " +
                "ADMX-backed policy under HKLM:\SOFTWARE\Policies\Microsoft\Windows\LAPS) - " +
                "https://learn.microsoft.com/en-us/windows-server/identity/laps/laps-overview"
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
            CurrentValue = "$(@($inactiveUsers).Count) inactive accounts"
            ExpectedValue = "0 inactive accounts"
            Remediation = "Disable or remove inactive user accounts"
        }
    }

    # AC-7 - Unsuccessful Logon Attempts
    $lockoutBadCount = (Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\Netlogon\Parameters' `
        -ErrorAction SilentlyContinue).LockoutBadCount
    if ($lockoutBadCount -gt 5 -or $lockoutBadCount -eq 0) {
        $findings += @{
            ControlID = "NIST-AC-7"
            Title = "Account Lockout Threshold"
            Description = "Account lockout threshold should be 5 or fewer invalid logon attempts"
            Severity = "High"
            Status = "Non-Compliant"
            CurrentValue = $lockoutBadCount
            ExpectedValue = "5 or less"
            Remediation = "Configure account lockout policy in Group Policy"
        }
    }

    # AU-12 - Audit Generation
    $auditQuery = Invoke-AuditPolicyQuery
    if (($auditQuery.Output | Out-String) -notmatch "Success and Failure") {
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
    # TLS enforcement is determined by the Schannel registry policy, not the
    # process-local [Net.ServicePointManager]::SecurityProtocol default.
    $schannelBase = 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols'
    $tls12Client = Get-ItemProperty -Path "$schannelBase\TLS 1.2\Client" -ErrorAction SilentlyContinue
    $tls13Client = Get-ItemProperty -Path "$schannelBase\TLS 1.3\Client" -ErrorAction SilentlyContinue

    $tls12Enabled = ($tls12Client.Enabled -eq 1 -and $tls12Client.DisabledByDefault -eq 0)
    # TLS 1.3 is absent on older Windows; when the key is present it must also be enabled
    $tls13Compliant = $true
    if ($null -ne $tls13Client) {
        $tls13Compliant = ($tls13Client.Enabled -eq 1 -and $tls13Client.DisabledByDefault -eq 0)
    }

    if (-not ($tls12Enabled -and $tls13Compliant)) {
        $findings += @{
            ControlID = "PCI-DSS-2.2.4"
            Title = "TLS Configuration"
            Description = "TLS 1.2 or higher should be enforced at the operating system level (Schannel)"
            Severity = "Critical"
            Status = "Non-Compliant"
            CurrentValue = "TLS 1.2 enforced: $tls12Enabled; TLS 1.3 compliant: $tls13Compliant"
            ExpectedValue = "TLS 1.2 enabled (and TLS 1.3 where present) with Enabled = 1 and DisabledByDefault = 0"
            Remediation = "Set 'Enabled' = 1 and 'DisabledByDefault' = 0 under " +
                "'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Client' " +
                "(and 'TLS 1.3\Client' where supported), then disable older protocols"
        }
    }

    # Requirement 8.2.3 - Password complexity
    # 'PasswordComplexity' is not a documented value under HKLM\...\Control\Lsa;
    # read it from the exported security policy the same way Test-CISBenchmark.ps1 does.
    $passComplexity = Get-SecurityPolicyValue -Section 'System Access' -Name 'PasswordComplexity'
    if ($passComplexity -ne '1') {
        $findings += @{
            ControlID = "PCI-DSS-8.2.3"
            Title = "Password Complexity"
            Description = "Password complexity requirements should be enabled"
            Severity = "Critical"
            Status = "Non-Compliant"
            CurrentValue = "Disabled"
            ExpectedValue = "Enabled"
            Remediation = "Enable password complexity in Group Policy (Security Options > Accounts: Limit local " +
                "account use of blank passwords / Password Policy > Password must meet complexity requirements)"
        }
    }

    return $findings
}

function Main {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [ValidateSet('CIS', 'NIST', 'PCI-DSS', 'All')]
        [string]$Framework = 'All',

        [ValidateSet('Windows')]
        [string]$TargetSystem = 'Windows',

        [ValidateSet('Critical', 'High', 'Medium', 'Low', 'All')]
        [string]$Severity = 'All',

        [ValidateSet('Console', 'HTML', 'CSV', 'JSON')]
        [string]$OutputFormat = 'HTML',

        [string]$OutputPath = (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Reports'),

        [switch]$RemediationGuidance
    )

    try {
        # Validate inputs early: throw before doing work (parameters are non-mandatory so that
        # dot-sourcing stays safe; missing values still fail at runtime)
        if ([string]::IsNullOrWhiteSpace($Framework)) { throw "-Framework is required" }
        if ([string]::IsNullOrWhiteSpace($TargetSystem)) { throw "-TargetSystem is required" }

        # Validate OutputPath: reject '..' traversal and UNC remote paths before resolution
        if ([string]::IsNullOrWhiteSpace($OutputPath) -or
            $OutputPath -match '(^|[\\/])\.\.([\\/]|$)' -or
            $OutputPath -match '^(\\\\|//)') {
            throw "Unsafe OutputPath: $OutputPath. OutputPath must be a local absolute path without '..' traversal."
        }
        $resolvedOutputPath = [System.IO.Path]::GetFullPath($OutputPath)
        if (-not (Test-Path -LiteralPath $resolvedOutputPath -PathType Container)) {
            New-Item -ItemType Directory -Path $resolvedOutputPath -Force -ErrorAction Stop | Out-Null
        }

        $results = @{
            Timestamp = Get-Date
            Framework = $Framework
            TargetSystem = $TargetSystem
            ComputerName = $env:COMPUTERNAME
            Findings = @()
            Summary = @{}
        }

        Write-Host "[*] Running security compliance scan..." -ForegroundColor Cyan
        Write-Host "[*] Framework: $Framework | Target: $TargetSystem | Severity: $Severity" -ForegroundColor Yellow

        # Check if running as administrator (required for many checks)
        if (-not (Test-AdministratorElevation) -and $TargetSystem -eq 'Windows') {
            Write-Warning "Some checks require Administrator privileges. Run as Administrator for complete scan."
        }

        # Execute compliance checks based on framework
        if ($Framework -eq 'CIS' -or $Framework -eq 'All') {
            Write-Host "`n[*] Running CIS Benchmark checks..." -ForegroundColor Yellow
            $results.Findings += Test-CISWindowsCompliance
        }

        if ($Framework -eq 'NIST' -or $Framework -eq 'All') {
            Write-Host "`n[*] Running NIST 800-53 checks..." -ForegroundColor Yellow
            $results.Findings += Test-NISTCompliance
        }

        if ($Framework -eq 'PCI-DSS' -or $Framework -eq 'All') {
            Write-Host "`n[*] Running PCI-DSS checks..." -ForegroundColor Yellow
            $results.Findings += Test-PCIDSSCompliance
        }

        # Filter by severity
        if ($Severity -ne 'All') {
            $severityOrder = @('Critical', 'High', 'Medium', 'Low')
            $severityIndex = $severityOrder.IndexOf($Severity)
            $results.Findings = @($results.Findings | Where-Object {
                $severityOrder.IndexOf($_.Severity) -le $severityIndex
            })
        }
        else {
            $results.Findings = @($results.Findings)
        }

        # Calculate summary
        $criticalCount = ($results.Findings | Where-Object { $_.Severity -eq 'Critical' }).Count
        $highCount = ($results.Findings | Where-Object { $_.Severity -eq 'High' }).Count
        $mediumCount = ($results.Findings | Where-Object { $_.Severity -eq 'Medium' }).Count
        $lowCount = ($results.Findings | Where-Object { $_.Severity -eq 'Low' }).Count

        $complianceScore = 100
        if ($results.Findings.Count -gt 0) {
            $weighted = ($criticalCount * 4 + $highCount * 3 + $mediumCount * 2 + $lowCount)
            $complianceScore = [math]::Round((1 - $weighted / ($results.Findings.Count * 4)) * 100, 2)
        }

        $results.Summary = @{
            TotalFindings = $results.Findings.Count
            CriticalFindings = $criticalCount
            HighFindings = $highCount
            MediumFindings = $mediumCount
            LowFindings = $lowCount
            ComplianceScore = $complianceScore
        }

        # Output results
        $RunTimestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $RunId = [Guid]::NewGuid().ToString('N').Substring(0, 8)

        switch ($OutputFormat) {
            'Console' {
                Write-Host "`n[*] === Security Compliance Scan Results ===" -ForegroundColor Cyan
                Write-Host "[*] Framework: $Framework | System: $TargetSystem" -ForegroundColor White
                Write-Host "[*] Total Findings: $($results.Summary.TotalFindings)" -ForegroundColor White
                Write-Host "[*] Critical: $criticalCount | High: $highCount | Medium: $mediumCount | Low: $lowCount" `
                    -ForegroundColor White
                if ($complianceScore -ge 80) { $scoreColor = 'Green' }
                elseif ($complianceScore -ge 60) { $scoreColor = 'Yellow' }
                else { $scoreColor = 'Red' }
                Write-Host "[*] Compliance Score: $($results.Summary.ComplianceScore)%" -ForegroundColor $scoreColor

                if ($results.Findings.Count -gt 0) {
                    Write-Host "`n[*] === Top Findings ===" -ForegroundColor Cyan
                    $topFindings = $results.Findings |
                        Sort-Object { @('Critical', 'High', 'Medium', 'Low').IndexOf($_.Severity) } |
                        Select-Object -First 10
                    foreach ($finding in $topFindings) {
                        $color = switch ($finding.Severity) {
                            'Critical' { 'Red' }
                            'High' { 'DarkRed' }
                            'Medium' { 'Yellow' }
                            'Low' { 'Gray' }
                        }
                        Write-Host "[!] [$($finding.Severity)] $($finding.ControlID) - $($finding.Title)" `
                            -ForegroundColor $color
                        Write-Host "    $($finding.Description)" -ForegroundColor Gray
                        if ($RemediationGuidance) {
                            Write-Host "    Remediation: $($finding.Remediation)" -ForegroundColor Cyan
                        }
                    }
                }
            }

            'HTML' {
                $htmlFile = Join-Path $resolvedOutputPath "Security-Compliance-${RunTimestamp}_${RunId}.html"
                if ($PSCmdlet.ShouldProcess($htmlFile, "Write HTML compliance report")) {
                    if ($complianceScore -ge 80) { $scoreHexColor = '#107c10' }
                    elseif ($complianceScore -ge 60) { $scoreHexColor = '#ff8c00' }
                    else { $scoreHexColor = '#d13438' }
                    $remediationHeader = ''
                    if ($RemediationGuidance) {
                        $remediationHeader = '<th>Remediation</th>'
                    }

                    $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>Security Compliance Report</title>
    <style>
        body { font-family: 'Segoe UI', Arial, sans-serif; margin: 20px; background-color: #f5f5f5; }
        h1 { color: #d13438; border-bottom: 3px solid #d13438; }
        .summary { background: white; padding: 20px; border-radius: 8px; margin-bottom: 20px; }
        .score { font-size: 48px; font-weight: bold; color: $scoreHexColor; text-align: center; }
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
        <strong>Framework:</strong> $([System.Net.WebUtility]::HtmlEncode("$Framework")) |
        <strong>System:</strong> $([System.Net.WebUtility]::HtmlEncode("$TargetSystem"))<br>
        <strong>Computer:</strong> $([System.Net.WebUtility]::HtmlEncode("$($results.ComputerName)")) |
        <strong>Scan Time:</strong> $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        <div class="score">$($results.Summary.ComplianceScore)%</div>
        <p style="text-align: center;">Compliance Score</p>
        <p>Critical: $criticalCount | High: $highCount | Medium: $mediumCount | Low: $lowCount</p>
    </div>
    <h2>Findings</h2>
    <table>
        <tr><th>Control ID</th><th>Title</th><th>Severity</th><th>Status</th>
            <th>Current Value</th><th>Expected Value</th>$remediationHeader</tr>
"@

                    $allFindings = $results.Findings |
                        Sort-Object { @('Critical', 'High', 'Medium', 'Low').IndexOf($_.Severity) }
                    foreach ($finding in $allFindings) {
                        $severityClass = $finding.Severity.ToLower()
                        $html += "<tr class='$severityClass'>"
                        $html += "<td>$([System.Net.WebUtility]::HtmlEncode("$($finding.ControlID)"))</td>"
                        $html += "<td>$([System.Net.WebUtility]::HtmlEncode("$($finding.Title)"))</td>"
                        $html += "<td>$([System.Net.WebUtility]::HtmlEncode("$($finding.Severity)"))</td>"
                        $html += "<td>$([System.Net.WebUtility]::HtmlEncode("$($finding.Status)"))</td>"
                        $html += "<td>$([System.Net.WebUtility]::HtmlEncode("$($finding.CurrentValue)"))</td>"
                        $html += "<td>$([System.Net.WebUtility]::HtmlEncode("$($finding.ExpectedValue)"))</td>"
                        if ($RemediationGuidance) {
                            $html += "<td>$([System.Net.WebUtility]::HtmlEncode("$($finding.Remediation)"))</td>"
                        }
                        $html += "</tr>"
                    }
                    $html += "</table><p style='margin-top: 30px; text-align: center; color: #666; "
                    $html += "font-size: 12px;'><strong>Note:</strong> This report has not been thoroughly "
                    $html += "tested. Validate findings before remediation.</p></body></html>"

                    $html | Out-File -FilePath $htmlFile -Encoding UTF8 -ErrorAction Stop
                    Write-Host "`n[+] HTML report saved to: $htmlFile" -ForegroundColor Green
                }
            }

            'CSV' {
                $csvFile = Join-Path $resolvedOutputPath "Security-Compliance-${RunTimestamp}_${RunId}.csv"
                if ($PSCmdlet.ShouldProcess($csvFile, "Write CSV compliance report")) {
                    $results.Findings | Export-Csv -Path $csvFile -NoTypeInformation -ErrorAction Stop
                    Write-Host "`n[+] CSV report saved to: $csvFile" -ForegroundColor Green
                }
            }

            'JSON' {
                $jsonFile = Join-Path $resolvedOutputPath "Security-Compliance-${RunTimestamp}_${RunId}.json"
                if ($PSCmdlet.ShouldProcess($jsonFile, "Write JSON compliance report")) {
                    $results | ConvertTo-Json -Depth 10 | Out-File -FilePath $jsonFile -ErrorAction Stop
                    Write-Host "`n[+] JSON saved to: $jsonFile" -ForegroundColor Green
                }
            }
        }

        Write-Host "`n[+] Security compliance scan complete!" -ForegroundColor Green
        return 0
    }
    catch {
        Write-Host "[-] Error: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main @PSBoundParameters) }
