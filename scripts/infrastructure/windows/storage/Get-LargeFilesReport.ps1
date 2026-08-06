<#
.SYNOPSIS
    Identifies and reports large files consuming disk space on Windows Server.

.DESCRIPTION
    This script scans drives to find large files and provides:
    - Top largest files by size
    - Files grouped by type/extension
    - Duplicate file detection (optional)
    - Age analysis of large files
    - Customizable size threshold
    - Export to HTML or CSV
    - Interactive cleanup suggestions

.PARAMETER Path
    Path to scan. If not specified, scans all fixed drives.

.PARAMETER MinimumSizeMB
    Minimum file size in MB to include in report (default: 100 MB).

.PARAMETER TopCount
    Number of largest files to report (default: 50).

.PARAMETER IncludeDuplicates
    Scan for duplicate files (based on size and hash).

.PARAMETER ExcludePath
    Paths to exclude from scan (e.g., "C:\Windows\WinSxS").

.PARAMETER ExportHTML
    Export report to HTML file.

.PARAMETER ExportCSV
    Export file list to CSV.

.EXAMPLE
    .\Get-LargeFilesReport.ps1
    Scans all drives for files larger than 100 MB.

.EXAMPLE
    .\Get-LargeFilesReport.ps1 -Path "D:\" -MinimumSizeMB 500 -TopCount 100 -ExportHTML
    Scans D: drive for files larger than 500 MB and exports top 100 to HTML.

.EXAMPLE
    .\Get-LargeFilesReport.ps1 -IncludeDuplicates -ExportHTML
    Scans for large files and identifies duplicates.

.NOTES
    Requires Administrator privileges for full filesystem access
    Compatible with Windows Server 2016, 2019, and 2022
    Scan time depends on drive size and file count
    Duplicate detection can be time-intensive
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$Path,

    [Parameter(Mandatory=$false)]
    [int]$MinimumSizeMB = 100,

    [Parameter(Mandatory=$false)]
    [int]$TopCount = 50,

    [Parameter(Mandatory=$false)]
    [switch]$IncludeDuplicates,

    [Parameter(Mandatory=$false)]
    [string[]]$ExcludePath = @('C:\Windows\WinSxS', 'C:\$Recycle.Bin'),

    [Parameter(Mandatory=$false)]
    [switch]$ExportHTML,

    [Parameter(Mandatory=$false)]
    [switch]$ExportCSV
)

$ReportDir = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Reports'
if ([string]::IsNullOrWhiteSpace($ReportDir) -or
    $ReportDir -match '(^|[\\/])\.\.([\\/]|$)' -or
    $ReportDir -match '^(\\\\|//)') {
    Write-Error "Unsafe report path: $ReportDir. Report path must be a local absolute path without '..' traversal."
    exit 1
}
$ReportDir = [System.IO.Path]::GetFullPath($ReportDir)
if (-not (Test-Path -LiteralPath $ReportDir -PathType Container)) {
    New-Item -ItemType Directory -Path $ReportDir -Force | Out-Null
}

#Requires -RunAsAdministrator

$script:report = @{
    ServerName = $env:COMPUTERNAME
    ScanTime = Get-Date
    MinimumSizeMB = $MinimumSizeMB
    LargeFiles = @()
    FilesByExtension = @{}
    DuplicateFiles = @()
    TotalSizeGB = 0
    TotalFiles = 0
}

function Write-ColorOutput {
    param([string]$Message, [string]$Level = 'Info')

    $color = switch($Level) {
        'Warning' { 'Yellow' }
        'Error' { 'Red' }
        'Success' { 'Green' }
        'Info' { 'Cyan' }
        default { 'White' }
    }
    Write-Host $Message -ForegroundColor $color
}

function Should-ExcludePath {
    param([string]$FilePath)

    foreach($exclude in $ExcludePath) {
        if($FilePath -like "$exclude*") {
            return $true
        }
    }
    return $false
}

