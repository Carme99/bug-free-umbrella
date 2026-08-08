<#
.SYNOPSIS
    TEMPLATE: winget-managed application update compliance report (SAMPLE DATA).

.DESCRIPTION
    This is a FORMATTING TEMPLATE for a winget application compliance report.
    It does NOT query real winget inventory - the sample data below is generated
    with Get-Random and is provided ONLY so you can preview the report layout.

    To build a real report you must first collect per-device winget inventory
    (e.g. via Intune proactive remediations writing to custom attributes or
    Log Analytics), then replace Get-SampleComplianceData with a query against
    that data source.

    Output files are suffixed -SAMPLE so they cannot be mistaken for real
    compliance data.

.PARAMETER TenantId
    Azure AD Tenant ID (optional if already connected).

.PARAMETER ApplicationFilter
    Filter by specific application name or winget ID (supports wildcards).

.PARAMETER IncludeUpToDate
    Include applications that are up to date in the report.

.PARAMETER ExportHTML
    Export report to HTML file.

.PARAMETER ExportCSV
    Export detailed data to CSV.

.PARAMETER Top
    Limit to top N devices (for testing).

.EXAMPLE
    .\Get-WingetUpdateCompliance.ps1 -ExportHTML
    Generates compliance report for all devices and exports to HTML.

.EXAMPLE
    .\Get-WingetUpdateCompliance.ps1 -ApplicationFilter "*Chrome*" -ExportCSV
    Reports on Chrome update compliance across all devices.

.EXAMPLE
    .\Get-WingetUpdateCompliance.ps1 -Top 50 -IncludeUpToDate
    Tests with first 50 devices, including up-to-date apps.

.NOTES
    Requires Microsoft.Graph PowerShell module
    Requires permissions: DeviceManagementManagedDevices.Read.All
    This script relies on Intune custom inventory data
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$TenantId,

    [Parameter(Mandatory=$false)]
    [string]$ApplicationFilter,

    [Parameter(Mandatory=$false)]
    [switch]$IncludeUpToDate,

    [Parameter(Mandatory=$false)]
    [switch]$ExportHTML,

    [Parameter(Mandatory=$false)]
    [switch]$ExportCSV,

    [Parameter(Mandatory=$false)]
    [int]$Top
)

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

#Requires -Modules Microsoft.Graph.Authentication, Microsoft.Graph.DeviceManagement

$script:report = @{
    ScanTime = Get-Date
    TotalDevices = 0
    TotalApps = 0
    OutdatedApps = 0
    UpToDateApps = 0
    Applications = @()
    DeviceSummary = @()
}

function Write-ColorOutput {
    param([string]$Message, [string]$Level = 'Info')
    $color = switch($Level) {
        'Success' { 'Green' }
        'Warning' { 'Yellow' }
        'Error' { 'Red' }
        default { 'Cyan' }
    }
    Write-Host $Message -ForegroundColor $color
}

function Connect-GraphAPI {
    Write-Host "Connecting to Microsoft Graph..." -ForegroundColor Cyan

    try {
        $context = Get-MgContext
        if(-not $context) {
            $params = @{
                Scopes = @(
                    "DeviceManagementManagedDevices.Read.All",
                    "DeviceManagementConfiguration.Read.All"
                )
            }
            if($TenantId) { $params.TenantId = $TenantId }

            Connect-MgGraph @params
            Write-ColorOutput "  Connected successfully" -Level Success
        } else {
            Write-ColorOutput "  Already connected to tenant: $($context.TenantId)" -Level Success
        }
    }
    catch {
        Write-ColorOutput "  Failed to connect: $($_.Exception.Message)" -Level Error
        exit 1
    }
}

function Get-DeviceWingetData {
    Write-Host "`nQuerying Intune devices..." -ForegroundColor Cyan

    try {
        $filter = "operatingSystem eq 'Windows'"
        $params = @{
            Filter = $filter
            All = $true
        }

        if($Top) {
            $params.Remove('All')
            $params.Top = $Top
        }

        $devices = Get-MgDeviceManagementManagedDevice @params
        $script:report.TotalDevices = $devices.Count

        Write-ColorOutput "  Found $($devices.Count) Windows devices" -Level Success

        # NOTE: This is a simplified version. In production, you would:
        # 1. Use Intune custom compliance/detection scripts to collect winget data
        # 2. Store data in device custom attributes or Log Analytics
        # 3. Query that data here

        Write-ColorOutput "`n  Note: Full implementation requires custom inventory collection" -Level Warning
        Write-ColorOutput "  This script provides the framework for winget compliance reporting" -Level Info

        return $devices
    }
    catch {
        Write-ColorOutput "  Error querying devices: $($_.Exception.Message)" -Level Error
        return @()
    }
}

