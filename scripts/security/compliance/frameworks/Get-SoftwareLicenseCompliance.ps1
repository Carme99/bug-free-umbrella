<#
.SYNOPSIS
    Audits installed software and checks license compliance status.

.DESCRIPTION
    This script inventories all installed software on Windows devices and provides:
    - Complete list of installed applications with versions
    - License key detection for major applications
    - Software installation dates and publishers
    - Identification of unauthorized or unlicensed software
    - Duplicate software detection
    - Export to HTML and CSV formats

.PARAMETER OutputFormat
    Specifies the output format: None, HTML, CSV, or All. Default is None (console only).

.PARAMETER OutputPath
    Path to save the output file(s). Default is current directory.

.PARAMETER CheckLicenseKeys
    Attempt to retrieve license keys for major software. Default is $true.

.PARAMETER HighlightUnlicensed
    Highlight potentially unlicensed software. Default is $true.

.EXAMPLE
    .\Get-SoftwareLicenseCompliance.ps1 -OutputFormat HTML -OutputPath "C:\Reports"

    Generates an HTML inventory report of installed software.

.EXAMPLE
    .\Get-SoftwareLicenseCompliance.ps1 -CheckLicenseKeys -HighlightUnlicensed

    Audits software with license key detection and highlights unlicensed products.

.NOTES
    File Name      : Get-SoftwareLicenseCompliance.ps1
    Requires       : PowerShell 5.1+, Administrator privileges for full key access
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
    [bool]$CheckLicenseKeys = $true,

    [Parameter()]
    [bool]$HighlightUnlicensed = $true
)

Write-Host "=== Software License Compliance Audit ===" -ForegroundColor Cyan
Write-Host "Scanning installed software..." -ForegroundColor Yellow

# Initialize results array
$softwareInventory = @()

# Registry paths for installed software
$registryPaths = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
)

# Get installed software from registry
foreach ($path in $registryPaths) {
    try {
        $installedSoftware = Get-ItemProperty $path -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName } |
            Select-Object DisplayName, DisplayVersion, Publisher, InstallDate, InstallLocation, UninstallString

        foreach ($app in $installedSoftware) {
            $licenseKey = "N/A"
            $licenseStatus = "Unknown"

            # Attempt to find license key if enabled
            if ($CheckLicenseKeys) {
                $productName = $app.DisplayName

                # Check for Office license
                if ($productName -match "Microsoft Office|Microsoft 365") {
                    try {
                        $officeLicense = Get-CimInstance -Query "SELECT * FROM SoftwareLicensingProduct WHERE ApplicationID = '0ff1ce15-a989-479d-af46-f275c6370663' AND LicenseStatus = 1" -ErrorAction SilentlyContinue
                        if ($officeLicense) {
                            $licenseKey = $officeLicense.ProductKeyID
                            $licenseStatus = "Licensed"
                        }
                        else {
                            $licenseStatus = "Unlicensed"
                        }
                    }
                    catch {
                        $licenseStatus = "Unknown"
                    }
                }

                # Check for Windows license
                if ($productName -match "Windows|Microsoft Windows") {
                    try {
                        $windowsLicense = Get-CimInstance -Query "SELECT * FROM SoftwareLicensingProduct WHERE ApplicationID = '55c92734-d682-4d71-983e-d6ec3f16059f' AND LicenseStatus = 1" -ErrorAction SilentlyContinue
                        if ($windowsLicense) {
                            $licenseKey = $windowsLicense.ProductKeyID
                            $licenseStatus = "Licensed"
                        }
                        else {
                            $licenseStatus = "Unlicensed"
                        }
                    }
                    catch {
                        $licenseStatus = "Unknown"
                    }
                }

                # For other software, check common registry locations
                if ($licenseKey -eq "N/A" -and $app.DisplayName) {
                    # Sanitize registry path components to prevent invalid paths (spaces are valid in registry keys)
                    $safePublisher = $app.Publisher -replace '[\\/:*?"<>|]', '_'
                    $safeDisplayName = $app.DisplayName -replace '[\\/:*?"<>|]', '_'

                    $possibleKeyPaths = @(
                        "HKLM:\SOFTWARE\$safePublisher\$safeDisplayName",
                        "HKCU:\SOFTWARE\$safePublisher\$safeDisplayName"
                    )

                    foreach ($keyPath in $possibleKeyPaths) {
                        try {
                            if (Test-Path -LiteralPath $keyPath) {
                                $regProps = Get-ItemProperty -LiteralPath $keyPath -ErrorAction SilentlyContinue
                                $keyProps = $regProps.PSObject.Properties | Where-Object {
                                    $_.Name -match "Key|License|Serial|Product.*Key"
                                }

                                if ($keyProps) {
                                    $licenseKey = $keyProps[0].Value
                                    $licenseStatus = if ($licenseKey) { "Licensed" } else { "Unknown" }
                                    break
                                }
                            }
                        }
                        catch {
                            Write-Verbose "Handled exception: $($_.Exception.Message)" -Verbose:$false
                        }
                    }
                }
            }

            # Parse install date
            $installDate = if ($app.InstallDate) {
                try {
                    [datetime]::ParseExact($app.InstallDate, "yyyyMMdd", $null).ToString("yyyy-MM-dd")
                }
                catch {
                    $app.InstallDate
                }
            }
            else {
                "Unknown"
            }

            $softwareInventory += [PSCustomObject]@{
                Name = $app.DisplayName
                Version = $app.DisplayVersion
                Publisher = $app.Publisher
                InstallDate = $installDate
                InstallLocation = $app.InstallLocation
                LicenseKey = $licenseKey
                LicenseStatus = $licenseStatus
            }
        }
    }
    catch {
        Write-Verbose "Could not access registry path: $path"
    }
}

