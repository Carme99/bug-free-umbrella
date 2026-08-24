<#
.SYNOPSIS
    Optimize Windows service startup types for better performance and security.

.DESCRIPTION
    Analyzes Windows services against a chosen optimization profile (Minimal, Balanced, or
    Performance) and reports startup type recommendations. In Optimize mode it backs up the
    current service configuration to Clixml first, then applies safe startup type changes
    (stopping running services before disabling them); in Restore mode it reapplies a saved
    backup. Mutations are gated behind -ApplyChanges and -WhatIf/-Confirm via SupportsShouldProcess,
    and the check-then-act design makes re-runs on converged systems no-ops that still exit 0.

.PARAMETER Mode
    Operation mode: Analyze, Optimize, or Restore.

.PARAMETER Profile
    Optimization profile: Minimal, Balanced, Performance (default: Balanced).

.PARAMETER BackupPath
    Path to save the service configuration backup to (Optimize) or restore from (Restore).

.PARAMETER ApplyChanges
    Actually apply the recommended changes; without this switch only recommendations are shown.

.PARAMETER ExportHTML
    Export results to an HTML report.

.PARAMETER ExportCSV
    Export results to a CSV file.

.EXAMPLE
    PS C:\> .\Optimize-WindowsServices.ps1 -Mode Analyze
    Analyzes current service configuration and provides recommendations.

.EXAMPLE
    PS C:\> .\Optimize-WindowsServices.ps1 -Mode Optimize -Profile Performance -ApplyChanges
    Applies performance-oriented service optimizations after creating a configuration backup.

.EXAMPLE
    PS C:\> .\Optimize-WindowsServices.ps1 -Mode Restore -BackupPath "C:\Backups\services.xml"
    Restores service configuration from the specified backup file.

.NOTES
    File Name: Optimize-WindowsServices.ps1
    Author: Bug-Free Umbrella
    Prerequisite: PowerShell 7.0
    Version: 1.0.0
    Date: 2026-08-23

    Requires Administrator privileges.
    Creates a backup before making changes.
    Compatible with Windows 10, 11, Server 2016, 2019, 2022.
    Use with caution on production servers.
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $false)]
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

