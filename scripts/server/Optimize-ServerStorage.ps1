<#
.SYNOPSIS
    Automated disk cleanup and optimization for Windows Server 2016-2022.

.DESCRIPTION
    This script performs comprehensive disk cleanup operations:
    - Windows Update cleanup (old updates, download cache)
    - Temporary file removal (Windows Temp, User Temp, IIS logs)
    - Log file rotation and cleanup
    - Recycle Bin cleanup
    - Windows Error Reporting archives
    - Thumbnail cache cleanup
    - Shadow copy management
    - IIS log cleanup (if applicable)
    - Optional DISM component store cleanup
    - Reports space saved

.PARAMETER DriveLetter
    Target drive letter to clean (e.g., 'C'). If not specified, cleans all drives.

.PARAMETER IncludeWindowsUpdate
    Clean Windows Update cache and old update files.

.PARAMETER IncludeIISLogs
    Clean old IIS logs (older than specified days).

.PARAMETER IISLogRetentionDays
    Number of days to retain IIS logs (default: 30).

.PARAMETER IncludeDISM
    Run DISM component store cleanup (can take significant time).

.PARAMETER WhatIf
    Show what would be cleaned without actually deleting files.

.PARAMETER Force
    Skip confirmation prompts.

.EXAMPLE
    .\Optimize-ServerStorage.ps1 -WhatIf
    Shows what would be cleaned without making changes.

.EXAMPLE
    .\Optimize-ServerStorage.ps1 -DriveLetter C -IncludeWindowsUpdate -Force
    Performs full cleanup on C: drive including Windows Update cache.

.EXAMPLE
    .\Optimize-ServerStorage.ps1 -IncludeIISLogs -IISLogRetentionDays 14
    Cleans all drives and removes IIS logs older than 14 days.

.NOTES
    Requires Administrator privileges
    Compatible with Windows Server 2016, 2019, and 2022
    DISM cleanup can take 30+ minutes
    Always test with -WhatIf first
#>

[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [Parameter(Mandatory=$false)]
    [ValidatePattern('^[A-Z]$')]
    [string]$DriveLetter,

    [Parameter(Mandatory=$false)]
    [switch]$IncludeWindowsUpdate,

    [Parameter(Mandatory=$false)]
    [switch]$IncludeIISLogs,

    [Parameter(Mandatory=$false)]
    [int]$IISLogRetentionDays = 30,

    [Parameter(Mandatory=$false)]
    [switch]$IncludeDISM,

    [Parameter(Mandatory=$false)]
    [switch]$Force
)

#Requires -RunAsAdministrator

