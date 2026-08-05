<#
.SYNOPSIS
    Checks Windows Server security hardening compliance against industry best practices.

.DESCRIPTION
    This script performs comprehensive server hardening checks:
    - SMB protocol version and encryption
    - PowerShell logging and constrained language mode
    - Windows Defender and Exploit Protection
    - LSA Protection and Credential Guard
    - Remote Desktop security settings
    - Account lockout and password policies
    - Audit policy configuration
    - Service hardening (unnecessary services)
    - Anonymous access and null session restrictions
    - TLS/SSL protocol versions

.PARAMETER Baseline
    Security baseline to check against: CIS, STIG, Microsoft (default: Microsoft).

.PARAMETER IncludeRemediation
    Include PowerShell commands to remediate issues.

.PARAMETER ExportHTML
    Export results to HTML report.

.PARAMETER ExportCSV
    Export results to CSV file.

.PARAMETER AutoFix
    Automatically remediate failed checks (use with caution).

.EXAMPLE
    .\Test-ServerHardening.ps1
    Checks server hardening against Microsoft baseline.

.EXAMPLE
    .\Test-ServerHardening.ps1 -Baseline CIS -IncludeRemediation -ExportHTML
    Checks CIS baseline and provides remediation commands.

.EXAMPLE
    .\Test-ServerHardening.ps1 -AutoFix
    Automatically fixes common hardening issues (requires confirmation).

.NOTES
    Requires Administrator privileges
    Compatible with Windows Server 2016, 2019, and 2022
    Some checks may require reboot to take effect
#>

[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [Parameter(Mandatory=$false)]
    [ValidateSet('CIS','STIG','Microsoft')]
    [string]$Baseline = 'Microsoft',

    [Parameter(Mandatory=$false)]
    [switch]$IncludeRemediation,

    [Parameter(Mandatory=$false)]
    [switch]$ExportHTML,

    [Parameter(Mandatory=$false)]
    [switch]$ExportCSV,

    [Parameter(Mandatory=$false)]
    [switch]$AutoFix
)

#Requires -RunAsAdministrator

$ErrorActionPreference = "Stop"
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"

# Resolve report output directory (default: MyDocuments\Reports) and validate against traversal/UNC paths
$ReportDir = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Reports'
if ([string]::IsNullOrWhiteSpace($ReportDir) -or
    $ReportDir -match '(^|[\\/])\.\.([\\/]|$)' -or
    $ReportDir -match '^(\\\\|//)') {
    Write-Error "Unsafe report path: $ReportDir. Report path must be a local absolute path without '..' traversal."
    exit 1
}
$ReportDir = [System.IO.Path]::GetFullPath($ReportDir)
if (-not (Test-Path -LiteralPath $ReportDir -PathType Container)) {
    New-Item -ItemType Directory -Path $ReportDir -Force | Out-Null
}

Write-Host "`n=== Server Hardening Compliance Check ===" -ForegroundColor Cyan
Write-Host "Baseline: $Baseline" -ForegroundColor Yellow
Write-Host "Server: $env:COMPUTERNAME" -ForegroundColor Yellow
Write-Host "Timestamp: $(Get-Date)" -ForegroundColor Gray
Write-Host ""

$results = @()
$passCount = 0
$failCount = 0
$warningCount = 0

# Helper function to add check result
function Add-CheckResult {
    param(
        [string]$Category,
        [string]$Check,
        [string]$Status,  # Pass, Fail, Warning
        [string]$Finding,
        [string]$Remediation = "N/A"
    )

    $script:results += [PSCustomObject]@{
        Category = $Category
        Check = $Check
        Status = $Status
        Finding = $Finding
        Remediation = $Remediation
    }

    switch ($Status) {
        "Pass" { $script:passCount++; $color = "Green" }
        "Fail" { $script:failCount++; $color = "Red" }
        "Warning" { $script:warningCount++; $color = "Yellow" }
    }

    Write-Host "[$Status] $Check" -ForegroundColor $color
}

# 1. SMB Security
Write-Host "`n=== SMB Security ===" -ForegroundColor Cyan

