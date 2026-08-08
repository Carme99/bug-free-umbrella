<#
.SYNOPSIS
    Audits USB device connections and usage on Windows devices.

.DESCRIPTION
    This script provides a comprehensive audit of USB devices connected to Windows devices:
    - Lists currently connected USB devices
    - Shows historical USB device connections (from registry)
    - Identifies unauthorized or unknown USB devices
    - Provides device serial numbers, manufacturers, and connection history
    - Supports export to HTML and CSV formats

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
    .\Get-USBDeviceAudit.ps1 -OutputFormat HTML -OutputPath "C:\Reports"

    Generates an HTML report of USB devices and saves to C:\Reports.

.EXAMPLE
    .\Get-USBDeviceAudit.ps1 -AuthorizedVendors @("045E", "046D") -HighlightUnauthorized

    Audits USB devices and highlights those not from Microsoft (045E) or Logitech (046D).

.NOTES
    File Name      : Get-USBDeviceAudit.ps1
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
    [bool]$IncludeHistory = $true,

    [Parameter()]
    [bool]$HighlightUnauthorized = $true,

    [Parameter()]
    [string[]]$AuthorizedVendors = @()  # Example: @("045E", "046D", "8087")
)

# Initialize results array
$results = @()

Write-Host "=== USB Device Audit ===" -ForegroundColor Cyan
Write-Host "Scanning for USB devices..." -ForegroundColor Yellow

# Get currently connected USB devices via CIM
$connectedDevices = Get-CimInstance -ClassName Win32_PnPEntity | Where-Object {
    $_.DeviceID -match "^USB"
}

foreach ($device in $connectedDevices) {
    # Parse USB device information
    $deviceID = $device.DeviceID
    $vidPid = if ($deviceID -match "VID_([0-9A-F]{4}).*PID_([0-9A-F]{4})") {
        @{VID = $matches[1]; PID = $matches[2]}
    } else {
        @{VID = "Unknown"; PID = "Unknown"}
    }

    $serialNumber = if ($deviceID -match "\\([^\\]+)$") {
        $matches[1]
    } else {
        "N/A"
    }

    $isAuthorized = if ($AuthorizedVendors.Count -eq 0) {
        "N/A"
    } elseif ($AuthorizedVendors -contains $vidPid.VID) {
        "Yes"
    } else {
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
    Write-Host "Scanning USB device history from registry..." -ForegroundColor Yellow

    $usbStorKey = "HKLM:\SYSTEM\CurrentControlSet\Enum\USBSTOR"
    if (Test-Path $usbStorKey) {
        $historicalDevices = Get-ChildItem -Path $usbStorKey

        foreach ($deviceKey in $historicalDevices) {
            $deviceInstances = Get-ChildItem -Path $deviceKey.PSPath

            foreach ($instance in $deviceInstances) {
                try {
                    $props = Get-ItemProperty -Path $instance.PSPath -ErrorAction SilentlyContinue

                    # Extract device information
                    $friendlyName = $props.FriendlyName -replace '^.*\s+', ''
                    $serialNum = $instance.PSChildName

                    # Parse manufacturer and model from device key name
                    $deviceName = $deviceKey.PSChildName
                    $manufacturer = if ($deviceName -match "^([^&]+)&") {
                        $matches[1]
                    } else {
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
                            } else {
                                "Unknown"
                            }
                            Source = "Registry"
                        }
                    }
                } catch {
                    Write-Verbose "Could not process device instance: $($instance.PSChildName)"
                }
            }
        }
    }
}

# Display results
Write-Host "`n=== USB Device Audit Results ===" -ForegroundColor Cyan
Write-Host "Total devices found: $($results.Count)" -ForegroundColor Green
Write-Host "Currently connected: $(($results | Where-Object {$_.CurrentlyConnected -eq 'Yes'}).Count)" -ForegroundColor Green
if ($IncludeHistory) {
    Write-Host "Historical devices: $(($results | Where-Object {$_.CurrentlyConnected -eq 'No'}).Count)" -ForegroundColor Yellow
}
if ($HighlightUnauthorized -and $AuthorizedVendors.Count -gt 0) {
    $unauthorized = ($results | Where-Object {$_.IsAuthorized -eq 'No'}).Count
    Write-Host "Unauthorized devices: $unauthorized" -ForegroundColor $(if ($unauthorized -gt 0) { 'Red' } else { 'Green' })
}

# Output to console
Write-Host "`n=== Device Details ===" -ForegroundColor Cyan
$results | Format-Table -Property Name, Manufacturer, VendorID, ProductID, IsAuthorized, CurrentlyConnected, Source -AutoSize

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
        <p><strong>Currently Connected:</strong> $(($results | Where-Object {$_.CurrentlyConnected -eq 'Yes'}).Count)</p>
        <p><strong>Historical Devices:</strong> $(($results | Where-Object {$_.CurrentlyConnected -eq 'No'}).Count)</p>
        $(if ($HighlightUnauthorized -and $AuthorizedVendors.Count -gt 0) {
            "<p><strong>Unauthorized Devices:</strong> <span style='color: red;'>$(($results | Where-Object {$_.IsAuthorized -eq 'No'}).Count)</span></p>"
        })
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
            <td>$($device.Name)</td>
            <td>$($device.Manufacturer)</td>
            <td>$($device.VendorID)</td>
            <td>$($device.ProductID)</td>
            <td>$($device.SerialNumber)</td>
            <td>$($device.IsAuthorized)</td>
            <td>$($device.CurrentlyConnected)</td>
            <td>$($device.FirstSeen)</td>
        </tr>
"@
    }

    $html += @"
    </table>
</body>
</html>
"@

    $html | Out-File -FilePath $htmlPath -Encoding UTF8
    Write-Host "`nHTML report saved to: $htmlPath" -ForegroundColor Green
}

if ($OutputFormat -eq 'CSV' -or $OutputFormat -eq 'All') {
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $csvPath = Join-Path $OutputPath "USBDeviceAudit_$timestamp.csv"
    $results | Export-Csv -Path $csvPath -NoTypeInformation
    Write-Host "CSV report saved to: $csvPath" -ForegroundColor Green
}

# Return results object
return $results