# Remove duplicates (same app from different registry locations)
$softwareInventory = $softwareInventory | Sort-Object Name, Version -Unique

Write-Host "`n=== Software Inventory Results ===" -ForegroundColor Cyan
Write-Host "Total applications found: $($softwareInventory.Count)" -ForegroundColor Green

if ($CheckLicenseKeys) {
    $licensed = ($softwareInventory | Where-Object { $_.LicenseStatus -eq 'Licensed' }).Count
    $unlicensed = ($softwareInventory | Where-Object { $_.LicenseStatus -eq 'Unlicensed' }).Count
    $unknown = ($softwareInventory | Where-Object { $_.LicenseStatus -eq 'Unknown' }).Count

    Write-Host "Licensed software: $licensed" -ForegroundColor Green
    Write-Host "Unlicensed software: $unlicensed" -ForegroundColor $(if ($unlicensed -gt 0) { 'Red' } else { 'Green' })
    Write-Host "Unknown license status: $unknown" -ForegroundColor Yellow
}

# Display software inventory
Write-Host "`n=== Top 20 Installed Applications ===" -ForegroundColor Cyan
$softwareInventory | Select-Object Name, Version, Publisher, LicenseStatus -First 20 | Format-Table -AutoSize

# Identify potentially problematic software
if ($HighlightUnlicensed) {
    $unlicensedSoftware = $softwareInventory | Where-Object {
        $_.LicenseStatus -eq 'Unlicensed' -and $_.Name -match "Microsoft Office|Windows|Adobe|AutoCAD"
    }

    if ($unlicensedSoftware) {
        Write-Host "`n=== WARNING: Potentially Unlicensed Critical Software ===" -ForegroundColor Red
        $unlicensedSoftware | Format-Table -Property Name, Version, Publisher -AutoSize
    }
}

# Detect duplicate installations
$duplicates = $softwareInventory | Group-Object Name | Where-Object { $_.Count -gt 1 }
if ($duplicates) {
    Write-Host "`n=== Duplicate Software Installations Detected ===" -ForegroundColor Yellow
    foreach ($dup in $duplicates) {
        Write-Host "$($dup.Name) - Installed $($dup.Count) times" -ForegroundColor Yellow
        $dup.Group | Format-Table -Property Version, InstallDate -AutoSize
    }
}

# Generate HTML report
if ($OutputFormat -eq 'HTML' -or $OutputFormat -eq 'All') {
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $htmlPath = Join-Path $OutputPath "SoftwareLicenseCompliance_$timestamp.html"

    $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>Software License Compliance Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        h1 { color: #333; }
        table { border-collapse: collapse; width: 100%; margin-top: 20px; }
        th { background-color: #4CAF50; color: white; padding: 12px; text-align: left; }
        td { border: 1px solid #ddd; padding: 8px; }
        tr:nth-child(even) { background-color: #f2f2f2; }
        .unlicensed { background-color: #ffcccc; }
        .licensed { background-color: #ccffcc; }
        .summary { background-color: #e7f3fe; padding: 15px; border-left: 6px solid #2196F3; margin-bottom: 20px; }
    </style>
</head>
<body>
    <h1>Software License Compliance Report</h1>
    <div class="summary">
        <p><strong>Generated:</strong> $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")</p>
        <p><strong>Total Applications:</strong> $($softwareInventory.Count)</p>
        <p><strong>Licensed:</strong> <span style="color: green;">$(($softwareInventory | Where-Object {$_.LicenseStatus -eq 'Licensed'}).Count)</span></p>
        <p><strong>Unlicensed:</strong> <span style="color: red;">$(($softwareInventory | Where-Object {$_.LicenseStatus -eq 'Unlicensed'}).Count)</span></p>
        <p><strong>Unknown Status:</strong> $(($softwareInventory | Where-Object {$_.LicenseStatus -eq 'Unknown'}).Count)</p>
    </div>
    <table>
        <tr>
            <th>Application</th>
            <th>Version</th>
            <th>Publisher</th>
            <th>Install Date</th>
            <th>License Status</th>
        </tr>
"@

    foreach ($app in $softwareInventory) {
        $rowClass = switch ($app.LicenseStatus) {
            'Licensed' { 'class="licensed"' }
            'Unlicensed' { 'class="unlicensed"' }
            default { '' }
        }

        $html += @"
        <tr $rowClass>
            <td>$($app.Name)</td>
            <td>$($app.Version)</td>
            <td>$($app.Publisher)</td>
            <td>$($app.InstallDate)</td>
            <td>$($app.LicenseStatus)</td>
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

# Generate CSV report
if ($OutputFormat -eq 'CSV' -or $OutputFormat -eq 'All') {
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $csvPath = Join-Path $OutputPath "SoftwareLicenseCompliance_$timestamp.csv"
    $softwareInventory | Export-Csv -Path $csvPath -NoTypeInformation
    Write-Host "CSV report saved to: $csvPath" -ForegroundColor Green
}

# Return results
return $softwareInventory
