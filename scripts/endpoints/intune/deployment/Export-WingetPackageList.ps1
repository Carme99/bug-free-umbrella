<#
.SYNOPSIS
    Exports installed winget packages from Intune-managed devices for inventory reporting.

.DESCRIPTION
    Collects all winget-installed packages on the local device and exports them for custom inventory:
    - Enumerates winget-installed packages via `winget list`
    - Captures package name, ID, installed/available versions, source, and update status
    - Supports filtering by source or excluding system (msstore) applications
    - Outputs JSON, CSV, or a console summary
    Designed to run as SYSTEM context on devices (e.g. as an Intune detection/inventory script).
    Exit codes: 0 = inventory collected (or winget absent / no packages found), 1 = enumeration or export failed.

.PARAMETER ExportFormat
    Output format: JSON, CSV, or Console (default: Console).

.PARAMETER OutputPath
    Where to save the export file. Optional for JSON (stdout when omitted); required target for CSV,
    which falls back to a timestamped file in $env:TEMP when omitted.

.PARAMETER SourceFilter
    Filter by winget source (e.g., 'winget', 'msstore').

.PARAMETER IncludeSystemApps
    Include system/built-in applications.

.EXAMPLE
    PS C:\> .\Export-WingetPackageList.ps1

    Lists all winget packages to the console with a summary.

.EXAMPLE
    PS C:\> .\Export-WingetPackageList.ps1 -ExportFormat JSON -OutputPath "C:\Temp\packages.json"

    Exports the package list to a JSON file.

.EXAMPLE
    PS C:\> .\Export-WingetPackageList.ps1 -SourceFilter "winget" -ExportFormat CSV

    Exports only winget-source packages to a CSV file.

.NOTES
    File Name  : Export-WingetPackageList.ps1
    Author     : Bug-Free Umbrella
    Prerequisite: PowerShell 7.0
    Version    : 1.0.0
    Date       : 2026-08-23
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $false)]
    [ValidateSet('JSON', 'CSV', 'Console')]
    [string]$ExportFormat = 'Console',

    [Parameter(Mandatory = $false)]
    [string]$OutputPath,

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$SourceFilter,

    [Parameter(Mandatory = $false)]
    [switch]$IncludeSystemApps
)

# PSAvoidUsingWriteHost is intentionally accepted: prefixed, colored console output is the mandated
# output convention of docs/RELAUNCH-SPEC.md section 3.
$ErrorActionPreference = 'Stop'

$script:Packages = @()

function Get-WingetPath {
    # Returns the newest winget.exe path under WindowsApps, or $null when winget is absent.
    $pattern = 'C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\winget.exe'
    $wingetExe = Resolve-Path -Path $pattern -ErrorAction SilentlyContinue

    if (-not $wingetExe) {
        Write-Host '[!] Winget not found on this system.' -ForegroundColor Yellow
        return $null
    }

    return $wingetExe[-1].Path
}

function Invoke-WingetList {
    # Thin wrapper seam around the native winget.exe so tests can mock this function.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$WingetExe
    )

    $output = & $WingetExe list --accept-source-agreements 2>&1

    if ($LASTEXITCODE -ne 0) {
        throw "winget list exited with code $LASTEXITCODE."
    }

    return ($output | Out-String)
}

function Get-WingetPackages {
    [CmdletBinding()]
    param()

    $wingetPath = Get-WingetPath
    if (-not $wingetPath) { return }

    Write-Host '[*] Enumerating winget packages...' -ForegroundColor Cyan

    $output = Invoke-WingetList -WingetExe $wingetPath -ErrorAction Stop

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
                Name             = $name
                ID               = $id
                Version          = $version
                AvailableVersion = $availableVersion
                Source           = $source
                UpdateAvailable  = $version -ne $availableVersion
                CollectionTime   = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
            }

            $script:Packages += $package
        }
    }

    Write-Host "[+] Found $($script:Packages.Count) packages." -ForegroundColor Green
}

function Export-Data {
    [CmdletBinding()]
    param()

    if ($script:Packages.Count -eq 0) {
        Write-Host '[!] No packages to export.' -ForegroundColor Yellow
        return
    }

    switch ($ExportFormat) {
        'JSON' {
            $jsonData = $script:Packages | ConvertTo-Json -Depth 10

            if ($OutputPath) {
                if (-not $PSCmdlet.ShouldProcess($OutputPath, 'Write JSON export')) { return }
                $jsonData | Out-File -FilePath $OutputPath -Encoding utf8 -ErrorAction Stop
                Write-Host "[+] Exported to: $OutputPath" -ForegroundColor Green
            }
            else {
                Write-Output $jsonData
            }
        }

        'CSV' {
            $csvPath = $OutputPath
            if (-not $csvPath) {
                $csvPath = "$env:TEMP\winget-packages_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
            }

            if (-not $PSCmdlet.ShouldProcess($csvPath, 'Write CSV export')) { return }
            $script:Packages | Export-Csv -Path $csvPath -NoTypeInformation -Encoding utf8 -ErrorAction Stop
            Write-Host "[+] Exported to: $csvPath" -ForegroundColor Green
        }

        'Console' {
            $script:Packages | Format-Table Name, ID, Version, AvailableVersion, UpdateAvailable, Source -AutoSize

            Write-Host "`nSummary:" -ForegroundColor Cyan
            $updatesAvailable = ($script:Packages | Where-Object UpdateAvailable).Count
            Write-Host "  Updates Available: $updatesAvailable" -ForegroundColor Yellow
        }
    }
}

function Main {
    try {
        Write-Host "`n========================================" -ForegroundColor Cyan
        Write-Host "  Winget Package Inventory Export" -ForegroundColor Cyan
        Write-Host "========================================`n" -ForegroundColor Cyan

        Get-WingetPackages -ErrorAction Stop
        Export-Data -ErrorAction Stop

        Write-Host "[+] Winget package inventory export complete." -ForegroundColor Green
        return 0
    }
    catch {
        Write-Host "[-] Error: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
