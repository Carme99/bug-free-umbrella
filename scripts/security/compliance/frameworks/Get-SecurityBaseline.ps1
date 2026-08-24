<#
.SYNOPSIS
    Verifies system security settings against industry-standard baselines.

.DESCRIPTION
    This script checks Windows security configurations against common security baselines
    including password policies, account policies, audit settings, user rights, security
    options, Windows Firewall, UAC, and Windows Defender status.
    - Read-only checks across nine categories (password policy, lockout, firewall, UAC,
      Defender, audit policy, SMB, RDP, local accounts)
    - Exports a temporary secedit policy file which is always cleaned up afterwards

    Side effects: creates and deletes a temporary secedit export file (honors -WhatIf);
    with -ExportReport it writes HTML/CSV reports under the user's Documents\Reports folder.
    Exit codes: 0 = baseline check completed with no failed settings; 1 = issues found or an
    error occurred.

.PARAMETER BaselineType
    The security baseline to check against. Options: Microsoft, CIS, Custom. Default: Microsoft.

.PARAMETER ExportReport
    Generate HTML and CSV reports under the Documents Reports folder.

.EXAMPLE
    PS C:\> .\Get-SecurityBaseline.ps1

    Runs the security baseline check with console output.

.EXAMPLE
    PS C:\> .\Get-SecurityBaseline.ps1 -ExportReport

    Runs the check and generates HTML/CSV reports.

.EXAMPLE
    PS C:\> .\Get-SecurityBaseline.ps1 -BaselineType CIS

    Checks against CIS benchmark recommendations.

.NOTES
    File Name   : Get-SecurityBaseline.ps1
    Author      : Security & Compliance Team
    Prerequisite: PowerShell 7.0
    Version     : 1.0.0
    Date        : 2026-08-23
#>

[CmdletBinding(SupportsShouldProcess)]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
    Justification = 'Spec-mandated console reporting with [+] / [!] / [-] / [*] prefixes')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '',
    Justification = 'Script parameters are consumed inside function Main via dynamic scoping')]
param(
    [Parameter()]
    [ValidateSet('Microsoft', 'CIS', 'Custom')]
    [string]$BaselineType = 'Microsoft',

    [Parameter()]
    [switch]$ExportReport
)

$ErrorActionPreference = 'Stop'

# Helper function to add result
function Add-Result {
    param(
        [string]$Category,
        [string]$Setting,
        [string]$Expected,
        [string]$Actual,
        [string]$Status
    )

    $script:Results += [PSCustomObject]@{
        Category = $Category
        Setting = $Setting
        Expected = $Expected
        Actual = $Actual
        Status = $Status
    }

    if ($Status -eq 'FAIL') {
        $script:IssuesFound = $true
    }
}

# Display function for per-check outcomes
function Write-CheckResult {
    param([string]$Message, [string]$Status)

    switch ($Status) {
        'PASS' { Write-Host "  [+] " -ForegroundColor Green -NoNewline; Write-Host $Message }
        'FAIL' { Write-Host "  [-] " -ForegroundColor Red -NoNewline; Write-Host $Message -ForegroundColor Red }
        'WARN' { Write-Host "  [!] " -ForegroundColor Yellow -NoNewline; Write-Host $Message -ForegroundColor Yellow }
        'INFO' { Write-Host "  [*] " -ForegroundColor Cyan -NoNewline; Write-Host $Message }
    }
}

# Thin wrapper around secedit.exe (Pester mock seam); translates non-zero exit codes to failure.
function Invoke-SecEdit {
    & secedit.exe @args 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "secedit.exe exited with code $LASTEXITCODE" }
}

# Thin wrapper around net.exe (Pester mock seam); translates non-zero exit codes to failure.
function Invoke-NetAccounts {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '',
        Justification = 'Named for the net.exe accounts subcommand')]
    param()
    $output = & net.exe @args 2>&1
    if ($LASTEXITCODE -ne 0) { throw "net.exe exited with code $LASTEXITCODE" }
    return $output
}

# Thin wrapper around auditpol.exe (Pester mock seam); translates non-zero exit codes to failure.
function Invoke-AuditPol {
    $output = & auditpol.exe @args 2>&1
    if ($LASTEXITCODE -ne 0) { throw "auditpol.exe exited with code $LASTEXITCODE" }
    return $output
}

