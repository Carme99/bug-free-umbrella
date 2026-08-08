<#
.SYNOPSIS
    Generates comprehensive disk usage report and suggests cleanup targets for Windows Server 2016-2022.

.DESCRIPTION
    This script analyzes disk usage across all volumes and provides:
    - Detailed disk space usage by drive
    - Top 20 largest folders on each drive
    - Temporary file analysis
    - Log file analysis
    - Windows Update cache size
    - IIS log analysis (if applicable)
    - Suggested cleanup targets with potential space savings

.PARAMETER DriveLetter
    Specific drive letter to analyze (e.g., 'C'). If not specified, analyzes all drives.

.PARAMETER ExportReport
    Exports detailed report to HTML file on desktop.

.PARAMETER ShowCleanupOnly
    Only displays cleanup suggestions without full disk analysis.

.PARAMETER MinimumFolderSizeMB
    Minimum folder size in MB to include in large folder report (default: 100MB).

.EXAMPLE
    .\Get-DiskReport.ps1
    Analyzes all drives and displays report in console.

.EXAMPLE
    .\Get-DiskReport.ps1 -DriveLetter C -ExportReport
    Analyzes C: drive and exports HTML report.

.EXAMPLE
    .\Get-DiskReport.ps1 -ShowCleanupOnly
    Displays only cleanup suggestions.

.NOTES
    Requires Administrator privileges for full analysis
    Compatible with Windows Server 2016, 2019, and 2022
    Analysis may take several minutes on large drives
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [ValidatePattern('^[A-Z]$')]
    [string]$DriveLetter,

    [Parameter(Mandatory = $false)]
    [switch]$ExportReport,

    [Parameter(Mandatory = $false)]
    [switch]$ShowCleanupOnly,

    [Parameter(Mandatory = $false)]
    [int]$MinimumFolderSizeMB = 100
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

$script:reportData = @{
    ServerName = $env:COMPUTERNAME
    ScanDate = Get-Date
    Volumes = @()
    CleanupSuggestions = @()
    TotalPotentialSavings = 0
}

