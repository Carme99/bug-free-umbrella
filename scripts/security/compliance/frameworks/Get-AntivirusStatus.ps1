<#
.SYNOPSIS
    Checks the status of antivirus and endpoint protection on Windows devices.

.DESCRIPTION
    This script provides comprehensive antivirus and endpoint protection status including:
    - Windows Defender/Microsoft Defender status
    - Third-party antivirus detection
    - Real-time protection status
    - Signature/definition update status
    - Scan history and last scan time
    - Threat detection history
    - Firewall status
    - Export to HTML and CSV formats

.PARAMETER OutputFormat
    Specifies the output format: None, HTML, CSV, or All. Default is None (console only).

.PARAMETER OutputPath
    Path to save the output file(s). Default is current directory.

.PARAMETER CheckThirdParty
    Check for third-party antivirus software. Default is $true.

.EXAMPLE
    .\Get-AntivirusStatus.ps1 -OutputFormat HTML -OutputPath "C:\Reports"

    Generates an HTML report of antivirus status.

.EXAMPLE
    .\Get-AntivirusStatus.ps1 -CheckThirdParty

    Checks both Windows Defender and third-party antivirus solutions.

.NOTES
    File Name      : Get-AntivirusStatus.ps1
    Requires       : PowerShell 5.1+, Administrator privileges recommended
    Version        : 1.0
#>

[CmdletBinding()]
param(
    [Parameter()]
    [ValidateSet('None', 'HTML', 'CSV', 'All')]
    [string]$OutputFormat = 'None',

    [Parameter()]
    [string]$OutputPath = (Get-Location),

    [Parameter()]
    [bool]$CheckThirdParty = $true
)

Write-Host "=== Antivirus & Endpoint Protection Status ===" -ForegroundColor Cyan

# Initialize results
$avStatus = @{
    ComputerName = $env:COMPUTERNAME
    ScanTime = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    WindowsDefender = @{}
    ThirdPartyAV = @()
    Firewall = @{}
    OverallStatus = "Unknown"
    Issues = @()
}

#region Windows Defender Status
Write-Host "`nChecking Windows Defender status..." -ForegroundColor Yellow

try {
    # Get Windows Defender status using Get-MpComputerStatus
    $defenderStatus = Get-MpComputerStatus -ErrorAction SilentlyContinue

    if ($defenderStatus) {
        $avStatus.WindowsDefender = @{
            Enabled = $defenderStatus.AntivirusEnabled
            RealTimeProtectionEnabled = $defenderStatus.RealTimeProtectionEnabled
            BehaviorMonitorEnabled = $defenderStatus.BehaviorMonitorEnabled
            IoavProtectionEnabled = $defenderStatus.IoavProtectionEnabled
            OnAccessProtectionEnabled = $defenderStatus.OnAccessProtectionEnabled
            AntivirusSignatureVersion = $defenderStatus.AntivirusSignatureVersion
            AntivirusSignatureAge = $defenderStatus.AntivirusSignatureAge
            AntivirusSignatureLastUpdated = $defenderStatus.AntivirusSignatureLastUpdated
            QuickScanAge = $defenderStatus.QuickScanAge
            FullScanAge = $defenderStatus.FullScanAge
            QuickScanEndTime = $defenderStatus.QuickScanEndTime
            FullScanEndTime = $defenderStatus.FullScanEndTime
        }

        # Check for issues
        if (-not $defenderStatus.AntivirusEnabled) {
            $avStatus.Issues += "Windows Defender is DISABLED"
        }
        if (-not $defenderStatus.RealTimeProtectionEnabled) {
            $avStatus.Issues += "Real-Time Protection is DISABLED"
        }
        if ($defenderStatus.AntivirusSignatureAge -gt 7) {
            $avStatus.Issues += "Antivirus signatures are OUTDATED ($($defenderStatus.AntivirusSignatureAge) days old)"
        }
        if ($defenderStatus.QuickScanAge -gt 7) {
            $avStatus.Issues += "Quick scan hasn't run in $($defenderStatus.QuickScanAge) days"
        }

        # Get threat history
        try {
            $threats = Get-MpThreatDetection -ErrorAction SilentlyContinue | Select-Object -First 10
            $avStatus.WindowsDefender.RecentThreats = $threats.Count
            $avStatus.WindowsDefender.ThreatHistory = $threats | ForEach-Object {
                [PSCustomObject]@{
                    ThreatName = $_.ThreatName
                    DetectionTime = $_.InitialDetectionTime
                    ActionSuccess = $_.ActionSuccess
                }
            }
        } catch {
            $avStatus.WindowsDefender.RecentThreats = 0
        }
    } else {
        $avStatus.WindowsDefender.Enabled = $false
        $avStatus.Issues += "Could not retrieve Windows Defender status"
    }
} catch {
    $avStatus.WindowsDefender.Error = $_.Exception.Message
    $avStatus.Issues += "Error checking Windows Defender: $($_.Exception.Message)"
}
#endregion

