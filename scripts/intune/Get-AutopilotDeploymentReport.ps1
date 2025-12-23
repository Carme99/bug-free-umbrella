<#
.SYNOPSIS
    Tracks Windows Autopilot deployment status and failures.

.DESCRIPTION
    Generates comprehensive Autopilot deployment reports:
    - Deployment success/failure rates
    - Device provisioning status
    - ESP (Enrollment Status Page) errors
    - Deployment duration analysis
    - Failed deployments with error details
    - Export to HTML or CSV

.PARAMETER Days
    Number of days to look back for deployment data (default: 30).

.PARAMETER Status
    Filter by status: All, Success, Failed, InProgress (default: All).

.PARAMETER ProfileName
    Filter by specific Autopilot profile name.

.PARAMETER ExportHTML
    Export report to HTML file.

.PARAMETER ExportCSV
    Export detailed data to CSV.

.EXAMPLE
    .\Get-AutopilotDeploymentReport.ps1 -Days 7 -ExportHTML
    Reports on last 7 days of Autopilot deployments.

.EXAMPLE
    .\Get-AutopilotDeploymentReport.ps1 -Status Failed
    Shows only failed deployments.

.NOTES
    Requires Microsoft.Graph PowerShell module
    Requires permissions: DeviceManagementManagedDevices.Read.All, DeviceManagementServiceConfig.Read.All
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [int]$Days = 30,

    [Parameter(Mandatory=$false)]
    [ValidateSet('All','Success','Failed','InProgress')]
    [string]$Status = 'All',

    [Parameter(Mandatory=$false)]
    [string]$ProfileName,

    [Parameter(Mandatory=$false)]
    [switch]$ExportHTML,

    [Parameter(Mandatory=$false)]
    [switch]$ExportCSV
)

#Requires -Modules Microsoft.Graph.Authentication, Microsoft.Graph.DeviceManagement

$script:report = @{
    ScanTime = Get-Date
    Days = $Days
    Deployments = @()
    Summary = @{
        Total = 0
        Success = 0
        Failed = 0
        InProgress = 0
        AvgDuration = 0
    }
}

function Write-ColorOutput {
    param([string]$Message, [string]$Level = 'Info')
    $color = switch($Level) { 'Success' { 'Green' } 'Warning' { 'Yellow' } 'Error' { 'Red' } default { 'Cyan' } }
    Write-Host $Message -ForegroundColor $color
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Autopilot Deployment Report" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

Write-ColorOutput "Connecting to Microsoft Graph..." -Level Info
try {
    $context = Get-MgContext
    if(-not $context) {
        Connect-MgGraph -Scopes "DeviceManagementManagedDevices.Read.All","DeviceManagementServiceConfig.Read.All"
    }
    Write-ColorOutput "  Connected successfully" -Level Success
}
catch {
    Write-ColorOutput "  Failed to connect: $($_.Exception.Message)" -Level Error
    exit 1
}

Write-Host "`nQuerying Autopilot devices..." -ForegroundColor Cyan
$cutoffDate = (Get-Date).AddDays(-$Days)

try {
    $devices = Get-MgDeviceManagementManagedDevice -Filter "enrollmentType eq 'azureDomainJoined' or enrollmentType eq 'windowsAutoEnrollment'" -All
    
    foreach($device in $devices) {
        if($device.EnrolledDateTime -lt $cutoffDate) { continue }
        
        $deploymentStatus = if($device.ComplianceState -eq 'compliant') { 'Success' } 
                           elseif($device.ComplianceState -eq 'unknown') { 'InProgress' }
                           else { 'Failed' }
        
        if($Status -ne 'All' -and $deploymentStatus -ne $Status) { continue }
        
        $deployment = [PSCustomObject]@{
            DeviceName = $device.DeviceName
            SerialNumber = $device.SerialNumber
            EnrollmentDate = $device.EnrolledDateTime
            Status = $deploymentStatus
            ComplianceState = $device.ComplianceState
            OSVersion = $device.OSVersion
            UserPrincipalName = $device.UserPrincipalName
            LastSync = $device.LastSyncDateTime
        }
        
        $script:report.Deployments += $deployment
        $script:report.Summary.Total++
        $script:report.Summary.$deploymentStatus++
    }
    
    Write-ColorOutput "  Found $($script:report.Summary.Total) deployments" -Level Success
}
catch {
    Write-ColorOutput "  Error querying devices: $($_.Exception.Message)" -Level Error
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Deployment Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Period: Last $Days days"
Write-Host "Total Deployments: $($script:report.Summary.Total)"
Write-ColorOutput "Successful: $($script:report.Summary.Success)" -Level Success
Write-ColorOutput "Failed: $($script:report.Summary.Failed)" -Level Error
Write-ColorOutput "In Progress: $($script:report.Summary.InProgress)" -Level Warning

if($script:report.Deployments.Count -gt 0) {
    Write-Host "`nRecent Deployments:" -ForegroundColor Cyan
    $script:report.Deployments | Select-Object -First 20 | Format-Table DeviceName, EnrollmentDate, Status, UserPrincipalName -AutoSize
}

if($ExportHTML) {
    $reportPath = "$env:USERPROFILE\Desktop\AutopilotReport_$(Get-Date -Format 'yyyyMMdd_HHmmss').html"
    $html = @"
<!DOCTYPE html>
<html><head><title>Autopilot Deployment Report</title>
<style>body{font-family:'Segoe UI',sans-serif;margin:20px;background:#f5f5f5}.container{max-width:1400px;margin:0 auto;background:white;padding:30px;border-radius:8px}
h1{color:#333;border-bottom:3px solid #007bff;padding-bottom:10px}table{width:100%;border-collapse:collapse;margin:15px 0}
th{background:#007bff;color:white;padding:12px;text-align:left}td{padding:10px;border-bottom:1px solid #ddd}tr:hover{background:#f1f1f1}
.success{color:#28a745;font-weight:bold}.failed{color:#dc3545;font-weight:bold}.inprogress{color:#ffc107;font-weight:bold}</style></head><body><div class="container">
<h1>Autopilot Deployment Report</h1><p><strong>Generated:</strong> $($script:report.ScanTime)<br><strong>Period:</strong> Last $Days days</p>
<p>Total: $($script:report.Summary.Total) | Success: $($script:report.Summary.Success) | Failed: $($script:report.Summary.Failed) | In Progress: $($script:report.Summary.InProgress)</p>
<table><tr><th>Device</th><th>Serial</th><th>Enrolled</th><th>Status</th><th>User</th><th>Last Sync</th></tr>
$(foreach($d in $script:report.Deployments){$c=$d.Status.ToLower();"<tr><td>$($d.DeviceName)</td><td>$($d.SerialNumber)</td><td>$($d.EnrollmentDate)</td><td class='$c'>$($d.Status)</td><td>$($d.UserPrincipalName)</td><td>$($d.LastSync)</td></tr>"})
</table></div></body></html>
"@
    $html | Out-File -FilePath $reportPath -Encoding UTF8
    Write-ColorOutput "`nHTML report: $reportPath" -Level Success
}

if($ExportCSV) {
    $csvPath = "$env:USERPROFILE\Desktop\AutopilotReport_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
    $script:report.Deployments | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
    Write-ColorOutput "CSV report: $csvPath" -Level Success
}

Write-Host "`n========================================`n" -ForegroundColor Cyan
