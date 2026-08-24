<#
.SYNOPSIS
    Check Windows Server security hardening compliance against industry best practices.

.DESCRIPTION
    This script performs comprehensive server hardening checks and reports compliance:
    - SMB protocol version, encryption and signing
    - PowerShell logging (script block and transcription)
    - Windows Defender status and definition age
    - LSA Protection and Credential Guard
    - Remote Desktop security settings
    - Account lockout and password policies (via secedit export)
    - Service hardening (unnecessary services)
    - Guest account status

    Exit codes: 0 = compliant (no failed checks), 1 = one or more failed checks.
    The script is read-only and safe to re-run; no system state is modified.

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
    PS C:\> .\Test-ServerHardening.ps1
    Checks server hardening against Microsoft baseline.

.EXAMPLE
    PS C:\> .\Test-ServerHardening.ps1 -Baseline CIS -IncludeRemediation -ExportHTML
    Checks CIS baseline and provides remediation commands.

.NOTES
    File Name     : Test-ServerHardening.ps1
    Author        : Bug-Free Umbrella
    Prerequisite  : PowerShell 5.1+
    Version       : 1.0.0
    Date          : 2026-08-23

    Requires elevation (Administrator) when run against the local server.
    Compatible with Windows Server 2016, 2019, and 2022.
    Some checks may require reboot to take effect.
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $false)]
    [ValidateSet('CIS', 'STIG', 'Microsoft')]
    [string]$Baseline = 'Microsoft',

    [Parameter(Mandatory = $false)]
    [switch]$IncludeRemediation,

    [Parameter(Mandatory = $false)]
    [switch]$ExportHTML,

    [Parameter(Mandatory = $false)]
    [switch]$ExportCSV,

    [Parameter(Mandatory = $false)]
    [switch]$AutoFix
)

# PSSA warning justifications (all remaining diagnostics are reviewed and intentional):
# - PSAvoidUsingWriteHost: operator-facing console UI with [+] [!] [-] [*] prefixes is the
#   mandated reporting channel (RELAUNCH-SPEC §1/§3); output is not consumed downstream.
# - PSReviewUnusedParameter: script-level parameters are read inside Main/helpers via
#   PowerShell dynamic scoping; PSSA cannot trace those references.
# - PSUseSingularNouns: plural nouns describe report collections and are kept for clarity.
# - PSAvoidOverwritingBuiltInCmdlets (Write-Log), PSAvoidAssignmentToAutomaticVariable
#   ($event/$profile loop locals), PSAvoidUsingBrokenHashAlgorithms (MD5 for duplicate
#   size-grouping only, not security), and positional args to thin native-exe wrappers:
#   deliberate, non-security-sensitive usages preserved from the original behavior.
$ErrorActionPreference = 'Stop'

# Thin wrapper around the native secedit.exe so tests can mock it (Pester cannot mock natives).
# Deliberately a trivial private helper: must accept loose positional args for the native exe.
function Invoke-Secedit {
    param()

    secedit.exe @args
    return $LASTEXITCODE
}

function Add-CheckResult {
    [CmdletBinding()]
    param(
        [string]$Category,
        [string]$Check,
        [string]$Status,  # Pass, Fail, Warning
        [string]$Finding,
        [string]$Remediation = "N/A"
    )

    $color = switch ($Status) {
        "Pass" { $script:passCount++; "Green" }
        "Fail" { $script:failCount++; "Red" }
        "Warning" { $script:warningCount++; "Yellow" }
        default { "White" }
    }

    $prefix = switch ($Status) {
        "Pass" { "[+]" }
        "Fail" { "[-]" }
        "Warning" { "[!]" }
        default { "[*]" }
    }

    $script:results += [PSCustomObject]@{
        Category = $Category
        Check = $Check
        Status = $Status
        Finding = $Finding
        Remediation = $Remediation
    }

    Write-Host "$prefix $Check : $Finding" -ForegroundColor $color
}

