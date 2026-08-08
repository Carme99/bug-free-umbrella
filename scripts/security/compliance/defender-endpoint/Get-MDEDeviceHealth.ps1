<#
.SYNOPSIS
    Comprehensive Microsoft Defender for Endpoint device health and security monitoring.

.DESCRIPTION
    Monitors MDE-managed devices including:
    - Device onboarding status and sensor health
    - Threat and vulnerability exposure scores
    - Active alerts and incidents
    - Security recommendations compliance
    - Antivirus/EDR sensor status
    - Missing security updates
    - Device risk levels
    - Isolation status

.PARAMETER TenantId
    Azure AD Tenant ID

.PARAMETER IncludeVulnerabilities
    Include vulnerability assessment data

.PARAMETER IncludeRecommendations
    Include security recommendations

.PARAMETER RiskLevelFilter
    Filter by risk level: 'High', 'Medium', 'Low', 'All'. Default: 'All'

.PARAMETER OutputFormat
    Output format: 'Console', 'HTML', 'CSV', or 'JSON'. Default: 'HTML'

.PARAMETER OutputPath
    Path for output files. Default: MyDocuments\Reports

.EXAMPLE
    Connect-AzAccount
    .\Get-MDEDeviceHealth.ps1 -TenantId "tenant-id"

.EXAMPLE
    .\Get-MDEDeviceHealth.ps1 -TenantId "tenant-id" `
        -IncludeVulnerabilities `
        -IncludeRecommendations `
        -RiskLevelFilter "High"

.NOTES
    Author: IT Operations
    Version: 1.0.0
    Requires: PowerShell 5.1+, Microsoft.Graph or API access to MDE

    WARNING: This script has not been thoroughly tested in production environments.
    Please test in a non-production environment first and validate results before relying on this data.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$TenantId,

    [Parameter(Mandatory = $false)]
    [switch]$IncludeVulnerabilities,

    [Parameter(Mandatory = $false)]
    [switch]$IncludeRecommendations,

    [Parameter(Mandatory = $false)]
    [ValidateSet('High', 'Medium', 'Low', 'All')]
    [string]$RiskLevelFilter = 'All',

    [Parameter(Mandatory = $false)]
    [ValidateSet('Console', 'HTML', 'CSV', 'JSON')]
    [string]$OutputFormat = 'HTML',

    [Parameter(Mandatory = $false)]
    [string]$OutputPath = (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Reports')
)

# Validate OutputPath: reject '..' traversal and UNC remote paths before resolution
if ([string]::IsNullOrWhiteSpace($OutputPath) -or
    $OutputPath -match '(^|[\\/])\.\.([\\/]|$)' -or
    $OutputPath -match '^(\\\\|//)') {
    Write-Error "Unsafe OutputPath: $OutputPath. OutputPath must be a local absolute path without '..' traversal."
    exit 1
}
$OutputPath = [System.IO.Path]::GetFullPath($OutputPath)
if (-not (Test-Path -LiteralPath $OutputPath -PathType Container)) {
    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
}

$RunTimestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$RunId = [Guid]::NewGuid().ToString('N').Substring(0, 8)

$results = @{
    Timestamp = Get-Date
    TenantId = $TenantId
    Devices = @()
    Alerts = @()
    Vulnerabilities = @()
    Recommendations = @()
    Summary = @{}
}

Write-Host "Monitoring Microsoft Defender for Endpoint devices..." -ForegroundColor Cyan

# WARNING: This script is a FRAMEWORK TEMPLATE and requires implementation of actual MDE API calls
# It will NOT produce real data without Microsoft Graph API or Microsoft Defender for Endpoint API integration
#
# Required implementation:
# - Microsoft Graph API: DeviceManagement.Read.All permission
# - Or Microsoft Defender for Endpoint API: Machine.Read.All / Machine.ReadWrite.All permission
#
# Example API call:
# $headers = @{ Authorization = "Bearer $token" }
# $devices = Invoke-RestMethod -Uri "https://api.security.microsoft.com/api/machines" -Headers $headers

try {
    Write-Host "`nWARNING: This script is a framework template - no live API data available" -ForegroundColor Yellow
    Write-Host "`nAuthenticating to Microsoft Defender API..." -ForegroundColor Yellow
    Write-Host "Note: Full implementation requires Microsoft Graph or Microsoft Defender for Endpoint API access" -ForegroundColor Gray

    # Simulated device health analysis
    Write-Host "`nRetrieving device inventory..." -ForegroundColor Yellow

    # Sample structure for device data - REPLACE with actual API calls
    $sampleDevice = @{
        ComputerDnsName = "Example-Device"
        OsPlatform = "Windows10"
        OSVersion = "21H2"
        HealthStatus = "Active"
        RiskScore = "High"
        ExposureLevel = "Medium"
        FirstSeen = (Get-Date).AddDays(-30)
        LastSeen = Get-Date
        OnboardingStatus = "Onboarded"
        DefenderAvStatus = "Updated"
        SensorHealthState = "Active"
        ActiveAlerts = 3
        HighSeverityAlerts = 1
    }

    Write-Host "MDE API framework ready" -ForegroundColor Green
    Write-Host "WARNING: Running with sample data only. Implement API calls for production use." -ForegroundColor Red

    # Alert analysis structure
    $sampleAlert = @{
        AlertId = "alert-123"
        Title = "Suspicious Process Execution"
        Severity = "High"
        Status = "New"
        Category = "Execution"
        DetectionSource = "EDR"
        MachineId = "machine-123"
        FirstActivity = Get-Date
    }

    # Vulnerability structure
    if ($IncludeVulnerabilities) {
        Write-Host "`nVulnerability assessment framework ready" -ForegroundColor Yellow

        $sampleVuln = @{
            CveId = "CVE-2024-0001"
            Severity = "Critical"
            ExploitAvailable = $true
            ExposedMachines = 10
            PublishedDate = (Get-Date).AddDays(-15)
        }
    }

    # Security recommendations structure
    if ($IncludeRecommendations) {
        Write-Host "`nSecurity recommendations framework ready" -ForegroundColor Yellow

        $sampleRecommendation = @{
            RecommendationName = "Enable attack surface reduction rules"
            Category = "Application and browser"
            RemediationType = "ConfigurationChange"
            Status = "Active"
            ExposedDevices = 25
            Severity = "Medium"
        }
    }

} catch {
    Write-Error "Error accessing Defender for Endpoint: $($_.Exception.Message)"
}

