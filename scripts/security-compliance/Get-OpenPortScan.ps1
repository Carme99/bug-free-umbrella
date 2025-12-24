<#
.SYNOPSIS
    Scans for open network ports and identifies associated processes.

.DESCRIPTION
    This script enumerates all listening TCP and optionally UDP ports on the local system,
    identifies the processes using each port, and flags potentially risky or unexpected
    open ports based on common security best practices.

    The script helps identify:
    - Unexpected or unauthorized services
    - High-risk ports (RDP, SMB, Telnet, etc.)
    - Processes listening on all interfaces (0.0.0.0)
    - Services running with elevated privileges

.PARAMETER HighRiskOnly
    Show only high-risk ports (e.g., RDP, SMB, Telnet)

.PARAMETER IncludeUDP
    Include UDP ports in the scan (slower)

.PARAMETER ExportReport
    Generate HTML and CSV reports on the Desktop

.EXAMPLE
    .\Get-OpenPortScan.ps1
    Scans all TCP listening ports

.EXAMPLE
    .\Get-OpenPortScan.ps1 -HighRiskOnly
    Shows only high-risk open ports

.EXAMPLE
    .\Get-OpenPortScan.ps1 -IncludeUDP -ExportReport
    Scans TCP and UDP, generates reports

.NOTES
    Author: Security & Compliance Team
    Requires: Administrator privileges (for process details)
    Compatible: Windows 10/11, Server 2016+
#>

[CmdletBinding()]
param(
    [Parameter()]
    [switch]$HighRiskOnly,

    [Parameter()]
    [switch]$IncludeUDP,

    [Parameter()]
    [switch]$ExportReport
)

#Requires -RunAsAdministrator

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "   Open Port Security Scan" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Define high-risk ports
$HighRiskPorts = @{
    21   = @{ Service = "FTP"; Risk = "High"; Reason = "Unencrypted file transfer" }
    22   = @{ Service = "SSH"; Risk = "Medium"; Reason = "Remote access (ensure strong auth)" }
    23   = @{ Service = "Telnet"; Risk = "Critical"; Reason = "Unencrypted remote access" }
    25   = @{ Service = "SMTP"; Risk = "Medium"; Reason = "Email relay (ensure secured)" }
    53   = @{ Service = "DNS"; Risk = "Low"; Reason = "Domain resolution" }
    80   = @{ Service = "HTTP"; Risk = "Medium"; Reason = "Unencrypted web traffic" }
    110  = @{ Service = "POP3"; Risk = "Medium"; Reason = "Unencrypted email" }
    135  = @{ Service = "RPC"; Risk = "High"; Reason = "Windows RPC - attack vector" }
    139  = @{ Service = "NetBIOS"; Risk = "High"; Reason = "SMB over NetBIOS" }
    143  = @{ Service = "IMAP"; Risk = "Medium"; Reason = "Unencrypted email" }
    389  = @{ Service = "LDAP"; Risk = "Medium"; Reason = "Directory services (use LDAPS)" }
    443  = @{ Service = "HTTPS"; Risk = "Low"; Reason = "Encrypted web traffic" }
    445  = @{ Service = "SMB"; Risk = "High"; Reason = "File sharing - common attack target" }
    1433 = @{ Service = "SQL Server"; Risk = "High"; Reason = "Database exposure" }
    3306 = @{ Service = "MySQL"; Risk = "High"; Reason = "Database exposure" }
    3389 = @{ Service = "RDP"; Risk = "High"; Reason = "Remote Desktop - secure properly" }
    5432 = @{ Service = "PostgreSQL"; Risk = "High"; Reason = "Database exposure" }
    5985 = @{ Service = "WinRM HTTP"; Risk = "Medium"; Reason = "PowerShell remoting" }
    5986 = @{ Service = "WinRM HTTPS"; Risk = "Low"; Reason = "Secure PowerShell remoting" }
    8080 = @{ Service = "HTTP Alt"; Risk = "Medium"; Reason = "Alternative HTTP port" }
}

# Get TCP connections
Write-Host "[1/3] Scanning TCP ports..." -ForegroundColor Yellow

$TCPConnections = Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue |
    Select-Object LocalAddress, LocalPort, OwningProcess, State

Write-Host "  Found $($TCPConnections.Count) listening TCP ports`n" -ForegroundColor Green

