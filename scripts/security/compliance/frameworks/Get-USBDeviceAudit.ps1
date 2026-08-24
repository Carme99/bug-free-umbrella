<#
.SYNOPSIS
    Audits USB device connections and usage on Windows devices.

.DESCRIPTION
    This script provides a comprehensive audit of USB devices connected to Windows devices:
    - Lists currently connected USB devices (via Win32_PnPEntity)
    - Shows historical USB device connections from the USBSTOR registry key
    - Identifies unauthorized or unknown USB devices against an authorized vendor list
    - Provides device serial numbers, manufacturers, and connection history

    Side effects: none by default (console only); when -OutputFormat requests HTML and/or CSV,
    report files are written under -OutputPath. Exit codes: 0 = audit completed; 1 = an error
    occurred.

.PARAMETER OutputFormat
    Specifies the output format: None, HTML, CSV, or All. Default is None (console only).

.PARAMETER OutputPath
    Path to save the output file(s). Default is current directory.

.PARAMETER IncludeHistory
    Include historical USB device connections from the registry. Default is $true.

.PARAMETER HighlightUnauthorized
    Highlight devices not in the authorized list. Default is $true.

.PARAMETER AuthorizedVendors
    Array of authorized vendor IDs (VID). Devices from other vendors will be flagged.

.EXAMPLE
    PS C:\> .\Get-USBDeviceAudit.ps1 -OutputFormat HTML -OutputPath "C:\Reports"

    Generates an HTML report of USB devices and saves it to C:\Reports.

.EXAMPLE
    PS C:\> .\Get-USBDeviceAudit.ps1 -AuthorizedVendors @("045E", "046D") -HighlightUnauthorized $true

    Audits USB devices and highlights those not from Microsoft (045E) or Logitech (046D).

.NOTES
    File Name   : Get-USBDeviceAudit.ps1
    Author      : Bug-Free Umbrella
    Prerequisite: PowerShell 7.0
    Version     : 1.0.0
    Date        : 2026-08-23
#>

[CmdletBinding(SupportsShouldProcess)]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
    Justification = 'Spec-mandated console reporting with [+] / [!] / [-] / [*] prefixes')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '',
    Justification = 'Script parameters are consumed inside function Main via dynamic scoping')]
param(
    [Parameter()]
    [ValidateSet('None', 'HTML', 'CSV', 'All')]
    [string]$OutputFormat = 'None',

    [Parameter()]
    [string]$OutputPath = (Get-Location),

    [Parameter()]
    [bool]$IncludeHistory = $true,

    [Parameter()]
    [bool]$HighlightUnauthorized = $true,

    [Parameter()]
    [string[]]$AuthorizedVendors = @()  # Example: @("045E", "046D", "8087")
)

$ErrorActionPreference = 'Stop'

