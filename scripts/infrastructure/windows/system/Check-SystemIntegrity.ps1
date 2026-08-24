<#
.SYNOPSIS
    Performs comprehensive system integrity checks on Windows Server 2016-2022.

.DESCRIPTION
    This script runs multiple system integrity verification tools and reports the outcome:
    - System File Checker (SFC)
    - Deployment Image Servicing and Management (DISM) component store analysis
    - Check Disk (CHKDSK) dirty-bit analysis
    - Event log analysis for critical errors (last 24 hours)

    With -AutoRepair, detected component store corruption is repaired via DISM
    /RestoreHealth (gated by -WhatIf/-Confirm). Findings are reported in the console
    log and optionally written to an HTML report under the user's Documents\Reports
    folder.

    Exit codes: 0 = scan completed (any overall status), 1 = fatal error or the
    session lacks Administrator privileges.

.PARAMETER QuickScan
    Performs only SFC and basic DISM checks (faster).

.PARAMETER AutoRepair
    Automatically attempts to repair detected component store issues.

.PARAMETER GenerateReport
    Creates a detailed HTML report of findings.

.EXAMPLE
    PS C:\> .\Check-SystemIntegrity.ps1
    Performs a standard integrity check.

.EXAMPLE
    PS C:\> .\Check-SystemIntegrity.ps1 -AutoRepair -GenerateReport
    Checks integrity, repairs issues, and generates a report.

.NOTES
    File Name:     Check-SystemIntegrity.ps1
    Author:        Bug-Free Umbrella
    Prerequisite:  PowerShell 5.1+
    Version:       1.0.0
    Date:          2026-08-23

    Requires Administrator privileges on supported operating systems.
    Compatible with Windows Server 2016, 2019, and 2022.
    May take 15-30 minutes to complete a full scan.
#>

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
    Justification = 'Console remediation tool: prefixed, color-coded host output is the intended user interface.')]
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $false)]
    [switch]$QuickScan,

    [Parameter(Mandatory = $false)]
    [switch]$AutoRepair,

    [Parameter(Mandatory = $false)]
    [switch]$GenerateReport
)

$ErrorActionPreference = 'Stop'

function Test-AdminPrivilege {
    [CmdletBinding()]
    param()

    try {
        $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = [System.Security.Principal.WindowsPrincipal]$identity
        return $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch {
        # Non-Windows platform or unavailable identity APIs.
        return $false
    }
}

function Write-LogEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [ValidateSet("INFO", "SUCCESS", "WARNING", "ERROR", "HEADER")]
        [string]$Type = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $prefix = switch ($Type) {
        "ERROR" { "[-]" }
        "SUCCESS" { "[+]" }
        "WARNING" { "[!]" }
        default { "[*]" }
    }
    $color = switch ($Type) {
        "ERROR" { "Red" }
        "SUCCESS" { "Green" }
        "WARNING" { "Yellow" }
        "HEADER" { "Cyan" }
        default { "Cyan" }
    }
    Write-Host "[$timestamp] $prefix $Message" -ForegroundColor $color
}

function Invoke-Sfc {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string[]]$ArgumentList = @('/scannow')
    )

    $output = & "$env:windir\System32\sfc.exe" @ArgumentList 2>&1
    return [PSCustomObject]@{ ExitCode = $LASTEXITCODE; Output = ($output | Out-String) }
}

function Invoke-Dism {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$ArgumentList
    )

    $output = & "$env:windir\System32\Dism.exe" @ArgumentList 2>&1
    return [PSCustomObject]@{ ExitCode = $LASTEXITCODE; Output = ($output | Out-String) }
}

function Invoke-Fsutil {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$ArgumentList
    )

    $output = & "$env:windir\System32\fsutil.exe" @ArgumentList 2>&1
    return [PSCustomObject]@{ ExitCode = $LASTEXITCODE; Output = ($output | Out-String) }
}