# Get UDP endpoints if requested
$UDPEndpoints = @()
if ($IncludeUDP) {
    Write-Host "[2/3] Scanning UDP ports..." -ForegroundColor Yellow
    $UDPEndpoints = Get-NetUDPEndpoint -ErrorAction SilentlyContinue |
        Select-Object LocalAddress, LocalPort, OwningProcess
    Write-Host "  Found $($UDPEndpoints.Count) UDP endpoints`n" -ForegroundColor Green
} else {
    Write-Host "[2/3] Skipping UDP scan (use -IncludeUDP to include)" -ForegroundColor Gray
}

# Analyze ports
Write-Host "`n[3/3] Analyzing open ports and processes..." -ForegroundColor Yellow

$Results = @()
$HighRiskFound = $false

# Process TCP ports
foreach ($Connection in $TCPConnections) {
    try {
        $Process = Get-Process -Id $Connection.OwningProcess -ErrorAction SilentlyContinue
        $ProcessName = if ($Process) { $Process.ProcessName } else { "Unknown" }
        $ProcessPath = if ($Process) { $Process.Path } else { "Unknown" }

        # Determine risk level
        $RiskInfo = $HighRiskPorts[$Connection.LocalPort]
        $RiskLevel = if ($RiskInfo) { $RiskInfo.Risk } else { "Low" }
        $ServiceName = if ($RiskInfo) { $RiskInfo.Service } else { "Unknown" }
        $RiskReason = if ($RiskInfo) { $RiskInfo.Reason } else { "Custom service" }

        # Flag listening on all interfaces as higher risk
        if ($Connection.LocalAddress -eq "0.0.0.0" -or $Connection.LocalAddress -eq "::") {
            $AllInterfaces = $true
            if ($RiskLevel -eq "Low") { $RiskLevel = "Medium" }
        } else {
            $AllInterfaces = $false
        }

        # Track critical/high risk
        if ($RiskLevel -in @("Critical", "High")) {
            $HighRiskFound = $true
        }

        $PortInfo = [PSCustomObject]@{
            Protocol = "TCP"
            Port = $Connection.LocalPort
            Address = $Connection.LocalAddress
            AllInterfaces = $AllInterfaces
            Service = $ServiceName
            ProcessName = $ProcessName
            ProcessPath = $ProcessPath
            PID = $Connection.OwningProcess
            RiskLevel = $RiskLevel
            Reason = $RiskReason
        }

        # Apply filter if HighRiskOnly is specified
        if (-not $HighRiskOnly -or ($RiskLevel -in @("Critical", "High", "Medium"))) {
            $Results += $PortInfo
        }

    } catch {
        Write-Verbose "Error processing port $($Connection.LocalPort): $($_.Exception.Message)"
    }
}

# Process UDP ports if included
if ($IncludeUDP) {
    foreach ($Endpoint in $UDPEndpoints) {
        try {
            $Process = Get-Process -Id $Endpoint.OwningProcess -ErrorAction SilentlyContinue
            $ProcessName = if ($Process) { $Process.ProcessName } else { "Unknown" }
            $ProcessPath = if ($Process) { $Process.Path } else { "Unknown" }

            $RiskInfo = $HighRiskPorts[$Endpoint.LocalPort]
            $RiskLevel = if ($RiskInfo) { $RiskInfo.Risk } else { "Low" }
            $ServiceName = if ($RiskInfo) { $RiskInfo.Service } else { "Unknown" }
            $RiskReason = if ($RiskInfo) { $RiskInfo.Reason } else { "Custom service" }

            if ($Endpoint.LocalAddress -eq "0.0.0.0" -or $Endpoint.LocalAddress -eq "::") {
                $AllInterfaces = $true
                if ($RiskLevel -eq "Low") { $RiskLevel = "Medium" }
            } else {
                $AllInterfaces = $false
            }

            if ($RiskLevel -in @("Critical", "High")) {
                $HighRiskFound = $true
            }

            $PortInfo = [PSCustomObject]@{
                Protocol = "UDP"
                Port = $Endpoint.LocalPort
                Address = $Endpoint.LocalAddress
                AllInterfaces = $AllInterfaces
                Service = $ServiceName
                ProcessName = $ProcessName
                ProcessPath = $ProcessPath
                PID = $Endpoint.OwningProcess
                RiskLevel = $RiskLevel
                Reason = $RiskReason
            }

            if (-not $HighRiskOnly -or ($RiskLevel -in @("Critical", "High", "Medium"))) {
                $Results += $PortInfo
            }

        } catch {
            Write-Verbose "Error processing UDP port $($Endpoint.LocalPort): $($_.Exception.Message)"
        }
    }
}

# Sort by risk level, then port number
$Results = $Results | Sort-Object @{Expression={
    switch ($_.RiskLevel) {
        "Critical" { 0 }
        "High" { 1 }
        "Medium" { 2 }
        "Low" { 3 }
        default { 4 }
    }
}}, Port