function Scan-LargeFiles {
    param([string]$ScanPath)

    Write-Host "`nScanning for files larger than $MinimumSizeMB MB..." -ForegroundColor Cyan
    Write-Host "Path: $ScanPath" -ForegroundColor Gray
    Write-Host "This may take several minutes..." -ForegroundColor Gray

    $minimumSizeBytes = $MinimumSizeMB * 1MB
    $filesScanned = 0

    try {
        $files = Get-ChildItem -Path $ScanPath -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object {
                $_.Length -ge $minimumSizeBytes -and
                -not (Should-ExcludePath -FilePath $_.FullName)
            }

        foreach($file in $files) {
            $filesScanned++
            if($filesScanned % 100 -eq 0) {
                Write-Progress -Activity "Scanning files" -Status "Found $($script:report.LargeFiles.Count) large files (scanned $filesScanned)" -PercentComplete -1
            }

            $fileInfo = [PSCustomObject]@{
                Path = $file.FullName
                Directory = $file.DirectoryName
                Name = $file.Name
                Extension = $file.Extension.ToLower()
                SizeMB = [math]::Round($file.Length / 1MB, 2)
                SizeGB = [math]::Round($file.Length / 1GB, 3)
                Created = $file.CreationTime
                Modified = $file.LastWriteTime
                Accessed = $file.LastAccessTime
                AgeDays = [math]::Round(((Get-Date) - $file.LastWriteTime).TotalDays, 0)
                Hash = $null
            }

            $script:report.LargeFiles += $fileInfo
            $script:report.TotalSizeGB += $fileInfo.SizeGB
            $script:report.TotalFiles++

            # Group by extension
            $ext = if($file.Extension) { $file.Extension.ToLower() } else { '(no extension)' }
            if($script:report.FilesByExtension.ContainsKey($ext)) {
                $script:report.FilesByExtension[$ext].Count++
                $script:report.FilesByExtension[$ext].TotalSizeMB += $fileInfo.SizeMB
            }
            else {
                $script:report.FilesByExtension[$ext] = @{
                    Count = 1
                    TotalSizeMB = $fileInfo.SizeMB
                }
            }
        }

        Write-Progress -Activity "Scanning files" -Completed
        Write-ColorOutput "  Found $($script:report.LargeFiles.Count) files larger than $MinimumSizeMB MB" -Level Success
        Write-ColorOutput "  Total size: $([math]::Round($script:report.TotalSizeGB, 2)) GB" -Level Info
    }
    catch {
        Write-ColorOutput "  Error scanning files: $($_.Exception.Message)" -Level Error
    }
}

function Find-Duplicates {
    Write-Host "`nScanning for duplicate files..." -ForegroundColor Cyan
    Write-Host "This may take significant time for large file sets..." -ForegroundColor Gray

    # Group files by size first (faster)
    $sizeGroups = $script:report.LargeFiles | Group-Object SizeMB | Where-Object {$_.Count -gt 1}

    if(-not $sizeGroups) {
        Write-Host "  No potential duplicates found (no files with matching sizes)" -ForegroundColor Gray
        return
    }

    Write-Host "  Found $($sizeGroups.Count) size groups with potential duplicates" -ForegroundColor Gray
    Write-Host "  Computing file hashes..." -ForegroundColor Gray

    $duplicateGroups = @{}
    $filesProcessed = 0
    $totalFilesToHash = ($sizeGroups | ForEach-Object {$_.Group}).Count

    foreach($group in $sizeGroups) {
        foreach($file in $group.Group) {
            $filesProcessed++
            Write-Progress -Activity "Computing file hashes" -Status "Processing $filesProcessed of $totalFilesToHash" -PercentComplete (($filesProcessed / $totalFilesToHash) * 100)

            try {
                $hash = (Get-FileHash -Path $file.Path -Algorithm MD5 -ErrorAction Stop).Hash
                $file.Hash = $hash

                if($duplicateGroups.ContainsKey($hash)) {
                    $duplicateGroups[$hash] += $file
                }
                else {
                    $duplicateGroups[$hash] = @($file)
                }
            }
            catch {
                Write-Verbose "Could not hash file: $($file.Path)"
            }
        }
    }

    Write-Progress -Activity "Computing file hashes" -Completed

    # Filter to only groups with multiple files
    $duplicateGroups.GetEnumerator() | Where-Object {$_.Value.Count -gt 1} | ForEach-Object {
        $dupGroup = $_.Value | Sort-Object Path
        $wastedSpace = ($dupGroup.Count - 1) * $dupGroup[0].SizeMB

        $script:report.DuplicateFiles += [PSCustomObject]@{
            Hash = $_.Key
            FileCount = $dupGroup.Count
            SizeMB = $dupGroup[0].SizeMB
            WastedSpaceMB = $wastedSpace
            Files = $dupGroup.Path -join '; '
            SampleFile = $dupGroup[0].Name
        }
    }

    if($script:report.DuplicateFiles.Count -gt 0) {
        $totalWasted = ($script:report.DuplicateFiles | Measure-Object -Property WastedSpaceMB -Sum).Sum
        Write-ColorOutput "  Found $($script:report.DuplicateFiles.Count) sets of duplicate files" -Level Warning
        Write-ColorOutput "  Potential space savings: $([math]::Round($totalWasted / 1024, 2)) GB" -Level Info
    }
    else {
        Write-ColorOutput "  No duplicate files found" -Level Success
    }
}