function Get-SampleComplianceData {
    # SAMPLE DATA - NOT REAL COMPLIANCE DATA
    Write-Host "`n⚠ ⚠ ⚠  WARNING: SAMPLE DATA  ⚠ ⚠ ⚠" -ForegroundColor Red
    Write-Host "  This report contains FABRICATED sample data (Get-Random) for" -ForegroundColor Red
    Write-Host "  formatting/preview purposes ONLY. It is NOT real compliance data." -ForegroundColor Red
    Write-Host "  Do NOT use this output for decisions, reporting, or audits." -ForegroundColor Red
    Write-Host "  Replace Get-SampleComplianceData with a real inventory query before use." -ForegroundColor Red
    Write-Host "`nGenerating sample compliance data..." -ForegroundColor Yellow
    Write-Host "  (In production, this would query actual device inventory)" -ForegroundColor Gray

    $sampleApps = @(
        @{App="Google Chrome"; Current="120.0.6099"; Available="121.0.6167"; Status="Outdated"}
        @{App="Microsoft Teams"; Current="1.6.00.36361"; Available="1.7.00.1234"; Status="Outdated"}
        @{App="7-Zip"; Current="23.01"; Available="24.01"; Status="Outdated"}
        @{App="Visual Studio Code"; Current="1.85.0"; Available="1.85.0"; Status="UpToDate"}
        @{App="Adobe Reader"; Current="23.008.20421"; Available="24.001.20604"; Status="Outdated"}
    )

    foreach($app in $sampleApps) {
        $appData = [PSCustomObject]@{
            ApplicationName = $app.App
            InstalledVersion = $app.Current
            AvailableVersion = $app.Available
            Status = $app.Status
            DeviceCount = Get-Random -Minimum 50 -Maximum 500
            OutdatedCount = if($app.Status -eq "Outdated") { Get-Random -Minimum 20 -Maximum 200 } else { 0 }
        }

        if($ApplicationFilter) {
            if($appData.ApplicationName -like $ApplicationFilter) {
                $script:report.Applications += $appData
            }
        }
        elseif($app.Status -eq "Outdated" -or $IncludeUpToDate) {
            $script:report.Applications += $appData
        }

        if($app.Status -eq "Outdated") {
            $script:report.OutdatedApps++
        } else {
            $script:report.UpToDateApps++
        }
    }

    $script:report.TotalApps = $script:report.Applications.Count
}

function Show-Summary {
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "  Winget Update Compliance Summary" -ForegroundColor Cyan
    Write-Host "  (SAMPLE DATA - FORMATTING PREVIEW ONLY)" -ForegroundColor Red
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Scan Time: $($script:report.ScanTime)"
    Write-Host "Total Devices Scanned: $($script:report.TotalDevices)"
    Write-Host "Total Applications: $($script:report.TotalApps)"
    Write-ColorOutput "Outdated Applications: $($script:report.OutdatedApps)" -Level Warning
    Write-ColorOutput "Up-to-Date Applications: $($script:report.UpToDateApps)" -Level Success

    if($script:report.Applications.Count -gt 0) {
        Write-Host "`nApplication Update Status:" -ForegroundColor Cyan
        $script:report.Applications | Format-Table ApplicationName, InstalledVersion, AvailableVersion, Status, DeviceCount, OutdatedCount -AutoSize
    }

    Write-Host "`n========================================`n" -ForegroundColor Cyan
}

