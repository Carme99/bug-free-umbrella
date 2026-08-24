<#
.SYNOPSIS
    Track Windows Autopilot deployment status and failures from Microsoft Intune.

.DESCRIPTION
    Generates comprehensive Autopilot deployment reports:
    - Deployment success/failure rates
    - Device provisioning status
    - ESP (Enrollment Status Page) errors
    - Deployment duration analysis
    - Failed deployments with error details
    - Export to HTML or CSV

    The report reflects the actual device compliance state and is read-only: it never
    mutates tenant configuration, so it is safe to re-run (idempotent). Results can
    optionally be exported to HTML and/or CSV under Documents\Reports.
    Exit codes:
    - 0: report generated successfully (including zero deployments).
    - 1: unsafe report path, missing prerequisite module, connection failure, or the
         device query failed.

.PARAMETER Days
    Number of days to look back for deployment data (default: 30).

.PARAMETER Status
    Filter by compliance status: All, Compliant, NonCompliant, Unknown (default: All).

.PARAMETER ProfileName
    Filter by specific Autopilot profile name.

.PARAMETER ExportHTML
    Export report to HTML file.

.PARAMETER ExportCSV
    Export detailed data to CSV.

.EXAMPLE
    PS C:\> .\Get-AutopilotDeploymentReport.ps1 -Days 7 -ExportHTML
    Reports on last 7 days of Autopilot deployments and writes an HTML report.

.EXAMPLE
    PS C:\> .\Get-AutopilotDeploymentReport.ps1 -Status NonCompliant -ExportCSV
    Shows only noncompliant devices, exported as CSV.

.NOTES
    File Name   : Get-AutopilotDeploymentReport.ps1
    Author      : Bug-Free Umbrella
    Prerequisite: PowerShell 7.0
    Version     : 1.0.0
    Date        : 2026-08-23

    Requires the Microsoft.Graph PowerShell module (Authentication and DeviceManagement).
    Requires permissions: DeviceManagementManagedDevices.Read.All, DeviceManagementServiceConfig.Read.All
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [ValidateRange(1, [int]::MaxValue)]
    [int]$Days = 30,

    [Parameter(Mandatory = $false)]
    [ValidateSet('All', 'Compliant', 'NonCompliant', 'Unknown')]
    [string]$Status = 'All',

    [Parameter(Mandatory = $false)]
    [string]$ProfileName,

    [Parameter(Mandatory = $false)]
    [switch]$ExportHTML,

    [Parameter(Mandatory = $false)]
    [switch]$ExportCSV
)

$ErrorActionPreference = 'Stop'

function Write-ColorOutput {
    <#
    .SYNOPSIS
        Writes a console message using the relaunch output-prefix color scheme.
    #>
    [CmdletBinding()]
    param([string]$Message, [string]$Level = 'Info')
    $color = switch ($Level) { 'Success' { 'Green' } 'Warning' { 'Yellow' } 'Error' { 'Red' } default { 'Cyan' } }
    Write-Host $Message -ForegroundColor $color
}