function Show-Summary {
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "  Large Files Report Summary" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Server: $($script:report.ServerName)"
    Write-Host "Scan Time: $($script:report.ScanTime)"
    Write-Host "Minimum Size: $($script:report.MinimumSizeMB) MB"
    Write-Host "`nFiles Found: $($script:report.TotalFiles)"
    Write-Host "Total Size: $([math]::Round($script:report.TotalSizeGB, 2)) GB"

    # Top files
    Write-Host "`nTop $TopCount Largest Files:" -ForegroundColor Cyan
    $script:report.LargeFiles |
        Sort-Object SizeMB -Descending |
        Select-Object -First $TopCount |
        Select-Object Name, @{Name='Size (GB)';Expression={$_.SizeGB}}, @{Name='Age (Days)';Expression={$_.AgeDays}}, Directory |
        Format-Table -AutoSize

    # Files by extension
    Write-Host "`nLarge Files by Type:" -ForegroundColor Cyan
    $script:report.FilesByExtension.GetEnumerator() |
        Sort-Object {$_.Value.TotalSizeMB} -Descending |
        Select-Object -First 10 |
        ForEach-Object {
            [PSCustomObject]@{
                Extension = $_.Key
                Count = $_.Value.Count
                'Total Size (GB)' = [math]::Round($_.Value.TotalSizeMB / 1024, 2)
            }
        } |
        Format-Table -AutoSize

    # Duplicates
    if($script:report.DuplicateFiles.Count -gt 0) {
        Write-Host "`nTop Duplicate Files (by wasted space):" -ForegroundColor Yellow
        $script:report.DuplicateFiles |
            Sort-Object WastedSpaceMB -Descending |
            Select-Object -First 10 |
            Select-Object SampleFile, FileCount, @{Name='Size (MB)';Expression={$_.SizeMB}}, @{Name='Wasted (MB)';Expression={$_.WastedSpaceMB}} |
            Format-Table -AutoSize
    }

    Write-Host "`n========================================`n" -ForegroundColor Cyan
}

