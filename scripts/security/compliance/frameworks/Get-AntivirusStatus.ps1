<#
.SYNOPSIS
    Check antivirus and endpoint protection status on Windows devices and report protection gaps.

.DESCRIPTION
    Queries Microsoft Defender via Get-MpComputerStatus, third-party antivirus products via the
    SecurityCenter2 CIM namespace, known antivirus service names, and Windows Firewall profile state.
    - Detects disabled real-time protection, outdated signatures, and stale scans
    - Optionally enumerates third-party antivirus products and decodes their product state
    - Exports HTML and/or CSV reports when -OutputFormat requests them
    Side effects: writes report files into -OutputPath when -OutputFormat is HTML, CSV, or All.
    Exit codes: 0 = no protection issues found; 1 = one or more issues detected or a fatal error.

.PARAMETER OutputFormat
    Output format for the generated report: None (console only), HTML, CSV, or All. Default is None.

.PARAMETER OutputPath
    Directory where report files are written when -OutputFormat requests a report.
    Default is the current location.

.PARAMETER CheckThirdParty
    When $true (default), also probes SecurityCenter2 and known antivirus service names
    for third-party products.

.EXAMPLE
    PS C:\> .\Get-AntivirusStatus.ps1 -OutputFormat HTML -OutputPath "C:\Reports"

    Generates an HTML report of antivirus status in C:\Reports; returns 1 if issues were found.

.EXAMPLE
    PS C:\> .\Get-AntivirusStatus.ps1

    Checks Windows Defender, third-party antivirus solutions, and firewall status in the console only.

.NOTES
    File Name   : Get-AntivirusStatus.ps1
    Author      : Bug-Free Umbrella
    Prerequisite: PowerShell 7.0
    Version     : 1.0.0
    Date        : 2026-08-23
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter()]
    [ValidateSet('None', 'HTML', 'CSV', 'All')]
    [string]$OutputFormat = 'None',

    [Parameter()]
    [string]$OutputPath = (Get-Location),

    [Parameter()]
    [bool]$CheckThirdParty = $true
)

# PSSA note: remaining warnings are intentional/false positives:
# - PSAvoidUsingWriteHost: colored [prefix] console reporting via Write-Host is
#   mandated by the relaunch output standard.
# - PSReviewUnusedParameter: parameters are consumed inside Main (PSSA cannot see
#   through the wrapper).
# - PSShouldProcess on Main: it deliberately uses the script-level CmdletBinding
#   SupportsShouldProcess binding's $PSCmdlet.
$ErrorActionPreference = 'Stop'

