<#
.SYNOPSIS
    Detailed analysis of application installation failures.

.DESCRIPTION
    Analyzes app deployment failures:
    - Failed installations by app
    - Error codes and descriptions
    - Device-specific failures
    - User-specific failures
    - Installation attempt history
    - Remediation suggestions

.PARAMETER AppName
    Filter by specific application name.

.PARAMETER Days
    Number of days to look back (default: 7).

.PARAMETER Top
    Limit to top N failures.

.PARAMETER ExportHTML
    Export to HTML report.

.PARAMETER ExportCSV
    Export to CSV.

.EXAMPLE
    .\Get-AppInstallErrorReport.ps1 -Days 7 -ExportHTML
    Reports on app failures in last 7 days.

.NOTES
    Requires Microsoft.Graph PowerShell module
    Requires permissions: DeviceManagementApps.Read.All, DeviceManagementManagedDevices.Read.All
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$AppName,

    [Parameter(Mandatory = $false)]
    [int]$Days = 7,

    [Parameter(Mandatory = $false)]
    [int]$Top,

    [Parameter(Mandatory = $false)]
    [switch]$ExportHTML,

    [Parameter(Mandatory = $false)]
    [switch]$ExportCSV
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

#Requires -Modules Microsoft.Graph.Authentication

$script:report = @{
    ScanTime = Get-Date
    Days = $Days
    Failures = @()
    Summary = @{
        TotalFailures = 0
        UniqueApps = 0
        UniqueDevices = 0
    }
}

function Write-ColorOutput {
    param([string]$Message, [string]$Level = 'Info')
    $color = switch ($Level) { 'Success' { 'Green' } 'Warning' { 'Yellow' } 'Error' { 'Red' } default { 'Cyan' } }
    Write-Host $Message -ForegroundColor $color
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  App Installation Error Report" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

Connect-MgGraph -Scopes "DeviceManagementApps.Read.All", "DeviceManagementManagedDevices.Read.All" -NoWelcome

Write-Host "Querying app installation status..." -ForegroundColor Cyan
$cutoffDate = (Get-Date).AddDays(-$Days)

try {
    $apps = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps" -Method GET
    
    foreach ($app in $apps.value) {
        if ($AppName -and $app.displayName -notlike "*$AppName*") { continue }
        
        $status = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/$($app.id)/deviceStatuses" -Method GET
        
        foreach ($deviceStatus in $status.value) {
            if ($deviceStatus.installState -eq 'failed' -and $deviceStatus.lastSyncDateTime -gt $cutoffDate) {
                $failure = [PSCustomObject]@{
                    AppName = $app.displayName
                    DeviceName = $deviceStatus.deviceName
                    UserName = $deviceStatus.userPrincipalName
                    ErrorCode = $deviceStatus.errorCode
                    InstallState = $deviceStatus.installState
                    LastSync = $deviceStatus.lastSyncDateTime
                }
                
                $script:report.Failures += $failure
                $script:report.Summary.TotalFailures++
            }
        }
    }
    
    $script:report.Summary.UniqueApps = ($script:report.Failures | Select-Object -ExpandProperty AppName -Unique).Count
    $script:report.Summary.UniqueDevices = ($script:report.Failures | Select-Object -ExpandProperty DeviceName -Unique).Count
    
    Write-ColorOutput "Found $($script:report.Summary.TotalFailures) failures" -Level Warning
}
catch {
    Write-ColorOutput "Error: $($_.Exception.Message)" -Level Error
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Failure Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-ColorOutput "Total Failures: $($script:report.Summary.TotalFailures)" -Level Warning
Write-Host "Unique Apps: $($script:report.Summary.UniqueApps)"
Write-Host "Unique Devices: $($script:report.Summary.UniqueDevices)"

if ($script:report.Failures.Count -gt 0) {
    Write-Host "`nTop Failures:" -ForegroundColor Cyan
    $displayCount = if ($Top) { $Top } else { 20 }
    $script:report.Failures | Select-Object -First $displayCount | Format-Table AppName, DeviceName, ErrorCode, LastSync -AutoSize
}

if ($ExportHTML) {
    $html = @"
<!DOCTYPE html><html><head><title>App Installation Failures</title>
<style>body{font-family:'Segoe UI',sans-serif;margin:20px}table{width:100%;border-collapse:collapse}
th{background:#007bff;color:white;padding:12px}td{padding:10px;border-bottom:1px solid #ddd}</style></head>
<body><h1>App Installation Failures</h1><p>Period: Last $Days days | Total Failures: $($script:report.Summary.TotalFailures)</p>
<table><tr><th>App</th><th>Device</th><th>User</th><th>Error Code</th><th>Last Sync</th></tr>
$(foreach($f in $script:report.Failures){"<tr><td>$($f.AppName)</td><td>$($f.DeviceName)</td><td>$($f.UserName)</td><td>$($f.ErrorCode)</td><td>$($f.LastSync)</td></tr>"})
</table></body></html>
"@
    $reportPath = "$ReportDir\AppInstallErrors_$(Get-Date -Format 'yyyyMMdd_HHmmss').html"
    $html | Out-File -FilePath $reportPath -Encoding UTF8
    Write-ColorOutput "`nHTML report: $reportPath" -Level Success
}

if ($ExportCSV) {
    $csvPath = "$ReportDir\AppInstallErrors_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
    $script:report.Failures | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
    Write-ColorOutput "CSV report: $csvPath" -Level Success
}

Write-Host "`n========================================`n" -ForegroundColor Cyan