#region Third-Party Antivirus Detection
if ($CheckThirdParty) {
    Write-Host "Checking for third-party antivirus software..." -ForegroundColor Yellow

    try {
        # Check using Windows Security Center (Windows 10/11)
        $namespace = "root\SecurityCenter2"
        $avProducts = Get-WmiObject -Namespace $namespace -Class AntiVirusProduct -ErrorAction SilentlyContinue

        if ($avProducts) {
            foreach ($av in $avProducts) {
                # Decode product state
                $hexState = [Convert]::ToString($av.productState, 16).PadLeft(6, '0')
                $provider = $hexState.Substring(0, 2)
                $realTimeProtection = $hexState.Substring(2, 2)
                $definition = $hexState.Substring(4, 2)

                $isEnabled = $realTimeProtection -in @('10', '11')
                $isUpdated = $definition -in @('00')

                $avStatus.ThirdPartyAV += [PSCustomObject]@{
                    Name = $av.displayName
                    InstanceGuid = $av.instanceGuid
                    PathToSignedProductExe = $av.pathToSignedProductExe
                    PathToSignedReportingExe = $av.pathToSignedReportingExe
                    ProductState = $av.productState
                    Enabled = $isEnabled
                    DefinitionsUpToDate = $isUpdated
                    Timestamp = $av.timestamp
                }

                if (-not $isEnabled) {
                    $avStatus.Issues += "$($av.displayName) is installed but DISABLED"
                }
                if (-not $isUpdated) {
                    $avStatus.Issues += "$($av.displayName) definitions are OUTDATED"
                }
            }
        }
    } catch {
        Write-Verbose "Could not query Security Center: $($_.Exception.Message)"
    }

    # Also check common antivirus services
    $commonAVServices = @(
        'McAfeeFramework', 'McShield', 'McAfeeEngineService',  # McAfee
        'SavService', 'SAVAdminService',  # Sophos
        'avp', 'AVP18.0.0',  # Kaspersky
        'TrueService', 'TrueAPI',  # TrendMicro
        'VSSERV', 'avast! Antivirus',  # Avast/AVG
        'NortonSecurity', 'NS'  # Norton/Symantec
    )

    foreach ($serviceName in $commonAVServices) {
        $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
        if ($service) {
            Write-Host "Found AV service: $($service.DisplayName) - Status: $($service.Status)" -ForegroundColor Cyan
        }
    }
}
#endregion

#region Firewall Status
Write-Host "Checking Windows Firewall status..." -ForegroundColor Yellow

try {
    $firewallProfiles = Get-NetFirewallProfile -ErrorAction SilentlyContinue

    $avStatus.Firewall = @{
        Domain = ($firewallProfiles | Where-Object {$_.Name -eq 'Domain'}).Enabled
        Private = ($firewallProfiles | Where-Object {$_.Name -eq 'Private'}).Enabled
        Public = ($firewallProfiles | Where-Object {$_.Name -eq 'Public'}).Enabled
    }

    foreach ($profile in $firewallProfiles) {
        if (-not $profile.Enabled) {
            $avStatus.Issues += "Windows Firewall is DISABLED for $($profile.Name) profile"
        }
    }
} catch {
    $avStatus.Firewall.Error = $_.Exception.Message
    $avStatus.Issues += "Error checking firewall status"
}
#endregion