function Main {
    [CmdletBinding()]
    param(
        [ValidateSet('None', 'HTML', 'CSV', 'All')]
        [string]$OutputFormat = 'None',

        [string]$OutputPath = (Get-Location),

        [bool]$IncludeHistory = $true,

        [bool]$HighlightUnauthorized = $true,

        [string[]]$AuthorizedVendors = @()
    )

    try {
        # Initialize results array (reset on every Main call so repeated runs behave identically)
        $results = @()

        Write-Host "[*] === USB Device Audit ===" -ForegroundColor Cyan
        Write-Host "[*] Scanning for USB devices..." -ForegroundColor Cyan

        # Get currently connected USB devices via CIM
        $connectedDevices = Get-CimInstance -ClassName Win32_PnPEntity -ErrorAction Stop | Where-Object {
            $_.DeviceID -match "^USB"
        }

        foreach ($device in $connectedDevices) {
            # Parse USB device information
            $deviceID = $device.DeviceID
            $vidPid = if ($deviceID -match "VID_([0-9A-F]{4}).*PID_([0-9A-F]{4})") {
                @{VID = $matches[1]; PID = $matches[2] }
            }
            else {
                @{VID = "Unknown"; PID = "Unknown" }
            }

            $serialNumber = if ($deviceID -match "\\([^\\]+)$") {
                $matches[1]
            }
            else {
                "N/A"
            }

            $isAuthorized = if ($AuthorizedVendors.Count -eq 0) {
                "N/A"
            }
            elseif ($AuthorizedVendors -contains $vidPid.VID) {
                "Yes"
            }
            else {
                "No"
            }

            $results += [PSCustomObject]@{
                Name = $device.Name
                Status = $device.Status
                Manufacturer = $device.Manufacturer
                DeviceID = $deviceID
                VendorID = $vidPid.VID
                ProductID = $vidPid.PID
                SerialNumber = $serialNumber
                IsAuthorized = $isAuthorized
                CurrentlyConnected = "Yes"
                FirstSeen = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
                Source = "Current"
            }
        }

        # Get historical USB devices from registry
        if ($IncludeHistory) {
            Write-Host "[*] Scanning USB device history from registry..." -ForegroundColor Cyan

            $usbStorKey = "HKLM:\SYSTEM\CurrentControlSet\Enum\USBSTOR"
            if (Test-Path -Path $usbStorKey) {
                $historicalDevices = Get-ChildItem -Path $usbStorKey -ErrorAction Stop

                foreach ($deviceKey in $historicalDevices) {
                    $deviceInstances = Get-ChildItem -Path $deviceKey.PSPath -ErrorAction Stop

                    foreach ($instance in $deviceInstances) {
                        try {
                            $props = Get-ItemProperty -Path $instance.PSPath -ErrorAction SilentlyContinue

                            # Extract device information
                            $friendlyName = "$($props.FriendlyName)" -replace '^.*\s+', ''
                            $serialNum = $instance.PSChildName

                            # Parse manufacturer and model from device key name
                            $deviceName = $deviceKey.PSChildName
                            $manufacturer = if ($deviceName -match "^([^&]+)&") {
                                $matches[1]
                            }
                            else {
                                "Unknown"
                            }

                            # Check if already in results (currently connected)
                            $existingDevice = $results | Where-Object {
                                $_.SerialNumber -eq $serialNum
                            }

                            if (-not $existingDevice) {
                                $results += [PSCustomObject]@{
                                    Name = $friendlyName
                                    Status = "Historical"
                                    Manufacturer = $manufacturer
                                    DeviceID = $deviceName
                                    VendorID = "N/A"
                                    ProductID = "N/A"
                                    SerialNumber = $serialNum
                                    IsAuthorized = "N/A"
                                    CurrentlyConnected = "No"
                                    FirstSeen = if ($props.PSObject.Properties['InstallDate']) {
                                        $props.InstallDate
                                    }
                                    else {
                                        "Unknown"
                                    }
                                    Source = "Registry"
                                }
                            }
                        }
                        catch {
                            Write-Verbose "Could not process device instance: $($instance.PSChildName)"
                        }
                    }
                }
            }
        }

        # Display results
        Write-Host "`n[*] === USB Device Audit Results ===" -ForegroundColor Cyan
        Write-Host "[+] Total devices found: $($results.Count)" -ForegroundColor Green
        $connectedCount = ($results | Where-Object {$_.CurrentlyConnected -eq 'Yes'}).Count
        Write-Host "[+] Currently connected: $connectedCount" -ForegroundColor Green
        if ($IncludeHistory) {
            $historicalCount = ($results | Where-Object {$_.CurrentlyConnected -eq 'No'}).Count
            Write-Host "[*] Historical devices: $historicalCount" -ForegroundColor Yellow
        }
        if ($HighlightUnauthorized -and $AuthorizedVendors.Count -gt 0) {
            $unauthorized = ($results | Where-Object { $_.IsAuthorized -eq 'No' }).Count
            $prefix = if ($unauthorized -gt 0) { '[-]' } else { '[+]' }
            $unauthColor = if ($unauthorized -gt 0) { 'Red' } else { 'Green' }
            Write-Host "$prefix Unauthorized devices: $unauthorized" -ForegroundColor $unauthColor
        }

        # Output to console
        Write-Host "`n[*] === Device Details ===" -ForegroundColor Cyan
        $detailProps = 'Name', 'Manufacturer', 'VendorID', 'ProductID',
            'IsAuthorized', 'CurrentlyConnected', 'Source'
        $results | Format-Table -Property $detailProps -AutoSize | Out-Host

        # Generate reports
        if ($OutputFormat -eq 'HTML' -or $OutputFormat -eq 'All') {
            $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
            $htmlPath = Join-Path $OutputPath "USBDeviceAudit_$timestamp.html"

            $unauthorizedStyle = if ($HighlightUnauthorized) { "background-color: #ffcccc;" } else { "" }

            $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>USB Device Audit Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        h1 { color: #333; }
        table { border-collapse: collapse; width: 100%; margin-top: 20px; }
        th { background-color: #4CAF50; color: white; padding: 12px; text-align: left; }
        td { border: 1px solid #ddd; padding: 8px; }
        tr:nth-child(even) { background-color: #f2f2f2; }
        .unauthorized { $unauthorizedStyle }
        .summary { background-color: #e7f3fe; padding: 15px; border-left: 6px solid #2196F3; margin-bottom: 20px; }
    </style>
</head>
<body>
    <h1>USB Device Audit Report</h1>
    <div class="summary">
        <p><strong>Generated:</strong> $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")</p>
        <p><strong>Total Devices:</strong> $($results.Count)</p>
        <p><strong>Currently Connected:</strong> $connectedCount</p>
        <p><strong>Historical Devices:</strong> $(($results | Where-Object {$_.CurrentlyConnected -eq 'No'}).Count)</p>
    </div>
    <table>
        <tr>
            <th>Name</th>
            <th>Manufacturer</th>
            <th>Vendor ID</th>
            <th>Product ID</th>
            <th>Serial Number</th>
            <th>Authorized</th>
            <th>Connected</th>
            <th>First Seen</th>
        </tr>
"@

            foreach ($device in $results) {
                $rowClass = if ($device.IsAuthorized -eq 'No') { 'class="unauthorized"' } else { '' }
                $html += @"
        <tr $rowClass>
            <td>$([System.Net.WebUtility]::HtmlEncode("$($device.Name)"))</td>
            <td>$([System.Net.WebUtility]::HtmlEncode("$($device.Manufacturer)"))</td>
            <td>$([System.Net.WebUtility]::HtmlEncode("$($device.VendorID)"))</td>
            <td>$([System.Net.WebUtility]::HtmlEncode("$($device.ProductID)"))</td>
            <td>$([System.Net.WebUtility]::HtmlEncode("$($device.SerialNumber)"))</td>
            <td>$([System.Net.WebUtility]::HtmlEncode("$($device.IsAuthorized)"))</td>
            <td>$([System.Net.WebUtility]::HtmlEncode("$($device.CurrentlyConnected)"))</td>
            <td>$([System.Net.WebUtility]::HtmlEncode("$($device.FirstSeen)"))</td>
        </tr>
"@
            }

            $html += @"
    </table>
</body>
</html>
"@

            $html | Out-File -FilePath $htmlPath -Encoding UTF8 -ErrorAction Stop
            Write-Host "`n[+] HTML report saved to: $htmlPath" -ForegroundColor Green
        }

        if ($OutputFormat -eq 'CSV' -or $OutputFormat -eq 'All') {
            $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
            $csvPath = Join-Path $OutputPath "USBDeviceAudit_$timestamp.csv"
            $results | Export-Csv -Path $csvPath -NoTypeInformation -ErrorAction Stop
            Write-Host "[+] CSV report saved to: $csvPath" -ForegroundColor Green
        }

        Write-Host "`n[+] USB device audit completed.`n" -ForegroundColor Green
        return 0
    }
    catch {
        Write-Host "[-] Error: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