function Write-Log {
    param([string]$Message, [string]$Type = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $color = switch ($Type) {
        "ERROR" { "Red" }
        "SUCCESS" { "Green" }
        "WARNING" { "Yellow" }
        "HEADER" { "Cyan" }
        default { "White" }
    }
    Write-Host "[$timestamp] $Message" -ForegroundColor $color
}

function Format-FileSize {
    param([long]$Size)

    if ($Size -gt 1TB) { return "{0:N2} TB" -f ($Size / 1TB) }
    elseif ($Size -gt 1GB) { return "{0:N2} GB" -f ($Size / 1GB) }
    elseif ($Size -gt 1MB) { return "{0:N2} MB" -f ($Size / 1MB) }
    elseif ($Size -gt 1KB) { return "{0:N2} KB" -f ($Size / 1KB) }
    else { return "{0} Bytes" -f $Size }
}

function Get-FolderSize {
    param([string]$Path)

    try {
        $size = (Get-ChildItem -Path $Path -Recurse -File -ErrorAction SilentlyContinue |
                Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
        return [long]$size
    }
    catch {
        return 0
    }
}

function Get-LargestFolders {
    param(
        [string]$DrivePath,
        [int]$TopCount = 20
    )

    Write-Log "Analyzing largest folders on $DrivePath (this may take a few minutes)..." "INFO"

    $folders = Get-ChildItem -Path $DrivePath -Directory -ErrorAction SilentlyContinue

    $folderSizes = @()
    foreach ($folder in $folders) {
        $size = Get-FolderSize -Path $folder.FullName
        $sizeMB = [math]::Round($size / 1MB, 2)

        if ($sizeMB -ge $MinimumFolderSizeMB) {
            $folderSizes += [PSCustomObject]@{
                Path = $folder.FullName
                SizeMB = $sizeMB
                SizeFormatted = Format-FileSize -Size $size
                LastModified = $folder.LastWriteTime
            }
        }
    }

    return $folderSizes | Sort-Object -Property SizeMB -Descending | Select-Object -First $TopCount
}

function Get-CleanupSuggestions {
    param([string]$DriveLetter)

    $suggestions = @()
    $drive = "${DriveLetter}:"

    # 1. Windows Temp Files
    $tempPath = "$drive\Windows\Temp"
    if (Test-Path $tempPath) {
        $tempSize = Get-FolderSize -Path $tempPath
        if ($tempSize -gt 0) {
            $suggestions += [PSCustomObject]@{
                Category = "Windows Temp Files"
                Path = $tempPath
                Size = Format-FileSize -Size $tempSize
                SizeBytes = $tempSize
                Action = "Delete files older than 7 days"
                Command = "Get-ChildItem '$tempPath' -Recurse | Where-Object {`$_.LastWriteTime -lt (Get-Date).AddDays(-7)} | Remove-Item -Force -Recurse"
                Risk = "Low"
            }
        }
    }

    # 2. User Temp Files
    $userTempPath = "$drive\Users\*\AppData\Local\Temp"
    $userTempFolders = Get-ChildItem -Path $userTempPath -Directory -ErrorAction SilentlyContinue
    $totalUserTempSize = 0
    foreach ($folder in $userTempFolders) {
        $totalUserTempSize += Get-FolderSize -Path $folder.FullName
    }
    if ($totalUserTempSize -gt 0) {
        $suggestions += [PSCustomObject]@{
            Category = "User Temp Files"
            Path = $userTempPath
            Size = Format-FileSize -Size $totalUserTempSize
            SizeBytes = $totalUserTempSize
            Action = "Delete files older than 7 days"
            Command = "Get-ChildItem '$userTempPath' -Recurse | Where-Object {`$_.LastWriteTime -lt (Get-Date).AddDays(-7)} | Remove-Item -Force -Recurse"
            Risk = "Low"
        }
    }

    # 3. Windows Update Cache
    $wuCachePath = "$drive\Windows\SoftwareDistribution\Download"
    if (Test-Path $wuCachePath) {
        $wuSize = Get-FolderSize -Path $wuCachePath
        if ($wuSize -gt 100MB) {
            $suggestions += [PSCustomObject]@{
                Category = "Windows Update Cache"
                Path = $wuCachePath
                Size = Format-FileSize -Size $wuSize
                SizeBytes = $wuSize
                Action = "Clear Windows Update cache (stop wuauserv first)"
                Command = "Stop-Service wuauserv; Remove-Item '$wuCachePath\*' -Recurse -Force; Start-Service wuauserv"
                Risk = "Low"
            }
        }
    }

    # 4. IIS Logs (if IIS is installed)
    $iisLogPath = "$drive\inetpub\logs\LogFiles"
    if (Test-Path $iisLogPath) {
        $iisLogSize = Get-FolderSize -Path $iisLogPath
        if ($iisLogSize -gt 500MB) {
            $suggestions += [PSCustomObject]@{
                Category = "IIS Log Files"
                Path = $iisLogPath
                Size = Format-FileSize -Size $iisLogSize
                SizeBytes = $iisLogSize
                Action = "Archive or delete logs older than 90 days"
                Command = "Get-ChildItem '$iisLogPath' -Recurse -Filter *.log | Where-Object {`$_.LastWriteTime -lt (Get-Date).AddDays(-90)} | Remove-Item -Force"
                Risk = "Medium - Ensure logs are backed up if needed"
            }
        }
    }

    # 5. Windows Error Reporting
    $werPath = "$drive\ProgramData\Microsoft\Windows\WER"
    if (Test-Path $werPath) {
        $werSize = Get-FolderSize -Path $werPath
        if ($werSize -gt 100MB) {
            $suggestions += [PSCustomObject]@{
                Category = "Windows Error Reports"
                Path = $werPath
                Size = Format-FileSize -Size $werSize
                SizeBytes = $werSize
                Action = "Delete old error reports"
                Command = "Remove-Item '$werPath\ReportQueue\*' -Recurse -Force; Remove-Item '$werPath\ReportArchive\*' -Recurse -Force"
                Risk = "Low"
            }
        }
    }

    # 6. Recycle Bin
    $recycleBin = Get-ChildItem "$drive\`$Recycle.Bin" -Force -ErrorAction SilentlyContinue
    if ($recycleBin) {
        $recycleSize = 0
        foreach ($item in $recycleBin) {
            $recycleSize += Get-FolderSize -Path $item.FullName
        }
        if ($recycleSize -gt 0) {
            $suggestions += [PSCustomObject]@{
                Category = "Recycle Bin"
                Path = "$drive\`$Recycle.Bin"
                Size = Format-FileSize -Size $recycleSize
                SizeBytes = $recycleSize
                Action = "Empty Recycle Bin"
                Command = "Clear-RecycleBin -DriveLetter $DriveLetter -Force"
                Risk = "Low - Files will be permanently deleted"
            }
        }
    }

    # 7. Old Log Files
    $logPaths = @("$drive\Windows\Logs", "$drive\Windows\System32\LogFiles")
    foreach ($logPath in $logPaths) {
        if (Test-Path $logPath) {
            $oldLogs = Get-ChildItem -Path $logPath -Recurse -File -Filter *.log -ErrorAction SilentlyContinue |
                Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-90) }
            $oldLogSize = ($oldLogs | Measure-Object -Property Length -Sum).Sum

            if ($oldLogSize -gt 100MB) {
                $suggestions += [PSCustomObject]@{
                    Category = "Old System Logs"
                    Path = $logPath
                    Size = Format-FileSize -Size $oldLogSize
                    SizeBytes = $oldLogSize
                    Action = "Delete log files older than 90 days"
                    Command = "Get-ChildItem '$logPath' -Recurse -Filter *.log | Where-Object {`$_.LastWriteTime -lt (Get-Date).AddDays(-90)} | Remove-Item -Force"
                    Risk = "Low - Ensure logs are backed up if needed"
                }
            }
        }
    }

    # 8. Windows.old folder
    $windowsOldPath = "$drive\Windows.old"
    if (Test-Path $windowsOldPath) {
        $windowsOldSize = Get-FolderSize -Path $windowsOldPath
        if ($windowsOldSize -gt 0) {
            $suggestions += [PSCustomObject]@{
                Category = "Previous Windows Installation"
                Path = $windowsOldPath
                Size = Format-FileSize -Size $windowsOldSize
                SizeBytes = $windowsOldSize
                Action = "Remove using Disk Cleanup or manually"
                Command = "Remove-Item '$windowsOldPath' -Recurse -Force"
                Risk = "Medium - Cannot rollback Windows after deletion"
            }
        }
    }

    return $suggestions | Sort-Object -Property SizeBytes -Descending
}

