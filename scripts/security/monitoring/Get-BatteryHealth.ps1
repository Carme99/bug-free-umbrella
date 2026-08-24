<#
.SYNOPSIS
    Monitors laptop battery health and generates detailed battery reports.

.DESCRIPTION
    This script analyzes laptop battery health including capacity, charge cycles, wear level, and historical
    performance. It is useful for asset management and for determining when batteries need replacement.
    Side effects: creates the output directory if missing, writes an HTML summary report, and optionally a CSV
    record and a powercfg battery report, under -OutputPath.
    Exit codes: 0 on success (including systems with no battery); 1 on fatal error or unsafe -OutputPath.

.PARAMETER OutputPath
    Path where the battery report will be saved.

.PARAMETER GenerateDetailedReport
    Switch to generate Windows battery report using powercfg.

.PARAMETER AlertThreshold
    Battery health percentage threshold for alerts. Default is 80%.

.PARAMETER ExportToCSV
    Switch to export battery data to CSV format.

.EXAMPLE
    PS C:\> .\Get-BatteryHealth.ps1 -OutputPath "C:\Reports"
    Generates a basic battery health report.

.EXAMPLE
    PS C:\> .\Get-BatteryHealth.ps1 -GenerateDetailedReport -AlertThreshold 70
    Generates detailed report and alerts if battery health is below 70%.

.NOTES
    File Name   : Get-BatteryHealth.ps1
    Author      : Server Management Team
    Prerequisite: PowerShell 5.1+
    Version     : 1.0.0
    Date        : 2026-08-23
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $false)]
    [string]$OutputPath = '',

    [Parameter(Mandatory = $false)]
    [switch]$GenerateDetailedReport,

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 100)]
    [int]$AlertThreshold = 80,

    [Parameter(Mandatory = $false)]
    [switch]$ExportToCSV
)

$ErrorActionPreference = 'Stop'

# PSSA note: Write-Host is mandated here for colorized [+]/[!]/[-]/[*] console status prefixes
# (RELAUNCH-SPEC section 3); PSAvoidUsingWriteHost warnings are accepted by design.

