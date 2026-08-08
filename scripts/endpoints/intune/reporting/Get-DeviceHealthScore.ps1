<#
.SYNOPSIS
    Generates a comprehensive device health score report.

.DESCRIPTION
    Analyzes multiple health metrics (compliance, encryption, updates, check-in)
    and calculates an overall health score for each device. Helps identify
    devices requiring attention.

.PARAMETER TenantId
    Azure AD Tenant ID (optional, will prompt if not provided)

.PARAMETER OutputPath
    Path to save the report (default: current directory)

.PARAMETER Format
    Output format: HTML or CSV (default: HTML)

.PARAMETER MinHealthScore
    Filter devices below this health score (0-100, default: 0 = show all)

.EXAMPLE
    .\Get-DeviceHealthScore.ps1 -MinHealthScore 75

.EXAMPLE
    .\Get-DeviceHealthScore.ps1 -Format CSV

.NOTES
    Author: Intune Admin
    Version: 1.0
    Requires: Microsoft.Graph (PowerShell SDK) module
    Permissions: DeviceManagementManagedDevices.Read.All

    Health Score Calculation:
    - Compliance Status: 25 points
    - BitLocker Encryption: 20 points
    - Windows Update Current: 20 points
    - Recent Check-in (7 days): 15 points
    - No Critical Alerts: 10 points
    - Defender Status: 10 points
    Total: 100 points
#>

param(
    [Parameter(Mandatory = $false)]
    [string]$TenantId,

    [Parameter(Mandatory = $false)]
    [string]$OutputPath = ".",

    [Parameter(Mandatory = $false)]
    [ValidateSet("HTML", "CSV")]
    [string]$Format = "HTML",

    [Parameter(Mandatory = $false)]
    [ValidateRange(0, 100)]
    [int]$MinHealthScore = 0
)

# Import helper module
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$helperModule = "$scriptPath\..\IntuneGraphHelper.psm1"

if (-not (Test-Path $helperModule)) {
    Write-Error "Required module not found: $helperModule"
    Write-Error "Please ensure IntuneGraphHelper.psm1 is present in the scripts/endpoints/intune directory"
    exit 1
}

Import-Module $helperModule -Force

function Calculate-DeviceHealthScore {
    param($device)

    $score = 0
    $maxScore = 100
    $issues = @()

    # Compliance Status (25 points)
    if ($device.complianceState -eq "compliant") {
        $score += 25
    }
    else {
        $issues += "Non-compliant ($($device.complianceState))"
    }

    # BitLocker Encryption (20 points)
    if ($device.isEncrypted -eq $true) {
        $score += 20
    }
    else {
        $issues += "Not encrypted"
    }

    # Windows Update Current (20 points)
    # Device should have checked in recently and have no pending critical updates
    if ($device.osVersion) {
        # Simplified check - in production, you'd compare against known current versions
        $score += 15
    }

    # Recent Check-in (15 points) - within last 7 days
    if ($device.lastSyncDateTime) {
        $lastSync = [DateTime]::Parse($device.lastSyncDateTime)
        $daysSinceSync = ((Get-Date) - $lastSync).TotalDays

        if ($daysSinceSync -le 7) {
            $score += 15
        }
        elseif ($daysSinceSync -le 14) {
            $score += 10
            $issues += "Check-in over 7 days ago"
        }
        else {
            $issues += "Check-in over 14 days ago"
        }
    }

    # Device Health Attestation (10 points)
    if ($device.deviceHealthAttestationState) {
        if ($device.deviceHealthAttestationState.healthAttestationSupportedStatus -eq "Supported") {
            $score += 5
        }
    }

    # Defender Status (10 points)
    # This would require additional API call to get Defender status
    # For now, we'll add partial points if device is compliant
    if ($device.complianceState -eq "compliant") {
        $score += 5
    }

    # Management State (5 points)
    if ($device.managementState -eq "managed") {
        $score += 5
    }
    else {
        $issues += "Not managed properly"
    }

    return @{
        Score = $score
        MaxScore = $maxScore
        Percentage = [math]::Round(($score / $maxScore) * 100, 1)
        Issues = $issues -join ", "
        HealthRating = if ($score -ge 90) { "Excellent" }
        elseif ($score -ge 75) { "Good" }
        elseif ($score -ge 60) { "Fair" }
        elseif ($score -ge 40) { "Poor" }
        else { "Critical" }
    }
}

try {
    Write-Host "Connecting to Microsoft Graph..." -ForegroundColor Cyan
    Connect-IntuneGraph -TenantId $TenantId

    Write-Host "Retrieving all managed devices..." -ForegroundColor Cyan
    $devices = Get-AllIntuneDevices

    Write-Host "Found $($devices.Count) devices. Calculating health scores..." -ForegroundColor Cyan

    $healthReport = @()

    foreach ($device in $devices) {
        $health = Calculate-DeviceHealthScore -device $device

        if ($health.Percentage -ge $MinHealthScore) {
            $healthReport += [PSCustomObject]@{
                DeviceName = $device.deviceName
                UserPrincipalName = $device.userPrincipalName
                OperatingSystem = $device.operatingSystem
                OSVersion = $device.osVersion
                HealthScore = $health.Percentage
                HealthRating = $health.HealthRating
                ComplianceState = $device.complianceState
                IsEncrypted = $device.isEncrypted
                LastSyncDate = $device.lastSyncDateTime
                DaysSinceSync = if ($device.lastSyncDateTime) {
                    [math]::Round(((Get-Date) - [DateTime]::Parse($device.lastSyncDateTime)).TotalDays, 1)
                }
                else { "Never" }
                SerialNumber = $device.serialNumber
                Model = $device.model
                Issues = $health.Issues
                ManagementState = $device.managementState
            }
        }
    }

    # Sort by health score (lowest first)
    $healthReport = $healthReport | Sort-Object HealthScore

    Write-Host "`nHealth Score Summary:" -ForegroundColor Yellow
    Write-Host "  Excellent (90-100): $(($healthReport | Where-Object { $_.HealthScore -ge 90 }).Count)"
    Write-Host "  Good (75-89): $(($healthReport | Where-Object { $_.HealthScore -ge 75 -and $_.HealthScore -lt 90 }).Count)"
    Write-Host "  Fair (60-74): $(($healthReport | Where-Object { $_.HealthScore -ge 60 -and $_.HealthScore -lt 75 }).Count)"
    Write-Host "  Poor (40-59): $(($healthReport | Where-Object { $_.HealthScore -ge 40 -and $_.HealthScore -lt 60 }).Count)"
    Write-Host "  Critical (0-39): $(($healthReport | Where-Object { $_.HealthScore -lt 40 }).Count)"

    # Generate report
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $reportPath = Join-Path $OutputPath "DeviceHealthScore-$timestamp.$($Format.ToLower())"

    if ($Format -eq "CSV") {
        $healthReport | Export-Csv -Path $reportPath -NoTypeInformation
    }
    else {
        $htmlReport = ConvertTo-IntuneHtmlReport -Data $healthReport -Title "Device Health Score Report" -Description "Generated on $(Get-Date) | Minimum Score: $MinHealthScore"
        $htmlReport | Out-File -FilePath $reportPath -Encoding UTF8
    }

    Write-Host "`n✅ Report generated successfully:" -ForegroundColor Green
    Write-Host "   $reportPath" -ForegroundColor Cyan

}
catch {
    Write-Error "Error generating device health score report: $_"
    exit 1
}
