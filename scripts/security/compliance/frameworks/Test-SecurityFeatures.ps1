<#
.SYNOPSIS
    Test modern Windows security features and report their configuration status.
.DESCRIPTION
    This script verifies that critical Windows security features are enabled and functioning,
    including TPM, Secure Boot, Credential Guard, Device Guard, BitLocker, Windows Defender,
    and various exploit protection mechanisms. All checks are read-only detectors; no system
    state is modified.

    Provides recommendations for enabling missing security features to improve system hardening.

    Exit codes: 0 = every feature enabled; 1 = one or more features disabled, unavailable, or
    the check failed.
.PARAMETER ShowRecommendations
    Display detailed recommendations for enabling missing features
.PARAMETER ExportReport
    Generate HTML and CSV reports in MyDocuments\Reports
.EXAMPLE
    PS C:\> .\Test-SecurityFeatures.ps1

    Tests all security features.
.EXAMPLE
    PS C:\> .\Test-SecurityFeatures.ps1 -ShowRecommendations

    Tests features and shows detailed recommendations.
.NOTES
    File Name   : Test-SecurityFeatures.ps1
    Author      : Security & Compliance Team
    Prerequisite: PowerShell 5.1+
    Version     : 1.0.0
    Date        : 2026-08-23

    Compatible: Windows 10/11, Server 2016+
    Best results on UEFI systems with TPM 2.0
#>

# Write-Host is intentional: RELAUNCH-SPEC section 3 mandates prefixed colored console output.
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter()]
    [switch]$ShowRecommendations,

    [Parameter()]
    [switch]$ExportReport
)

$ErrorActionPreference = 'Stop'

# Returns $true when the session is elevated; $false otherwise (including non-Windows platforms).
function Test-AdministratorElevation {
    [CmdletBinding()]
    param()

    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = [Security.Principal.WindowsPrincipal]$identity
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch {
        return $false
    }
}

# Helper function to add a result ($script:Results / $script:IssuesFound live in Main's scope)
function Add-Result {
    param(
        [string]$Feature,
        [string]$Status,
        [string]$Details,
        [string]$Recommendation = ""
    )

    $script:Results += [PSCustomObject]@{
        Feature = $Feature
        Status = $Status
        Details = $Details
        Recommendation = $Recommendation
    }

    if ($Status -in @('Disabled', 'Not Available', 'Failed')) {
        $script:IssuesFound = $true
    }
}