function Test-SystemFileChecker {
    [CmdletBinding()]
    param()

    Write-LogEntry "Running System File Checker (SFC)..." "INFO"
    Write-LogEntry "This may take several minutes..." "WARNING"

    try {
        $sfcLog = "$env:windir\Logs\CBS\CBS.log"
        $sfcResult = Invoke-Sfc

        if ($sfcResult.ExitCode -ne 0) {
            Write-LogEntry "SFC exited with code $($sfcResult.ExitCode)" "WARNING"
        }

        Start-Sleep -Seconds 5

        if (Test-Path $sfcLog) {
            $logContent = Get-Content $sfcLog -Tail 50 | Out-String

            if ($logContent -match "Windows Resource Protection did not find any integrity violations") {
                Write-LogEntry "SFC: No integrity violations found" "SUCCESS"
                $script:results.SFCResult = "PASSED"
                return $true
            }
            elseif ($logContent -match
                "Windows Resource Protection found corrupt files and successfully repaired them") {
                Write-LogEntry "SFC: Found and repaired corrupt files" "SUCCESS"
                $script:results.SFCResult = "REPAIRED"
                return $true
            }
            elseif ($logContent -match
                "Windows Resource Protection found corrupt files but was unable to fix some of them") {
                Write-LogEntry "SFC: Found corrupt files that could not be repaired" "ERROR"
                $script:results.SFCResult = "FAILED - Manual intervention required"
                return $false
            }
        }

        Write-LogEntry "SFC: Scan completed - Check CBS.log for details" "WARNING"
        $script:results.SFCResult = "COMPLETED - Review logs"
        return $true
    }
    catch {
        Write-LogEntry "SFC: Error during scan - $($_.Exception.Message)" "ERROR"
        $script:results.SFCResult = "ERROR"
        return $false
    }
}

function Test-DISM {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [bool]$Repair = $false
    )

    Write-LogEntry "Running DISM Component Store verification..." "INFO"

    try {
        # Check Component Store health
        Write-LogEntry "Checking component store health..." "INFO"
        $dismCheck = (Invoke-Dism -ArgumentList @('/Online', '/Cleanup-Image', '/CheckHealth')).Output

        if ($dismCheck -match "No component store corruption detected") {
            Write-LogEntry "DISM CheckHealth: No corruption detected" "SUCCESS"
            $script:results.DISMResult = "PASSED"
            return $true
        }

        # Scan for corruption
        Write-LogEntry "Scanning for component store corruption..." "INFO"
        $dismScan = (Invoke-Dism -ArgumentList @('/Online', '/Cleanup-Image', '/ScanHealth')).Output

        if ($dismScan -match "No component store corruption detected") {
            Write-LogEntry "DISM ScanHealth: No corruption detected" "SUCCESS"
            $script:results.DISMResult = "PASSED"
            return $true
        }

        if ($Repair -or $AutoRepair) {
            Write-LogEntry "Attempting to repair component store..." "WARNING"
            Write-LogEntry "This may take 10-15 minutes..." "WARNING"

            if ($PSCmdlet.ShouldProcess("Windows component store", "Run DISM /RestoreHealth repair")) {
                $dismRepair = (Invoke-Dism -ArgumentList @('/Online', '/Cleanup-Image', '/RestoreHealth')).Output

                if ($dismRepair -match "The restore operation completed successfully" -or
                    $dismRepair -match "No component store corruption detected") {
                    Write-LogEntry "DISM RestoreHealth: Repair completed successfully" "SUCCESS"
                    $script:results.DISMResult = "REPAIRED"
                    return $true
                }
                else {
                    Write-LogEntry "DISM RestoreHealth: Repair failed" "ERROR"
                    $script:results.DISMResult = "FAILED"
                    return $false
                }
            }
            else {
                Write-LogEntry "DISM repair skipped (-WhatIf or user declined)" "WARNING"
                $script:results.DISMResult = "CORRUPTION DETECTED"
                return $false
            }
        }
        else {
            Write-LogEntry "DISM: Corruption detected - Run with -AutoRepair to fix" "WARNING"
            $script:results.DISMResult = "CORRUPTION DETECTED"
            return $false
        }
    }
    catch {
        Write-LogEntry "DISM: Error during scan - $($_.Exception.Message)" "ERROR"
        $script:results.DISMResult = "ERROR"
        return $false
    }
}

function Test-DiskHealth {
    [CmdletBinding()]
    param()

    Write-LogEntry "Analyzing disk health..." "INFO"

    try {
        $volumes = Get-Volume | Where-Object { $null -ne $_.DriveLetter -and $_.FileSystem -eq "NTFS" }

        foreach ($volume in $volumes) {
            $driveLetter = $volume.DriveLetter
            Write-LogEntry "Checking drive $driveLetter..." "INFO"

            # Check for dirty bit
            $dirtyBit = (Invoke-Fsutil -ArgumentList @('dirty', 'query', "$($driveLetter):")).Output

            if ($dirtyBit -match "NOT set") {
                Write-LogEntry "Drive ${driveLetter}: File system is clean" "SUCCESS"
            }
            else {
                Write-LogEntry "Drive ${driveLetter}: Disk check scheduled on next reboot" "WARNING"
                $script:results.CHKDSKResult += "Drive ${driveLetter}: Requires check on reboot`n"
            }
        }

        if ([string]::IsNullOrEmpty($script:results.CHKDSKResult)) {
            $script:results.CHKDSKResult = "All drives healthy"
        }

        return $true
    }
    catch {
        Write-LogEntry "Disk Health: Error during check - $($_.Exception.Message)" "ERROR"
        $script:results.CHKDSKResult = "ERROR"
        return $false
    }
}

