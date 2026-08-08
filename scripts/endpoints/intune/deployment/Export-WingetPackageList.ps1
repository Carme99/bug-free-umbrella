<#
.SYNOPSIS
    Exports installed winget packages from Intune-managed devices.

.DESCRIPTION
    This detection script collects installed winget packages and exports to Intune custom inventory:
    - Enumerates all winget-installed packages
    - Captures package ID, version, and source
    - Can be deployed as Intune detection script
    - Outputs JSON for custom reporting
    - Supports filtering by source or package name

.PARAMETER ExportFormat
    Output format: JSON, CSV, or Console (default: Console).

.PARAMETER OutputPath
    Where to save the export file.

.PARAMETER SourceFilter
    Filter by winget source (e.g., 'winget', 'msstore').

.PARAMETER IncludeSystemApps
    Include system/built-in applications.

.EXAMPLE
    .\Export-WingetPackageList.ps1
    Lists all winget packages to console.

.EXAMPLE
    .\Export-WingetPackageList.ps1 -ExportFormat JSON -OutputPath "C:\Temp\packages.json"
    Exports package list to JSON file.

.EXAMPLE
    .\Export-WingetPackageList.ps1 -SourceFilter "winget" -ExportFormat CSV
    Exports only winget source packages to CSV.

.NOTES
    Designed to run as SYSTEM context on devices
    Can be used as Intune detection script for inventory
    Requires winget to be installed
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [ValidateSet('JSON', 'CSV', 'Console')]
    [string]$ExportFormat = 'Console',

    [Parameter(Mandatory = $false)]
    [string]$OutputPath,

    [Parameter(Mandatory = $false)]
    [string]$SourceFilter,

    [Parameter(Mandatory = $false)]
    [switch]$IncludeSystemApps
)

$packages = @()

function Get-WingetPath {
    $wingetExe = Resolve-Path "C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\winget.exe" -ErrorAction SilentlyContinue

    if (-not $wingetExe) {
        Write-Error "Winget not found on this system."
        return $null
    }

    return $wingetExe[-1].Path
}

function Get-WingetPackages {
    $wingetPath = Get-WingetPath
    if (-not $wingetPath) { return @() }

    Write-Host "Enumerating winget packages..." -ForegroundColor Cyan

    try {
        # Run winget list and parse output
        $output = & $wingetPath list --accept-source-agreements 2>&1 | Out-String

        $lines = $output -split "`n" | Where-Object { $_ -match '\S' }

        # Skip header lines
        $dataLines = $lines | Select-Object -Skip 2

        foreach ($line in $dataLines) {
            # Parse winget list output format
            if ($line -match '^\s*(.+?)\s+(.+?)\s+([\d\.]+)\s*(<\s*([\d\.]+))?\s*(.*)$') {
                $name = $matches[1].Trim()
                $id = $matches[2].Trim()
                $version = $matches[3].Trim()
                $availableVersion = if ($matches[5]) { $matches[5].Trim() } else { $version }
                $source = $matches[6].Trim()

                # Apply filters
                if ($SourceFilter -and $source -notlike "*$SourceFilter*") {
                    continue
                }

                if (-not $IncludeSystemApps -and $source -like "*msstore*") {
                    continue
                }

                $package = [PSCustomObject]@{
                    Name = $name
                    ID = $id
                    Version = $version
                    AvailableVersion = $availableVersion
                    Source = $source
                    UpdateAvailable = $version -ne $availableVersion
                    CollectionTime = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
                }

                $script:packages += $package
            }
        }

        Write-Host "Found $($script:packages.Count) packages" -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to enumerate packages: $($_.Exception.Message)"
    }
}

function Export-Data {
    if ($script:packages.Count -eq 0) {
        Write-Warning "No packages to export"
        return
    }

    switch ($ExportFormat) {
        'JSON' {
            $jsonData = $script:packages | ConvertTo-Json -Depth 10

            if ($OutputPath) {
                $jsonData | Out-File -FilePath $OutputPath -Encoding UTF8
                Write-Host "Exported to: $OutputPath" -ForegroundColor Green
            }
            else {
                Write-Output $jsonData
            }
        }

        'CSV' {
            if (-not $OutputPath) {
                $OutputPath = "$env:TEMP\winget-packages_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
            }

            $script:packages | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8
            Write-Host "Exported to: $OutputPath" -ForegroundColor Green
        }

        'Console' {
            $script:packages | Format-Table Name, ID, Version, AvailableVersion, UpdateAvailable, Source -AutoSize

            Write-Host "`nSummary:" -ForegroundColor Cyan
            Write-Host "  Total Packages: $($script:packages.Count)"
            Write-Host "  Updates Available: $(($script:packages | Where-Object UpdateAvailable).Count)" -ForegroundColor Yellow
        }
    }
}

# Main execution
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Winget Package Inventory Export" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

Get-WingetPackages
Export-Data

Write-Host "`n========================================`n" -ForegroundColor Cyan