function Main {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [switch]$ShowRecommendations,

        [switch]$ExportReport
    )

    try {
        # Reset run state so repeated Main calls behave identically
        $script:Results = @()
        $script:IssuesFound = $false

        if (-not (Test-AdministratorElevation)) {
            Write-Warning "Administrator privileges recommended: some checks require elevated access."
        }

        Write-Host "[*] ========================================" -ForegroundColor Cyan
        Write-Host "[*]    Security Features Assessment" -ForegroundColor Cyan
        Write-Host "[*] ========================================`n" -ForegroundColor Cyan

        # 1. TPM (Trusted Platform Module)
        Write-Host "[*] [1/10] Checking TPM Status..." -ForegroundColor Yellow
        try {
            $TPM = Get-Tpm -ErrorAction Stop

            if ($TPM.TpmPresent) {
                if ($TPM.TpmReady) {
                    $TPMVersion = $TPM.ManufacturerVersion
                    Write-Host "  [✓] TPM Present and Ready (Version: $TPMVersion)" -ForegroundColor Green
                    Add-Result "TPM (Trusted Platform Module)" "Enabled" "Present and ready, Version: $TPMVersion" ""
                }
                else {
                    Write-Host "  [!] TPM Present but Not Ready" -ForegroundColor Yellow
                    Add-Result "TPM (Trusted Platform Module)" "Disabled" "Present but not ready" `
                        "Initialize TPM in BIOS/UEFI settings"
                }
            }
            else {
                Write-Host "  [✗] TPM Not Present" -ForegroundColor Red
                Add-Result "TPM (Trusted Platform Module)" "Not Available" "No TPM detected" `
                    "Enable TPM in BIOS/UEFI or upgrade hardware"
            }
        }
        catch {
            Write-Host "  [✗] Unable to check TPM: $($_.Exception.Message)" -ForegroundColor Red
            Add-Result "TPM (Trusted Platform Module)" "Failed" "Unable to check TPM status" `
                "Verify TPM is enabled in BIOS/UEFI"
        }

        # 2. Secure Boot
        Write-Host "`n[*] [2/10] Checking Secure Boot..." -ForegroundColor Yellow
        try {
            $SecureBoot = Confirm-SecureBootUEFI -ErrorAction Stop

            if ($SecureBoot) {
                Write-Host "  [✓] Secure Boot Enabled" -ForegroundColor Green
                Add-Result "Secure Boot" "Enabled" "UEFI Secure Boot is active" ""
            }
            else {
                Write-Host "  [✗] Secure Boot Disabled" -ForegroundColor Red
                Add-Result "Secure Boot" "Disabled" "Secure Boot is not enabled" `
                    "Enable Secure Boot in UEFI firmware settings"
            }
        }
        catch {
            Write-Host "  [!] Secure Boot Not Supported (Legacy BIOS)" -ForegroundColor Yellow
            Add-Result "Secure Boot" "Not Available" "System using Legacy BIOS" `
                "Convert to UEFI and enable Secure Boot"
        }

        # 3. Virtualization-Based Security (VBS)
        Write-Host "`n[*] [3/10] Checking Virtualization-Based Security..." -ForegroundColor Yellow
        try {
            $DevGuard = Get-CimInstance -ClassName Win32_DeviceGuard `
                -Namespace root\Microsoft\Windows\DeviceGuard -ErrorAction Stop

            if ($DevGuard.VirtualizationBasedSecurityStatus -eq 2) {
                Write-Host "  [✓] VBS Running" -ForegroundColor Green
                Add-Result "Virtualization-Based Security (VBS)" "Enabled" "VBS is running" ""
            }
            elseif ($DevGuard.VirtualizationBasedSecurityStatus -eq 1) {
                Write-Host "  [!] VBS Enabled but Not Running" -ForegroundColor Yellow
                Add-Result "Virtualization-Based Security (VBS)" "Disabled" "VBS enabled but not running" `
                    "Reboot system or check hardware virtualization"
            }
            else {
                Write-Host "  [✗] VBS Not Enabled" -ForegroundColor Red
                Add-Result "Virtualization-Based Security (VBS)" "Disabled" "VBS is not enabled" `
                    "Enable via Group Policy or Intune"
            }
        }
        catch {
            Write-Host "  [✗] Unable to check VBS status" -ForegroundColor Red
            Add-Result "Virtualization-Based Security (VBS)" "Not Available" "Cannot determine VBS status" `
                "Ensure Windows 10/11 Pro/Enterprise"
        }

        # 4. Credential Guard
        Write-Host "`n[*] [4/10] Checking Credential Guard..." -ForegroundColor Yellow
        try {
            $DevGuard = Get-CimInstance -ClassName Win32_DeviceGuard `
                -Namespace root\Microsoft\Windows\DeviceGuard -ErrorAction Stop

            if ($DevGuard.SecurityServicesRunning -contains 1) {
                Write-Host "  [✓] Credential Guard Running" -ForegroundColor Green
                Add-Result "Credential Guard" "Enabled" "Credential Guard is running" ""
            }
            elseif ($DevGuard.SecurityServicesConfigured -contains 1) {
                Write-Host "  [!] Credential Guard Configured but Not Running" -ForegroundColor Yellow
                Add-Result "Credential Guard" "Disabled" "Configured but not running" `
                    "Reboot system or check VBS prerequisites"
            }
            else {
                Write-Host "  [✗] Credential Guard Not Configured" -ForegroundColor Red
                Add-Result "Credential Guard" "Disabled" "Not configured" `
                    "Enable via Group Policy: Computer Config > Admin Templates > System > Device Guard"
            }
        }
        catch {
            Write-Host "  [✗] Unable to check Credential Guard" -ForegroundColor Red
            Add-Result "Credential Guard" "Not Available" "Cannot determine status" `
                "Requires Windows 10/11 Enterprise and compatible hardware"
        }

        # 5. BitLocker
        Write-Host "`n[*] [5/10] Checking BitLocker Encryption..." -ForegroundColor Yellow
        try {
            $BitLockerVolumes = Get-BitLockerVolume -ErrorAction Stop
            $OSVolume = $BitLockerVolumes | Where-Object { $_.VolumeType -eq 'OperatingSystem' } |
                Select-Object -First 1

            if ($OSVolume) {
                if ($OSVolume.ProtectionStatus -eq 'On') {
                    Write-Host "  [✓] BitLocker Enabled on OS Drive ($($OSVolume.MountPoint))" -ForegroundColor Green
                    Add-Result "BitLocker Drive Encryption" "Enabled" `
                        "OS drive encrypted: $($OSVolume.MountPoint) - $($OSVolume.EncryptionPercentage)%" ""
                }
                else {
                    Write-Host "  [✗] BitLocker Not Enabled on OS Drive" -ForegroundColor Red
                    Add-Result "BitLocker Drive Encryption" "Disabled" "OS drive not encrypted" `
                        "Enable BitLocker via Control Panel or Intune policy"
                }

                # Check encryption method
                if ($OSVolume.EncryptionMethod) {
                    Write-Host "      Encryption Method: $($OSVolume.EncryptionMethod)" -ForegroundColor Gray
                }
            }
            else {
                Write-Host "  [!] No OS Volume Found for BitLocker Check" -ForegroundColor Yellow
                Add-Result "BitLocker Drive Encryption" "Not Available" "Cannot detect OS volume" `
                    "Verify BitLocker support"
            }
        }
        catch {
            Write-Host "  [✗] BitLocker Not Available: $($_.Exception.Message)" -ForegroundColor Red
            Add-Result "BitLocker Drive Encryption" "Not Available" "BitLocker not available on this system" `
                "Requires Windows 10/11 Pro or Enterprise"
        }

        # 6. Windows Defender Antivirus
        Write-Host "`n[*] [6/10] Checking Windows Defender..." -ForegroundColor Yellow
        try {
            $Defender = Get-MpComputerStatus -ErrorAction Stop

            if ($Defender.AntivirusEnabled) {
                Write-Host "  [✓] Windows Defender Antivirus Enabled" -ForegroundColor Green
                Add-Result "Windows Defender Antivirus" "Enabled" "Antivirus protection active" ""
            }
            else {
                Write-Host "  [✗] Windows Defender Antivirus Disabled" -ForegroundColor Red
                Add-Result "Windows Defender Antivirus" "Disabled" "Antivirus protection disabled" `
                    "Enable Windows Defender or ensure third-party AV is active"
            }

            if ($Defender.RealTimeProtectionEnabled) {
                Write-Host "  [✓] Real-Time Protection Enabled" -ForegroundColor Green
                Add-Result "Windows Defender Real-Time Protection" "Enabled" "Real-time scanning active" ""
            }
            else {
                Write-Host "  [✗] Real-Time Protection Disabled" -ForegroundColor Red
                Add-Result "Windows Defender Real-Time Protection" "Disabled" "Real-time scanning disabled" `
                    "Enable real-time protection in Windows Security"
            }

            if ($Defender.BehaviorMonitorEnabled) {
                Write-Host "  [✓] Behavior Monitoring Enabled" -ForegroundColor Green
            }
            else {
                Write-Host "  [!] Behavior Monitoring Disabled" -ForegroundColor Yellow
            }

            if ($Defender.IoavProtectionEnabled) {
                Write-Host "  [✓] Cloud-Delivered Protection Enabled" -ForegroundColor Green
            }
            else {
                Write-Host "  [!] Cloud-Delivered Protection Disabled" -ForegroundColor Yellow
            }

        }
        catch {
            Write-Host "  [!] Windows Defender Status Unknown (Third-party AV may be active)" -ForegroundColor Yellow
            Add-Result "Windows Defender" "Not Available" "Cannot determine status - third-party AV may be in use" ""
        }

        # 7. Windows Firewall
        Write-Host "`n[*] [7/10] Checking Windows Firewall..." -ForegroundColor Yellow
        try {
            $Firewall = Get-NetFirewallProfile -ErrorAction Stop
            $AllEnabled = $true

            foreach ($FirewallProfile in $Firewall) {
                if ($FirewallProfile.Enabled) {
                    Write-Host "  [✓] $($FirewallProfile.Name) Profile: Enabled" -ForegroundColor Green
                }
                else {
                    Write-Host "  [✗] $($FirewallProfile.Name) Profile: Disabled" -ForegroundColor Red
                    $AllEnabled = $false
                }
            }

            if ($AllEnabled) {
                Add-Result "Windows Firewall" "Enabled" "All firewall profiles enabled" ""
            }
            else {
                Add-Result "Windows Firewall" "Disabled" "One or more firewall profiles disabled" `
                    "Enable all firewall profiles in Windows Security"
            }
        }
        catch {
            Write-Host "  [✗] Unable to check Windows Firewall" -ForegroundColor Red
            Add-Result "Windows Firewall" "Failed" "Cannot determine firewall status" "Check Windows Security settings"
        }

        # 8. UEFI vs Legacy BIOS
        Write-Host "`n[*] [8/10] Checking Boot Mode..." -ForegroundColor Yellow
        try {
            $BootMode = $env:firmware_type
            if (-not $BootMode) {
                # Alternative method
                $BootMode = (Get-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control" `
                    -Name "PEFirmwareType" -ErrorAction SilentlyContinue).PEFirmwareType
            }

            if ($BootMode -eq "UEFI" -or $BootMode -eq 2) {
                Write-Host "  [✓] UEFI Boot Mode" -ForegroundColor Green
                Add-Result "Boot Mode" "Enabled" "System using UEFI firmware" ""
            }
            else {
                Write-Host "  [!] Legacy BIOS Mode" -ForegroundColor Yellow
                Add-Result "Boot Mode" "Disabled" "System using Legacy BIOS" `
                    "Convert to UEFI for enhanced security features"
            }
        }
        catch {
            Write-Host "  [!] Unable to determine boot mode" -ForegroundColor Yellow
            Add-Result "Boot Mode" "Not Available" "Cannot determine boot mode" ""
        }

        # 9. Exploit Protection
        Write-Host "`n[*] [9/10] Checking Exploit Protection..." -ForegroundColor Yellow
        try {
            # Check DEP (Data Execution Prevention)
            $DEP = Get-CimInstance -ClassName Win32_OperatingSystem |
                Select-Object -ExpandProperty DataExecutionPrevention_SupportPolicy

            if ($DEP -eq 3) {
                Write-Host "  [✓] DEP (Data Execution Prevention): Enabled for all programs" -ForegroundColor Green
                Add-Result "DEP (Data Execution Prevention)" "Enabled" "Enabled for all programs and services" ""
            }
            elseif ($DEP -eq 2) {
                Write-Host "  [!] DEP: Enabled for essential Windows programs only" -ForegroundColor Yellow
                Add-Result "DEP (Data Execution Prevention)" "Enabled" "Enabled for essential programs only" `
                    "Enable for all programs in System Properties"
            }
            else {
                Write-Host "  [✗] DEP: Not properly configured" -ForegroundColor Red
                Add-Result "DEP (Data Execution Prevention)" "Disabled" "Not properly configured" `
                    "Enable DEP for all programs"
            }

            # Check for Windows Defender Exploit Guard
            $ExploitGuard = Get-ProcessMitigation -System -ErrorAction SilentlyContinue
            if ($ExploitGuard) {
                Write-Host "  [✓] Windows Defender Exploit Guard: Available" -ForegroundColor Green
            }
            else {
                Write-Host "  [!] Windows Defender Exploit Guard: Status unknown" -ForegroundColor Yellow
            }

        }
        catch {
            Write-Host "  [!] Unable to fully check exploit protection" -ForegroundColor Yellow
            Add-Result "Exploit Protection" "Not Available" "Cannot determine full exploit protection status" ""
        }

        # 10. Windows Update
        Write-Host "`n[*] [10/10] Checking Windows Update Status..." -ForegroundColor Yellow
        try {
            # Check if Windows Update service is running
            $WUService = Get-Service -Name wuauserv -ErrorAction Stop

            if ($WUService.Status -eq 'Running') {
                Write-Host "  [✓] Windows Update Service: Running" -ForegroundColor Green
                Add-Result "Windows Update Service" "Enabled" "Service is running" ""
            }
            else {
                Write-Host "  [!] Windows Update Service: $($WUService.Status)" -ForegroundColor Yellow
                Add-Result "Windows Update Service" "Disabled" "Service is $($WUService.Status)" `
                    "Ensure Windows Update service is running"
            }

        }
        catch {
            Write-Host "  [✗] Unable to check Windows Update service" -ForegroundColor Red
            Add-Result "Windows Update Service" "Failed" "Cannot determine service status" "Check Services.msc"
        }

        # Summary
        Write-Host "`n[*] ========================================" -ForegroundColor Cyan
        Write-Host "[*]    Security Features Summary" -ForegroundColor Cyan
        Write-Host "[*] ========================================" -ForegroundColor Cyan

        $TotalFeatures = @($script:Results).Count
        $EnabledFeatures = ($script:Results | Where-Object { $_.Status -eq 'Enabled' }).Count
        $DisabledFeatures = ($script:Results |
            Where-Object { $_.Status -in @('Disabled', 'Not Available', 'Failed') }).Count

        Write-Host "[*] Total Features Checked: $TotalFeatures" -ForegroundColor White
        Write-Host "[+] Enabled: $EnabledFeatures" -ForegroundColor Green
        Write-Host "[!] Disabled/Not Available: $DisabledFeatures" -ForegroundColor Red

        $SecurityScore = 0
        if ($TotalFeatures -gt 0) {
            $SecurityScore = [math]::Round(($EnabledFeatures / $TotalFeatures) * 100, 2)
        }
        $scoreColor = if ($SecurityScore -ge 80) { 'Green' } elseif ($SecurityScore -ge 60) { 'Yellow' } else { 'Red' }
        Write-Host "`n[*] Security Score: $SecurityScore%" -ForegroundColor $scoreColor

        # Show recommendations if requested
        if ($ShowRecommendations -or $DisabledFeatures -gt 0) {
            Write-Host "`n[!] ========================================" -ForegroundColor Yellow
            Write-Host "[!]    Recommendations" -ForegroundColor Yellow
            Write-Host "[!] ========================================" -ForegroundColor Yellow

            $DisabledItems = $script:Results |
                Where-Object { $_.Status -in @('Disabled', 'Not Available') -and $_.Recommendation }

            if ($DisabledItems) {
                foreach ($Item in $DisabledItems) {
                    Write-Host "`n$($Item.Feature):" -ForegroundColor White
                    $statusColor = if ($Item.Status -eq 'Disabled') { 'Red' } else { 'Yellow' }
                    Write-Host "  Status: $($Item.Status)" -ForegroundColor $statusColor
                    Write-Host "  → $($Item.Recommendation)" -ForegroundColor Cyan
                }
            }
            else {
                Write-Host "`n[+] All critical security features are enabled!" -ForegroundColor Green
            }
        }

        # Export reports if requested
        if ($ExportReport) {
            if ($PSCmdlet.ShouldProcess("MyDocuments\Reports", "Write security features CSV and HTML reports")) {
                $ReportPath = (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Reports')
                # Reject '..' traversal and UNC remote paths before resolution
                if ([string]::IsNullOrWhiteSpace($ReportPath) -or
                    $ReportPath -match '(^|[\\/])\.\.([\\/]|$)' -or
                    $ReportPath -match '^(\\\\|//)') {
                    throw ("Unsafe report directory: $ReportPath. Report directory must be a local " +
                        "absolute path without '..' traversal.")
                }
                $ReportPath = [System.IO.Path]::GetFullPath($ReportPath)
                if (-not (Test-Path -LiteralPath $ReportPath -PathType Container)) {
                    New-Item -ItemType Directory -Path $ReportPath -Force -ErrorAction Stop | Out-Null
                }

                $Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
                $RunId = [Guid]::NewGuid().ToString('N').Substring(0, 8)
                $TimestampRunId = "${Timestamp}_${RunId}"

                # CSV Export
                $CSVPath = Join-Path $ReportPath "SecurityFeatures_${TimestampRunId}.csv"
                $script:Results | Export-Csv -Path $CSVPath -NoTypeInformation -ErrorAction Stop
                Write-Host "`n[+] CSV Report: $CSVPath" -ForegroundColor Green

                # HTML Export
                $HTMLPath = Join-Path $ReportPath "SecurityFeatures_${TimestampRunId}.html"
                $HTML = @"
<!DOCTYPE html>
<html>
<head>
    <title>Security Features Report - $Timestamp</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background-color: #f5f5f5; }
        h1 { color: #2c3e50; border-bottom: 3px solid #3498db; padding-bottom: 10px; }
        h2 { color: #34495e; margin-top: 30px; }
        .summary { background-color: #ecf0f1; padding: 15px; border-radius: 5px; margin: 20px 0; }
        .summary-item { display: inline-block; margin-right: 30px; font-size: 18px; }
        .score { font-size: 48px; font-weight: bold; margin: 20px 0; }
        .score.good { color: #27ae60; }
        .score.medium { color: #f39c12; }
        .score.poor { color: #e74c3c; }
        table { border-collapse: collapse; width: 100%; margin-top: 20px; background-color: white;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        th { background-color: #3498db; color: white; padding: 12px; text-align: left; }
        td { padding: 10px; border-bottom: 1px solid #ddd; }
        tr:hover { background-color: #f5f5f5; }
        .enabled { color: #27ae60; font-weight: bold; }
        .disabled { color: #e74c3c; font-weight: bold; }
        .not-available { color: #f39c12; font-weight: bold; }
    </style>
</head>
<body>
    <h1>Security Features Assessment Report</h1>
    <p><strong>Generated:</strong> $(Get-Date -Format "yyyy-MM-dd HH:mm:ss") | <strong>Run ID:</strong> $RunId</p>
    <p><strong>Computer:</strong> $([System.Net.WebUtility]::HtmlEncode("$env:COMPUTERNAME"))</p>

    <div class="summary">
        <div class="summary-item"><strong>Total Features:</strong> $TotalFeatures</div>
        <div class="summary-item"><strong>Enabled:</strong> <span style="color: #27ae60;">$EnabledFeatures</span></div>
        <div class="summary-item"><strong>Disabled:</strong>
            <span style="color: #e74c3c;">$DisabledFeatures</span></div>
    </div>

    <div class="score $(if ($SecurityScore -ge 80) { 'good' } elseif ($SecurityScore -ge 60)
        { 'medium' } else { 'poor' })">
        Security Score: $SecurityScore%
    </div>

    <h2>Feature Details</h2>
    <table>
        <tr>
            <th>Feature</th>
            <th>Status</th>
            <th>Details</th>
            <th>Recommendation</th>
        </tr>
"@

                foreach ($Result in $script:Results) {
                    $StatusClass = switch ($Result.Status) {
                        'Enabled' { 'enabled' }
                        'Disabled' { 'disabled' }
                        default { 'not-available' }
                    }

                    $HTML += @"
        <tr>
            <td><strong>$([System.Net.WebUtility]::HtmlEncode("$($Result.Feature)"))</strong></td>
            <td class="$StatusClass">$([System.Net.WebUtility]::HtmlEncode("$($Result.Status)"))</td>
            <td>$([System.Net.WebUtility]::HtmlEncode("$($Result.Details)"))</td>
            <td>$([System.Net.WebUtility]::HtmlEncode("$($Result.Recommendation)"))</td>
        </tr>
"@
                }

                $HTML += @"
    </table>
</body>
</html>
"@

                $HTML | Out-File -FilePath $HTMLPath -Encoding UTF8 -ErrorAction Stop
                Write-Host "[+] HTML Report: $HTMLPath" -ForegroundColor Green
            }
        }

        # Exit code contract: 0 = all features enabled, 1 = issues found
        if ($script:IssuesFound) {
            Write-Host "`n[!] Security assessment completed with missing features.`n" -ForegroundColor Yellow
            return 1
        }

        Write-Host "`n[+] Security assessment completed. All features enabled.`n" -ForegroundColor Green
        return 0
    }
    catch {
        Write-Host "[-] Error: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main @PSBoundParameters) }