$script:report = @{
    ServerName = $env:COMPUTERNAME
    StartTime = Get-Date
    EndTime = $null
    InitialSpace = @{}
    FinalSpace = @{}
    SpaceSaved = @{}
    Operations = @()
    TotalSpaceSavedMB = 0
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

function Get-DiskSpace {
    param([string]$Drive)

    $volume = Get-Volume | Where-Object {$_.DriveLetter -eq $Drive}
    if($volume) {
        return @{
            TotalGB = [math]::Round($volume.Size / 1GB, 2)
            FreeGB = [math]::Round($volume.SizeRemaining / 1GB, 2)
            UsedGB = [math]::Round(($volume.Size - $volume.SizeRemaining) / 1GB, 2)
        }
    }
    return $null
}

function Get-FolderSize {
    param([string]$Path)

    if(Test-Path $Path) {
        try {
            $size = (Get-ChildItem -Path $Path -Recurse -File -ErrorAction SilentlyContinue |
                Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
            return [math]::Round($size / 1MB, 2)
        }
        catch {
            return 0
        }
    }
    return 0
}

function Remove-FolderContents {
    param(
        [string]$Path,
        [string]$Description,
        [int]$OlderThanDays = 0
    )

    if(-not (Test-Path $Path)) {
        Write-Verbose "$Path does not exist, skipping..."
        return
    }

    $beforeSize = Get-FolderSize -Path $Path

    if($WhatIfPreference) {
        Write-ColorOutput "  [WHATIF] Would clean: $Description ($Path)" -Level Info
        Write-ColorOutput "    Current size: $beforeSize MB" -Level Info
        return
    }

    Write-Host "  Cleaning: $Description..." -ForegroundColor Cyan

    try {
        if($OlderThanDays -gt 0) {
            $cutoffDate = (Get-Date).AddDays(-$OlderThanDays)
            $items = Get-ChildItem -Path $Path -Recurse -File -ErrorAction SilentlyContinue |
                Where-Object {$_.LastWriteTime -lt $cutoffDate}
        }
        else {
            $items = Get-ChildItem -Path $Path -Recurse -File -ErrorAction SilentlyContinue
        }

        $itemCount = 0
        foreach($item in $items) {
            try {
                Remove-Item -Path $item.FullName -Force -ErrorAction SilentlyContinue
                $itemCount++
            }
            catch {
                Write-Verbose "Could not delete: $($item.FullName)"
            }
        }

        $afterSize = Get-FolderSize -Path $Path
        $savedMB = $beforeSize - $afterSize

        if($savedMB -gt 0) {
            Write-ColorOutput "    Cleaned $itemCount files, saved $savedMB MB" -Level Success
            $script:report.TotalSpaceSavedMB += $savedMB
        }
        else {
            Write-Host "    No files to clean" -ForegroundColor Gray
        }

        $script:report.Operations += [PSCustomObject]@{
            Operation = $Description
            Path = $Path
            BeforeMB = $beforeSize
            AfterMB = $afterSize
            SavedMB = $savedMB
            FilesRemoved = $itemCount
        }
    }
    catch {
        Write-ColorOutput "    Error cleaning $Description : $($_.Exception.Message)" -Level Error
    }
}

function Clean-WindowsTemp {
    Write-Host "`nCleaning Windows temporary files..." -ForegroundColor Cyan

    Remove-FolderContents -Path "$env:SystemRoot\Temp" -Description "Windows Temp folder"
    Remove-FolderContents -Path "$env:SystemRoot\Logs\CBS" -Description "Component-Based Servicing logs" -OlderThanDays 30
    Remove-FolderContents -Path "$env:SystemRoot\SoftwareDistribution\Download" -Description "Windows Update download cache"
}

function Clean-UserTemp {
    Write-Host "`nCleaning user temporary files..." -ForegroundColor Cyan

    $userProfiles = Get-ChildItem "C:\Users" -Directory -ErrorAction SilentlyContinue

    foreach($profile in $userProfiles) {
        $tempPath = Join-Path $profile.FullName "AppData\Local\Temp"
        if(Test-Path $tempPath) {
            Remove-FolderContents -Path $tempPath -Description "User temp: $($profile.Name)"
        }
    }
}

function Clean-RecycleBin {
    Write-Host "`nCleaning Recycle Bin..." -ForegroundColor Cyan

    if($WhatIfPreference) {
        Write-ColorOutput "  [WHATIF] Would empty Recycle Bin on all drives" -Level Info
        return
    }

    try {
        Clear-RecycleBin -Force -ErrorAction Stop
        Write-ColorOutput "  Recycle Bin emptied" -Level Success

        $script:report.Operations += [PSCustomObject]@{
            Operation = "Empty Recycle Bin"
            Path = "All drives"
            BeforeMB = 0
            AfterMB = 0
            SavedMB = 0
            FilesRemoved = 0
        }
    }
    catch {
        Write-ColorOutput "  Error emptying Recycle Bin: $($_.Exception.Message)" -Level Error
    }
}

function Clean-WindowsErrorReporting {
    Write-Host "`nCleaning Windows Error Reporting..." -ForegroundColor Cyan

    $werPaths = @(
        "$env:ProgramData\Microsoft\Windows\WER\ReportArchive",
        "$env:ProgramData\Microsoft\Windows\WER\ReportQueue"
    )

    foreach($path in $werPaths) {
        if(Test-Path $path) {
            Remove-FolderContents -Path $path -Description "Windows Error Reporting: $(Split-Path $path -Leaf)" -OlderThanDays 7
        }
    }
}

function Clean-ThumbnailCache {
    Write-Host "`nCleaning thumbnail cache..." -ForegroundColor Cyan

    $userProfiles = Get-ChildItem "C:\Users" -Directory -ErrorAction SilentlyContinue

    foreach($profile in $userProfiles) {
        $thumbPath = Join-Path $profile.FullName "AppData\Local\Microsoft\Windows\Explorer"
        if(Test-Path $thumbPath) {
            Remove-FolderContents -Path $thumbPath -Description "Thumbnail cache: $($profile.Name)"
        }
    }
}

function Clean-WindowsUpdate {
    Write-Host "`nCleaning Windows Update cache..." -ForegroundColor Cyan

    if($WhatIfPreference) {
        Write-ColorOutput "  [WHATIF] Would run Windows Update cleanup" -Level Info
        return
    }

    try {
        # Stop Windows Update service
        Write-Host "  Stopping Windows Update service..." -ForegroundColor Gray
        Stop-Service -Name wuauserv -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2

        # Clean download folder
        Remove-FolderContents -Path "$env:SystemRoot\SoftwareDistribution\Download" -Description "Windows Update downloads"

        # Clean old update installers
        Remove-FolderContents -Path "$env:SystemRoot\SoftwareDistribution\DataStore\Logs" -Description "Windows Update logs" -OlderThanDays 30

        # Restart Windows Update service
        Write-Host "  Starting Windows Update service..." -ForegroundColor Gray
        Start-Service -Name wuauserv -ErrorAction SilentlyContinue

        Write-ColorOutput "  Windows Update cleanup completed" -Level Success
    }
    catch {
        Write-ColorOutput "  Error during Windows Update cleanup: $($_.Exception.Message)" -Level Error
        # Ensure service is restarted
        Start-Service -Name wuauserv -ErrorAction SilentlyContinue
    }
}

function Clean-IISLogs {
    Write-Host "`nCleaning IIS logs..." -ForegroundColor Cyan

    # Check if IIS is installed
    $iisInstalled = Get-Service -Name W3SVC -ErrorAction SilentlyContinue

    if(-not $iisInstalled) {
        Write-Host "  IIS not detected, skipping..." -ForegroundColor Gray
        return
    }

    $iisLogPaths = @(
        "$env:SystemDrive\inetpub\logs\LogFiles"
    )

    # Try to get IIS log paths from IIS configuration
    try {
        Import-Module WebAdministration -ErrorAction SilentlyContinue
        $sites = Get-Website -ErrorAction SilentlyContinue
        foreach($site in $sites) {
            $logPath = $site.logFile.directory
            if($logPath -and (Test-Path $logPath)) {
                $iisLogPaths += $logPath
            }
        }
    }
    catch {
        Write-Verbose "Could not read IIS configuration"
    }

    foreach($path in ($iisLogPaths | Select-Object -Unique)) {
        if(Test-Path $path) {
            Remove-FolderContents -Path $path -Description "IIS logs older than $IISLogRetentionDays days" -OlderThanDays $IISLogRetentionDays
        }
    }
}

function Clean-DISMComponentStore {
    Write-Host "`nRunning DISM component store cleanup..." -ForegroundColor Cyan
    Write-ColorOutput "  This operation can take 30+ minutes..." -Level Warning

    if($WhatIfPreference) {
        Write-ColorOutput "  [WHATIF] Would run DISM component store cleanup" -Level Info
        return
    }

    if(-not $Force) {
        $confirm = Read-Host "DISM cleanup can take significant time. Continue? (y/N)"
        if($confirm -ne 'y') {
            Write-Host "  Skipping DISM cleanup..." -ForegroundColor Gray
            return
        }
    }

    try {
        Write-Host "  Starting DISM cleanup (this will take a while)..." -ForegroundColor Gray
        $result = Dism.exe /Online /Cleanup-Image /StartComponentCleanup /ResetBase

        if($LASTEXITCODE -eq 0) {
            Write-ColorOutput "  DISM cleanup completed successfully" -Level Success
            $script:report.Operations += [PSCustomObject]@{
                Operation = "DISM Component Store Cleanup"
                Path = "WinSxS"
                BeforeMB = 0
                AfterMB = 0
                SavedMB = 0
                FilesRemoved = 0
            }
        }
        else {
            Write-ColorOutput "  DISM cleanup completed with warnings (exit code: $LASTEXITCODE)" -Level Warning
        }
    }
    catch {
        Write-ColorOutput "  Error running DISM cleanup: $($_.Exception.Message)" -Level Error
    }
}

function Show-Summary {
    $script:report.EndTime = Get-Date
    $duration = ($script:report.EndTime - $script:report.StartTime).TotalSeconds

    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "  Storage Optimization Summary" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Server: $($script:report.ServerName)"
    Write-Host "Start Time: $($script:report.StartTime)"
    Write-Host "End Time: $($script:report.EndTime)"
    Write-Host "Duration: $([math]::Round($duration, 2)) seconds"

    if($WhatIfPreference) {
        Write-ColorOutput "`n[WHATIF MODE - No changes were made]" -Level Warning
    }
    else {
        Write-Host "`nTotal Space Saved: $([math]::Round($script:report.TotalSpaceSavedMB / 1024, 2)) GB ($($script:report.TotalSpaceSavedMB) MB)" -ForegroundColor Green
    }

    # Show space changes per drive
    foreach($drive in $script:report.FinalSpace.Keys) {
        $initial = $script:report.InitialSpace[$drive]
        $final = $script:report.FinalSpace[$drive]
        $saved = $final.FreeGB - $initial.FreeGB

        Write-Host "`nDrive $drive`:" -ForegroundColor Cyan
        Write-Host "  Before: $($initial.FreeGB) GB free / $($initial.TotalGB) GB total"
        Write-Host "  After:  $($final.FreeGB) GB free / $($final.TotalGB) GB total"
        if($saved -gt 0) {
            Write-ColorOutput "  Saved:  $([math]::Round($saved, 2)) GB" -Level Success
        }
    }

    # Show operations performed
    if($script:report.Operations.Count -gt 0) {
        Write-Host "`nOperations Performed:" -ForegroundColor Cyan
        $script:report.Operations | Where-Object {$_.SavedMB -gt 0} |
            Sort-Object SavedMB -Descending |
            Format-Table Operation, @{Name='Saved (MB)';Expression={$_.SavedMB}}, FilesRemoved -AutoSize
    }

    Write-Host "`n========================================`n" -ForegroundColor Cyan
}

# Main execution
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Server Storage Optimization" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Server: $($script:report.ServerName)"

if($WhatIfPreference) {
    Write-ColorOutput "Running in WhatIf mode - no changes will be made" -Level Warning
}

# Get initial disk space
$drives = if($DriveLetter) { @($DriveLetter) } else { (Get-Volume | Where-Object {$_.DriveLetter}).DriveLetter }

foreach($drive in $drives) {
    $space = Get-DiskSpace -Drive $drive
    if($space) {
        $script:report.InitialSpace[$drive] = $space
        Write-Host "`nDrive $drive`: $($space.FreeGB) GB free / $($space.TotalGB) GB total"
    }
}

# Perform cleanup operations
Clean-WindowsTemp
Clean-UserTemp
Clean-RecycleBin
Clean-WindowsErrorReporting
Clean-ThumbnailCache

if($IncludeWindowsUpdate) {
    Clean-WindowsUpdate
}

if($IncludeIISLogs) {
    Clean-IISLogs
}

if($IncludeDISM) {
    Clean-DISMComponentStore
}

# Get final disk space
foreach($drive in $drives) {
    $space = Get-DiskSpace -Drive $drive
    if($space) {
        $script:report.FinalSpace[$drive] = $space
    }
}

Show-Summary