function Main {
    [CmdletBinding()]
    param(
        [string]$OutputPath = '',
        [switch]$GenerateDetailedReport,
        [int]$AlertThreshold = 0,
        [switch]$ExportToCSV
    )

    try {
        # Normalize unset parameters to their documented defaults
        if ($AlertThreshold -le 0) { $AlertThreshold = 80 }
        # Resolve default output location first (MyDocuments is unavailable on non-Windows hosts)
        if ([string]::IsNullOrWhiteSpace($OutputPath)) {
            $documentsDir = [Environment]::GetFolderPath('MyDocuments')
            if ([string]::IsNullOrWhiteSpace($documentsDir)) {
                $documentsDir = (Get-Location).Path
            }
            $OutputPath = Join-Path $documentsDir 'Reports'
        }

        # Validate OutputPath: reject '..' traversal and UNC remote paths before resolution
        if ([string]::IsNullOrWhiteSpace($OutputPath) -or
            $OutputPath -match '(^|[\\/])\.\.([\\/]|$)' -or
            $OutputPath -match '^(\\\\|//)') {
            throw "Unsafe OutputPath: $OutputPath. OutputPath must be a local absolute path without '..' traversal."
        }
        $OutputPath = [System.IO.Path]::GetFullPath($OutputPath)

        $RunTimestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $RunId = [Guid]::NewGuid().ToString('N').Substring(0, 8)

        Write-Host "`n=== Battery Health Monitor ===" -ForegroundColor Cyan
        Write-Host "[*] Computer: $env:COMPUTERNAME" -ForegroundColor Cyan
        Write-Host "[*] Start Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Cyan

        # Create output directory
        if (-not (Test-Path -LiteralPath $OutputPath -PathType Container)) {
            New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
        }

        # Check if system has a battery
        Write-Host "[*] Detecting battery..." -ForegroundColor Cyan

        $battery = Get-CimInstance -ClassName Win32_Battery -ErrorAction SilentlyContinue

        if (-not $battery) {
            Write-Host "[!] No battery detected. This appears to be a desktop system." -ForegroundColor Yellow
            Write-Host "[!] This script is designed for laptops and tablets with batteries." -ForegroundColor Yellow
            return 0
        }

        Write-Host "[+] Battery detected: $($battery.Name)" -ForegroundColor Green

        # Get battery status
        $batteryStatus = switch ($battery.BatteryStatus) {
            1 { "Discharging" }
            2 { "On AC Power" }
            3 { "Fully Charged" }
            4 { "Low" }
            5 { "Critical" }
            6 { "Charging" }
            7 { "Charging High" }
            8 { "Charging Low" }
            9 { "Charging Critical" }
            10 { "Undefined" }
            11 { "Partially Charged" }
            default { "Unknown" }
        }

        # Get battery chemistry
        $batteryChemistry = switch ($battery.Chemistry) {
            1 { "Other" }
            2 { "Unknown" }
            3 { "Lead Acid" }
            4 { "Nickel Cadmium" }
            5 { "Nickel Metal Hydride" }
            6 { "Lithium-ion" }
            7 { "Zinc air" }
            8 { "Lithium Polymer" }
            default { "Unknown" }
        }

        # Calculate battery health
        $designCapacity = $battery.DesignCapacity
        $fullChargeCapacity = $battery.FullChargeCapacity
        $currentCapacity = $battery.EstimatedChargeRemaining

        if ($designCapacity -and $fullChargeCapacity) {
            $batteryHealth = [math]::Round(($fullChargeCapacity / $designCapacity) * 100, 2)
            $wearLevel = [math]::Round(100 - $batteryHealth, 2)
        }
        else {
            $batteryHealth = "N/A"
            $wearLevel = "N/A"
        }

        # Estimate runtime: EstimatedRunTime is meaningless while on AC power (WMI/CIM
        # reports a sentinel value); use BatteryStatus (2 = On AC Power) instead.
        $estimatedRunTime = $battery.EstimatedRunTime
        if ($battery.BatteryStatus -eq 2) {
            $estimatedRunTimeText = "On AC Power"
        }
        elseif ($estimatedRunTime) {
            $hours = [math]::Floor($estimatedRunTime / 60)
            $minutes = $estimatedRunTime % 60
            $estimatedRunTimeText = "$hours hours, $minutes minutes"
        }
        else {
            $estimatedRunTimeText = "Unknown"
        }

        # Display battery information
        Write-Host "`n=== Battery Information ===" -ForegroundColor Cyan
        Write-Host "Name: $($battery.Name)" -ForegroundColor White
        Write-Host "Chemistry: $batteryChemistry" -ForegroundColor White
        Write-Host "Status: $batteryStatus" -ForegroundColor White
        Write-Host "Current Charge: $currentCapacity%" -ForegroundColor White
        Write-Host ""
        Write-Host "=== Battery Health ===" -ForegroundColor Cyan
        Write-Host "Design Capacity: $designCapacity mWh" -ForegroundColor White
        Write-Host "Full Charge Capacity: $fullChargeCapacity mWh" -ForegroundColor White
        $healthForeground = if ([int]$batteryHealth -ge $AlertThreshold) { 'Green' }
        elseif ([int]$batteryHealth -ge 60) { 'Yellow' }
        else { 'Red' }
        Write-Host "[+] Battery Health: $batteryHealth%" -ForegroundColor $healthForeground
        $wearForeground = if ([int]$wearLevel -le 20) { 'Green' }
        elseif ([int]$wearLevel -le 40) { 'Yellow' }
        else { 'Red' }
        Write-Host "[*] Wear Level: $wearLevel%" -ForegroundColor $wearForeground
        Write-Host "Estimated Runtime: $estimatedRunTimeText" -ForegroundColor White

        # Alert if below threshold
        if ($batteryHealth -ne "N/A" -and [int]$batteryHealth -lt $AlertThreshold) {
            Write-Host "[!] WARNING: Battery health is below threshold ($AlertThreshold%)!" -ForegroundColor Yellow
            Write-Host "[!] Current health: $batteryHealth%" -ForegroundColor Yellow
            Write-Host "[!] Recommendation: Consider battery replacement" -ForegroundColor Yellow
        }

        # Get additional battery details from CIM
        $portableBattery = Get-CimInstance -ClassName Win32_PortableBattery -ErrorAction SilentlyContinue

        if ($portableBattery) {
            $manufacturer = $portableBattery.Manufacturer
            $manufactureDate = $portableBattery.ManufactureDate

            Write-Host "`n=== Battery Details ===" -ForegroundColor Cyan
            Write-Host "Manufacturer: $manufacturer" -ForegroundColor White
            if ($manufactureDate) {
                try {
                    $mfgDate = [System.Management.ManagementDateTimeConverter]::ToDateTime($manufactureDate)
                    $batteryAge = ((Get-Date) - $mfgDate).Days
                    $batteryAgeYears = [math]::Round($batteryAge / 365, 1)

                    Write-Host "Manufacture Date: $($mfgDate.ToString('yyyy-MM-dd'))" -ForegroundColor White
                    $ageForeground = if ($batteryAgeYears -lt 2) { 'Green' }
                    elseif ($batteryAgeYears -lt 3) { 'Yellow' }
                    else { 'Red' }
                    Write-Host "[*] Battery Age: $batteryAgeYears years" -ForegroundColor $ageForeground
                }
                catch {
                    Write-Host "[!] Manufacture Date: Unable to parse" -ForegroundColor Yellow
                }
            }
        }

        # Generate detailed Windows battery report
        if ($GenerateDetailedReport) {
            Write-Host "[*] Generating detailed battery report..." -ForegroundColor Cyan

            $batteryReportPath = Join-Path -Path $OutputPath -ChildPath "battery-report_${RunTimestamp}_${RunId}.html"

            try {
                $powercfgArgs = "/batteryreport", "/output", "`"$batteryReportPath`""
                $result = Start-Process -FilePath "powercfg" -ArgumentList $powercfgArgs `
                    -Wait -NoNewWindow -PassThru -ErrorAction Stop

                if ($result.ExitCode -eq 0 -and (Test-Path $batteryReportPath)) {
                    Write-Host "[+] Detailed battery report generated: $batteryReportPath" -ForegroundColor Green
                }
                else {
                    Write-Host "[!] Failed to generate detailed battery report" -ForegroundColor Yellow
                }
            }
            catch {
                Write-Host "[!] Could not generate detailed report: $_" -ForegroundColor Yellow
            }
        }

        # Create battery health record
        $batteryRecord = [PSCustomObject]@{
            ComputerName = $env:COMPUTERNAME
            Timestamp = Get-Date
            BatteryName = $battery.Name
            Chemistry = $batteryChemistry
            Status = $batteryStatus
            CurrentCharge = $currentCapacity
            DesignCapacity = $designCapacity
            FullChargeCapacity = $fullChargeCapacity
            BatteryHealth = $batteryHealth
            WearLevel = $wearLevel
            EstimatedRuntime = $estimatedRunTimeText
            Manufacturer = if ($portableBattery) { $portableBattery.Manufacturer } else { "Unknown" }
        }

        # Export to CSV
        if ($ExportToCSV) {
            $csvPath = Join-Path -Path $OutputPath -ChildPath "BatteryHealth_${RunTimestamp}_${RunId}.csv"
            $batteryRecord | Export-Csv -Path $csvPath -NoTypeInformation -Append -ErrorAction Stop
            Write-Host "[+] Data exported to: $csvPath" -ForegroundColor Green
        }

        # Generate HTML report
        Write-Host "[*] Generating summary report..." -ForegroundColor Cyan
        $htmlPath = Join-Path -Path $OutputPath -ChildPath "BatteryHealthReport_${RunTimestamp}_${RunId}.html"
        $estimatedRunTimeEncoded = [System.Net.WebUtility]::HtmlEncode("$estimatedRunTimeText")
        $healthCellStyle = "color: $healthColor; font-weight: bold;"

        $healthColor = if ([int]$batteryHealth -ge 80) { "green" }
        elseif ([int]$batteryHealth -ge 60) { "orange" }
        else { "red" }
        $statusIcon = if ([int]$batteryHealth -ge 80) { "✓" } elseif ([int]$batteryHealth -ge 60) { "⚠" } else { "✗" }

        $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>Battery Health Report - $env:COMPUTERNAME</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background-color: #f5f5f5; }
        h1 { color: #0066cc; }
        h2 { color: #0099cc; margin-top: 30px; }
        .health-score { font-size: 48px; font-weight: bold; color: $healthColor; text-align: center; margin: 20px 0; }
        .status-icon { font-size: 64px; text-align: center; }
        table {
            border-collapse: collapse; width: 100%; background-color: white;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1); margin: 20px 0;
        }
        th { background-color: #0066cc; color: white; padding: 12px; text-align: left; }
        td { padding: 10px; border-bottom: 1px solid #ddd; }
        .info { background-color: #e6f3ff; padding: 15px; border-left: 4px solid #0066cc; margin: 20px 0; }
        .warning { background-color: #fff3cd; padding: 15px; border-left: 4px solid #ffc107; margin: 20px 0; }
        .critical { background-color: #f8d7da; padding: 15px; border-left: 4px solid #dc3545; margin: 20px 0; }
    </style>
</head>
<body>
    <h1>Battery Health Report</h1>
    <div class="info">
        <strong>Computer:</strong> $([System.Net.WebUtility]::HtmlEncode("$env:COMPUTERNAME"))<br>
        <strong>Report Date:</strong> $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | <strong>Run ID:</strong> $RunId<br>
        <strong>Battery:</strong> $([System.Net.WebUtility]::HtmlEncode("$($battery.Name)"))
    </div>

    <div class="status-icon">$statusIcon</div>
    <div class="health-score">$batteryHealth%</div>
    <p style="text-align: center; font-size: 18px;">Battery Health</p>

    <h2>Battery Information</h2>
    <table>
        <tr><td><strong>Name</strong></td><td>$([System.Net.WebUtility]::HtmlEncode("$($battery.Name)"))</td></tr>
        <tr><td><strong>Chemistry</strong></td><td>$([System.Net.WebUtility]::HtmlEncode("$batteryChemistry"))</td></tr>
        <tr><td><strong>Status</strong></td><td>$([System.Net.WebUtility]::HtmlEncode("$batteryStatus"))</td></tr>
        <tr><td><strong>Current Charge</strong></td><td>$currentCapacity%</td></tr>
        <tr><td><strong>Estimated Runtime</strong></td><td>$estimatedRunTimeEncoded</td></tr>
    </table>

    <h2>Health Metrics</h2>
    <table>
        <tr><td><strong>Design Capacity</strong></td><td>$designCapacity mWh</td></tr>
        <tr><td><strong>Full Charge Capacity</strong></td><td>$fullChargeCapacity mWh</td></tr>
        <tr><td><strong>Battery Health</strong></td><td style="$healthCellStyle">$batteryHealth%</td></tr>
        <tr><td><strong>Wear Level</strong></td><td>$wearLevel%</td></tr>
    </table>
"@

        # Add recommendations based on health
        if ([int]$batteryHealth -ge 80) {
            $html += @"
    <div class="info">
        <strong>Status:</strong> Battery health is good.<br>
        <strong>Recommendation:</strong> No action required. Continue normal usage.
    </div>
"@
        }
        elseif ([int]$batteryHealth -ge 60) {
            $html += @"
    <div class="warning">
        <strong>Status:</strong> Battery health is fair.<br>
        <strong>Recommendation:</strong> Monitor battery performance. Consider replacement in next 6-12 months.
    </div>
"@
        }
        else {
            $html += @"
    <div class="critical">
        <strong>Status:</strong> Battery health is poor.<br>
        <strong>Recommendation:</strong> Battery replacement recommended soon to maintain portable productivity.
    </div>
"@
        }

        $detailedReportFile = Join-Path -Path $OutputPath -ChildPath "battery-report_${RunTimestamp}_${RunId}.html"
        if ($GenerateDetailedReport -and (Test-Path $detailedReportFile)) {
            $html += @"
    <h2>Additional Reports</h2>
    <p><a href="battery-report_${RunTimestamp}_${RunId}.html">View Detailed Windows Battery Report</a></p>
"@
        }

        $html += @"
</body>
</html>
"@

        $html | Out-File -FilePath $htmlPath -Encoding UTF8 -ErrorAction Stop
        Write-Host "[+] Summary report saved to: $htmlPath" -ForegroundColor Green
        Write-Host "[+] Battery health check completed successfully." -ForegroundColor Green

        return 0
    }
    catch {
        Write-Host "[-] Error checking battery health: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main @PSBoundParameters) }