function Get-CriticalEventLogError {
    [CmdletBinding()]
    param()

    Write-LogEntry "Checking Event Logs for critical errors (last 24 hours)..." "INFO"

    try {
        $startTime = (Get-Date).AddDays(-1)
        $logs = @("System", "Application")

        foreach ($logName in $logs) {
            $errors = Get-WinEvent -FilterHashtable @{
                LogName = $logName
                Level = 1, 2  # Critical and Error
                StartTime = $startTime
            } -ErrorAction SilentlyContinue | Select-Object -First 10

            if ($errors) {
                foreach ($err in $errors) {
                    $errorInfo = [PSCustomObject]@{
                        Time = $err.TimeCreated
                        Log = $logName
                        Source = $err.ProviderName
                        EventID = $err.Id
                        Message = $err.Message.Substring(0, [Math]::Min(200, $err.Message.Length))
                    }
                    $script:results.EventLogErrors += $errorInfo
                }
            }
        }

        if ($script:results.EventLogErrors.Count -gt 0) {
            Write-LogEntry "Found $($script:results.EventLogErrors.Count) critical errors in event logs" "WARNING"
        }
        else {
            Write-LogEntry "No critical errors found in event logs" "SUCCESS"
        }

        return $true
    }
    catch {
        Write-LogEntry "Event Log: Error during check - $($_.Exception.Message)" "WARNING"
        return $false
    }
}