function Main {
    try {
        Write-Host "[*] === Antivirus & Endpoint Protection Status ===" -ForegroundColor Cyan

        # Initialize results
        $avStatus = @{
            ComputerName    = $env:COMPUTERNAME
            ScanTime        = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            WindowsDefender = @{}
            ThirdPartyAV    = @()
            Firewall        = @{}
            OverallStatus   = "Unknown"
            Issues          = @()
        }

        #region Windows Defender Status
        Write-Host "[*] Checking Windows Defender status..." -ForegroundColor Yellow

        try {
            # Get Windows Defender status using Get-MpComputerStatus
            $defenderStatus = Get-MpComputerStatus -ErrorAction SilentlyContinue

            if ($defenderStatus) {
                $avStatus.WindowsDefender = @{
                    Enabled                     = $defenderStatus.AntivirusEnabled
                    RealTimeProtectionEnabled   = $defenderStatus.RealTimeProtectionEnabled
                    BehaviorMonitorEnabled      = $defenderStatus.BehaviorMonitorEnabled
                    IoavProtectionEnabled       = $defenderStatus.IoavProtectionEnabled
                    OnAccessProtectionEnabled   = $defenderStatus.OnAccessProtectionEnabled
                    AntivirusSignatureVersion   = $defenderStatus.AntivirusSignatureVersion
                    AntivirusSignatureAge       = $defenderStatus.AntivirusSignatureAge
                    AntivirusSignatureLastUpdated = $defenderStatus.AntivirusSignatureLastUpdated
                    QuickScanAge                = $defenderStatus.QuickScanAge
                    FullScanAge                 = $defenderStatus.FullScanAge
                    QuickScanEndTime            = $defenderStatus.QuickScanEndTime
                    FullScanEndTime             = $defenderStatus.FullScanEndTime
                }

                # Check for issues
                if (-not $defenderStatus.AntivirusEnabled) {
                    $avStatus.Issues += "Windows Defender is DISABLED"
                }
                if (-not $defenderStatus.RealTimeProtectionEnabled) {
                    $avStatus.Issues += "Real-Time Protection is DISABLED"
                }
                if ($defenderStatus.AntivirusSignatureAge -gt 7) {
                    $sigAgeDays = $defenderStatus.AntivirusSignatureAge
                    $avStatus.Issues += "Antivirus signatures are OUTDATED ($sigAgeDays days old)"
                }
                if ($defenderStatus.QuickScanAge -gt 7) {
                    $avStatus.Issues += "Quick scan hasn't run in $($defenderStatus.QuickScanAge) days"
                }

                # Get threat history
                try {
                    $threats = @(Get-MpThreatDetection -ErrorAction SilentlyContinue | Select-Object -First 10)
                    # Get-MpThreatDetection does not expose ThreatName; resolve names via
                    # Get-MpThreat keyed by ThreatID (cache the lookup).
                    $threatLookup = @{}
                    if ($threats.Count -gt 0) {
                        Get-MpThreat -ErrorAction SilentlyContinue | ForEach-Object {
                            $threatLookup[$_.ThreatID] = $_.ThreatName
                        }
                    }
                    $avStatus.WindowsDefender.RecentThreats = $threats.Count
                    $avStatus.WindowsDefender.ThreatHistory = @($threats | ForEach-Object {
                        $threatName = "Unknown (ThreatID $($_.ThreatID))"
                        if ($threatLookup.ContainsKey($_.ThreatID)) {
                            $threatName = $threatLookup[$_.ThreatID]
                        }
                        [PSCustomObject]@{
                            ThreatName    = $threatName
                            DetectionTime = $_.InitialDetectionTime
                            ActionSuccess = $_.ActionSuccess
                        }
                    })
                }
                catch {
                    $avStatus.WindowsDefender.RecentThreats = 0
                }
            }
            else {
                $avStatus.WindowsDefender.Enabled = $false
                $avStatus.Issues += "Could not retrieve Windows Defender status"
            }
        }
        catch {
            $avStatus.WindowsDefender.Error = $_.Exception.Message
            $avStatus.Issues += "Error checking Windows Defender: $($_.Exception.Message)"
        }
        #endregion

        #region Third-Party Antivirus Detection
        if ($CheckThirdParty) {
            Write-Host "[*] Checking for third-party antivirus software..." -ForegroundColor Yellow

            try {
                # Check using Windows Security Center (Windows 10/11)
                $namespace = "root\SecurityCenter2"
                $avProducts = Get-CimInstance -Namespace $namespace `
                    -ClassName AntiVirusProduct -ErrorAction SilentlyContinue

                if ($avProducts) {
                    foreach ($av in $avProducts) {
                        # Decode product state
                        $hexState = [Convert]::ToString($av.productState, 16).PadLeft(6, '0')
                        $realTimeProtection = $hexState.Substring(2, 2)
                        $definition = $hexState.Substring(4, 2)

                        $isEnabled = $realTimeProtection -in @('10', '11')
                        $isUpdated = $definition -in @('00')

                        $avStatus.ThirdPartyAV += [PSCustomObject]@{
                            Name                       = $av.displayName
                            InstanceGuid               = $av.instanceGuid
                            PathToSignedProductExe     = $av.pathToSignedProductExe
                            PathToSignedReportingExe   = $av.pathToSignedReportingExe
                            ProductState               = $av.productState
                            Enabled                    = $isEnabled
                            DefinitionsUpToDate        = $isUpdated
                            Timestamp                  = $av.timestamp
                        }

                        if (-not $isEnabled) {
                            $avStatus.Issues += "$($av.displayName) is installed but DISABLED"
                        }
                        if (-not $isUpdated) {
                            $avStatus.Issues += "$($av.displayName) definitions are OUTDATED"
                        }
                    }
                }
            }
            catch {
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
                    Write-Host "[*] Found AV service: $($service.DisplayName) - Status: $($service.Status)"  `
                        -ForegroundColor Cyan
                }
            }
        }
        #endregion

        #region Firewall Status
        Write-Host "[*] Checking Windows Firewall status..." -ForegroundColor Yellow

        try {
            $firewallProfiles = Get-NetFirewallProfile -ErrorAction SilentlyContinue

            $avStatus.Firewall = @{
                Domain  = ($firewallProfiles | Where-Object { $_.Name -eq 'Domain' }).Enabled
                Private = ($firewallProfiles | Where-Object { $_.Name -eq 'Private' }).Enabled
                Public  = ($firewallProfiles | Where-Object { $_.Name -eq 'Public' }).Enabled
            }

            foreach ($fwProfile in $firewallProfiles) {
                if (-not $fwProfile.Enabled) {
                    $avStatus.Issues += "Windows Firewall is DISABLED for $($fwProfile.Name) profile"
                }
            }
        }
        catch {
            $avStatus.Firewall.Error = $_.Exception.Message
            $avStatus.Issues += "Error checking firewall status"
        }
        #endregion

        # Determine overall status
        if ($avStatus.Issues.Count -eq 0) {
            $avStatus.OverallStatus = "Protected"
            $statusColor = "Green"
        }
        elseif ($avStatus.Issues.Count -le 2) {
            $avStatus.OverallStatus = "Warning"
            $statusColor = "Yellow"
        }
        else {
            $avStatus.OverallStatus = "At Risk"
            $statusColor = "Red"
        }

        #region Display Results
        Write-Host "[*] === Antivirus Status Summary ===" -ForegroundColor Cyan
        Write-Host "Overall Status: $($avStatus.OverallStatus)" -ForegroundColor $statusColor

        $wd = $avStatus.WindowsDefender
        $enabledColor = if ($wd.Enabled) { 'Green' } else { 'Red' }
        $rtpColor = if ($wd.RealTimeProtectionEnabled) { 'Green' } else { 'Red' }
        $sigAgeColor = if ($wd.AntivirusSignatureAge -le 7) { 'Green' } else { 'Yellow' }

        Write-Host "[*] Windows Defender:" -ForegroundColor Cyan
        Write-Host "  Enabled: $($wd.Enabled)" -ForegroundColor $enabledColor
        Write-Host "  Real-Time Protection: $($wd.RealTimeProtectionEnabled)" -ForegroundColor $rtpColor
        Write-Host "  Signature Version: $($wd.AntivirusSignatureVersion)"
        Write-Host "  Signature Age: $($wd.AntivirusSignatureAge) days" -ForegroundColor $sigAgeColor
        Write-Host "  Last Quick Scan: $($wd.QuickScanEndTime)"
        Write-Host "  Last Full Scan: $($wd.FullScanEndTime)"

        if ($avStatus.ThirdPartyAV.Count -gt 0) {
            Write-Host "[*] Third-Party Antivirus:" -ForegroundColor Cyan
            foreach ($av in $avStatus.ThirdPartyAV) {
                Write-Host "  $($av.Name) - Enabled: $($av.Enabled), Updated: $($av.DefinitionsUpToDate)"  `
                    -ForegroundColor Cyan
            }
        }

        $fw = $avStatus.Firewall
        $domainColor = if ($fw.Domain) { 'Green' } else { 'Red' }
        $privateColor = if ($fw.Private) { 'Green' } else { 'Red' }
        $publicColor = if ($fw.Public) { 'Green' } else { 'Red' }

        Write-Host "[*] Windows Firewall:" -ForegroundColor Cyan
        Write-Host "  Domain Profile: $($fw.Domain)" -ForegroundColor $domainColor
        Write-Host "  Private Profile: $($fw.Private)" -ForegroundColor $privateColor
        Write-Host "  Public Profile: $($fw.Public)" -ForegroundColor $publicColor

        if ($avStatus.Issues.Count -gt 0) {
            Write-Host "[-] === Issues Found ===" -ForegroundColor Red
            $avStatus.Issues | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
        }
        else {
            Write-Host "[+] No issues found. System is properly protected." -ForegroundColor Green
        }
        #endregion

        #region Generate Reports
        if ($OutputFormat -eq 'HTML' -or $OutputFormat -eq 'All') {
            if ($PSCmdlet.ShouldProcess($OutputPath, "Write antivirus status HTML report")) {
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
                }
                else {
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
        .status-box { padding: 15px; border-left: 6px solid $statusColorHtml;
            background-color: #f9f9f9; margin: 20px 0; }
        table { border-collapse: collapse; width: 100%; margin-top: 20px; }
        th { background-color: #4CAF50; color: white; padding: 12px; text-align: left; }
        td { border: 1px solid #ddd; padding: 8px; }
        tr:nth-child(even) { background-color: #f2f2f2; }
        .good { color: green; font-weight: bold; }
        .bad { color: red; font-weight: bold; }
    </style>
</head>
<body>
    <h1>Antivirus &amp; Endpoint Protection Status Report</h1>
    <div class="status-box">
        <p><strong>Computer Name:</strong> $($avStatus.ComputerName)</p>
        <p><strong>Scan Time:</strong> $($avStatus.ScanTime)</p>
        <p><strong>Overall Status:</strong>
            <span style="color: $statusColorHtml;
                font-size: 1.2em; font-weight: bold;">$($avStatus.OverallStatus)</span>
        </p>
    </div>
    <h2>Windows Defender Status</h2>
    <table>
        <tr>
            <td><strong>Enabled</strong></td>
            <td class="$(if ($wd.Enabled) {'good'} else {'bad'})">
                $($wd.Enabled)
            </td>
        </tr>
        <tr>
            <td><strong>Real-Time Protection</strong></td>
            <td class="$(if ($wd.RealTimeProtectionEnabled) {'good'} else {'bad'})">
                $($wd.RealTimeProtectionEnabled)
            </td>
        </tr>
        <tr>
            <td><strong>Signature Version</strong></td>
            <td>$($wd.AntivirusSignatureVersion)</td>
        </tr>
        <tr>
            <td><strong>Signature Age (days)</strong></td>
            <td class="$(if ($wd.AntivirusSignatureAge -le 7) {'good'} else {'bad'})">
                $($wd.AntivirusSignatureAge)
            </td>
        </tr>
        <tr>
            <td><strong>Last Quick Scan</strong></td>
            <td>$($wd.QuickScanEndTime)</td>
        </tr>
        <tr>
            <td><strong>Last Full Scan</strong></td>
            <td>$($wd.FullScanEndTime)</td>
        </tr>
    </table>
    <h2>Windows Firewall Status</h2>
    <table>
        <tr>
            <td><strong>Domain Profile</strong></td>
            <td class="$(if ($fw.Domain) {'good'} else {'bad'})">$($fw.Domain)</td>
        </tr>
        <tr>
            <td><strong>Private Profile</strong></td>
            <td class="$(if ($fw.Private) {'good'} else {'bad'})">$($fw.Private)</td>
        </tr>
        <tr>
            <td><strong>Public Profile</strong></td>
            <td class="$(if ($fw.Public) {'good'} else {'bad'})">$($fw.Public)</td>
        </tr>
    </table>
    <h2>Issues Found</h2>
    $issuesHtml
</body>
</html>
"@

                $html | Out-File -FilePath $htmlPath -Encoding UTF8 -ErrorAction Stop
                Write-Host "[+] HTML report saved to: $htmlPath" -ForegroundColor Green
            }
        }

        if ($OutputFormat -eq 'CSV' -or $OutputFormat -eq 'All') {
            if ($PSCmdlet.ShouldProcess($OutputPath, "Write antivirus status CSV report")) {
                $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
                $csvPath = Join-Path $OutputPath "AntivirusStatus_$timestamp.csv"

                $csvData = [PSCustomObject]@{
                    ComputerName              = $avStatus.ComputerName
                    ScanTime                  = $avStatus.ScanTime
                    OverallStatus             = $avStatus.OverallStatus
                    DefenderEnabled           = $wd.Enabled
                    RealTimeProtectionEnabled = $wd.RealTimeProtectionEnabled
                    SignatureAge              = $wd.AntivirusSignatureAge
                    QuickScanAge              = $wd.QuickScanAge
                    FirewallDomain            = $fw.Domain
                    FirewallPrivate           = $fw.Private
                    FirewallPublic            = $fw.Public
                    IssuesCount               = $avStatus.Issues.Count
                    Issues                    = ($avStatus.Issues -join '; ')
                }

                $csvData | Export-Csv -Path $csvPath -NoTypeInformation -ErrorAction Stop
                Write-Host "[+] CSV report saved to: $csvPath" -ForegroundColor Green
            }
        }
        #endregion

        # Exit code contract: 0 = no issues, 1 = issues detected
        if ($avStatus.Issues.Count -gt 0) {
            Write-Host "[!] Antivirus status check completed with $($avStatus.Issues.Count) issue(s) found."  `
            -ForegroundColor Yellow
            return 1
        }

        Write-Host "[+] Antivirus status check completed. System is properly protected." -ForegroundColor Green
        return 0
    }
    catch {
        Write-Host "[-] Error: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