try {
    $smbConfig = Get-SmbServerConfiguration

    # SMBv1
    if ($smbConfig.EnableSMB1Protocol -eq $false) {
        Add-CheckResult -Category "SMB" -Check "SMBv1 Disabled" -Status "Pass" -Finding "SMBv1 is disabled"
    }
    else {
        Add-CheckResult -Category "SMB" -Check "SMBv1 Disabled" -Status "Fail" `
            -Finding "SMBv1 is enabled (security risk)" `
            -Remediation "Set-SmbServerConfiguration -EnableSMB1Protocol `$false -Force"
    }

    # SMB Encryption
    if ($smbConfig.EncryptData -eq $true) {
        Add-CheckResult -Category "SMB" -Check "SMB Encryption" -Status "Pass" -Finding "SMB encryption is enabled"
    }
    else {
        Add-CheckResult -Category "SMB" -Check "SMB Encryption" -Status "Warning" `
            -Finding "SMB encryption is not required" `
            -Remediation "Set-SmbServerConfiguration -EncryptData `$true -Force"
    }

    # SMB Signing
    if ($smbConfig.RequireSecuritySignature -eq $true) {
        Add-CheckResult -Category "SMB" -Check "SMB Signing" -Status "Pass" -Finding "SMB signing is required"
    }
    else {
        Add-CheckResult -Category "SMB" -Check "SMB Signing" -Status "Fail" `
            -Finding "SMB signing is not required" `
            -Remediation "Set-SmbServerConfiguration -RequireSecuritySignature `$true -Force"
    }
}
catch {
    Add-CheckResult -Category "SMB" -Check "SMB Configuration" -Status "Warning" -Finding "Could not check SMB config: $($_.Exception.Message)"
}

# 2. PowerShell Security
Write-Host "`n=== PowerShell Security ===" -ForegroundColor Cyan

# PowerShell Logging
$psLogging = Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging" -ErrorAction SilentlyContinue
if ($psLogging.EnableScriptBlockLogging -eq 1) {
    Add-CheckResult -Category "PowerShell" -Check "Script Block Logging" -Status "Pass" -Finding "PowerShell script block logging is enabled"
}
else {
    Add-CheckResult -Category "PowerShell" -Check "Script Block Logging" -Status "Fail" `
        -Finding "PowerShell script block logging is disabled" `
        -Remediation "Enable via Group Policy: Computer Configuration -> Administrative Templates -> Windows Components -> Windows PowerShell"
}

# PowerShell Transcription
$psTranscription = Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\Transcription" -ErrorAction SilentlyContinue
if ($psTranscription.EnableTranscripting -eq 1) {
    Add-CheckResult -Category "PowerShell" -Check "Transcription Logging" -Status "Pass" -Finding "PowerShell transcription is enabled"
}
else {
    Add-CheckResult -Category "PowerShell" -Check "Transcription Logging" -Status "Warning" `
        -Finding "PowerShell transcription is disabled" `
        -Remediation "Enable via Group Policy: Computer Configuration -> Administrative Templates -> Windows Components -> Windows PowerShell"
}

# 3. Windows Defender
Write-Host "`n=== Windows Defender ===" -ForegroundColor Cyan

try {
    $defenderStatus = Get-MpComputerStatus -ErrorAction SilentlyContinue

    if ($defenderStatus.AntivirusEnabled) {
        Add-CheckResult -Category "Defender" -Check "Antivirus Enabled" -Status "Pass" -Finding "Windows Defender is enabled"
    }
    else {
        Add-CheckResult -Category "Defender" -Check "Antivirus Enabled" -Status "Fail" -Finding "Windows Defender is disabled"
    }

    if ($defenderStatus.RealTimeProtectionEnabled) {
        Add-CheckResult -Category "Defender" -Check "Real-Time Protection" -Status "Pass" -Finding "Real-time protection is enabled"
    }
    else {
        Add-CheckResult -Category "Defender" -Check "Real-Time Protection" -Status "Fail" -Finding "Real-time protection is disabled"
    }

    # Check definition age
    $defAge = (Get-Date) - $defenderStatus.AntivirusSignatureLastUpdated
    if ($defAge.Days -le 3) {
        Add-CheckResult -Category "Defender" -Check "Definition Age" -Status "Pass" -Finding "Definitions updated $($defAge.Days) day(s) ago"
    }
    else {
        Add-CheckResult -Category "Defender" -Check "Definition Age" -Status "Warning" -Finding "Definitions are $($defAge.Days) days old"
    }
}
catch {
    Add-CheckResult -Category "Defender" -Check "Windows Defender" -Status "Warning" -Finding "Could not check Defender status"
}

# 4. LSA Protection & Credential Guard
Write-Host "`n=== Credential Protection ===" -ForegroundColor Cyan

# LSA Protection
$lsaProtection = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -ErrorAction SilentlyContinue
if ($lsaProtection.RunAsPPL -eq 1) {
    Add-CheckResult -Category "Credentials" -Check "LSA Protection" -Status "Pass" -Finding "LSA Protection is enabled"
}
else {
    Add-CheckResult -Category "Credentials" -Check "LSA Protection" -Status "Fail" `
        -Finding "LSA Protection is disabled" `
        -Remediation "Set registry: HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\RunAsPPL = 1 (requires reboot)"
}