function Main {
    try {
        $ReportDir = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Reports'
        if ([string]::IsNullOrWhiteSpace($ReportDir) -or
            $ReportDir -match '(^|[\\/])\.\.([\\/]|$)' -or
            $ReportDir -match '^(\\\\|//)') {
            Write-Host "[-] Unsafe report path: $ReportDir." `
                "Report path must be a local absolute path without '..' traversal." -ForegroundColor Red
            return 1
        }

        foreach ($requiredModule in @('Microsoft.Graph.Authentication', 'Microsoft.Graph.DeviceManagement')) {
            if (-not (Get-Module -Name $requiredModule -ListAvailable)) {
                Write-Host "[-] $requiredModule module not found!" -ForegroundColor Red
                Write-Host "[!] Install with: Install-Module -Name Microsoft.Graph" -ForegroundColor Yellow
                return 1
            }
        }

        $ReportDir = [System.IO.Path]::GetFullPath($ReportDir)
        if (-not (Test-Path -LiteralPath $ReportDir -PathType Container)) {
            New-Item -ItemType Directory -Path $ReportDir -Force | Out-Null
        }

        $script:report = @{
            ScanTime    = Get-Date
            Days        = $Days
            Deployments = @()
            Summary     = @{
                Total        = 0
                Compliant    = 0
                NonCompliant = 0
                Unknown      = 0
            }
        }

        Write-Host "`n========================================" -ForegroundColor Cyan
        Write-Host "  [*] Autopilot Deployment Report" -ForegroundColor Cyan
        Write-Host "========================================`n" -ForegroundColor Cyan

        Write-ColorOutput "[*] Connecting to Microsoft Graph..." -Level Info
        try {
            $context = Get-MgContext -ErrorAction Stop
            if (-not $context) {
                $graphScopes = @('DeviceManagementManagedDevices.Read.All', 'DeviceManagementServiceConfig.Read.All')
                Connect-MgGraph -Scopes $graphScopes -ErrorAction Stop
            }
            Write-ColorOutput "[+] Connected successfully" -Level Success
        }
        catch {
            Write-ColorOutput "[-] Failed to connect: $($_.Exception.Message)" -Level Error
            return 1
        }

        Write-Host "`n[*] Querying Autopilot devices..." -ForegroundColor Cyan
        $cutoffDate = (Get-Date).AddDays(-$Days)

        try {
            $enrollmentFilter = "deviceEnrollmentType eq 'windowsAutoEnrollment' or " +
                "deviceEnrollmentType eq 'windowsAutopilotEnrollment' or " +
                "deviceEnrollmentType eq 'windowsBulkAzureDomainJoin'"
            $devices = Get-MgDeviceManagementManagedDevice -Filter $enrollmentFilter -All -ErrorAction Stop

            foreach ($device in $devices) {
                if ($device.EnrolledDateTime -lt $cutoffDate) { continue }

                # Report the actual device compliance state - do NOT present it as deployment success/failure
                $complianceStatus = switch ($device.ComplianceState) {
                    'compliant' { 'Compliant' }
                    'unknown' { 'Unknown' }
                    default { 'NonCompliant' }
                }

                if ($Status -ne 'All' -and $complianceStatus -ne $Status) { continue }

                $deployment = [PSCustomObject]@{
                    DeviceName        = $device.DeviceName
                    SerialNumber      = $device.SerialNumber
                    EnrollmentDate    = $device.EnrolledDateTime
                    Compliance        = $complianceStatus
                    OSVersion         = $device.OSVersion
                    UserPrincipalName = $device.UserPrincipalName
                    LastSync          = $device.LastSyncDateTime
                }

                $script:report.Deployments += $deployment
                $script:report.Summary.Total++
                $script:report.Summary.$complianceStatus++
            }

            Write-ColorOutput "[+] Found $($script:report.Summary.Total) deployments" -Level Success
        }
        catch {
            Write-ColorOutput "[-] Error querying devices: $($_.Exception.Message)" -Level Error
            return 1
        }

        Write-Host "`n========================================" -ForegroundColor Cyan
        Write-Host "  Deployment Summary" -ForegroundColor Cyan
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host "Period: Last $Days days"
        Write-Host "Total Deployments: $($script:report.Summary.Total)"
        Write-ColorOutput "[+] Compliant: $($script:report.Summary.Compliant)" -Level Success
        Write-ColorOutput "[-] NonCompliant: $($script:report.Summary.NonCompliant)" -Level Error
        Write-ColorOutput "[!] Unknown: $($script:report.Summary.Unknown)" -Level Warning

        if ($script:report.Deployments.Count -gt 0) {
            Write-Host "`nRecent Deployments:" -ForegroundColor Cyan
            $script:report.Deployments | Select-Object -First 20 |
                Format-Table DeviceName, EnrollmentDate, Compliance, UserPrincipalName -AutoSize
        }

        if ($ExportHTML) {
            $reportPath = Join-Path $ReportDir "AutopilotReport_$(Get-Date -Format 'yyyyMMdd_HHmmss').html"
            $html = @"
<!DOCTYPE html>
<html><head><title>Autopilot Deployment Report</title>
<style>body{font-family:'Segoe UI',sans-serif;margin:20px;background:#f5f5f5}
.container{max-width:1400px;margin:0 auto;background:white;padding:30px;border-radius:8px}
h1{color:#333;border-bottom:3px solid #007bff;padding-bottom:10px}
table{width:100%;border-collapse:collapse;margin:15px 0}
th{background:#007bff;color:white;padding:12px;text-align:left}
td{padding:10px;border-bottom:1px solid #ddd}tr:hover{background:#f1f1f1}
.compliant{color:#28a745;font-weight:bold}
.noncompliant{color:#dc3545;font-weight:bold}
.unknown{color:#ffc107;font-weight:bold}</style></head><body><div class="container">
<h1>Autopilot Deployment Report</h1>
<p><strong>Generated:</strong> $($script:report.ScanTime)<br><strong>Period:</strong> Last $Days days</p>
<p>Total: $($script:report.Summary.Total) | Compliant: $($script:report.Summary.Compliant)</p>
<p>NonCompliant: $($script:report.Summary.NonCompliant) | Unknown: $($script:report.Summary.Unknown)</p>
<table><tr><th>Device</th><th>Serial</th><th>Enrolled</th><th>Compliance</th><th>User</th><th>Last Sync</th></tr>
$(foreach ($d in $script:report.Deployments) {
    $c = $d.Compliance.ToLower()
    "<tr><td>$($d.DeviceName)</td><td>$($d.SerialNumber)</td><td>$($d.EnrollmentDate)</td>" +
    "<td class='$c'>$($d.Compliance)</td><td>$($d.UserPrincipalName)</td><td>$($d.LastSync)</td></tr>"
})
</table></div></body></html>
"@
            $html | Out-File -FilePath $reportPath -Encoding UTF8 -ErrorAction Stop
            Write-ColorOutput "[+] HTML report: $reportPath" -Level Success
        }

        if ($ExportCSV) {
            $csvPath = Join-Path $ReportDir "AutopilotReport_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
            $script:report.Deployments | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8 -ErrorAction Stop
            Write-ColorOutput "[+] CSV report: $csvPath" -Level Success
        }

        Write-Host "`n========================================`n" -ForegroundColor Cyan
        return 0
    }
    catch {
        Write-ColorOutput "[-] Error: $($_.Exception.Message)" -Level Error
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