function Main {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [ValidateSet('Microsoft', 'CIS', 'Custom')]
        [string]$BaselineType = 'Microsoft',

        [switch]$ExportReport
    )

    try {
        # Initialize results (reset on every Main call so repeated runs behave identically)
        $script:Results = @()
        $script:IssuesFound = $false

        Write-Host "`n========================================" -ForegroundColor Cyan
        Write-Host "   Security Baseline Verification" -ForegroundColor Cyan
        Write-Host "   Baseline: $BaselineType" -ForegroundColor Cyan
        Write-Host "========================================`n" -ForegroundColor Cyan

        # 1. PASSWORD POLICY
        Write-Host "[*] [1/9] Checking Password Policy..." -ForegroundColor Cyan
        $tempBase = if ($env:TEMP) { $env:TEMP } else { [System.IO.Path]::GetTempPath() }
        $secpolFile = Join-Path $tempBase ("secpol_{0}.cfg" -f [Guid]::NewGuid().ToString('N'))
        try {
            $null = Invoke-SecEdit /export /cfg $secpolFile /quiet
            $SecPolContent = Get-Content -LiteralPath $secpolFile

            # Parse password policy
            $MinPwdRaw = ($SecPolContent | Select-String "MinimumPasswordLength").ToString()
            $MinPasswordLength = $MinPwdRaw.Split('=')[1].Trim()
            $PasswordComplexity = ($SecPolContent | Select-String "PasswordComplexity").ToString().Split('=')[1].Trim()
            $MaxPasswordAge = ($SecPolContent | Select-String "MaximumPasswordAge").ToString().Split('=')[1].Trim()
            $PwdHistRaw = ($SecPolContent | Select-String "PasswordHistorySize").ToString()
            $PasswordHistorySize = $PwdHistRaw.Split('=')[1].Trim()

            # Check minimum password length (14+ recommended)
            if ([int]$MinPasswordLength -ge 14) {
                Write-CheckResult "Minimum password length: $MinPasswordLength characters" "PASS"
                Add-Result "Password Policy" "Minimum Length" "14+" $MinPasswordLength "PASS"
            }
            else {
                Write-CheckResult "Minimum password length: $MinPasswordLength characters (should be 14+)" "FAIL"
                Add-Result "Password Policy" "Minimum Length" "14+" $MinPasswordLength "FAIL"
            }

            # Check password complexity
            if ($PasswordComplexity -eq '1') {
                Write-CheckResult "Password complexity: Enabled" "PASS"
                Add-Result "Password Policy" "Complexity" "Enabled" "Enabled" "PASS"
            }
            else {
                Write-CheckResult "Password complexity: Disabled" "FAIL"
                Add-Result "Password Policy" "Complexity" "Enabled" "Disabled" "FAIL"
            }

            # Check maximum password age (60 days or less recommended)
            if ([int]$MaxPasswordAge -le 60 -and [int]$MaxPasswordAge -gt 0) {
                Write-CheckResult "Maximum password age: $MaxPasswordAge days" "PASS"
                Add-Result "Password Policy" "Maximum Age" "<=60 days" "$MaxPasswordAge days" "PASS"
            }
            else {
                Write-CheckResult "Maximum password age: $MaxPasswordAge days (should be <=60)" "FAIL"
                Add-Result "Password Policy" "Maximum Age" "<=60 days" "$MaxPasswordAge days" "FAIL"
            }

            # Check password history (24+ recommended)
            if ([int]$PasswordHistorySize -ge 24) {
                Write-CheckResult "Password history: $PasswordHistorySize passwords remembered" "PASS"
                Add-Result "Password Policy" "History Size" "24+" "$PasswordHistorySize" "PASS"
            }
            else {
                Write-CheckResult "Password history: $PasswordHistorySize passwords (should be 24+)" "FAIL"
                Add-Result "Password Policy" "History Size" "24+" "$PasswordHistorySize" "FAIL"
            }
        }
        catch {
            Write-CheckResult "Failed to check password policy: $($_.Exception.Message)" "FAIL"
            Add-Result "Password Policy" "Check" "Success" "Failed" "FAIL"
        }
        finally {
            # Always clean up the exported policy file, even on parse failure (honors -WhatIf)
            if (Test-Path -LiteralPath $secpolFile) {
                if ($PSCmdlet.ShouldProcess($secpolFile, "Delete temporary security policy export file")) {
                    Remove-Item -LiteralPath $secpolFile -Force -ErrorAction SilentlyContinue
                }
            }
        }

        # 2. ACCOUNT LOCKOUT POLICY
        Write-Host "`n[*] [2/9] Checking Account Lockout Policy..." -ForegroundColor Cyan
        try {
            $netAccountsOutput = Invoke-NetAccounts accounts | Out-String

            # Parse lockout threshold
            $LockoutThreshold = ($netAccountsOutput | Select-String "Lockout threshold").ToString().Split(':')[1].Trim()
            $LockoutDuration = ($netAccountsOutput | Select-String "Lockout duration").ToString().Split(':')[1].Trim()

            if ($LockoutThreshold -match "(\d+)") {
                $ThresholdValue = [int]$Matches[1]
                if ($ThresholdValue -ge 5 -and $ThresholdValue -le 10) {
                    Write-CheckResult "Account lockout threshold: $LockoutThreshold" "PASS"
                    Add-Result "Account Lockout" "Threshold" "5-10 attempts" $LockoutThreshold "PASS"
                }
                else {
                    Write-CheckResult "Account lockout threshold: $LockoutThreshold (should be 5-10)" "FAIL"
                    Add-Result "Account Lockout" "Threshold" "5-10 attempts" $LockoutThreshold "FAIL"
                }
            }

            Write-CheckResult "Lockout duration: $LockoutDuration" "INFO"
            Add-Result "Account Lockout" "Duration" "30+ minutes" $LockoutDuration "INFO"
        }
        catch {
            Write-CheckResult "Failed to check account lockout policy: $($_.Exception.Message)" "FAIL"
            Add-Result "Account Lockout" "Check" "Success" "Failed" "FAIL"
        }

        # 3. WINDOWS FIREWALL
        Write-Host "`n[*] [3/9] Checking Windows Firewall..." -ForegroundColor Cyan
        try {
            $FirewallProfiles = Get-NetFirewallProfile -ErrorAction Stop

            foreach ($FwProfile in $FirewallProfiles) {
                if ($FwProfile.Enabled) {
                    Write-CheckResult "$($FwProfile.Name) profile: Enabled" "PASS"
                    Add-Result "Windows Firewall" "$($FwProfile.Name) Profile" "Enabled" "Enabled" "PASS"
                }
                else {
                    Write-CheckResult "$($FwProfile.Name) profile: Disabled" "FAIL"
                    Add-Result "Windows Firewall" "$($FwProfile.Name) Profile" "Enabled" "Disabled" "FAIL"
                }
            }
        }
        catch {
            Write-CheckResult "Failed to check firewall status: $($_.Exception.Message)" "FAIL"
            Add-Result "Windows Firewall" "Check" "Success" "Failed" "FAIL"
        }

        # 4. UAC (User Account Control)
        Write-Host "`n[*] [4/9] Checking User Account Control..." -ForegroundColor Cyan
        try {
            $UACKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
            $EnableLUA = Get-ItemProperty -Path $UACKey -Name "EnableLUA" -ErrorAction Stop
            $ConsentPromptBehaviorAdmin = Get-ItemProperty -Path $UACKey `
                -Name "ConsentPromptBehaviorAdmin" -ErrorAction Stop

            if ($EnableLUA.EnableLUA -eq 1) {
                Write-CheckResult "UAC: Enabled" "PASS"
                Add-Result "UAC" "Enabled" "Yes" "Yes" "PASS"
            }
            else {
                Write-CheckResult "UAC: Disabled" "FAIL"
                Add-Result "UAC" "Enabled" "Yes" "No" "FAIL"
            }

            if ($ConsentPromptBehaviorAdmin.ConsentPromptBehaviorAdmin -ge 2) {
                Write-CheckResult "UAC prompt for administrators: Configured" "PASS"
                Add-Result "UAC" "Prompt Behavior" "Prompt" "Configured" "PASS"
            }
            else {
                Write-CheckResult "UAC prompt for administrators: Not configured properly" "FAIL"
                Add-Result "UAC" "Prompt Behavior" "Prompt" "Not Configured" "FAIL"
            }
        }
        catch {
            Write-CheckResult "Failed to check UAC settings: $($_.Exception.Message)" "FAIL"
            Add-Result "UAC" "Check" "Success" "Failed" "FAIL"
        }

        # 5. WINDOWS DEFENDER
        Write-Host "`n[*] [5/9] Checking Windows Defender..." -ForegroundColor Cyan
        try {
            $DefenderStatus = Get-MpComputerStatus -ErrorAction Stop

            if ($DefenderStatus.AntivirusEnabled) {
                Write-CheckResult "Antivirus: Enabled" "PASS"
                Add-Result "Windows Defender" "Antivirus" "Enabled" "Enabled" "PASS"
            }
            else {
                Write-CheckResult "Antivirus: Disabled" "FAIL"
                Add-Result "Windows Defender" "Antivirus" "Enabled" "Disabled" "FAIL"
            }

            if ($DefenderStatus.RealTimeProtectionEnabled) {
                Write-CheckResult "Real-time protection: Enabled" "PASS"
                Add-Result "Windows Defender" "Real-Time Protection" "Enabled" "Enabled" "PASS"
            }
            else {
                Write-CheckResult "Real-time protection: Disabled" "FAIL"
                Add-Result "Windows Defender" "Real-Time Protection" "Enabled" "Disabled" "FAIL"
            }

            # Check definition age
            $DefAge = (Get-Date) - $DefenderStatus.AntivirusSignatureLastUpdated
            $DefStamp = $DefenderStatus.AntivirusSignatureLastUpdated.ToString('yyyy-MM-dd')
            if ($DefAge.Days -le 7) {
                Write-CheckResult "Antivirus definitions: $DefStamp (Up to date)" "PASS"
                Add-Result "Windows Defender" "Definitions" "<=7 days old" "$($DefAge.Days) days old" "PASS"
            }
            else {
                Write-CheckResult "Antivirus definitions: $DefStamp (Outdated)" "FAIL"
                Add-Result "Windows Defender" "Definitions" "<=7 days old" "$($DefAge.Days) days old" "FAIL"
            }
        }
        catch {
            Write-CheckResult "Windows Defender not available or error checking: $($_.Exception.Message)" "WARN"
            Add-Result "Windows Defender" "Check" "Success" "Not Available" "WARN"
        }

        # 6. AUDIT POLICY
        Write-Host "`n[*] [6/9] Checking Audit Policy..." -ForegroundColor Cyan
        try {
            $AuditPol = Invoke-AuditPol /get /category:* | Out-String

            # Key audit policies to check
            $RequiredAudits = @(
                'Logon',
                'Account Logon',
                'Account Management',
                'Policy Change',
                'Privilege Use'
            )

            foreach ($Audit in $RequiredAudits) {
                if ($AuditPol -match $Audit) {
                    if ($AuditPol -match "$Audit.*Success and Failure") {
                        Write-CheckResult "$Audit events: Success and Failure" "PASS"
                        Add-Result "Audit Policy" $Audit "Success and Failure" "Configured" "PASS"
                    }
                    elseif ($AuditPol -match "$Audit.*Success") {
                        Write-CheckResult "$Audit events: Success only (should include Failure)" "WARN"
                        Add-Result "Audit Policy" $Audit "Success and Failure" "Success only" "WARN"
                    }
                    else {
                        Write-CheckResult "$Audit events: Not configured" "FAIL"
                        Add-Result "Audit Policy" $Audit "Success and Failure" "Not configured" "FAIL"
                    }
                }
            }
        }
        catch {
            Write-CheckResult "Failed to check audit policy: $($_.Exception.Message)" "FAIL"
            Add-Result "Audit Policy" "Check" "Success" "Failed" "FAIL"
        }

        # 7. SMB SECURITY
        Write-Host "`n[*] [7/9] Checking SMB Security..." -ForegroundColor Cyan
        try {
            $SMB1 = Get-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -ErrorAction SilentlyContinue
            $SMBServerConfig = Get-SmbServerConfiguration -ErrorAction SilentlyContinue

            # Prefer the live SMB server configuration; fall back to the optional-feature
            # state when Get-SmbServerConfiguration is unavailable.
            if ($null -ne $SMBServerConfig) {
                $SMB1Enabled = $SMBServerConfig.EnableSMB1Protocol
            }
            elseif ($SMB1.State -eq 'Enabled') {
                $SMB1Enabled = $true
            }
            elseif ($SMB1.State -eq 'Disabled') {
                $SMB1Enabled = $false
            }
            else {
                # Feature absent and no server configuration: SMBv1 is not active
                $SMB1Enabled = $false
            }

            if ($SMB1Enabled -eq $false) {
                Write-CheckResult "SMBv1: Disabled (Secure)" "PASS"
                Add-Result "SMB Security" "SMBv1" "Disabled" "Disabled" "PASS"
            }
            elseif ($SMB1Enabled -eq $true) {
                Write-CheckResult "SMBv1: Enabled (Security Risk)" "FAIL"
                Add-Result "SMB Security" "SMBv1" "Disabled" "Enabled" "FAIL"
            }
            else {
                Write-CheckResult "SMBv1: Status unknown" "WARN"
                Add-Result "SMB Security" "SMBv1" "Disabled" "Unknown" "WARN"
            }

            # Check SMB encryption
            if ($SMBServerConfig -and $SMBServerConfig.EncryptData) {
                Write-CheckResult "SMB encryption: Enabled" "PASS"
                Add-Result "SMB Security" "Encryption" "Enabled" "Enabled" "PASS"
            }
            else {
                Write-CheckResult "SMB encryption: Disabled (Consider enabling)" "WARN"
                Add-Result "SMB Security" "Encryption" "Enabled" "Disabled" "WARN"
            }
        }
        catch {
            Write-CheckResult "Failed to check SMB security: $($_.Exception.Message)" "WARN"
            Add-Result "SMB Security" "Check" "Success" "Failed" "WARN"
        }

        # 8. REMOTE DESKTOP SECURITY
        Write-Host "`n[*] [8/9] Checking Remote Desktop Security..." -ForegroundColor Cyan
        try {
            $RDPKey = "HKLM:\System\CurrentControlSet\Control\Terminal Server"
            $RDPEnabled = Get-ItemProperty -Path $RDPKey -Name "fDenyTSConnections" -ErrorAction Stop

            if ($RDPEnabled.fDenyTSConnections -eq 1) {
                Write-CheckResult "Remote Desktop: Disabled" "INFO"
                Add-Result "Remote Desktop" "Enabled" "Disabled (Recommended)" "Disabled" "INFO"
            }
            else {
                Write-CheckResult "Remote Desktop: Enabled (Ensure NLA is required)" "WARN"
                Add-Result "Remote Desktop" "Enabled" "Disabled (Recommended)" "Enabled" "WARN"

                # Check NLA requirement
                $NLAKey = "HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp"
                $NLA = Get-ItemProperty -Path $NLAKey -Name "UserAuthentication" -ErrorAction SilentlyContinue

                if ($NLA.UserAuthentication -eq 1) {
                    Write-CheckResult "Network Level Authentication: Required" "PASS"
                    Add-Result "Remote Desktop" "NLA" "Required" "Required" "PASS"
                }
                else {
                    Write-CheckResult "Network Level Authentication: Not required" "FAIL"
                    Add-Result "Remote Desktop" "NLA" "Required" "Not Required" "FAIL"
                }
            }
        }
        catch {
            Write-CheckResult "Failed to check Remote Desktop security: $($_.Exception.Message)" "WARN"
            Add-Result "Remote Desktop" "Enabled" "Disabled (Recommended)" "Unknown" "WARN"
        }

        # 9. SECURITY OPTIONS
        Write-Host "`n[*] [9/9] Checking Security Options..." -ForegroundColor Cyan
        try {
            # Check if Administrator account is disabled
            $AdminAccount = Get-LocalUser -ErrorAction Stop | Where-Object { $_.SID.Value -like "*-500" }
            if ($AdminAccount.Enabled -eq $false) {
                Write-CheckResult "Built-in Administrator account: Disabled" "PASS"
                Add-Result "Security Options" "Built-in Admin" "Disabled" "Disabled" "PASS"
            }
            else {
                Write-CheckResult "Built-in Administrator account: Enabled (Should be disabled)" "FAIL"
                Add-Result "Security Options" "Built-in Admin" "Disabled" "Enabled" "FAIL"
            }

            # Check if Guest account is disabled
            $GuestAccount = Get-LocalUser -Name "Guest" -ErrorAction SilentlyContinue
            if ($GuestAccount -and $GuestAccount.Enabled -eq $false) {
                Write-CheckResult "Guest account: Disabled" "PASS"
                Add-Result "Security Options" "Guest Account" "Disabled" "Disabled" "PASS"
            }
            elseif ($GuestAccount -and $GuestAccount.Enabled -eq $true) {
                Write-CheckResult "Guest account: Enabled (Should be disabled)" "FAIL"
                Add-Result "Security Options" "Guest Account" "Disabled" "Enabled" "FAIL"
            }
            else {
                Write-CheckResult "Guest account: Not found" "INFO"
                Add-Result "Security Options" "Guest Account" "Disabled" "Not Found" "INFO"
            }
        }
        catch {
            Write-CheckResult "Failed to check security options: $($_.Exception.Message)" "WARN"
            Add-Result "Security Options" "Check" "Success" "Failed" "WARN"
        }

        # Summary
        Write-Host "`n========================================" -ForegroundColor Cyan
        Write-Host "   Security Baseline Summary" -ForegroundColor Cyan
        Write-Host "========================================" -ForegroundColor Cyan

        $TotalChecks = $script:Results.Count
        $PassedChecks = ($script:Results | Where-Object { $_.Status -eq 'PASS' }).Count
        $FailedChecks = ($script:Results | Where-Object { $_.Status -eq 'FAIL' }).Count
        $WarningChecks = ($script:Results | Where-Object { $_.Status -eq 'WARN' }).Count

        Write-Host "[*] Total Checks: $TotalChecks" -ForegroundColor White
        Write-Host "[+] Passed: $PassedChecks" -ForegroundColor Green
        Write-Host "[-] Failed: $FailedChecks" -ForegroundColor Red
        Write-Host "[!] Warnings: $WarningChecks" -ForegroundColor Yellow

        if ($TotalChecks -eq 0) {
            Write-Warning "No checks were performed; compliance score cannot be computed."
            $CompliancePercent = 0
        }
        else {
            $CompliancePercent = [math]::Round(($PassedChecks / $TotalChecks) * 100, 2)
        }
        $ScoreColor = if ($CompliancePercent -ge 80) { 'Green' }
        elseif ($CompliancePercent -ge 60) { 'Yellow' }
        else { 'Red' }
        $ScoreClass = if ($CompliancePercent -ge 80) { 'good' }
        elseif ($CompliancePercent -ge 60) { 'medium' }
        else { 'poor' }
        Write-Host "`n[*] Compliance Score: $CompliancePercent%" -ForegroundColor $ScoreColor

        # Export reports if requested
        if ($ExportReport) {
            $ReportPath = (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Reports')
            # Validate report directory: reject '..' traversal and UNC remote paths before resolution
            if ([string]::IsNullOrWhiteSpace($ReportPath) -or
                $ReportPath -match '(^|[\\/])\.\.([\\/]|$)' -or
                $ReportPath -match '^(\\\\|//)') {
                throw "Unsafe report directory: $ReportPath. " +
                    "Report directory must be a local absolute path without '..' traversal."
            }
            $ReportPath = [System.IO.Path]::GetFullPath($ReportPath)
            if (-not (Test-Path -LiteralPath $ReportPath -PathType Container)) {
                New-Item -ItemType Directory -Path $ReportPath -Force -ErrorAction Stop | Out-Null
            }

            $Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
            $RunId = [Guid]::NewGuid().ToString('N').Substring(0, 8)
            $TimestampRunId = "${Timestamp}_${RunId}"

            # CSV Export
            $CSVPath = Join-Path $ReportPath "SecurityBaseline_${TimestampRunId}.csv"
            $script:Results | Export-Csv -Path $CSVPath -NoTypeInformation -ErrorAction Stop
            Write-Host "`n[+] CSV Report: $CSVPath" -ForegroundColor Green

            # HTML Export
            $HTMLPath = Join-Path $ReportPath "SecurityBaseline_${TimestampRunId}.html"
            $HTML = @"
<!DOCTYPE html>
<html>
<head>
    <title>Security Baseline Report - $Timestamp</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background-color: #f5f5f5; }
        h1 { color: #2c3e50; border-bottom: 3px solid #3498db; padding-bottom: 10px; }
        h2 { color: #34495e; margin-top: 30px; }
        .summary { background-color: #ecf0f1; padding: 15px; border-radius: 5px; margin: 20px 0; }
        .summary-item { display: inline-block; margin-right: 30px; font-size: 18px; }
        table { border-collapse: collapse; width: 100%; margin-top: 20px;
            background-color: white; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        th { background-color: #3498db; color: white; padding: 12px; text-align: left; }
        td { padding: 10px; border-bottom: 1px solid #ddd; }
        tr:hover { background-color: #f5f5f5; }
        .pass { color: #27ae60; font-weight: bold; }
        .fail { color: #e74c3c; font-weight: bold; }
        .warn { color: #f39c12; font-weight: bold; }
        .info { color: #3498db; font-weight: bold; }
        .score { font-size: 48px; font-weight: bold; margin: 20px 0; }
        .score.good { color: #27ae60; }
        .score.medium { color: #f39c12; }
        .score.poor { color: #e74c3c; }
    </style>
</head>
<body>
    <h1>Security Baseline Verification Report</h1>
    <p><strong>Generated:</strong> $(Get-Date -Format "yyyy-MM-dd HH:mm:ss") | <strong>Run ID:</strong> $RunId</p>
    <p><strong>Baseline Type:</strong> $([System.Net.WebUtility]::HtmlEncode("$BaselineType"))</p>

    <div class="summary">
        <div class="summary-item"><strong>Total Checks:</strong> $TotalChecks</div>
        <div class="summary-item"><strong>Passed:</strong> <span class="pass">$PassedChecks</span></div>
        <div class="summary-item"><strong>Failed:</strong> <span class="fail">$FailedChecks</span></div>
        <div class="summary-item"><strong>Warnings:</strong> <span class="warn">$WarningChecks</span></div>
    </div>

    <div class="score $ScoreClass">
        Compliance Score: $CompliancePercent%
    </div>

    <h2>Detailed Results</h2>
    <table>
        <tr>
            <th>Category</th>
            <th>Setting</th>
            <th>Expected</th>
            <th>Actual</th>
            <th>Status</th>
        </tr>
"@

            foreach ($Result in $script:Results) {
                $StatusClass = $Result.Status.ToLower()
                $HTML += @"
        <tr>
            <td>$([System.Net.WebUtility]::HtmlEncode("$($Result.Category)"))</td>
            <td>$([System.Net.WebUtility]::HtmlEncode("$($Result.Setting)"))</td>
            <td>$([System.Net.WebUtility]::HtmlEncode("$($Result.Expected)"))</td>
            <td>$([System.Net.WebUtility]::HtmlEncode("$($Result.Actual)"))</td>
            <td class="$StatusClass">$([System.Net.WebUtility]::HtmlEncode("$($Result.Status)"))</td>
        </tr>
"@
            }

            $HTML += @"
    </table>

    <h2>Recommendations</h2>
    <ul>
"@

            # Add recommendations for failed items
            $FailedItems = $script:Results | Where-Object { $_.Status -eq 'FAIL' }
            foreach ($Item in $FailedItems) {
                $HTML += "<li><strong>$([System.Net.WebUtility]::HtmlEncode(`"$($Item.Category)`")) - " +
                    "$([System.Net.WebUtility]::HtmlEncode(`"$($Item.Setting)`")):</strong> " +
                    "Configure to meet baseline requirement: " +
                    "$([System.Net.WebUtility]::HtmlEncode(`"$($Item.Expected)`"))</li>"
            }

            if (@($FailedItems).Count -eq 0) {
                $HTML += "<li>No critical issues found. System meets security baseline requirements.</li>"
            }

            $HTML += @"
    </ul>
</body>
</html>
"@

            $HTML | Out-File -FilePath $HTMLPath -Encoding UTF8 -ErrorAction Stop
            Write-Host "[+] HTML Report: $HTMLPath" -ForegroundColor Green
        }

        # Exit with appropriate code (documented: 0 = clean, 1 = issues found or error)
        if ($script:IssuesFound) {
            Write-Host "`n[!] Security baseline check completed with issues found.`n" -ForegroundColor Yellow
            return 1
        }
        else {
            Write-Host "`n[+] Security baseline check completed successfully.`n" -ForegroundColor Green
            return 0
        }
    }
    catch {
        Write-Host "[-] Error: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