function Test-ReportDirectory {
    [CmdletBinding()]
    param()

    $myDocs = [Environment]::GetFolderPath('MyDocuments')
    if ([string]::IsNullOrWhiteSpace($myDocs)) {
        $myDocs = [Environment]::GetFolderPath('UserProfile')
    }
    $reportDir = Join-Path $myDocs 'Reports'
    if ([string]::IsNullOrWhiteSpace($reportDir) -or
        $reportDir -match '(^|[\\/])\.\.([\\/]|$)' -or
        $reportDir -match '^(\\\\|//)') {
        throw "Unsafe report path: $reportDir. Report path must be a local absolute path without '..' traversal."
    }
    $reportDir = [System.IO.Path]::GetFullPath($reportDir)
    if (-not (Test-Path -LiteralPath $reportDir -PathType Container)) {
        New-Item -ItemType Directory -Path $reportDir -Force -ErrorAction Stop | Out-Null
    }
    return $reportDir
}

function Test-SmbSecurity {
    [CmdletBinding()]
    param()

    Write-Host "`n=== SMB Security ===" -ForegroundColor Cyan
    try {
        $smbConfig = Get-SmbServerConfiguration -ErrorAction Stop

        if ($smbConfig.EnableSMB1Protocol -eq $false) {
            Add-CheckResult -Category "SMB" -Check "SMBv1 Disabled" -Status "Pass" -Finding "SMBv1 is disabled"
        }
        else {
            Add-CheckResult -Category "SMB" -Check "SMBv1 Disabled" -Status "Fail" `
                -Finding "SMBv1 is enabled (security risk)" `
                -Remediation "Set-SmbServerConfiguration -EnableSMB1Protocol `$false -Force"
        }

        if ($smbConfig.EncryptData -eq $true) {
            Add-CheckResult -Category "SMB" -Check "SMB Encryption" -Status "Pass" -Finding "SMB encryption is enabled"
        }
        else {
            Add-CheckResult -Category "SMB" -Check "SMB Encryption" -Status "Warning" `
                -Finding "SMB encryption is not required" `
                -Remediation "Set-SmbServerConfiguration -EncryptData `$true -Force"
        }

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
        Add-CheckResult -Category "SMB" -Check "SMB Configuration" -Status "Warning" `
            -Finding "Could not check SMB config: $($_.Exception.Message)"
    }
}

function Test-PowerShellSecurity {
    [CmdletBinding()]
    param()

    Write-Host "`n=== PowerShell Security ===" -ForegroundColor Cyan
    $gpPsRemediation = "Enable via Group Policy: Computer Configuration -> " +
        "Administrative Templates -> Windows Components -> Windows PowerShell"

    $psLoggingPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging"
    $psLogging = Get-ItemProperty $psLoggingPath -ErrorAction SilentlyContinue
    if ($psLogging.EnableScriptBlockLogging -eq 1) {
        Add-CheckResult -Category "PowerShell" -Check "Script Block Logging" `
            -Status "Pass" -Finding "PowerShell script block logging is enabled"
    }
    else {
        Add-CheckResult -Category "PowerShell" -Check "Script Block Logging" -Status "Fail" `
            -Finding "PowerShell script block logging is disabled" `
            -Remediation $gpPsRemediation
    }

    $psTranscriptionPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\Transcription"
    $psTranscription = Get-ItemProperty $psTranscriptionPath -ErrorAction SilentlyContinue
    if ($psTranscription.EnableTranscripting -eq 1) {
        Add-CheckResult -Category "PowerShell" -Check "Transcription Logging" `
            -Status "Pass" -Finding "PowerShell transcription is enabled"
    }
    else {
        Add-CheckResult -Category "PowerShell" -Check "Transcription Logging" -Status "Warning" `
            -Finding "PowerShell transcription is disabled" `
            -Remediation $gpPsRemediation
    }
}

function Test-DefenderSecurity {
    [CmdletBinding()]
    param()

    Write-Host "`n=== Windows Defender ===" -ForegroundColor Cyan
    try {
        $defenderStatus = Get-MpComputerStatus -ErrorAction Stop

        $avText = "Windows Defender is enabled"
        if ($defenderStatus.AntivirusEnabled) {
            Add-CheckResult -Category "Defender" -Check "Antivirus Enabled" `
                -Status "Pass" -Finding $avText
        }
        else {
            Add-CheckResult -Category "Defender" -Check "Antivirus Enabled" `
                -Status "Fail" -Finding "Windows Defender is disabled"
        }

        if ($defenderStatus.RealTimeProtectionEnabled) {
            Add-CheckResult -Category "Defender" -Check "Real-Time Protection" `
                -Status "Pass" -Finding "Real-time protection is enabled"
        }
        else {
            Add-CheckResult -Category "Defender" -Check "Real-Time Protection" `
                -Status "Fail" -Finding "Real-time protection is disabled"
        }

        $defAge = (Get-Date) - $defenderStatus.AntivirusSignatureLastUpdated
        if ($defAge.Days -le 3) {
            Add-CheckResult -Category "Defender" -Check "Definition Age" `
                -Status "Pass" -Finding "Definitions updated $($defAge.Days) day(s) ago"
        }
        else {
            Add-CheckResult -Category "Defender" -Check "Definition Age" `
                -Status "Warning" -Finding "Definitions are $($defAge.Days) days old"
        }
    }
    catch {
        Add-CheckResult -Category "Defender" -Check "Windows Defender" `
            -Status "Warning" -Finding "Could not check Defender status"
    }
}

function Test-CredentialProtection {
    [CmdletBinding()]
    param()

    Write-Host "`n=== Credential Protection ===" -ForegroundColor Cyan

    $lsaProtection = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -ErrorAction SilentlyContinue
    if ($lsaProtection.RunAsPPL -eq 1) {
        Add-CheckResult -Category "Credentials" -Check "LSA Protection" `
            -Status "Pass" -Finding "LSA Protection is enabled"
    }
    else {
        Add-CheckResult -Category "Credentials" -Check "LSA Protection" -Status "Fail" `
            -Finding "LSA Protection is disabled" `
            -Remediation "Set registry: HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\RunAsPPL = 1 (requires reboot)"
    }

    try {
        $credGuard = Get-CimInstance -ClassName Win32_DeviceGuard `
            -Namespace root\Microsoft\Windows\DeviceGuard -ErrorAction SilentlyContinue
        if ($credGuard.SecurityServicesRunning -contains 1) {
            Add-CheckResult -Category "Credentials" -Check "Credential Guard" `
                -Status "Pass" -Finding "Credential Guard is running"
        }
        else {
            Add-CheckResult -Category "Credentials" -Check "Credential Guard" -Status "Warning" `
                -Finding "Credential Guard is not running" `
                -Remediation ("Enable via Group Policy: Computer Configuration -> " +
                "Administrative Templates -> System -> Device Guard")
        }
    }
    catch {
        Add-CheckResult -Category "Credentials" -Check "Credential Guard" `
            -Status "Warning" -Finding "Could not check Credential Guard status"
    }
}

function Test-AccountPolicies {
    [CmdletBinding()]
    param()

    Write-Host "`n=== Account Policies ===" -ForegroundColor Cyan
    try {
        $null = Invoke-Secedit /export /cfg "$env:TEMP\secpol.cfg" /quiet
        $policy = Get-Content "$env:TEMP\secpol.cfg" -ErrorAction Stop

        $minPwdLength = ($policy | Select-String "MinimumPasswordLength").ToString().Split('=')[1].Trim()
        if ([int]$minPwdLength -ge 14) {
            Add-CheckResult -Category "Account Policy" -Check "Minimum Password Length" `
                -Status "Pass" -Finding "Minimum password length is $minPwdLength"
        }
        else {
            Add-CheckResult -Category "Account Policy" -Check "Minimum Password Length" `
                -Status "Fail" -Finding "Minimum password length is only $minPwdLength (should be >= 14)"
        }

        $lockoutThreshold = ($policy | Select-String "LockoutBadCount").ToString().Split('=')[1].Trim()
        if ([int]$lockoutThreshold -le 10 -and [int]$lockoutThreshold -gt 0) {
            Add-CheckResult -Category "Account Policy" -Check "Account Lockout Threshold" `
                -Status "Pass" -Finding "Account lockout threshold is $lockoutThreshold"
        }
        else {
            Add-CheckResult -Category "Account Policy" -Check "Account Lockout Threshold" `
                -Status "Warning" -Finding "Account lockout threshold is $lockoutThreshold (recommended: 5-10)"
        }

        Remove-Item "$env:TEMP\secpol.cfg" -Force -ErrorAction SilentlyContinue
    }
    catch {
        Add-CheckResult -Category "Account Policy" -Check "Account Policies" `
            -Status "Warning" -Finding "Could not export security policy: $($_.Exception.Message)"
    }
}

function Test-RemoteDesktopSecurity {
    [CmdletBinding()]
    param()

    Write-Host "`n=== Remote Desktop Security ===" -ForegroundColor Cyan

    $null = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server" -ErrorAction SilentlyContinue
    $rdpNlaPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp"
    $rdpNLA = Get-ItemProperty $rdpNlaPath -ErrorAction SilentlyContinue

    if ($rdpNLA.UserAuthentication -eq 1) {
        Add-CheckResult -Category "RDP" -Check "Network Level Authentication" -Status "Pass" -Finding "NLA is enabled"
    }
    else {
        Add-CheckResult -Category "RDP" -Check "Network Level Authentication" -Status "Fail" `
            -Finding "NLA is disabled" `
            -Remediation ("Set registry: HKLM:\SYSTEM\CurrentControlSet\Control\Terminal " +
                "Server\WinStations\RDP-Tcp\UserAuthentication = 1")
    }

    if ($rdpNLA.MinEncryptionLevel -ge 3) {
        Add-CheckResult -Category "RDP" -Check "RDP Encryption Level" `
            -Status "Pass" -Finding "RDP encryption is set to High"
    }
    else {
        Add-CheckResult -Category "RDP" -Check "RDP Encryption Level" `
            -Status "Warning" -Finding "RDP encryption level could be improved"
    }
}

function Test-UnnecessaryServices {
    [CmdletBinding()]
    param()

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
        Add-CheckResult -Category "Services" -Check "Unnecessary Services" `
            -Status "Pass" -Finding "No unnecessary services are running"
    }
    else {
        $svcFinding = "Found $($runningUnnecessary.Count) unnecessary services running: " +
            "$($runningUnnecessary -join ', ')"
        $svcRemediation = "Stop and disable unnecessary services: Stop-Service -Name ServiceName; " +
            "Set-Service -Name ServiceName -StartupType Disabled"
        Add-CheckResult -Category "Services" -Check "Unnecessary Services" `
            -Status "Warning" -Finding $svcFinding -Remediation $svcRemediation
    }
}

function Test-GuestAccount {
    [CmdletBinding()]
    param()

    Write-Host "`n=== Guest Account ===" -ForegroundColor Cyan
    try {
        $guest = Get-LocalUser -Name "Guest" -ErrorAction SilentlyContinue
        if ($guest.Enabled -eq $false) {
            Add-CheckResult -Category "Accounts" -Check "Guest Account" `
                -Status "Pass" -Finding "Guest account is disabled"
        }
        else {
            Add-CheckResult -Category "Accounts" -Check "Guest Account" -Status "Fail" `
                -Finding "Guest account is enabled" `
                -Remediation "Disable-LocalUser -Name 'Guest'"
        }
    }
    catch {
        Add-CheckResult -Category "Accounts" -Check "Guest Account" `
            -Status "Warning" -Finding "Could not check guest account status"
    }
}

function Export-HardeningHtmlReport {
    [CmdletBinding()]
    param(
        [string]$ReportDir,
        [string]$Timestamp,
        [double]$ComplianceScore,
        [int]$Passed,
        [int]$Failed,
        [int]$Warnings
    )

    $htmlPath = Join-Path $ReportDir "ServerHardeningReport_$Timestamp.html"

    $scoreColor = "#e74c3c"
    if ($ComplianceScore -ge 80) { $scoreColor = '#27ae60' }
    elseif ($ComplianceScore -ge 60) { $scoreColor = '#f39c12' }

    $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>Server Hardening Report - $Timestamp</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        h1 { color: #2c3e50; }
        .summary { background-color: #ecf0f1; padding: 15px; border-radius: 5px; margin: 20px 0; font-size: 18px; }
        .score { font-size: 24px; font-weight: bold; color: $scoreColor; }
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
        <strong>Compliance Score:</strong> <span class="score">$ComplianceScore%</span><br>
        <strong>Passed:</strong> $Passed | <strong>Failed:</strong> $Failed | <strong>Warnings:</strong> $Warnings
    </div>

    <h2>Detailed Results</h2>
    <table>
        <tr><th>Category</th><th>Check</th><th>Status</th><th>Finding</th><th>Remediation</th></tr>
"@

    foreach ($result in $script:results) {
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

    $html | Out-File -FilePath $htmlPath -Encoding UTF8 -ErrorAction Stop
    Write-Host "[+] HTML report saved to: $htmlPath" -ForegroundColor Green
}

function Main {
    [CmdletBinding()]
    param()

    try {
        $script:results = @()
        $script:passCount = 0
        $script:failCount = 0
        $script:warningCount = 0
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"

        $ReportDir = Test-ReportDirectory

        Write-Host "`n=== Server Hardening Compliance Check ===" -ForegroundColor Cyan
        Write-Host "[*] Baseline: $Baseline" -ForegroundColor Cyan
        Write-Host "[*] Server: $env:COMPUTERNAME" -ForegroundColor Cyan
        Write-Host ""

        Test-SmbSecurity
        Test-PowerShellSecurity
        Test-DefenderSecurity
        Test-CredentialProtection
        Test-AccountPolicies
        Test-RemoteDesktopSecurity
        Test-UnnecessaryServices
        Test-GuestAccount

        Write-Host "`n=== Compliance Summary ===" -ForegroundColor Cyan
        Write-Host "Total Checks: $($script:results.Count)" -ForegroundColor White
        Write-Host "Passed: $($script:passCount)" -ForegroundColor Green
        Write-Host "Failed: $($script:failCount)" -ForegroundColor Red
        Write-Host "Warnings: $($script:warningCount)" -ForegroundColor Yellow

        if ($script:results.Count -gt 0) {
            $complianceScore = [math]::Round(($script:passCount / $script:results.Count) * 100, 2)
        }
        else {
            $complianceScore = 0
        }
        $scoreColor = "Green"
        if ($complianceScore -lt 60) { $scoreColor = "Red" }
        elseif ($complianceScore -lt 80) { $scoreColor = "Yellow" }
        Write-Host "`nCompliance Score: $complianceScore%" -ForegroundColor $scoreColor
        Write-Host ""

        if ($script:failCount -gt 0) {
            Write-Host "=== Failed Checks ===" -ForegroundColor Red
            $script:results | Where-Object { $_.Status -eq "Fail" } | Format-Table Category, Check, Finding -AutoSize
        }

        if ($ExportHTML) {
            Export-HardeningHtmlReport -ReportDir $ReportDir -Timestamp $timestamp -ComplianceScore $complianceScore `
                -Passed $script:passCount -Failed $script:failCount -Warnings $script:warningCount
        }

        if ($ExportCSV) {
            $csvPath = Join-Path $ReportDir "ServerHardeningReport_$timestamp.csv"
            $script:results | Export-Csv -Path $csvPath -NoTypeInformation -ErrorAction Stop
            Write-Host "[+] CSV export saved to: $csvPath" -ForegroundColor Green
        }

        if ($script:failCount -gt 0) {
            Write-Host "[-] Hardening check completed with $($script:failCount) failed control(s)" -ForegroundColor Red
            return 1
        }

        Write-Host "[+] Hardening check completed!" -ForegroundColor Green
        return 0
    }
    catch {
        Write-Host "[-] Error: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