function Show-DiskReport {
    param([array]$Volumes)

    Write-Log "`n========================================" "HEADER"
    Write-Log "DISK USAGE REPORT - $($script:reportData.ServerName)" "HEADER"
    Write-Log "========================================" "HEADER"

    foreach ($volume in $Volumes) {
        Write-Log "`n--- Drive $($volume.DriveLetter): ---" "HEADER"
        Write-Log "Total Size:    $($volume.TotalSize)" "INFO"
        Write-Log "Used Space:    $($volume.UsedSpace)" "INFO"
        Write-Log "Free Space:    $($volume.FreeSpace)" "SUCCESS"
        Write-Log "Free Percent:  $($volume.FreePercent)%" "SUCCESS"

        if ($volume.LargestFolders.Count -gt 0) {
            Write-Log "`nTop $($volume.LargestFolders.Count) Largest Folders:" "INFO"
            $volume.LargestFolders | Format-Table -Property Path, SizeFormatted, LastModified -AutoSize | Out-String | Write-Host
        }
    }
}

function Show-CleanupSuggestions {
    param([array]$Suggestions)

    Write-Log "`n========================================" "HEADER"
    Write-Log "CLEANUP SUGGESTIONS" "HEADER"
    Write-Log "========================================" "HEADER"

    if ($Suggestions.Count -eq 0) {
        Write-Log "No significant cleanup opportunities found." "SUCCESS"
        return
    }

    $totalSavings = ($Suggestions | Measure-Object -Property SizeBytes -Sum).Sum
    Write-Log "Total Potential Savings: $(Format-FileSize -Size $totalSavings)" "SUCCESS"

    $Suggestions | Format-Table -Property Category, Path, Size, Action, Risk -AutoSize | Out-String | Write-Host

    Write-Log "`nTo execute cleanup commands, copy and run them individually." "WARNING"
}

