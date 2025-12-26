<#
.SYNOPSIS
    Generates comprehensive software inventory report for Windows systems.

.DESCRIPTION
    This script creates detailed software inventory including:
    - Installed applications (Programs and Features)
    - Microsoft Store apps
    - Winget-installed applications
    - Windows Updates/Patches
    - Installed Windows Features
    - Browser extensions (optional)
    - Software versions and install dates
    - License information (where available)

.PARAMETER IncludeUpdates
    Include Windows Updates in the inventory.

.PARAMETER IncludeFeatures
    Include Windows Features in the inventory.

.PARAMETER IncludeStoreApps
    Include Microsoft Store apps.

.PARAMETER IncludeWinget
    Include winget-managed applications.

.PARAMETER ExportHTML
    Export results to HTML report.

.PARAMETER ExportCSV
    Export results to CSV file.

.PARAMETER ExportJSON
    Export results to JSON file for automation.

.EXAMPLE
    .\Get-SoftwareInventory.ps1
    Generates basic software inventory.

.EXAMPLE
    .\Get-SoftwareInventory.ps1 -IncludeUpdates -IncludeFeatures -ExportHTML
    Comprehensive inventory with updates and features.

.EXAMPLE
    .\Get-SoftwareInventory.ps1 -IncludeWinget -ExportJSON
    Inventory including winget apps, exported to JSON.

.NOTES
    Requires Administrator privileges for full inventory
    Compatible with Windows 10, 11, Server 2016, 2019, 2022
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [switch]$IncludeUpdates,

    [Parameter(Mandatory=$false)]
    [switch]$IncludeFeatures,

    [Parameter(Mandatory=$false)]
    [switch]$IncludeStoreApps,

    [Parameter(Mandatory=$false)]
    [switch]$IncludeWinget,

    [Parameter(Mandatory=$false)]
    [switch]$ExportHTML,

    [Parameter(Mandatory=$false)]
    [switch]$ExportCSV,

    [Parameter(Mandatory=$false)]
    [switch]$ExportJSON
)

$ErrorActionPreference = "Continue"
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"

Write-Host "`n=== Software Inventory Report ===" -ForegroundColor Cyan
Write-Host "Computer: $env:COMPUTERNAME" -ForegroundColor Yellow
Write-Host "Generated: $(Get-Date)" -ForegroundColor Gray
Write-Host ""

$inventory = @{
    ComputerName = $env:COMPUTERNAME
    Timestamp = Get-Date
    InstalledApplications = @()
    StoreApps = @()
    WingetApps = @()
    WindowsUpdates = @()
    WindowsFeatures = @()
}

# 1. Get installed applications
Write-Host "[*] Scanning installed applications..." -ForegroundColor Cyan

$regPaths = @(
    'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
)

