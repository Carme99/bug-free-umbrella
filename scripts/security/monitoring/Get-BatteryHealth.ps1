<#
.SYNOPSIS
    Monitors laptop battery health and generates detailed battery reports.

.DESCRIPTION
    This script analyzes laptop battery health including capacity, charge cycles,
    wear level, and historical performance. Useful for asset management and
    determining when batteries need replacement.

.PARAMETER OutputPath
    Path where the battery report will be saved.

.PARAMETER GenerateDetailedReport
    Switch to generate Windows battery report using powercfg.

.PARAMETER AlertThreshold
    Battery health percentage threshold for alerts. Default is 80%.

.PARAMETER ExportToCSV
    Switch to export battery data to CSV format.

.EXAMPLE
    .\Get-BatteryHealth.ps1 -OutputPath "C:\Reports"
    Generates a basic battery health report.

.EXAMPLE
    .\Get-BatteryHealth.ps1 -GenerateDetailedReport -AlertThreshold 70
    Generates detailed report and alerts if battery health is below 70%.

.NOTES
    Author: Server Management Team
    Requires: Windows system with battery (laptop, tablet)
    Version: 1.0
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$OutputPath = (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Reports'),

    [Parameter(Mandatory = $false)]
    [switch]$GenerateDetailedReport,

    [Parameter(Mandatory = $false)]
    [int]$AlertThreshold = 80,

    [Parameter(Mandatory = $false)]
    [switch]$ExportToCSV
)

# Validate OutputPath: reject '..' traversal and UNC remote paths before resolution
if ([string]::IsNullOrWhiteSpace($OutputPath) -or
    $OutputPath -match '(^|[\\/])\.\.([\\/]|$)' -or
    $OutputPath -match '^(\\\\|//)') {
    Write-Error "Unsafe OutputPath: $OutputPath. OutputPath must be a local absolute path without '..' traversal."
    exit 1
}
$OutputPath = [System.IO.Path]::GetFullPath($OutputPath)

$RunTimestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$RunId = [Guid]::NewGuid().ToString('N').Substring(0, 8)

Write-Host "`n=== Battery Health Monitor ===" -ForegroundColor Cyan
Write-Host "Computer: $env:COMPUTERNAME" -ForegroundColor Gray
Write-Host "Start Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray

# Create output directory
if (-not (Test-Path -LiteralPath $OutputPath -PathType Container)) {
    New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
}

try {
    # Check if system has a battery
    Write-Host "`nDetecting battery..." -ForegroundColor Yellow

    $battery = Get-WmiObject -Class Win32_Battery -ErrorAction SilentlyContinue

    if (-not $battery) {
        Write-Host "No battery detected. This appears to be a desktop system." -ForegroundColor Yellow
        Write-Host "This script is designed for laptops and tablets with batteries." -ForegroundColor Yellow
        exit 0
    }

    Write-Host "Battery detected: $($battery.Name)" -ForegroundColor Green

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

    # Estimate runtime
    $estimatedRunTime = $battery.EstimatedRunTime
    if ($estimatedRunTime -eq 71582788) {
        $estimatedRunTimeText = "On AC Power / Fully Charged"
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
    Write-Host "Battery Health: $batteryHealth%" -ForegroundColor $(if ([int]$batteryHealth -ge $AlertThreshold) { 'Green' } elseif ([int]$batteryHealth -ge 60) { 'Yellow' } else { 'Red' })
    Write-Host "Wear Level: $wearLevel%" -ForegroundColor $(if ([int]$wearLevel -le 20) { 'Green' } elseif ([int]$wearLevel -le 40) { 'Yellow' } else { 'Red' })
    Write-Host "Estimated Runtime: $estimatedRunTimeText" -ForegroundColor White

    # Alert if below threshold
    if ($batteryHealth -ne "N/A" -and [int]$batteryHealth -lt $AlertThreshold) {
        Write-Host "`n⚠ WARNING: Battery health is below threshold ($AlertThreshold%)!" -ForegroundColor Red
        Write-Host "  Current health: $batteryHealth%" -ForegroundColor Red
        Write-Host "  Recommendation: Consider battery replacement" -ForegroundColor Yellow
    }

    # Get additional battery details from WMI
    $portableBattery = Get-WmiObject -Class Win32_PortableBattery -ErrorAction SilentlyContinue

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
                Write-Host "Battery Age: $batteryAgeYears years" -ForegroundColor $(if ($batteryAgeYears -lt 2) { 'Green' } elseif ($batteryAgeYears -lt 3) { 'Yellow' } else { 'Red' })
            }
            catch {
                Write-Host "Manufacture Date: Unable to parse" -ForegroundColor Gray
            }
        }
    }

    # Generate detailed Windows battery report
    if ($GenerateDetailedReport) {
        Write-Host "`nGenerating detailed battery report..." -ForegroundColor Yellow

        $batteryReportPath = Join-Path -Path $OutputPath -ChildPath "battery-report_${RunTimestamp}_${RunId}.html"

        try {
            $result = Start-Process -FilePath "powercfg" -ArgumentList "/batteryreport", "/output", "`"$batteryReportPath`"" -Wait -NoNewWindow -PassThru

            if ($result.ExitCode -eq 0 -and (Test-Path $batteryReportPath)) {
                Write-Host "Detailed battery report generated: $batteryReportPath" -ForegroundColor Green
            }
            else {
                Write-Warning "Failed to generate detailed battery report"
            }
        }
        catch {
            Write-Warning "Could not generate detailed report: $_"
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
        $batteryRecord | Export-Csv -Path $csvPath -NoTypeInformation -Append
        Write-Host "`nData exported to: $csvPath" -ForegroundColor Green
    }

    # Generate HTML report
    Write-Host "`nGenerating summary report..." -ForegroundColor Yellow
    $htmlPath = Join-Path -Path $OutputPath -ChildPath "BatteryHealthReport_${RunTimestamp}_${RunId}.html"

    $healthColor = if ([int]$batteryHealth -ge 80) { "green" } elseif ([int]$batteryHealth -ge 60) { "orange" } else { "red" }
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
        table { border-collapse: collapse; width: 100%; background-color: white; box-shadow: 0 2px 4px rgba(0,0,0,0.1); margin: 20px 0; }
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
        <tr><td><strong>Estimated Runtime</strong></td><td>$([System.Net.WebUtility]::HtmlEncode("$estimatedRunTimeText"))</td></tr>
    </table>

    <h2>Health Metrics</h2>
    <table>
        <tr><td><strong>Design Capacity</strong></td><td>$designCapacity mWh</td></tr>
        <tr><td><strong>Full Charge Capacity</strong></td><td>$fullChargeCapacity mWh</td></tr>
        <tr><td><strong>Battery Health</strong></td><td style="color: $healthColor; font-weight: bold;">$batteryHealth%</td></tr>
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

    if ($GenerateDetailedReport -and (Test-Path (Join-Path -Path $OutputPath -ChildPath "battery-report_${RunTimestamp}_${RunId}.html"))) {
        $html += @"
    <h2>Additional Reports</h2>
    <p><a href="battery-report_${RunTimestamp}_${RunId}.html">View Detailed Windows Battery Report</a></p>
"@
    }

    $html += @"
</body>
</html>
"@

    $html | Out-File -FilePath $htmlPath -Encoding UTF8
    Write-Host "Summary report saved to: $htmlPath" -ForegroundColor Green

}
catch {
    Write-Error "Error checking battery health: $_"
    Write-Error $_.ScriptStackTrace
    exit 1
}

Write-Host "`nEnd Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray
