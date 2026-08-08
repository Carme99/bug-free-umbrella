<#
.SYNOPSIS
    Optimizes Windows service startup types for better performance and security.

.DESCRIPTION
    This script analyzes and optimizes Windows services by:
    - Identifying unnecessary services
    - Recommending startup type changes
    - Detecting security risks (unnecessary services)
    - Creating service configuration backup
    - Applying safe optimization changes
    - Generating detailed report

.PARAMETER Mode
    Operation mode: Analyze, Optimize, or Restore.

.PARAMETER Profile
    Optimization profile: Minimal, Balanced, Performance (default: Balanced).

.PARAMETER BackupPath
    Path to save service configuration backup.

.PARAMETER ApplyChanges
    Actually apply the recommended changes (requires confirmation).

.PARAMETER ExportHTML
    Export results to HTML report.

.PARAMETER ExportCSV
    Export results to CSV file.

.EXAMPLE
    .\Optimize-WindowsServices.ps1 -Mode Analyze
    Analyzes current service configuration and provides recommendations.

.EXAMPLE
    .\Optimize-WindowsServices.ps1 -Mode Optimize -Profile Performance -ApplyChanges
    Applies performance-oriented service optimizations.

.EXAMPLE
    .\Optimize-WindowsServices.ps1 -Mode Restore -BackupPath "C:\Backups\services.xml"
    Restores service configuration from backup.

.NOTES
    Requires Administrator privileges
    Creates backup before making changes
    Compatible with Windows 10, 11, Server 2016, 2019, 2022
    Use with caution on production servers
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Analyze', 'Optimize', 'Restore')]
    [string]$Mode,

    [Parameter(Mandatory = $false)]
    [ValidateSet('Minimal', 'Balanced', 'Performance')]
    [string]$Profile = 'Balanced',

    [Parameter(Mandatory = $false)]
    [string]$BackupPath,

    [Parameter(Mandatory = $false)]
    [switch]$ApplyChanges,

    [Parameter(Mandatory = $false)]
    [switch]$ExportHTML,

    [Parameter(Mandatory = $false)]
    [switch]$ExportCSV
)

#Requires -RunAsAdministrator

$ErrorActionPreference = "Stop"
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"

# Reports directory (internal output location)
$ReportDir = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Reports'
# Validate report directory: reject '..' traversal and UNC remote paths before resolution
if ([string]::IsNullOrWhiteSpace($ReportDir) -or
    $ReportDir -match '(^|[\\/])\.\.([\\/]|$)' -or
    $ReportDir -match '^(\\\\|//)') {
    Write-Error "Unsafe report directory: $ReportDir. Report directory must be a local absolute path without '..' traversal."
    exit 1
}
$ReportDir = [System.IO.Path]::GetFullPath($ReportDir)
if (-not (Test-Path -LiteralPath $ReportDir -PathType Container)) {
    New-Item -ItemType Directory -Path $ReportDir -Force | Out-Null
}
Write-Host "Mode: $Mode" -ForegroundColor Yellow
Write-Host "Profile: $Profile" -ForegroundColor Yellow
Write-Host ""

# Service optimization rules
$optimizationRules = @{
    Minimal = @{
        "Fax" = "Disabled"
        "RemoteRegistry" = "Disabled"
        "TapiSrv" = "Disabled"
        "WMPNetworkSvc" = "Disabled"
        "XblAuthManager" = "Disabled"
        "XblGameSave" = "Disabled"
        "XboxNetApiSvc" = "Disabled"
        "XboxGipSvc" = "Disabled"
    }
    Balanced = @{
        "Fax" = "Disabled"
        "RemoteRegistry" = "Disabled"
        "TapiSrv" = "Manual"
        "WMPNetworkSvc" = "Manual"
        "XblAuthManager" = "Manual"
        "XblGameSave" = "Manual"
        "XboxNetApiSvc" = "Manual"
        "XboxGipSvc" = "Manual"
        "MapsBroker" = "Manual"
        "PhoneSvc" = "Manual"
        "WSearch" = "Manual"  # Windows Search - manual for performance
    }
    Performance = @{
        "Fax" = "Disabled"
        "RemoteRegistry" = "Disabled"
        "TapiSrv" = "Disabled"
        "WMPNetworkSvc" = "Disabled"
        "XblAuthManager" = "Disabled"
        "XblGameSave" = "Disabled"
        "XboxNetApiSvc" = "Disabled"
        "XboxGipSvc" = "Disabled"
        "MapsBroker" = "Disabled"
        "PhoneSvc" = "Disabled"
        "WSearch" = "Disabled"  # Disable for max performance
        "DiagTrack" = "Disabled"  # Diagnostic Tracking
        "dmwappushservice" = "Disabled"  # Device Management Wireless App Push
        "SysMain" = "Disabled"  # Superfetch/Prefetch
    }
}

$results = @()
$changeCount = 0

# Mode: Analyze
if ($Mode -eq 'Analyze') {
    Write-Host "[*] Analyzing current service configuration..." -ForegroundColor Cyan

    $allServices = Get-Service | Select-Object Name, DisplayName, Status, StartType

    Write-Host "[+] Found $($allServices.Count) services" -ForegroundColor Green
    Write-Host ""

    $rules = $optimizationRules[$Profile]

    foreach ($serviceName in $rules.Keys) {
        $service = $allServices | Where-Object { $_.Name -eq $serviceName }

        if ($service) {
            $recommendedStartup = $rules[$serviceName]
            $currentStartup = $service.StartType

            $needsChange = $currentStartup -ne $recommendedStartup

            $result = [PSCustomObject]@{
                ServiceName = $service.Name
                DisplayName = $service.DisplayName
                CurrentStartup = $currentStartup
                RecommendedStartup = $recommendedStartup
                CurrentStatus = $service.Status
                NeedsChange = $needsChange
                Profile = $Profile
            }

            $results += $result

            if ($needsChange) {
                $changeCount++
                Write-Host "[*] $($service.DisplayName)" -ForegroundColor Yellow
                Write-Host "    Current: $currentStartup -> Recommended: $recommendedStartup" -ForegroundColor Gray
            }
        }
    }

    Write-Host ""
    Write-Host "=== Analysis Summary ===" -ForegroundColor Cyan
    Write-Host "Total Services Analyzed: $($results.Count)" -ForegroundColor White
    Write-Host "Changes Recommended: $changeCount" -ForegroundColor Yellow
    Write-Host ""

    if ($changeCount -gt 0) {
        Write-Host "Recommended Changes:" -ForegroundColor Cyan
        $results | Where-Object { $_.NeedsChange } |
            Select-Object DisplayName, CurrentStartup, RecommendedStartup |
            Format-Table -AutoSize
    }
}

# Mode: Optimize
elseif ($Mode -eq 'Optimize') {
    Write-Host "[*] Optimizing services..." -ForegroundColor Cyan

    # Create backup first
    if (-not $BackupPath) {
        $BackupPath = Join-Path $ReportDir "ServiceBackup_$timestamp.xml"
    }

    Write-Host "[*] Creating backup at: $BackupPath" -ForegroundColor Cyan

    try {
        $allServices = Get-Service | Select-Object Name, DisplayName, Status, StartType
        $allServices | Export-Clixml -Path $BackupPath
        Write-Host "[+] Backup created successfully" -ForegroundColor Green
    }
    catch {
        Write-Host "[-] Failed to create backup: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }

    Write-Host ""

    $rules = $optimizationRules[$Profile]

    foreach ($serviceName in $rules.Keys) {
        $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue

        if ($service) {
            $recommendedStartup = $rules[$serviceName]
            $currentStartup = $service.StartType

            if ($currentStartup -ne $recommendedStartup) {
                if ($ApplyChanges) {
                    if ($PSCmdlet.ShouldProcess($service.DisplayName, "Change startup type to $recommendedStartup")) {
                        try {
                            # Stop service if it's running and we're disabling it
                            if ($recommendedStartup -eq "Disabled" -and $service.Status -eq "Running") {
                                Stop-Service -Name $serviceName -Force -ErrorAction Stop
                                Write-Host "[+] Stopped: $($service.DisplayName)" -ForegroundColor Green
                            }

                            Set-Service -Name $serviceName -StartupType $recommendedStartup -ErrorAction Stop
                            Write-Host "[+] Changed: $($service.DisplayName) -> $recommendedStartup" -ForegroundColor Green
                            $changeCount++
                        }
                        catch {
                            Write-Host "[-] Failed to change $($service.DisplayName): $($_.Exception.Message)" -ForegroundColor Red
                        }
                    }
                }
                else {
                    Write-Host "[*] Would change: $($service.DisplayName) -> $recommendedStartup" -ForegroundColor Yellow
                    $changeCount++
                }

                $results += [PSCustomObject]@{
                    ServiceName = $service.Name
                    DisplayName = $service.DisplayName
                    OldStartup = $currentStartup
                    NewStartup = $recommendedStartup
                    Applied = $ApplyChanges
                }
            }
        }
    }

    Write-Host ""
    Write-Host "=== Optimization Summary ===" -ForegroundColor Cyan
    Write-Host "Services Modified: $changeCount" -ForegroundColor Green
    Write-Host "Backup Location: $BackupPath" -ForegroundColor Gray
    Write-Host ""

    if (-not $ApplyChanges) {
        Write-Host "[!] Run with -ApplyChanges to actually modify services" -ForegroundColor Yellow
    }
}

# Mode: Restore
elseif ($Mode -eq 'Restore') {
    if (-not $BackupPath -or -not (Test-Path $BackupPath)) {
        Write-Host "[-] Backup file not found: $BackupPath" -ForegroundColor Red
        exit 1
    }

    Write-Host "[*] Restoring services from: $BackupPath" -ForegroundColor Cyan

    try {
        $backupServices = Import-Clixml -Path $BackupPath

        foreach ($backupService in $backupServices) {
            $currentService = Get-Service -Name $backupService.Name -ErrorAction SilentlyContinue

            if ($currentService -and $currentService.StartType -ne $backupService.StartType) {
                if ($PSCmdlet.ShouldProcess($backupService.DisplayName, "Restore startup type to $($backupService.StartType)")) {
                    try {
                        Set-Service -Name $backupService.Name -StartupType $backupService.StartType -ErrorAction Stop
                        Write-Host "[+] Restored: $($backupService.DisplayName) -> $($backupService.StartType)" -ForegroundColor Green
                        $changeCount++
                    }
                    catch {
                        Write-Host "[-] Failed to restore $($backupService.DisplayName): $($_.Exception.Message)" -ForegroundColor Red
                    }
                }
            }
        }

        Write-Host ""
        Write-Host "[+] Restored $changeCount service(s)" -ForegroundColor Green
    }
    catch {
        Write-Host "[-] Error restoring backup: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}

# Export results
if ($ExportHTML -and $results.Count -gt 0) {
    $htmlPath = Join-Path $ReportDir "ServiceOptimization_$timestamp.html"

    $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>Service Optimization Report - $timestamp</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        h1 { color: #9b59b6; }
        .summary { background-color: #ecf0f1; padding: 15px; border-radius: 5px; margin: 20px 0; }
        table { border-collapse: collapse; width: 100%; margin-top: 10px; }
        th { background-color: #9b59b6; color: white; padding: 10px; text-align: left; }
        td { border: 1px solid #ddd; padding: 8px; }
        tr:nth-child(even) { background-color: #f2f2f2; }
    </style>
</head>
<body>
    <h1>Service Optimization Report</h1>
    <div class="summary">
        <strong>Computer:</strong> $([System.Net.WebUtility]::HtmlEncode("$env:COMPUTERNAME"))<br>
        <strong>Generated:</strong> $(Get-Date)<br>
        <strong>Mode:</strong> $Mode<br>
        <strong>Profile:</strong> $Profile<br>
        <strong>Changes:</strong> $changeCount
    </div>

    <h2>Service Details</h2>
    <table>
        <tr><th>Service Name</th><th>Display Name</th><th>Current/Old</th><th>Recommended/New</th></tr>
"@

    foreach ($result in $results) {
        $html += "<tr><td>$([System.Net.WebUtility]::HtmlEncode("$($result.ServiceName)"))</td><td>$([System.Net.WebUtility]::HtmlEncode("$($result.DisplayName)"))</td><td>$($result.CurrentStartup)$($result.OldStartup)</td><td>$($result.RecommendedStartup)$($result.NewStartup)</td></tr>`n"
    }

    $html += "</table></body></html>"

    $html | Out-File -FilePath $htmlPath -Encoding UTF8
    Write-Host "[+] HTML report saved to: $htmlPath" -ForegroundColor Green
}

if ($ExportCSV -and $results.Count -gt 0) {
    $csvPath = Join-Path $ReportDir "ServiceOptimization_$timestamp.csv"
    $results | Export-Csv -Path $csvPath -NoTypeInformation
    Write-Host "[+] CSV export saved to: $csvPath" -ForegroundColor Green
}

Write-Host "`n[+] Operation completed!" -ForegroundColor Green
exit 0