# Display results
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "   Open Ports Report" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

foreach ($Result in $Results) {
    $RiskColor = switch ($Result.RiskLevel) {
        "Critical" { "Magenta" }
        "High" { "Red" }
        "Medium" { "Yellow" }
        "Low" { "Green" }
        default { "White" }
    }

    Write-Host "[" -NoNewline
    Write-Host $Result.RiskLevel.PadRight(8) -ForegroundColor $RiskColor -NoNewline
    Write-Host "] " -NoNewline
    Write-Host "$($Result.Protocol) Port $($Result.Port) " -ForegroundColor White -NoNewline
    Write-Host "($($Result.Service))" -ForegroundColor Cyan

    Write-Host "           Process: " -ForegroundColor Gray -NoNewline
    Write-Host "$($Result.ProcessName) " -ForegroundColor White -NoNewline
    Write-Host "(PID: $($Result.PID))" -ForegroundColor Gray

    Write-Host "           Address: " -ForegroundColor Gray -NoNewline
    if ($Result.AllInterfaces) {
        Write-Host "$($Result.Address) " -ForegroundColor Yellow -NoNewline
        Write-Host "(All Interfaces - Higher Risk)" -ForegroundColor Yellow
    } else {
        Write-Host $Result.Address -ForegroundColor White
    }

    Write-Host "           Reason:  " -ForegroundColor Gray -NoNewline
    Write-Host $Result.Reason -ForegroundColor White
    Write-Host ""
}

# Summary
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "   Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$CriticalCount = ($Results | Where-Object { $_.RiskLevel -eq "Critical" }).Count
$HighCount = ($Results | Where-Object { $_.RiskLevel -eq "High" }).Count
$MediumCount = ($Results | Where-Object { $_.RiskLevel -eq "Medium" }).Count
$LowCount = ($Results | Where-Object { $_.RiskLevel -eq "Low" }).Count

Write-Host "Total Open Ports: $($Results.Count)" -ForegroundColor White
Write-Host "  Critical Risk: $CriticalCount" -ForegroundColor Magenta
Write-Host "  High Risk: $HighCount" -ForegroundColor Red
Write-Host "  Medium Risk: $MediumCount" -ForegroundColor Yellow
Write-Host "  Low Risk: $LowCount" -ForegroundColor Green

# Recommendations
if ($CriticalCount -gt 0 -or $HighCount -gt 0) {
    Write-Host "`n========================================" -ForegroundColor Yellow
    Write-Host "   Recommendations" -ForegroundColor Yellow
    Write-Host "========================================" -ForegroundColor Yellow

    $HighRiskPorts = $Results | Where-Object { $_.RiskLevel -in @("Critical", "High") }
    foreach ($Port in $HighRiskPorts) {
        Write-Host "`nPort $($Port.Port) ($($Port.Service)) - " -ForegroundColor White -NoNewline
        Write-Host $Port.RiskLevel -ForegroundColor $(if ($Port.RiskLevel -eq "Critical") { "Magenta" } else { "Red" })
        Write-Host "  → $($Port.Reason)" -ForegroundColor Yellow

        # Specific recommendations
        switch ($Port.Port) {
            3389 { Write-Host "  → Enable Network Level Authentication (NLA)" -ForegroundColor Cyan
                   Write-Host "  → Use VPN or restrict by IP address" -ForegroundColor Cyan
                   Write-Host "  → Consider changing default port" -ForegroundColor Cyan }
            445  { Write-Host "  → Ensure SMB signing is enabled" -ForegroundColor Cyan
                   Write-Host "  → Disable SMBv1 protocol" -ForegroundColor Cyan
                   Write-Host "  → Use firewall to restrict access" -ForegroundColor Cyan }
            135  { Write-Host "  → Restrict RPC access via firewall" -ForegroundColor Cyan
                   Write-Host "  → Disable if not required" -ForegroundColor Cyan }
            139  { Write-Host "  → Disable NetBIOS over TCP/IP if not needed" -ForegroundColor Cyan }
            23   { Write-Host "  → CRITICAL: Replace Telnet with SSH immediately" -ForegroundColor Red }
            21   { Write-Host "  → Replace FTP with SFTP or FTPS" -ForegroundColor Cyan }
        }
    }

    Write-Host "`nGeneral Security Tips:" -ForegroundColor Cyan
    Write-Host "  • Close unused ports and disable unnecessary services" -ForegroundColor White
    Write-Host "  • Use Windows Firewall to restrict access" -ForegroundColor White
    Write-Host "  • Enable encryption for all remote access protocols" -ForegroundColor White
    Write-Host "  • Regularly audit open ports and running services" -ForegroundColor White
    Write-Host "  • Use VPN for remote access instead of exposing services directly" -ForegroundColor White
}