$ErrorActionPreference = 'Stop'
function Main {
    [OutputType([int])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
        Justification = 'Console report tool')]
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $false)]
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

    try {
        # Validate inputs early: throw before doing work.
        if (-not $Mode) {
            throw "Parameter -Mode is required (Analyze, Optimize, or Restore)"
        }

        $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'

        $documentsPath = [Environment]::GetFolderPath('MyDocuments')
        if ([string]::IsNullOrWhiteSpace($documentsPath)) {
            # Fallback for non-Windows/non-interactive hosts (e.g. offline CI)
            $documentsPath = Join-Path $HOME 'Documents'
        }
        $ReportDir = Join-Path $documentsPath 'Reports'

        # Validate report directory: reject '..' traversal and UNC remote paths before resolution
        if ([string]::IsNullOrWhiteSpace($ReportDir) -or
            $ReportDir -match '(^|[\\/])\.\.([\\/]|$)' -or
            $ReportDir -match '^(\\\\|//)') {
            $reason = "must be a local absolute path without '..' traversal."
            throw "Unsafe report directory: $ReportDir. $reason"
        }
        $ReportDir = [System.IO.Path]::GetFullPath($ReportDir)

        # Idempotent check-then-act: create the report directory only when missing.
        if (-not (Test-Path -LiteralPath $ReportDir -PathType Container)) {
            New-Item -ItemType Directory -Path $ReportDir -Force -ErrorAction Stop | Out-Null
        }

        Write-Host "[*] Mode: $Mode" -ForegroundColor Cyan
        Write-Host "[*] Profile: $Profile" -ForegroundColor Cyan
        Write-Host ""

        # Service optimization rules
        $optimizationRules = @{
            Minimal = @{
                "Fax"            = "Disabled"
                "RemoteRegistry" = "Disabled"
                "TapiSrv"        = "Disabled"
                "WMPNetworkSvc"  = "Disabled"
                "XblAuthManager" = "Disabled"
                "XblGameSave"    = "Disabled"
                "XboxNetApiSvc"  = "Disabled"
                "XboxGipSvc"     = "Disabled"
            }
            Balanced = @{
                "Fax"            = "Disabled"
                "RemoteRegistry" = "Disabled"
                "TapiSrv"        = "Manual"
                "WMPNetworkSvc"  = "Manual"
                "XblAuthManager" = "Manual"
                "XblGameSave"    = "Manual"
                "XboxNetApiSvc"  = "Manual"
                "XboxGipSvc"     = "Manual"
                "MapsBroker"     = "Manual"
                "PhoneSvc"       = "Manual"
                "WSearch"        = "Manual"  # Windows Search - manual for performance
            }
            Performance = @{
                "Fax"              = "Disabled"
                "RemoteRegistry"   = "Disabled"
                "TapiSrv"          = "Disabled"
                "WMPNetworkSvc"    = "Disabled"
                "XblAuthManager"   = "Disabled"
                "XblGameSave"      = "Disabled"
                "XboxNetApiSvc"    = "Disabled"
                "XboxGipSvc"       = "Disabled"
                "MapsBroker"       = "Disabled"
                "PhoneSvc"         = "Disabled"
                "WSearch"          = "Disabled"  # Disable for max performance
                "DiagTrack"        = "Disabled"  # Diagnostic Tracking
                "dmwappushservice" = "Disabled"  # Device Management Wireless App Push
                "SysMain"          = "Disabled"  # Superfetch/Prefetch
            }
        }

        $results = @()
        $changeCount = 0

        # Mode: Analyze
        if ($Mode -eq 'Analyze') {
            Write-Host "[*] Analyzing current service configuration..." -ForegroundColor Cyan

            $allServices = Get-Service -ErrorAction Stop | Select-Object Name, DisplayName, Status, StartType

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
                        ServiceName        = $service.Name
                        DisplayName        = $service.DisplayName
                        CurrentStartup     = $currentStartup
                        RecommendedStartup = $recommendedStartup
                        CurrentStatus      = $service.Status
                        NeedsChange        = $needsChange
                        Profile            = $Profile
                    }

                    $results += $result

                    if ($needsChange) {
                        $changeCount++
                        Write-Host "[!] $($service.DisplayName)" -ForegroundColor Yellow
                        Write-Host "    Current: $currentStartup -> Recommended: $recommendedStartup"
                    }
                }
            }

            Write-Host ""
            Write-Host "=== Analysis Summary ===" -ForegroundColor Cyan
            Write-Host "Total Services Analyzed: $($results.Count)"
            Write-Host "Changes Recommended: $changeCount"
            Write-Host ""

            if ($changeCount -gt 0) {
                Write-Host "[*] Recommended Changes:" -ForegroundColor Cyan
                $results | Where-Object { $_.NeedsChange } |
                    Select-Object DisplayName, CurrentStartup, RecommendedStartup |
                    Format-Table -AutoSize
            }
            else {
                Write-Host "[+] All services already match the '$Profile' profile"
                    Write-Host "[+] Nothing to change" -ForegroundColor Green
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
                $allServices = Get-Service -ErrorAction Stop | Select-Object Name, DisplayName, Status, StartType
                $allServices | Export-Clixml -Path $BackupPath -ErrorAction Stop
                Write-Host "[+] Backup created successfully" -ForegroundColor Green
            }
            catch {
                Write-Host "[-] Failed to create backup: $($_.Exception.Message)" -ForegroundColor Red
                return 1
            }

            Write-Host ""

            $rules = $optimizationRules[$Profile]

            foreach ($serviceName in $rules.Keys) {
                $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue

                if ($service) {
                    $recommendedStartup = $rules[$serviceName]
                    $currentStartup = $service.StartType

                    # Idempotent check-then-act: only touch services whose state differs.
                    if ($currentStartup -ne $recommendedStartup) {
                        if ($ApplyChanges) {
                            $operation = "Change startup type to $recommendedStartup"
                            if ($PSCmdlet.ShouldProcess($service.DisplayName, $operation)) {
                                try {
                                    # Stop service if it's running and we're disabling it
                                    if ($recommendedStartup -eq "Disabled" -and $service.Status -eq "Running") {
                                        Stop-Service -Name $serviceName -Force -ErrorAction Stop
                                        Write-Host "[+] Stopped: $($service.DisplayName)" -ForegroundColor Green
                                    }

                                    Set-Service -Name $serviceName -StartupType $recommendedStartup -ErrorAction Stop
                                    $changeMsg = "[+] Changed: $($service.DisplayName) -> $recommendedStartup"
                                    Write-Host $changeMsg -ForegroundColor Green
                                    $changeCount++
                                }
                                catch {
                                    $failMsg = "[-] Failed to change $($service.DisplayName): $($_.Exception.Message)"
                                    Write-Host $failMsg -ForegroundColor Red
                                }
                            }
                        }
                        else {
                            $wouldMsg = "[!] Would change: $($service.DisplayName) -> $recommendedStartup"
                            Write-Host $wouldMsg -ForegroundColor Yellow
                            $changeCount++
                        }

                        $results += [PSCustomObject]@{
                            ServiceName = $service.Name
                            DisplayName = $service.DisplayName
                            OldStartup  = $currentStartup
                            NewStartup  = $recommendedStartup
                            Applied     = $ApplyChanges
                        }
                    }
                }
            }

            Write-Host ""
            Write-Host "=== Optimization Summary ===" -ForegroundColor Cyan
            Write-Host "Services Modified: $changeCount"
            Write-Host "Backup Location: $BackupPath"
            Write-Host ""

            if (-not $ApplyChanges) {
                Write-Host "[!] Run with -ApplyChanges to actually modify services" -ForegroundColor Yellow
            }
            elseif ($changeCount -eq 0) {
                Write-Host "[+] All services already match the '$Profile' profile"
                    Write-Host "[+] No changes made" -ForegroundColor Green
            }
        }

        # Mode: Restore
        elseif ($Mode -eq 'Restore') {
            if (-not $BackupPath -or -not (Test-Path $BackupPath)) {
                Write-Host "[-] Backup file not found: $BackupPath" -ForegroundColor Red
                return 1
            }

            Write-Host "[*] Restoring services from: $BackupPath" -ForegroundColor Cyan

            try {
                $backupServices = Import-Clixml -Path $BackupPath -ErrorAction Stop

                foreach ($backupService in $backupServices) {
                    $currentService = Get-Service -Name $backupService.Name -ErrorAction SilentlyContinue

                    # Idempotent check-then-act: skip services already at their backed-up startup type.
                    if ($currentService -and $currentService.StartType -ne $backupService.StartType) {
                        $restoreOp = "Restore startup type to $($backupService.StartType)"
                        if ($PSCmdlet.ShouldProcess($backupService.DisplayName, $restoreOp)) {
                            try {
                                Set-Service -Name $backupService.Name `
                                    -StartupType $backupService.StartType -ErrorAction Stop
                                $restoredName = $backupService.DisplayName
                                $restoredType = $backupService.StartType
                                Write-Host "[+] Restored: $restoredName -> $restoredType" -ForegroundColor Green
                                $changeCount++
                            }
                            catch {
                                $restoreFailMsg = "[-] Failed to restore $($backupService.DisplayName):"
                                $restoreFailMsg += " $($_.Exception.Message)"
                                Write-Host $restoreFailMsg -ForegroundColor Red
                            }
                        }
                    }
                }

                Write-Host ""
                Write-Host "[+] Restored $changeCount service(s)" -ForegroundColor Green
            }
            catch {
                Write-Host "[-] Error restoring backup: $($_.Exception.Message)" -ForegroundColor Red
                return 1
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
                $svcName = [System.Net.WebUtility]::HtmlEncode("$($result.ServiceName)")
                $svcDisplay = [System.Net.WebUtility]::HtmlEncode("$($result.DisplayName)")
                $oldStartup = "$($result.CurrentStartup)$($result.OldStartup)"
                $newStartup = "$($result.RecommendedStartup)$($result.NewStartup)"
                $html += "<tr><td>$svcName</td><td>$svcDisplay</td><td>$oldStartup</td><td>$newStartup</td></tr>`n"
            }

            $html += "</table></body></html>"

            $html | Out-File -FilePath $htmlPath -Encoding UTF8 -ErrorAction Stop
            Write-Host "[+] HTML report saved to: $htmlPath" -ForegroundColor Green
        }

        if ($ExportCSV -and $results.Count -gt 0) {
            $csvPath = Join-Path $ReportDir "ServiceOptimization_$timestamp.csv"
            $results | Export-Csv -Path $csvPath -NoTypeInformation -ErrorAction Stop
            Write-Host "[+] CSV export saved to: $csvPath" -ForegroundColor Green
        }

        Write-Host ""
        Write-Host "[+] Operation completed!" -ForegroundColor Green
        return 0
    }
    catch {
        Write-Host "[-] Error: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main @PSBoundParameters) }