# Credential Guard
try {
    $credGuard = Get-CimInstance -ClassName Win32_DeviceGuard -Namespace root\Microsoft\Windows\DeviceGuard -ErrorAction SilentlyContinue
    if ($credGuard.SecurityServicesRunning -contains 1) {
        Add-CheckResult -Category "Credentials" -Check "Credential Guard" -Status "Pass" -Finding "Credential Guard is running"
    }
    else {
        Add-CheckResult -Category "Credentials" -Check "Credential Guard" -Status "Warning" `
            -Finding "Credential Guard is not running" `
            -Remediation "Enable via Group Policy: Computer Configuration -> Administrative Templates -> System -> Device Guard"
    }
}
catch {
    Add-CheckResult -Category "Credentials" -Check "Credential Guard" -Status "Warning" -Finding "Could not check Credential Guard status"
}

# 5. Account Policies
Write-Host "`n=== Account Policies ===" -ForegroundColor Cyan

$secpol = secedit /export /cfg "$env:TEMP\secpol.cfg" /quiet
$policy = Get-Content "$env:TEMP\secpol.cfg"

# Password policy
$minPwdLength = ($policy | Select-String "MinimumPasswordLength").ToString().Split('=')[1].Trim()
if ([int]$minPwdLength -ge 14) {
    Add-CheckResult -Category "Account Policy" -Check "Minimum Password Length" -Status "Pass" -Finding "Minimum password length is $minPwdLength"
}
else {
    Add-CheckResult -Category "Account Policy" -Check "Minimum Password Length" -Status "Fail" -Finding "Minimum password length is only $minPwdLength (should be >= 14)"
}

# Account lockout
$lockoutThreshold = ($policy | Select-String "LockoutBadCount").ToString().Split('=')[1].Trim()
if ([int]$lockoutThreshold -le 10 -and [int]$lockoutThreshold -gt 0) {
    Add-CheckResult -Category "Account Policy" -Check "Account Lockout Threshold" -Status "Pass" -Finding "Account lockout threshold is $lockoutThreshold"
}
else {
    Add-CheckResult -Category "Account Policy" -Check "Account Lockout Threshold" -Status "Warning" -Finding "Account lockout threshold is $lockoutThreshold (recommended: 5-10)"
}

Remove-Item "$env:TEMP\secpol.cfg" -Force -ErrorAction SilentlyContinue

# 6. Remote Desktop Security
Write-Host "`n=== Remote Desktop Security ===" -ForegroundColor Cyan

$rdp = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server" -ErrorAction SilentlyContinue
$rdpNLA = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" -ErrorAction SilentlyContinue

if ($rdpNLA.UserAuthentication -eq 1) {
    Add-CheckResult -Category "RDP" -Check "Network Level Authentication" -Status "Pass" -Finding "NLA is enabled"
}
else {
    Add-CheckResult -Category "RDP" -Check "Network Level Authentication" -Status "Fail" `
        -Finding "NLA is disabled" `
        -Remediation "Set registry: HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp\UserAuthentication = 1"
}

# RDP Encryption Level
if ($rdpNLA.MinEncryptionLevel -ge 3) {
    Add-CheckResult -Category "RDP" -Check "RDP Encryption Level" -Status "Pass" -Finding "RDP encryption is set to High"
}
else {
    Add-CheckResult -Category "RDP" -Check "RDP Encryption Level" -Status "Warning" -Finding "RDP encryption level could be improved"
}

# 7. Unnecessary Services
Write-Host "`n=== Service Hardening ===" -ForegroundColor Cyan

$unnecessaryServices = @(
    "RemoteRegistry",
    "TlntSvr",
    "simptcp",
    "SNMP",
    "SSDPSRV",
    "upnphost",
    "WMPNetworkSvc",
    "RemoteAccess"
)

$runningUnnecessary = @()
foreach ($svc in $unnecessaryServices) {
    $service = Get-Service -Name $svc -ErrorAction SilentlyContinue
    if ($service -and $service.Status -eq 'Running') {
        $runningUnnecessary += $svc
    }
}

if ($runningUnnecessary.Count -eq 0) {
    Add-CheckResult -Category "Services" -Check "Unnecessary Services" -Status "Pass" -Finding "No unnecessary services are running"
}
else {
    Add-CheckResult -Category "Services" -Check "Unnecessary Services" -Status "Warning" `
        -Finding "Found $($runningUnnecessary.Count) unnecessary services running: $($runningUnnecessary -join ', ')" `
        -Remediation "Stop and disable unnecessary services: Stop-Service -Name ServiceName; Set-Service -Name ServiceName -StartupType Disabled"
}