function New-IntegrityReport {
    [CmdletBinding(SupportsShouldProcess)]
    param()
    $RunTimestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $RunId = [Guid]::NewGuid().ToString('N').Substring(0, 8)

    # Reports directory (internal output location)
    $myDocs = [Environment]::GetFolderPath('MyDocuments')
    if ([string]::IsNullOrWhiteSpace($myDocs)) {
        # Profile-less contexts (CI runners, SYSTEM services): MyDocuments resolves empty;
        # fall back so report writing degrades gracefully instead of crashing.
        $myDocs = [Environment]::GetFolderPath('UserProfile')
    }
    $reportDir = Join-Path $myDocs 'Reports'
    # Validate report directory: reject '..' traversal and UNC remote paths before resolution
    if ([string]::IsNullOrWhiteSpace($reportDir) -or
        $reportDir -match '(^|[\\/])\.\.([\\/]|$)' -or
        $reportDir -match '^(\\\\|//)') {
        $reason = "Report directory must be a local absolute path without '..' traversal."
        throw "Unsafe report directory: $reportDir. $reason"
    }
    $reportDir = [System.IO.Path]::GetFullPath($reportDir)
    if (-not (Test-Path -LiteralPath $reportDir -PathType Container)) {
        if ($PSCmdlet.ShouldProcess($reportDir, 'Create report directory')) {
            New-Item -ItemType Directory -Path $reportDir -Force | Out-Null
        }
    }

    $reportPath = Join-Path $reportDir "SystemIntegrityReport_$($env:COMPUTERNAME)_${RunTimestamp}_${RunId}.html"

    $sfcResultClass = switch -Regex ($script:results.SFCResult) {
        'PASSED|REPAIRED' { 'passed'; break }
        'FAILED' { 'failed'; break }
        default { 'warning' }
    }
    $dismResultClass = switch -Regex ($script:results.DISMResult) {
        'PASSED|REPAIRED' { 'passed'; break }
        'FAILED' { 'failed'; break }
        default { 'warning' }
    }
    $chkdskResultClass = switch -Regex ($script:results.CHKDSKResult) {
        'healthy' { 'passed'; break }
        default { 'warning' }
    }

    $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>System Integrity Report - $($script:results.ServerName)</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background-color: #f5f5f5; }
        .container { background-color: white; padding: 20px; border-radius: 5px;
            box-shadow: 0 2px 5px rgba(0,0,0,0.1); }
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
            <tr><th>Server Name</th><td>$([System.Net.WebUtility]::HtmlEncode(
                "$($script:results.ServerName)"))</td></tr>
            <tr><th>Scan Date</th><td>$($script:results.ScanDate) | Run ID: $RunId</td></tr>
            <tr><th>OS Version</th><td>$([System.Net.WebUtility]::HtmlEncode("$($script:results.OSVersion)"))</td></tr>
        </table>

        <h2>Integrity Check Results</h2>
        <table class="info-table">
            <tr><th>Check Type</th><th>Result</th></tr>
            <tr><td>System File Checker (SFC)</td><td class="$sfcResultClass">
                $([System.Net.WebUtility]::HtmlEncode("$($script:results.SFCResult)"))</td></tr>
            <tr><td>DISM Component Store</td><td class="$dismResultClass">
                $([System.Net.WebUtility]::HtmlEncode("$($script:results.DISMResult)"))</td></tr>
            <tr><td>Disk Health</td><td class="$chkdskResultClass">
                $([System.Net.WebUtility]::HtmlEncode("$($script:results.CHKDSKResult)"))</td></tr>
        </table>

        <h2>Critical Event Log Errors (Last 24 Hours)</h2>
        <table class="info-table event-log">
            <tr><th>Time</th><th>Log</th><th>Source</th><th>Event ID</th><th>Message</th></tr>
"@

    if ($script:results.EventLogErrors.Count -gt 0) {
        foreach ($err in $script:results.EventLogErrors) {
                $cells = "<td>$([System.Net.WebUtility]::HtmlEncode("$($err.Time)"))</td>" +
                    "<td>$([System.Net.WebUtility]::HtmlEncode("$($err.Log)"))</td>" +
                    "<td>$([System.Net.WebUtility]::HtmlEncode("$($err.Source)"))</td>"
                $cells += "<td>$([System.Net.WebUtility]::HtmlEncode("$($err.EventID)"))</td>" +
                    "<td>$([System.Net.WebUtility]::HtmlEncode("$($err.Message)"))</td>"
                $html += "<tr>$cells</tr>"
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

    if ($PSCmdlet.ShouldProcess($reportPath, 'Write integrity report')) {
        $html | Out-File -FilePath $reportPath -Encoding UTF8
    }
    Write-LogEntry "Report generated: $reportPath" "SUCCESS"
    Write-Host "[+] HTML report saved to: $reportPath" -ForegroundColor Green
}

function Main {
    [CmdletBinding(SupportsShouldProcess)]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'diskPassed',
        Justification = 'Preserved original diagnostic assignment; status derives from SFC/DISM results.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'eventLogPassed',
        Justification = 'Preserved original diagnostic assignment; status derives from SFC/DISM results.')]
    param(
        [Parameter(Mandatory = $false)]
        [switch]$QuickScan,

        [Parameter(Mandatory = $false)]
        [switch]$AutoRepair,

        [Parameter(Mandatory = $false)]
        [switch]$GenerateReport
    )

    try {
        Write-LogEntry "=== System Integrity Check Started ===" "HEADER"

        if (-not (Test-AdminPrivilege)) {
            Write-LogEntry "Administrator privileges are required. Re-run from an elevated PowerShell session." "ERROR"
            return 1
        }

        $script:results = @{
            ServerName = $env:COMPUTERNAME
            ScanDate = Get-Date
            OSVersion = (Get-CimInstance -ClassName Win32_OperatingSystem).Caption
            SFCResult = ""
            DISMResult = ""
            CHKDSKResult = ""
            EventLogErrors = @()
            OverallStatus = "UNKNOWN"
        }

        Write-LogEntry "Server: $($script:results.ServerName) | OS: $($script:results.OSVersion)" "INFO"

        $sfcPassed = Test-SystemFileChecker

        if (-not $QuickScan) {
            $dismPassed = Test-DISM -Repair $AutoRepair
            $diskPassed = Test-DiskHealth # diagnostic parity with original; status derives from SFC/DISM
            $eventLogPassed = Get-CriticalEventLogError # diagnostic parity; see overall status below
        }
        else {
            Write-LogEntry "Quick scan mode - running SFC only" "INFO"
            $dismPassed = Test-DISM -Repair $false
        }

        # Determine overall status
        if ($sfcPassed -and $dismPassed) {
            $script:results.OverallStatus = "HEALTHY"
            Write-LogEntry "=== Overall Status: HEALTHY ===" "SUCCESS"
        }
        elseif ($script:results.SFCResult -match "REPAIRED" -or $script:results.DISMResult -match "REPAIRED") {
            $script:results.OverallStatus = "REPAIRED"
            Write-LogEntry "=== Overall Status: ISSUES REPAIRED ===" "SUCCESS"
        }
        else {
            $script:results.OverallStatus = "ATTENTION REQUIRED"
            Write-LogEntry "=== Overall Status: ATTENTION REQUIRED ===" "WARNING"
        }

        if ($GenerateReport) {
            New-IntegrityReport
        }

        Write-LogEntry "=== System Integrity Check Completed ===" "INFO"
        return 0
    }
    catch {
        Write-Host "[-] Error: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main @PSBoundParameters) }