foreach ($path in $regPaths) {
    try {
        $apps = Get-ItemProperty $path -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName } |
            Select-Object DisplayName, DisplayVersion, Publisher, InstallDate, InstallLocation, UninstallString

        foreach ($app in $apps) {
            $inventory.InstalledApplications += [PSCustomObject]@{
                Name = $app.DisplayName
                Version = $app.DisplayVersion
                Publisher = $app.Publisher
                InstallDate = $app.InstallDate
                InstallLocation = $app.InstallLocation
                UninstallString = $app.UninstallString
            }
        }
    }
    catch {
        Write-Host "[-] Error reading $path : $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Remove duplicates
$inventory.InstalledApplications = $inventory.InstalledApplications | Sort-Object Name -Unique

Write-Host "[+] Found $($inventory.InstalledApplications.Count) installed applications" -ForegroundColor Green

# 2. Get Microsoft Store apps
if ($IncludeStoreApps) {
    Write-Host "[*] Scanning Microsoft Store apps..." -ForegroundColor Cyan

    try {
        $storeApps = Get-AppxPackage | Select-Object Name, Version, Publisher, InstallLocation

        foreach ($app in $storeApps) {
            $inventory.StoreApps += [PSCustomObject]@{
                Name = $app.Name
                Version = $app.Version
                Publisher = $app.Publisher
                InstallLocation = $app.InstallLocation
            }
        }

        Write-Host "[+] Found $($inventory.StoreApps.Count) Store apps" -ForegroundColor Green
    }
    catch {
        Write-Host "[-] Error scanning Store apps: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# 3. Get Winget apps
if ($IncludeWinget) {
    Write-Host "[*] Scanning winget-managed applications..." -ForegroundColor Cyan

    try {
        $wingetList = winget list --accept-source-agreements 2>$null |
            Select-String -Pattern "^[a-zA-Z0-9]" |
            ForEach-Object { $_.Line }

        # Parse winget output
        foreach ($line in $wingetList) {
            if ($line -match '^(.+?)\s{2,}(.+?)\s{2,}(.+?)$') {
                $inventory.WingetApps += [PSCustomObject]@{
                    Name = $Matches[1].Trim()
                    ID = $Matches[2].Trim()
                    Version = $Matches[3].Trim()
                }
            }
        }

        Write-Host "[+] Found $($inventory.WingetApps.Count) winget apps" -ForegroundColor Green
    }
    catch {
        Write-Host "[-] Winget not available or error occurred" -ForegroundColor Yellow
    }
}

# 4. Get Windows Updates
if ($IncludeUpdates) {
    Write-Host "[*] Scanning installed Windows Updates..." -ForegroundColor Cyan

    try {
        $session = New-Object -ComObject Microsoft.Update.Session
        $searcher = $session.CreateUpdateSearcher()
        $historyCount = $searcher.GetTotalHistoryCount()

        if ($historyCount -gt 0) {
            $updates = $searcher.QueryHistory(0, [Math]::Min(100, $historyCount)) |
                Where-Object { $_.ResultCode -eq 2 } |
                Select-Object -First 50

            foreach ($update in $updates) {
                $inventory.WindowsUpdates += [PSCustomObject]@{
                    Title = $update.Title
                    Date = $update.Date
                    Description = $update.Description
                }
            }

            Write-Host "[+] Found $($inventory.WindowsUpdates.Count) recent updates" -ForegroundColor Green
        }
    }
    catch {
        Write-Host "[-] Error scanning Windows Updates: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

# 5. Get Windows Features
if ($IncludeFeatures) {
    Write-Host "[*] Scanning Windows Features..." -ForegroundColor Cyan

    try {
        # Check if this is Windows Server
        $isServer = (Get-WmiObject -Class Win32_OperatingSystem).ProductType -ne 1

        if ($isServer) {
            $features = Get-WindowsFeature | Where-Object { $_.Installed }

            foreach ($feature in $features) {
                $inventory.WindowsFeatures += [PSCustomObject]@{
                    Name = $feature.Name
                    DisplayName = $feature.DisplayName
                    FeatureType = $feature.FeatureType
                }
            }
        }
        else {
            # Windows 10/11
            $features = Get-WindowsOptionalFeature -Online | Where-Object { $_.State -eq "Enabled" }

            foreach ($feature in $features) {
                $inventory.WindowsFeatures += [PSCustomObject]@{
                    Name = $feature.FeatureName
                    State = $feature.State
                }
            }
        }

        Write-Host "[+] Found $($inventory.WindowsFeatures.Count) installed features" -ForegroundColor Green
    }
    catch {
        Write-Host "[-] Error scanning features: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

Write-Host ""

# Display summary
Write-Host "=== Inventory Summary ===" -ForegroundColor Cyan
Write-Host "Installed Applications: $($inventory.InstalledApplications.Count)" -ForegroundColor White
if ($IncludeStoreApps) {
    Write-Host "Microsoft Store Apps: $($inventory.StoreApps.Count)" -ForegroundColor White
}
if ($IncludeWinget) {
    Write-Host "Winget Applications: $($inventory.WingetApps.Count)" -ForegroundColor White
}
if ($IncludeUpdates) {
    Write-Host "Windows Updates: $($inventory.WindowsUpdates.Count)" -ForegroundColor White
}
if ($IncludeFeatures) {
    Write-Host "Windows Features: $($inventory.WindowsFeatures.Count)" -ForegroundColor White
}
Write-Host ""

# Show sample applications
Write-Host "=== Sample Applications ===" -ForegroundColor Cyan
$inventory.InstalledApplications | Select-Object -First 10 Name, Version, Publisher | Format-Table -AutoSize

# Export results
if ($ExportHTML) {
    $htmlPath = "$env:USERPROFILE\Desktop\SoftwareInventory_$timestamp.html"

    $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>Software Inventory - $timestamp</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        h1 { color: #3498db; }
        h2 { color: #2980b9; margin-top: 30px; }
        table { border-collapse: collapse; width: 100%; margin-top: 10px; }
        th { background-color: #3498db; color: white; padding: 10px; text-align: left; }
        td { border: 1px solid #ddd; padding: 8px; font-size: 12px; }
        tr:nth-child(even) { background-color: #f2f2f2; }
        .summary { background-color: #ecf0f1; padding: 15px; border-radius: 5px; margin: 20px 0; }
    </style>
</head>
<body>
    <h1>Software Inventory Report</h1>
    <div class="summary">
        <strong>Computer:</strong> $env:COMPUTERNAME<br>
        <strong>Generated:</strong> $(Get-Date)<br>
        <strong>Total Applications:</strong> $($inventory.InstalledApplications.Count)
    </div>

    <h2>Installed Applications</h2>
    <table>
        <tr><th>Name</th><th>Version</th><th>Publisher</th><th>Install Date</th></tr>
"@

    foreach ($app in ($inventory.InstalledApplications | Sort-Object Name)) {
        $html += "<tr><td>$($app.Name)</td><td>$($app.Version)</td><td>$($app.Publisher)</td><td>$($app.InstallDate)</td></tr>`n"
    }

    $html += "</table>"

    if ($IncludeStoreApps -and $inventory.StoreApps.Count -gt 0) {
        $html += "<h2>Microsoft Store Apps</h2><table><tr><th>Name</th><th>Version</th><th>Publisher</th></tr>"
        foreach ($app in ($inventory.StoreApps | Sort-Object Name)) {
            $html += "<tr><td>$($app.Name)</td><td>$($app.Version)</td><td>$($app.Publisher)</td></tr>`n"
        }
        $html += "</table>"
    }

    $html += "</body></html>"

    $html | Out-File -FilePath $htmlPath -Encoding UTF8
    Write-Host "[+] HTML report saved to: $htmlPath" -ForegroundColor Green
}

if ($ExportCSV) {
    $csvPath = "$env:USERPROFILE\Desktop\SoftwareInventory_$timestamp.csv"
    $inventory.InstalledApplications | Export-Csv -Path $csvPath -NoTypeInformation
    Write-Host "[+] CSV export saved to: $csvPath" -ForegroundColor Green
}

if ($ExportJSON) {
    $jsonPath = "$env:USERPROFILE\Desktop\SoftwareInventory_$timestamp.json"
    $inventory | ConvertTo-Json -Depth 10 | Out-File -FilePath $jsonPath -Encoding UTF8
    Write-Host "[+] JSON export saved to: $jsonPath" -ForegroundColor Green
}

Write-Host "`n[+] Inventory completed!" -ForegroundColor Green
exit 0