# Sample summary
$results.Summary = @{
    TotalDevices = 0
    OnboardedDevices = 0
    HighRiskDevices = 0
    ActiveAlerts = 0
    CriticalVulnerabilities = 0
    PendingRecommendations = 0
    HealthStatus = "Framework Ready"
}

# Output
switch ($OutputFormat) {
    'Console' {
        Write-Host "`n=== Microsoft Defender for Endpoint Summary ===" -ForegroundColor Cyan
        Write-Host "Tenant ID: $TenantId" -ForegroundColor White
        Write-Host "Status: MDE monitoring framework ready" -ForegroundColor Green
        Write-Host "`nNext Steps:" -ForegroundColor Yellow
        Write-Host "1. Configure Microsoft Graph API access" -ForegroundColor White
        Write-Host "2. Grant DeviceManagement.Read.All permission (or Machine.Read.All / Machine.ReadWrite.All for the Microsoft Defender for Endpoint API)" -ForegroundColor White
        Write-Host "3. Implement API authentication" -ForegroundColor White
        Write-Host "4. Connect to https://api.security.microsoft.com" -ForegroundColor White
    }

    'HTML' {
        $htmlFile = Join-Path $OutputPath "MDE-DeviceHealth-${RunTimestamp}_${RunId}.html"

        $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>Microsoft Defender for Endpoint - Device Health</title>
    <style>
        body { font-family: 'Segoe UI', Arial, sans-serif; margin: 20px; background-color: #f5f5f5; }
        h1 { color: #d13438; border-bottom: 3px solid #d13438; padding-bottom: 10px; }
        .summary { background: white; padding: 20px; border-radius: 8px; margin-bottom: 20px; }
        .info { background: #d1ecf1; padding: 15px; border-left: 5px solid #0c5460; margin: 20px 0; }
        table { border-collapse: collapse; width: 100%; background: white; margin: 10px 0; }
        th { background: #d13438; color: white; padding: 10px; }
        td { padding: 8px; border-bottom: 1px solid #ddd; }
    </style>
</head>
<body>
    <h1>Microsoft Defender for Endpoint - Device Health Report</h1>
    <div class="summary">
        <strong>Tenant ID:</strong> $([System.Net.WebUtility]::HtmlEncode("$TenantId"))<br>
        <strong>Generated:</strong> $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | <strong>Run ID:</strong> $RunId<br>
        <strong>Status:</strong> MDE Monitoring Framework Ready
    </div>

    <div class="info">
        <h3>Implementation Notes</h3>
        <p>This script provides the framework for MDE device monitoring. To enable live data:</p>
        <ol>
            <li>Register an Azure AD application</li>
            <li>Grant <strong>DeviceManagement.Read.All</strong> (Microsoft Graph) or <strong>Machine.Read.All</strong> / <strong>Machine.ReadWrite.All</strong> (Microsoft Defender for Endpoint API) permission</li>
            <li>Implement OAuth2 authentication</li>
            <li>Connect to Microsoft Defender for Endpoint API: <code>https://api.security.microsoft.com</code></li>
        </ol>
        <p><strong>Sample API Endpoints:</strong></p>
        <ul>
            <li>Devices: <code>GET /api/machines</code></li>
            <li>Alerts: <code>GET /api/alerts</code></li>
            <li>Vulnerabilities: <code>GET /api/vulnerabilities</code></li>
            <li>Recommendations: <code>GET /api/recommendations</code></li>
        </ul>
    </div>

    <p style="margin-top: 30px; text-align: center; color: #666; font-size: 12px;">
        <strong>Note:</strong> This report has not been thoroughly tested. Full implementation requires API access.<br>
        Generated by Get-MDEDeviceHealth.ps1
    </p>
</body>
</html>
"@

        $html | Out-File -FilePath $htmlFile -Encoding UTF8
        Write-Host "`nHTML report saved to: $htmlFile" -ForegroundColor Green
    }

    'JSON' {
        $jsonFile = Join-Path $OutputPath "MDE-DeviceHealth-${RunTimestamp}_${RunId}.json"
        $results | ConvertTo-Json -Depth 10 | Out-File -FilePath $jsonFile
        Write-Host "`nJSON framework saved to: $jsonFile" -ForegroundColor Green
    }
}

Write-Host "`nMDE device health framework ready!" -ForegroundColor Green
Write-Host "Implement API authentication to enable live data monitoring." -ForegroundColor Yellow