# Determine overall status
if ($avStatus.Issues.Count -eq 0) {
    $avStatus.OverallStatus = "Protected"
    $statusColor = "Green"
} elseif ($avStatus.Issues.Count -le 2) {
    $avStatus.OverallStatus = "Warning"
    $statusColor = "Yellow"
} else {
    $avStatus.OverallStatus = "At Risk"
    $statusColor = "Red"
}

#region Display Results
Write-Host "`n=== Antivirus Status Summary ===" -ForegroundColor Cyan
Write-Host "Overall Status: $($avStatus.OverallStatus)" -ForegroundColor $statusColor
Write-Host "`nWindows Defender:" -ForegroundColor Cyan
Write-Host "  Enabled: $($avStatus.WindowsDefender.Enabled)" -ForegroundColor $(if ($avStatus.WindowsDefender.Enabled) {'Green'} else {'Red'})
Write-Host "  Real-Time Protection: $($avStatus.WindowsDefender.RealTimeProtectionEnabled)" -ForegroundColor $(if ($avStatus.WindowsDefender.RealTimeProtectionEnabled) {'Green'} else {'Red'})
Write-Host "  Signature Version: $($avStatus.WindowsDefender.AntivirusSignatureVersion)"
Write-Host "  Signature Age: $($avStatus.WindowsDefender.AntivirusSignatureAge) days" -ForegroundColor $(if ($avStatus.WindowsDefender.AntivirusSignatureAge -le 7) {'Green'} else {'Yellow'})
Write-Host "  Last Quick Scan: $($avStatus.WindowsDefender.QuickScanEndTime)"
Write-Host "  Last Full Scan: $($avStatus.WindowsDefender.FullScanEndTime)"

if ($avStatus.ThirdPartyAV.Count -gt 0) {
    Write-Host "`nThird-Party Antivirus:" -ForegroundColor Cyan
    foreach ($av in $avStatus.ThirdPartyAV) {
        Write-Host "  $($av.Name) - Enabled: $($av.Enabled), Updated: $($av.DefinitionsUpToDate)" -ForegroundColor Cyan
    }
}

Write-Host "`nWindows Firewall:" -ForegroundColor Cyan
Write-Host "  Domain Profile: $($avStatus.Firewall.Domain)" -ForegroundColor $(if ($avStatus.Firewall.Domain) {'Green'} else {'Red'})
Write-Host "  Private Profile: $($avStatus.Firewall.Private)" -ForegroundColor $(if ($avStatus.Firewall.Private) {'Green'} else {'Red'})
Write-Host "  Public Profile: $($avStatus.Firewall.Public)" -ForegroundColor $(if ($avStatus.Firewall.Public) {'Green'} else {'Red'})

if ($avStatus.Issues.Count -gt 0) {
    Write-Host "`n=== Issues Found ===" -ForegroundColor Red
    $avStatus.Issues | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
} else {
    Write-Host "`nNo issues found. System is properly protected." -ForegroundColor Green
}
#endregion