function Export-HTMLReport {
    $reportPath = "$ReportDir\WingetCompliance_SAMPLE_$(Get-Date -Format 'yyyyMMdd_HHmmss').html"

    $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>Winget Update Compliance Report (SAMPLE)</title>
    <style>
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; margin: 20px; background-color: #f5f5f5; }
        .container { max-width: 1400px; margin: 0 auto; background-color: white; padding: 30px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        h1 { color: #333; border-bottom: 3px solid #007bff; padding-bottom: 10px; }
        .summary { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 15px; margin: 20px 0; }
        .metric { background-color: #f8f9fa; padding: 20px; border-radius: 4px; border-left: 4px solid #007bff; text-align: center; }
        .metric.warning { border-left-color: #ffc107; }
        .metric.success { border-left-color: #28a745; }
        .metric-value { font-size: 2em; font-weight: bold; color: #007bff; }
        .metric.warning .metric-value { color: #ffc107; }
        .metric.success .metric-value { color: #28a745; }
        table { width: 100%; border-collapse: collapse; margin: 15px 0; }
        th { background-color: #007bff; color: white; padding: 12px; text-align: left; }
        td { padding: 10px; border-bottom: 1px solid #ddd; }
        tr:hover { background-color: #f1f1f1; }
        .outdated { background-color: #fff3cd; }
        .uptodate { background-color: #d4edda; }
        .footer { margin-top: 30px; padding-top: 20px; border-top: 1px solid #ddd; color: #777; font-size: 0.9em; }
    </style>
</head>
<body>
    <div class="container">
        <h1>Winget Update Compliance Report (SAMPLE)</h1>
        <p><strong>Generated:</strong> $($script:report.ScanTime)</p>
        <p style="color:#dc3545;font-weight:bold">⚠ SAMPLE DATA - formatting preview only. Not real compliance data.</p>

        <div class="summary">
            <div class="metric">
                <div class="metric-value">$($script:report.TotalDevices)</div>
                <div>Devices Scanned</div>
            </div>
            <div class="metric">
                <div class="metric-value">$($script:report.TotalApps)</div>
                <div>Applications Tracked</div>
            </div>
            <div class="metric warning">
                <div class="metric-value">$($script:report.OutdatedApps)</div>
                <div>Outdated Apps</div>
            </div>
            <div class="metric success">
                <div class="metric-value">$($script:report.UpToDateApps)</div>
                <div>Up-to-Date Apps</div>
            </div>
        </div>

        <h2>Application Update Status</h2>
        <table>
            <tr>
                <th>Application</th>
                <th>Installed Version</th>
                <th>Available Version</th>
                <th>Status</th>
                <th>Total Devices</th>
                <th>Outdated Devices</th>
            </tr>
            $(foreach($app in $script:report.Applications) {
                $rowClass = if($app.Status -eq "Outdated") { "outdated" } else { "uptodate" }
                "<tr class='$rowClass'>
                    <td>$($app.ApplicationName)</td>
                    <td>$($app.InstalledVersion)</td>
                    <td>$($app.AvailableVersion)</td>
                    <td>$($app.Status)</td>
                    <td>$($app.DeviceCount)</td>
                    <td>$($app.OutdatedCount)</td>
                </tr>"
            })
        </table>

        <div class="footer">
            Report generated by Get-WingetUpdateCompliance.ps1<br>
            <strong>Note:</strong> This report uses sample data. Full implementation requires custom inventory collection via Intune.
        </div>
    </div>
</body>
</html>
"@

    $html | Out-File -FilePath $reportPath -Encoding UTF8
    Write-ColorOutput "`nHTML report exported to: $reportPath" -Level Success
}

function Export-CSVReport {
    $reportPath = "$ReportDir\WingetCompliance_SAMPLE_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"

    $script:report.Applications | Export-Csv -Path $reportPath -NoTypeInformation -Encoding UTF8
    Write-ColorOutput "CSV report exported to: $reportPath" -Level Success
}

# Main execution
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Winget Update Compliance Reporter" -ForegroundColor Cyan
Write-Host "  TEMPLATE - OUTPUTS SAMPLE DATA ONLY" -ForegroundColor Yellow
Write-Host "========================================`n" -ForegroundColor Cyan

Connect-GraphAPI
Get-DeviceWingetData

# Generate sample data (replace with actual inventory query in production)
Get-SampleComplianceData

Show-Summary

if($ExportHTML) {
    Write-Host "Generating HTML report..." -ForegroundColor Cyan
    Export-HTMLReport
}

if($ExportCSV) {
    Write-Host "Generating CSV report..." -ForegroundColor Cyan
    Export-CSVReport
}

Write-Host "⚠ This script is a TEMPLATE and outputs SAMPLE DATA for formatting purposes only." -ForegroundColor Red
Write-Host "  Do not use these numbers for decisions, reporting, or audits." -ForegroundColor Red
Write-Host "  For real compliance data, implement custom inventory collection via Intune" -ForegroundColor Yellow
Write-Host "  proactive remediations and replace Get-SampleComplianceData with a real query." -ForegroundColor Yellow
Write-Host "`n========================================`n" -ForegroundColor Cyan