function Export-HTMLReport {
    $reportPath = "$ReportDir\LargeFilesReport_$(Get-Date -Format 'yyyyMMdd_HHmmss').html"

    $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>Large Files Report - $($script:report.ServerName)</title>
    <style>
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; margin: 20px; background-color: #f5f5f5; }
        .container { max-width: 1600px; margin: 0 auto; background-color: white; padding: 30px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        h1 { color: #333; border-bottom: 3px solid #007bff; padding-bottom: 10px; }
        h2 { color: #555; margin-top: 30px; border-bottom: 1px solid #ddd; padding-bottom: 5px; }
        .summary { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 15px; margin: 20px 0; }
        .metric { background-color: #f8f9fa; padding: 20px; border-radius: 4px; border-left: 4px solid #007bff; text-align: center; }
        .metric-value { font-size: 2em; font-weight: bold; color: #007bff; }
        table { width: 100%; border-collapse: collapse; margin: 15px 0; font-size: 0.9em; }
        th { background-color: #007bff; color: white; padding: 12px; text-align: left; position: sticky; top: 0; }
        td { padding: 10px; border-bottom: 1px solid #ddd; }
        tr:hover { background-color: #f1f1f1; }
        .file-path { font-family: 'Courier New', monospace; font-size: 0.85em; color: #666; max-width: 400px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
        .warning { background-color: #fff3cd; padding: 15px; border-left: 4px solid #ffc107; margin: 15px 0; }
        .footer { margin-top: 30px; padding-top: 20px; border-top: 1px solid #ddd; color: #777; font-size: 0.9em; }
    </style>
</head>
<body>
    <div class="container">
        <h1>Large Files Report</h1>
        <p><strong>Server:</strong> $($script:report.ServerName)<br>
        <strong>Scan Time:</strong> $($script:report.ScanTime)<br>
        <strong>Minimum File Size:</strong> $($script:report.MinimumSizeMB) MB</p>

        <div class="summary">
            <div class="metric">
                <div class="metric-value">$($script:report.TotalFiles)</div>
                <div>Large Files</div>
            </div>
            <div class="metric">
                <div class="metric-value">$([math]::Round($script:report.TotalSizeGB, 2))</div>
                <div>Total Size (GB)</div>
            </div>
            $(if($script:report.DuplicateFiles.Count -gt 0) {
                $totalWasted = ($script:report.DuplicateFiles | Measure-Object -Property WastedSpaceMB -Sum).Sum
                "<div class='metric'><div class='metric-value'>$($script:report.DuplicateFiles.Count)</div><div>Duplicate Sets</div></div>"
                "<div class='metric'><div class='metric-value'>$([math]::Round($totalWasted / 1024, 2))</div><div>Wasted Space (GB)</div></div>"
            })
        </div>

        <h2>Top $TopCount Largest Files</h2>
        <table>
            <tr><th>File Name</th><th>Size (GB)</th><th>Age (Days)</th><th>Modified</th><th>Path</th></tr>
            $(foreach($file in ($script:report.LargeFiles | Sort-Object SizeMB -Descending | Select-Object -First $TopCount)) {
                "<tr>
                    <td>$($file.Name)</td>
                    <td>$($file.SizeGB)</td>
                    <td>$($file.AgeDays)</td>
                    <td>$($file.Modified.ToString('yyyy-MM-dd HH:mm'))</td>
                    <td class='file-path' title='$($file.Path)'>$($file.Directory)</td>
                </tr>"
            })
        </table>

        <h2>Files by Type</h2>
        <table>
            <tr><th>Extension</th><th>Count</th><th>Total Size (GB)</th></tr>
            $(foreach($ext in ($script:report.FilesByExtension.GetEnumerator() | Sort-Object {$_.Value.TotalSizeMB} -Descending | Select-Object -First 15)) {
                "<tr>
                    <td>$($ext.Key)</td>
                    <td>$($ext.Value.Count)</td>
                    <td>$([math]::Round($ext.Value.TotalSizeMB / 1024, 2))</td>
                </tr>"
            })
        </table>

        $(if($script:report.DuplicateFiles.Count -gt 0) {
            "<div class='warning'><h3>Duplicate Files Detected</h3><p>The following files appear to be duplicates and may be candidates for cleanup.</p></div>"
            "<h2>Duplicate Files</h2>"
            "<table><tr><th>Sample File</th><th>Copies</th><th>Size (MB)</th><th>Wasted Space (MB)</th></tr>"
            foreach($dup in ($script:report.DuplicateFiles | Sort-Object WastedSpaceMB -Descending | Select-Object -First 20)) {
                "<tr>
                    <td>$($dup.SampleFile)</td>
                    <td>$($dup.FileCount)</td>
                    <td>$($dup.SizeMB)</td>
                    <td>$($dup.WastedSpaceMB)</td>
                </tr>"
            }
            "</table>"
        })

        <div class="footer">
            Report generated by Get-LargeFilesReport.ps1
        </div>
    </div>
</body>
</html>
"@

    $html | Out-File -FilePath $reportPath -Encoding UTF8
    Write-ColorOutput "`nHTML report exported to: $reportPath" -Level Success
    return $reportPath
}

function Export-CSVReport {
    $reportPath = "$ReportDir\LargeFiles_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"

    $script:report.LargeFiles | Export-Csv -Path $reportPath -NoTypeInformation -Encoding UTF8
    Write-ColorOutput "CSV report exported to: $reportPath" -Level Success
    return $reportPath
}

# Main execution
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Large Files Scanner" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Server: $($script:report.ServerName)"
Write-Host "Minimum Size: $MinimumSizeMB MB"

# Determine scan paths
if($Path) {
    $scanPaths = @($Path)
}
else {
    $scanPaths = (Get-Volume | Where-Object {$_.DriveLetter -and $_.DriveType -eq 'Fixed'}).DriveLetter | ForEach-Object {"$_`:"}
}

Write-Host "Scan Paths: $($scanPaths -join ', ')"
Write-Host "Excluded Paths: $($ExcludePath -join ', ')"

# Scan each path
foreach($scanPath in $scanPaths) {
    Scan-LargeFiles -ScanPath $scanPath
}

# Find duplicates if requested
if($IncludeDuplicates) {
    Find-Duplicates
}

Show-Summary

if($ExportHTML) {
    Write-Host "Generating HTML report..." -ForegroundColor Cyan
    Export-HTMLReport
}

if($ExportCSV) {
    Write-Host "Generating CSV report..." -ForegroundColor Cyan
    Export-CSVReport
}