#region Generate Reports
if ($OutputFormat -eq 'HTML' -or $OutputFormat -eq 'All') {
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $htmlPath = Join-Path $OutputPath "AntivirusStatus_$timestamp.html"

    $statusColorHtml = switch ($avStatus.OverallStatus) {
        'Protected' { 'green' }
        'Warning' { 'orange' }
        'At Risk' { 'red' }
        default { 'gray' }
    }

    $issuesHtml = if ($avStatus.Issues.Count -gt 0) {
        "<ul>" + ($avStatus.Issues | ForEach-Object { "<li style='color: red;'>$_</li>" }) + "</ul>"
    } else {
        "<p style='color: green;'>No issues found.</p>"
    }

    $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>Antivirus Status Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        h1 { color: #333; }
        .status-box { padding: 15px; border-left: 6px solid $statusColorHtml; background-color: #f9f9f9; margin: 20px 0; }
        table { border-collapse: collapse; width: 100%; margin-top: 20px; }
        th { background-color: #4CAF50; color: white; padding: 12px; text-align: left; }
        td { border: 1px solid #ddd; padding: 8px; }
        tr:nth-child(even) { background-color: #f2f2f2; }
        .good { color: green; font-weight: bold; }
        .bad { color: red; font-weight: bold; }
    </style>
</head>
<body>
    <h1>Antivirus & Endpoint Protection Status Report</h1>
    <div class="status-box">
        <p><strong>Computer Name:</strong> $($avStatus.ComputerName)</p>
        <p><strong>Scan Time:</strong> $($avStatus.ScanTime)</p>
        <p><strong>Overall Status:</strong> <span style="color: $statusColorHtml; font-size: 1.2em; font-weight: bold;">$($avStatus.OverallStatus)</span></p>
    </div>
    <h2>Windows Defender Status</h2>
    <table>
        <tr><td><strong>Enabled</strong></td><td class="$(if ($avStatus.WindowsDefender.Enabled) {'good'} else {'bad'})">$($avStatus.WindowsDefender.Enabled)</td></tr>
        <tr><td><strong>Real-Time Protection</strong></td><td class="$(if ($avStatus.WindowsDefender.RealTimeProtectionEnabled) {'good'} else {'bad'})">$($avStatus.WindowsDefender.RealTimeProtectionEnabled)</td></tr>
        <tr><td><strong>Signature Version</strong></td><td>$($avStatus.WindowsDefender.AntivirusSignatureVersion)</td></tr>
        <tr><td><strong>Signature Age (days)</strong></td><td class="$(if ($avStatus.WindowsDefender.AntivirusSignatureAge -le 7) {'good'} else {'bad'})">$($avStatus.WindowsDefender.AntivirusSignatureAge)</td></tr>
        <tr><td><strong>Last Quick Scan</strong></td><td>$($avStatus.WindowsDefender.QuickScanEndTime)</td></tr>
        <tr><td><strong>Last Full Scan</strong></td><td>$($avStatus.WindowsDefender.FullScanEndTime)</td></tr>
    </table>
    <h2>Windows Firewall Status</h2>
    <table>
        <tr><td><strong>Domain Profile</strong></td><td class="$(if ($avStatus.Firewall.Domain) {'good'} else {'bad'})">$($avStatus.Firewall.Domain)</td></tr>
        <tr><td><strong>Private Profile</strong></td><td class="$(if ($avStatus.Firewall.Private) {'good'} else {'bad'})">$($avStatus.Firewall.Private)</td></tr>
        <tr><td><strong>Public Profile</strong></td><td class="$(if ($avStatus.Firewall.Public) {'good'} else {'bad'})">$($avStatus.Firewall.Public)</td></tr>
    </table>
    <h2>Issues Found</h2>
    $issuesHtml
</body>
</html>
"@

    $html | Out-File -FilePath $htmlPath -Encoding UTF8
    Write-Host "`nHTML report saved to: $htmlPath" -ForegroundColor Green
}

if ($OutputFormat -eq 'CSV' -or $OutputFormat -eq 'All') {
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $csvPath = Join-Path $OutputPath "AntivirusStatus_$timestamp.csv"

    $csvData = [PSCustomObject]@{
        ComputerName = $avStatus.ComputerName
        ScanTime = $avStatus.ScanTime
        OverallStatus = $avStatus.OverallStatus
        DefenderEnabled = $avStatus.WindowsDefender.Enabled
        RealTimeProtectionEnabled = $avStatus.WindowsDefender.RealTimeProtectionEnabled
        SignatureAge = $avStatus.WindowsDefender.AntivirusSignatureAge
        QuickScanAge = $avStatus.WindowsDefender.QuickScanAge
        FirewallDomain = $avStatus.Firewall.Domain
        FirewallPrivate = $avStatus.Firewall.Private
        FirewallPublic = $avStatus.Firewall.Public
        IssuesCount = $avStatus.Issues.Count
        Issues = ($avStatus.Issues -join '; ')
    }

    $csvData | Export-Csv -Path $csvPath -NoTypeInformation
    Write-Host "CSV report saved to: $csvPath" -ForegroundColor Green
}
#endregion

return $avStatus