function Export-HTMLReport {
    $reportPath = "$ReportDir\DiskReport_$($env:COMPUTERNAME)_$(Get-Date -Format 'yyyyMMdd_HHmmss').html"

    $volumesHTML = ""
    foreach ($volume in $script:reportData.Volumes) {
        $volumesHTML += @"
        <h2>Drive $($volume.DriveLetter):</h2>
        <table class="info-table">
            <tr><th>Total Size</th><td>$($volume.TotalSize)</td></tr>
            <tr><th>Used Space</th><td>$($volume.UsedSpace)</td></tr>
            <tr><th>Free Space</th><td class="$(if($volume.FreePercentValue -lt 10){'critical'}elseif($volume.FreePercentValue -lt 20){'warning'}else{'good'})">$($volume.FreeSpace) ($($volume.FreePercent)%)</td></tr>
        </table>
        <h3>Largest Folders</h3>
        <table class="data-table">
            <tr><th>Path</th><th>Size</th><th>Last Modified</th></tr>
"@
        foreach ($folder in $volume.LargestFolders) {
            $volumesHTML += "<tr><td>$($folder.Path)</td><td>$($folder.SizeFormatted)</td><td>$($folder.LastModified)</td></tr>"
        }
        $volumesHTML += "</table>"
    }

    $suggestionsHTML = ""
    if ($script:reportData.CleanupSuggestions.Count -gt 0) {
        $suggestionsHTML = "<h2>Cleanup Suggestions</h2><p><strong>Total Potential Savings: $(Format-FileSize -Size $script:reportData.TotalPotentialSavings)</strong></p><table class='data-table'><tr><th>Category</th><th>Path</th><th>Size</th><th>Action</th><th>Risk</th></tr>"
        foreach ($suggestion in $script:reportData.CleanupSuggestions) {
            $suggestionsHTML += "<tr><td>$($suggestion.Category)</td><td>$($suggestion.Path)</td><td>$($suggestion.Size)</td><td>$($suggestion.Action)</td><td>$($suggestion.Risk)</td></tr>"
        }
        $suggestionsHTML += "</table>"
    }

    $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>Disk Report - $($script:reportData.ServerName)</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background-color: #f5f5f5; }
        .container { background-color: white; padding: 20px; border-radius: 5px; box-shadow: 0 2px 5px rgba(0,0,0,0.1); }
        h1 { color: #333; border-bottom: 2px solid #0078d4; padding-bottom: 10px; }
        h2 { color: #0078d4; margin-top: 30px; }
        h3 { color: #555; }
        .info-table, .data-table { width: 100%; border-collapse: collapse; margin: 15px 0; }
        .info-table th, .info-table td, .data-table th, .data-table td { padding: 10px; text-align: left; border-bottom: 1px solid #ddd; }
        .info-table th, .data-table th { background-color: #0078d4; color: white; }
        .good { color: green; font-weight: bold; }
        .warning { color: orange; font-weight: bold; }
        .critical { color: red; font-weight: bold; }
        .data-table { font-size: 13px; }
    </style>
</head>
<body>
    <div class="container">
        <h1>Disk Usage Report</h1>
        <p><strong>Server:</strong> $($script:reportData.ServerName)</p>
        <p><strong>Report Date:</strong> $($script:reportData.ScanDate)</p>
        $volumesHTML
        $suggestionsHTML
    </div>
</body>
</html>
"@

    $html | Out-File -FilePath $reportPath -Encoding UTF8
    Write-Log "HTML report exported to: $reportPath" "SUCCESS"
    Start-Process $reportPath
}

# Main execution
Write-Log "Starting disk analysis on $env:COMPUTERNAME..." "INFO"

# Get volumes to analyze
if ($DriveLetter) {
    $volumes = Get-Volume | Where-Object { $_.DriveLetter -eq $DriveLetter -and $_.FileSystem -eq "NTFS" }
}
else {
    $volumes = Get-Volume | Where-Object { $_.DriveLetter -ne $null -and $_.FileSystem -eq "NTFS" }
}

if (-not $ShowCleanupOnly) {
    foreach ($volume in $volumes) {
        $driveLetter = $volume.DriveLetter
        $totalSize = $volume.Size
        $freeSpace = $volume.SizeRemaining
        $usedSpace = $totalSize - $freeSpace
        $freePercent = [math]::Round(($freeSpace / $totalSize) * 100, 2)

        $largestFolders = Get-LargestFolders -DrivePath "${driveLetter}:\" -TopCount 20

        $volumeData = [PSCustomObject]@{
            DriveLetter = $driveLetter
            TotalSize = Format-FileSize -Size $totalSize
            UsedSpace = Format-FileSize -Size $usedSpace
            FreeSpace = Format-FileSize -Size $freeSpace
            FreePercent = $freePercent
            FreePercentValue = $freePercent
            LargestFolders = $largestFolders
        }

        $script:reportData.Volumes += $volumeData
    }

    Show-DiskReport -Volumes $script:reportData.Volumes
}

# Get cleanup suggestions
foreach ($volume in $volumes) {
    $suggestions = Get-CleanupSuggestions -DriveLetter $volume.DriveLetter
    $script:reportData.CleanupSuggestions += $suggestions
}

$script:reportData.TotalPotentialSavings = ($script:reportData.CleanupSuggestions | Measure-Object -Property SizeBytes -Sum).Sum

Show-CleanupSuggestions -Suggestions $script:reportData.CleanupSuggestions

if ($ExportReport) {
    Export-HTMLReport
}

Write-Log "`nDisk analysis completed." "SUCCESS"