# Export reports if requested
if ($ExportReport) {
    $ReportPath = [Environment]::GetFolderPath('Desktop')
    $Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"

    # CSV Export
    $CSVPath = Join-Path $ReportPath "OpenPortScan_$Timestamp.csv"
    $Results | Export-Csv -Path $CSVPath -NoTypeInformation
    Write-Host "`nCSV Report: $CSVPath" -ForegroundColor Green

    # HTML Export
    $HTMLPath = Join-Path $ReportPath "OpenPortScan_$Timestamp.html"
    $HTML = @"
<!DOCTYPE html>
<html>
<head>
    <title>Open Port Scan Report - $Timestamp</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background-color: #f5f5f5; }
        h1 { color: #2c3e50; border-bottom: 3px solid #3498db; padding-bottom: 10px; }
        h2 { color: #34495e; margin-top: 30px; }
        .summary { background-color: #ecf0f1; padding: 15px; border-radius: 5px; margin: 20px 0; }
        .summary-item { margin: 10px 0; font-size: 16px; }
        table { border-collapse: collapse; width: 100%; margin-top: 20px; background-color: white; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        th { background-color: #3498db; color: white; padding: 12px; text-align: left; font-size: 14px; }
        td { padding: 10px; border-bottom: 1px solid #ddd; font-size: 13px; }
        tr:hover { background-color: #f5f5f5; }
        .critical { background-color: #f3e5f5; color: #6a1b9a; font-weight: bold; }
        .high { background-color: #ffebee; color: #c62828; font-weight: bold; }
        .medium { background-color: #fff3e0; color: #ef6c00; font-weight: bold; }
        .low { background-color: #e8f5e9; color: #2e7d32; font-weight: bold; }
        .all-interfaces { color: #ef6c00; font-weight: bold; }
    </style>
</head>
<body>
    <h1>Open Port Security Scan Report</h1>
    <p><strong>Generated:</strong> $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")</p>
    <p><strong>Computer:</strong> $env:COMPUTERNAME</p>

    <div class="summary">
        <div class="summary-item"><strong>Total Open Ports:</strong> $($Results.Count)</div>
        <div class="summary-item"><strong>Critical Risk:</strong> <span style="color: #6a1b9a;">$CriticalCount</span></div>
        <div class="summary-item"><strong>High Risk:</strong> <span style="color: #c62828;">$HighCount</span></div>
        <div class="summary-item"><strong>Medium Risk:</strong> <span style="color: #ef6c00;">$MediumCount</span></div>
        <div class="summary-item"><strong>Low Risk:</strong> <span style="color: #2e7d32;">$LowCount</span></div>
    </div>

    <h2>Open Ports Details</h2>
    <table>
        <tr>
            <th>Protocol</th>
            <th>Port</th>
            <th>Service</th>
            <th>Address</th>
            <th>Process</th>
            <th>PID</th>
            <th>Risk</th>
            <th>Reason</th>
        </tr>
"@

    foreach ($Result in $Results) {
        $RiskClass = $Result.RiskLevel.ToLower()
        $AddressDisplay = if ($Result.AllInterfaces) {
            "$($Result.Address) <span class='all-interfaces'>(All Interfaces)</span>"
        } else {
            $Result.Address
        }

        $HTML += @"
        <tr>
            <td>$($Result.Protocol)</td>
            <td><strong>$($Result.Port)</strong></td>
            <td>$($Result.Service)</td>
            <td>$AddressDisplay</td>
            <td>$($Result.ProcessName)</td>
            <td>$($Result.PID)</td>
            <td class="$RiskClass">$($Result.RiskLevel)</td>
            <td>$($Result.Reason)</td>
        </tr>
"@
    }

    $HTML += @"
    </table>
</body>
</html>
"@

    $HTML | Out-File -FilePath $HTMLPath -Encoding UTF8
    Write-Host "HTML Report: $HTMLPath" -ForegroundColor Green
}

# Exit with appropriate code
Write-Host ""
if ($HighRiskFound) {
    Write-Host "⚠ Scan completed. High-risk ports detected - review recommendations.`n" -ForegroundColor Yellow
    exit 1
} else {
    Write-Host "✓ Scan completed. No critical issues found.`n" -ForegroundColor Green
    exit 0
}