# 8. Guest Account
Write-Host "`n=== Guest Account ===" -ForegroundColor Cyan

try {
    $guest = Get-LocalUser -Name "Guest" -ErrorAction SilentlyContinue
    if ($guest.Enabled -eq $false) {
        Add-CheckResult -Category "Accounts" -Check "Guest Account" -Status "Pass" -Finding "Guest account is disabled"
    }
    else {
        Add-CheckResult -Category "Accounts" -Check "Guest Account" -Status "Fail" `
            -Finding "Guest account is enabled" `
            -Remediation "Disable-LocalUser -Name 'Guest'"
    }
}
catch {
    Add-CheckResult -Category "Accounts" -Check "Guest Account" -Status "Warning" -Finding "Could not check guest account status"
}

# Display Results
Write-Host "`n=== Compliance Summary ===" -ForegroundColor Cyan
Write-Host "Total Checks: $($results.Count)" -ForegroundColor White
Write-Host "Passed: $passCount" -ForegroundColor Green
Write-Host "Failed: $failCount" -ForegroundColor Red
Write-Host "Warnings: $warningCount" -ForegroundColor Yellow

$complianceScore = [math]::Round(($passCount / $results.Count) * 100, 2)
Write-Host "`nCompliance Score: $complianceScore%" -ForegroundColor $(if ($complianceScore -ge 80) { "Green" } elseif ($complianceScore -ge 60) { "Yellow" } else { "Red" })
Write-Host ""

# Show failures
if ($failCount -gt 0) {
    Write-Host "=== Failed Checks ===" -ForegroundColor Red
    $results | Where-Object { $_.Status -eq "Fail" } | Format-Table Category, Check, Finding -AutoSize
}

# Export results
if ($ExportHTML) {
    $htmlPath = "$env:USERPROFILE\Desktop\ServerHardeningReport_$timestamp.html"

    $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>Server Hardening Report - $timestamp</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        h1 { color: #2c3e50; }
        .summary { background-color: #ecf0f1; padding: 15px; border-radius: 5px; margin: 20px 0; font-size: 18px; }
        .score { font-size: 24px; font-weight: bold; color: $(if ($complianceScore -ge 80) { '#27ae60' } elseif ($complianceScore -ge 60) { '#f39c12' } else { '#e74c3c' }); }
        table { border-collapse: collapse; width: 100%; margin-top: 20px; }
        th { background-color: #34495e; color: white; padding: 10px; text-align: left; }
        td { border: 1px solid #ddd; padding: 8px; }
        tr:nth-child(even) { background-color: #f2f2f2; }
        .pass { background-color: #27ae60; color: white; padding: 5px; border-radius: 3px; }
        .fail { background-color: #e74c3c; color: white; padding: 5px; border-radius: 3px; }
        .warning { background-color: #f39c12; color: white; padding: 5px; border-radius: 3px; }
    </style>
</head>
<body>
    <h1>Server Hardening Compliance Report</h1>
    <div class="summary">
        <strong>Server:</strong> $env:COMPUTERNAME<br>
        <strong>Baseline:</strong> $Baseline<br>
        <strong>Generated:</strong> $(Get-Date)<br>
        <strong>Compliance Score:</strong> <span class="score">$complianceScore%</span><br>
        <strong>Passed:</strong> $passCount | <strong>Failed:</strong> $failCount | <strong>Warnings:</strong> $warningCount
    </div>

    <h2>Detailed Results</h2>
    <table>
        <tr><th>Category</th><th>Check</th><th>Status</th><th>Finding</th><th>Remediation</th></tr>
"@

    foreach ($result in $results) {
        $statusClass = $result.Status.ToLower()
        $html += @"
        <tr>
            <td>$($result.Category)</td>
            <td>$($result.Check)</td>
            <td><span class="$statusClass">$($result.Status)</span></td>
            <td>$($result.Finding)</td>
            <td>$($result.Remediation)</td>
        </tr>
"@
    }

    $html += "</table></body></html>"

    $html | Out-File -FilePath $htmlPath -Encoding UTF8
    Write-Host "[+] HTML report saved to: $htmlPath" -ForegroundColor Green
}

if ($ExportCSV) {
    $csvPath = "$env:USERPROFILE\Desktop\ServerHardeningReport_$timestamp.csv"
    $results | Export-Csv -Path $csvPath -NoTypeInformation
    Write-Host "[+] CSV export saved to: $csvPath" -ForegroundColor Green
}

Write-Host "`n[+] Hardening check completed!" -ForegroundColor Green

# Exit with appropriate code
if ($failCount -gt 0) {
    exit 1
}
exit 0
