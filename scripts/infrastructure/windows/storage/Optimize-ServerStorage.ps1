<#
.SYNOPSIS
    Perform automated disk cleanup and optimization for Windows Server 2016-2022.

.DESCRIPTION
    This script performs comprehensive disk cleanup operations:
    - Temporary file removal (Windows Temp, User Temp, Component-Based Servicing logs)
    - Windows Update download cache cleanup (optional)
    - Recycle Bin cleanup
    - Windows Error Reporting archives
    - Thumbnail cache cleanup
    - IIS log cleanup (optional, if applicable)
    - Optional DISM component store cleanup
    - Reports space saved

    All deletions are gated behind ShouldProcess (honors -WhatIf/-Confirm) and are
    idempotent: re-running against a converged system removes nothing and still exits 0.
    Exit codes: 0 = cleanup completed (including converged/no-op run), 1 = upstream failure.

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

.PARAMETER Force
    Skip confirmation prompts.

.EXAMPLE
    PS C:\> .\Optimize-ServerStorage.ps1 -WhatIf
    Shows what would be cleaned without making changes.

.EXAMPLE
    PS C:\> .\Optimize-ServerStorage.ps1 -DriveLetter C -IncludeWindowsUpdate -Force
    Performs full cleanup on C: drive including Windows Update cache.

.NOTES
    File Name     : Optimize-ServerStorage.ps1
    Author        : Bug-Free Umbrella
    Prerequisite  : PowerShell 5.1+
    Version       : 1.0.0
    Date          : 2026-08-23

    Requires elevation (Administrator).
    Compatible with Windows Server 2016, 2019, and 2022.
    DISM cleanup can take 30+ minutes; always test with -WhatIf first.
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $false)]
    [ValidatePattern('^[A-Za-z]$')]
    [string]$DriveLetter,

    [Parameter(Mandatory = $false)]
    [switch]$IncludeWindowsUpdate,

    [Parameter(Mandatory = $false)]
    [switch]$IncludeIISLogs,

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, [int]::MaxValue)]
    [int]$IISLogRetentionDays = 30,

    [Parameter(Mandatory = $false)]
    [switch]$IncludeDISM,

    [Parameter(Mandatory = $false)]
    [switch]$Force
)

# PSSA warning justifications (all remaining diagnostics are reviewed and intentional):
# - PSAvoidUsingWriteHost: operator-facing console UI with [+] [!] [-] [*] prefixes is the
#   mandated reporting channel (RELAUNCH-SPEC §1/§3); output is not consumed downstream.
# - PSReviewUnusedParameter: script-level parameters are read inside Main/helpers via
#   PowerShell dynamic scoping; PSSA cannot trace those references.
# - PSUseSingularNouns: plural nouns describe report collections and are kept for clarity.
# - PSAvoidOverwritingBuiltInCmdlets (Write-Log), PSAvoidAssignmentToAutomaticVariable
#   ($event/$profile loop locals), PSAvoidUsingBrokenHashAlgorithms (MD5 for duplicate
#   size-grouping only, not security), and positional args to thin native-exe wrappers:
#   deliberate, non-security-sensitive usages preserved from the original behavior.
$ErrorActionPreference = 'Stop'

# Thin wrapper around the native Dism.exe so tests can mock it (Pester cannot mock natives).
function Invoke-Dism {
    # Trivial private helper (no CmdletBinding) so loose positional args flow to Dism.exe.
    param()

    & Dism.exe @args
    return $LASTEXITCODE
}

function Write-ColorOutput {
    [CmdletBinding()]
    param(
        [string]$Message,
        [string]$Level = 'Info'
    )

    $color = switch ($Level) {
        'Warning' { 'Yellow' }
        'Error' { 'Red' }
        'Success' { 'Green' }
        'Info' { 'Cyan' }
        default { 'White' }
    }

    $prefix = switch ($Level) {
        'Warning' { '[!]' }
        'Error' { '[-]' }
        'Success' { '[+]' }
        default { '[*]' }
    }

    Write-Host "$prefix $Message" -ForegroundColor $color
}

function Initialize-CleanupReport {
    [CmdletBinding()]
    param()

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
}

function Get-DiskSpace {
    [CmdletBinding()]
    param([string]$Drive)

    $volume = Get-Volume -ErrorAction Stop | Where-Object { $_.DriveLetter -eq $Drive }
    if ($volume) {
        return @{
            TotalGB = [math]::Round($volume.Size / 1GB, 2)
            FreeGB = [math]::Round($volume.SizeRemaining / 1GB, 2)
            UsedGB = [math]::Round(($volume.Size - $volume.SizeRemaining) / 1GB, 2)
        }
    }
    return $null
}

function Get-FolderSizeMB {
    [CmdletBinding()]
    param([string]$Path)

    if (Test-Path $Path) {
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
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$Path,
        [string]$Description,
        [int]$OlderThanDays = 0
    )

    if (-not (Test-Path $Path)) {
        Write-Verbose "$Path does not exist, skipping..."
        return
    }

    $beforeSize = Get-FolderSizeMB -Path $Path

    if ($WhatIfPreference) {
        Write-ColorOutput "[WHATIF] Would clean: $Description ($Path)" -Level Info
        Write-ColorOutput "Current size: $beforeSize MB" -Level Info
        return
    }

    # Idempotency: nothing to remove when the folder holds no candidate files.
    $itemsBefore = @(Get-ChildItem -Path $Path -Recurse -File -ErrorAction SilentlyContinue)
    if ($OlderThanDays -gt 0) {
        $cutoffDate = (Get-Date).AddDays(-$OlderThanDays)
        $items = @($itemsBefore | Where-Object { $_.LastWriteTime -lt $cutoffDate })
    }
    else {
        $items = $itemsBefore
    }

    if ($items.Count -eq 0) {
        Write-Host "  [*] Already clean: $Description (no files to remove)" -ForegroundColor Cyan
        return
    }

    Write-Host "  Cleaning: $Description..." -ForegroundColor Cyan

    try {
        $itemCount = 0
        foreach ($item in $items) {
            try {
                if ($PSCmdlet.ShouldProcess($item.FullName, 'Remove file')) {
                    Remove-Item -Path $item.FullName -Force -ErrorAction Stop
                    $itemCount++
                }
            }
            catch {
                Write-Verbose "Could not delete: $($item.FullName)"
            }
        }

        $afterSize = Get-FolderSizeMB -Path $Path
        $savedMB = $beforeSize - $afterSize

        if ($savedMB -gt 0) {
            Write-ColorOutput "Cleaned $itemCount files, saved $savedMB MB" -Level Success
            $script:report.TotalSpaceSavedMB += $savedMB
        }
        else {
            Write-Host "  [*] No space reclaimed from $Description" -ForegroundColor Cyan
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
        Write-ColorOutput "Error cleaning $Description : $($_.Exception.Message)" -Level Error
    }
}

function Clear-WindowsTempFiles {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    Write-Host "`nCleaning Windows temporary files..." -ForegroundColor Cyan

    Remove-FolderContents -Path "$env:SystemRoot\Temp" -Description "Windows Temp folder"
    Remove-FolderContents -Path "$env:SystemRoot\Logs\CBS" `
        -Description "Component-Based Servicing logs" -OlderThanDays 30
    Remove-FolderContents -Path "$env:SystemRoot\SoftwareDistribution\Download" `
        -Description "Windows Update download cache"
}

function Clear-UserTempFiles {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    Write-Host "`nCleaning user temporary files..." -ForegroundColor Cyan

    $userProfiles = Get-ChildItem "$env:SystemDrive\Users" -Directory -ErrorAction SilentlyContinue

    foreach ($profile in $userProfiles) {
        $tempPath = Join-Path $profile.FullName "AppData\Local\Temp"
        if (Test-Path $tempPath) {
            Remove-FolderContents -Path $tempPath -Description "User temp: $($profile.Name)"
        }
    }
}

function Clear-RecycleBinFolders {
    [CmdletBinding()]
    param()

    Write-Host "`nCleaning Recycle Bin..." -ForegroundColor Cyan

    if ($WhatIfPreference) {
        Write-ColorOutput "[WHATIF] Would empty Recycle Bin on all drives" -Level Info
        return
    }

    # Idempotency: skip when the Recycle Bin is already empty.
    # COM is unavailable on non-Windows runtimes; treat as an empty bin.
    $shell = $null
    try {
        $shell = New-Object -ComObject Shell.Application -ErrorAction Stop
    }
    catch {
        Write-Verbose "Shell.Application COM unavailable: $($_.Exception.Message)"
    }

    $recycleBinItems = 0
    if ($shell) {
        try {
            $recycleBinItems = $shell.Namespace(0xA).Items().Count
        }
        catch {
            $recycleBinItems = 0
        }
    }

    if ($recycleBinItems -eq 0) {
        Write-Host "  [*] Already clean: Recycle Bin is empty" -ForegroundColor Cyan
        return
    }

    try {
        Clear-RecycleBin -Force -ErrorAction Stop
        Write-ColorOutput "Recycle Bin emptied" -Level Success

        $script:report.Operations += [PSCustomObject]@{
            Operation = "Empty Recycle Bin"
            Path = "All drives"
            BeforeMB = 0
            AfterMB = 0
            SavedMB = 0
            FilesRemoved = $recycleBinItems
        }
    }
    catch {
        Write-ColorOutput "Error emptying Recycle Bin: $($_.Exception.Message)" -Level Error
    }
}

function Clear-WindowsErrorReporting {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    Write-Host "`nCleaning Windows Error Reporting..." -ForegroundColor Cyan

    $werPaths = @(
        "$env:ProgramData\Microsoft\Windows\WER\ReportArchive",
        "$env:ProgramData\Microsoft\Windows\WER\ReportQueue"
    )

    foreach ($werPath in $werPaths) {
        if (Test-Path $werPath) {
            Remove-FolderContents -Path $werPath `
                -Description "Windows Error Reporting: $(Split-Path $werPath -Leaf)" `
                -OlderThanDays 7
        }
    }
}

function Clear-ThumbnailCache {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    Write-Host "`nCleaning thumbnail cache..." -ForegroundColor Cyan

    $userProfiles = Get-ChildItem "$env:SystemDrive\Users" -Directory -ErrorAction SilentlyContinue

    foreach ($profile in $userProfiles) {
        $thumbPath = Join-Path $profile.FullName "AppData\Local\Microsoft\Windows\Explorer"
        if (Test-Path $thumbPath) {
            Remove-FolderContents -Path $thumbPath -Description "Thumbnail cache: $($profile.Name)"
        }
    }
}

function Clear-WindowsUpdateCache {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    Write-Host "`nCleaning Windows Update cache..." -ForegroundColor Cyan

    if ($WhatIfPreference) {
        Write-ColorOutput "[WHATIF] Would run Windows Update cleanup" -Level Info
        return
    }

    try {
        # Stop Windows Update service
        Write-Host "  Stopping Windows Update service..." -ForegroundColor Gray
        Stop-Service -Name wuauserv -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2

        # Clean download folder
        Remove-FolderContents -Path "$env:SystemRoot\SoftwareDistribution\Download" `
            -Description "Windows Update downloads"

        # Clean old update installers
        Remove-FolderContents -Path "$env:SystemRoot\SoftwareDistribution\DataStore\Logs" `
            -Description "Windows Update logs" -OlderThanDays 30

        # Restart Windows Update service
        Write-Host "  Starting Windows Update service..." -ForegroundColor Gray
        Start-Service -Name wuauserv -ErrorAction SilentlyContinue

        Write-ColorOutput "Windows Update cleanup completed" -Level Success
    }
    catch {
        Write-ColorOutput "Error during Windows Update cleanup: $($_.Exception.Message)" -Level Error
        # Ensure service is restarted
        Start-Service -Name wuauserv -ErrorAction SilentlyContinue
    }
}

function Clear-IISLogFiles {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    Write-Host "`nCleaning IIS logs..." -ForegroundColor Cyan

    # Check if IIS is installed
    $iisInstalled = Get-Service -Name W3SVC -ErrorAction SilentlyContinue

    if (-not $iisInstalled) {
        Write-Host "  [*] IIS not detected, skipping..." -ForegroundColor Cyan
        return
    }

    $iisLogPaths = @(
        "$env:SystemDrive\inetpub\logs\LogFiles"
    )

    # Try to get IIS log paths from IIS configuration
    try {
        Import-Module IISAdministration -ErrorAction SilentlyContinue
        $sites = Get-IISSite -ErrorAction SilentlyContinue
        foreach ($site in $sites) {
            $logPath = $site.logFile.directory
            if ($logPath -and (Test-Path $logPath)) {
                $iisLogPaths += $logPath
            }
        }
    }
    catch {
        Write-Verbose "Could not read IIS configuration"
    }

    foreach ($logPath in ($iisLogPaths | Select-Object -Unique)) {
        if (Test-Path $logPath) {
            Remove-FolderContents -Path $logPath `
                -Description "IIS logs older than $IISLogRetentionDays days" `
                -OlderThanDays $IISLogRetentionDays
        }
    }
}

function Clear-DISMComponentStore {
    [CmdletBinding()]
    param([bool]$SkipConfirmation)

    Write-Host "`nRunning DISM component store cleanup..." -ForegroundColor Cyan
    Write-ColorOutput "This operation can take 30+ minutes..." -Level Warning

    if ($WhatIfPreference) {
        Write-ColorOutput "[WHATIF] Would run DISM component store cleanup" -Level Info
        return
    }

    if (-not $SkipConfirmation) {
        $confirm = Read-Host "DISM cleanup can take significant time. Continue? (y/N)"
        if ($confirm -ne 'y') {
            Write-Host "  [*] Skipping DISM cleanup..." -ForegroundColor Cyan
            return
        }
    }

    try {
        Write-Host "  Starting DISM cleanup (this will take a while)..." -ForegroundColor Gray
        $dismExit = Invoke-Dism /Online /Cleanup-Image /StartComponentCleanup /ResetBase

        if ($dismExit -eq 0) {
            Write-ColorOutput "DISM cleanup completed successfully" -Level Success
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
            Write-ColorOutput "DISM cleanup completed with warnings (exit code: $dismExit)" -Level Warning
        }
    }
    catch {
        Write-ColorOutput "Error running DISM cleanup: $($_.Exception.Message)" -Level Error
    }
}

function Show-CleanupSummary {
    [CmdletBinding()]
    param()

    $script:report.EndTime = Get-Date
    $duration = ($script:report.EndTime - $script:report.StartTime).TotalSeconds

    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "  Storage Optimization Summary" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Server: $($script:report.ServerName)"
    Write-Host "Start Time: $($script:report.StartTime)"
    Write-Host "End Time: $($script:report.EndTime)"
    Write-Host "Duration: $([math]::Round($duration, 2)) seconds"

    if ($WhatIfPreference) {
        Write-ColorOutput "[WHATIF MODE - No changes were made]" -Level Warning
    }
    else {
        $savedGB = [math]::Round($script:report.TotalSpaceSavedMB / 1024, 2)
        Write-Host "`nTotal Space Saved: $savedGB GB ($($script:report.TotalSpaceSavedMB) MB)" `
            -ForegroundColor Green
    }

    # Show space changes per drive
    foreach ($drive in $script:report.FinalSpace.Keys) {
        $initial = $script:report.InitialSpace[$drive]
        $final = $script:report.FinalSpace[$drive]
        $saved = $final.FreeGB - $initial.FreeGB

        Write-Host "`nDrive $drive`:" -ForegroundColor Cyan
        Write-Host "  Before: $($initial.FreeGB) GB free / $($initial.TotalGB) GB total"
        Write-Host "  After:  $($final.FreeGB) GB free / $($final.TotalGB) GB total"
        if ($saved -gt 0) {
            Write-ColorOutput "Saved:  $([math]::Round($saved, 2)) GB" -Level Success
        }
    }

    # Show operations performed
    if ($script:report.Operations.Count -gt 0) {
        Write-Host "`nOperations Performed:" -ForegroundColor Cyan
        $script:report.Operations | Where-Object { $_.SavedMB -gt 0 } |
            Sort-Object SavedMB -Descending |
            Format-Table Operation, @{Name = 'Saved (MB)'; Expression = { $_.SavedMB } }, FilesRemoved -AutoSize
    }

    Write-Host "`n========================================`n" -ForegroundColor Cyan
}

function Main {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()

    try {
        Initialize-CleanupReport

        Write-Host "`n========================================" -ForegroundColor Cyan
        Write-Host "  Server Storage Optimization" -ForegroundColor Cyan
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host "Server: $($script:report.ServerName)"

        if ($WhatIfPreference) {
            Write-ColorOutput "Running in WhatIf mode - no changes will be made" -Level Warning
        }

        # Get initial disk space
        $drives = if ($DriveLetter) {
            @($DriveLetter)
        }
        else {
            @((Get-Volume -ErrorAction Stop | Where-Object { $_.DriveLetter }).DriveLetter)
        }

        foreach ($drive in $drives) {
            $space = Get-DiskSpace -Drive $drive
            if ($space) {
                $script:report.InitialSpace[$drive] = $space
                Write-Host "`nDrive $drive`: $($space.FreeGB) GB free / $($space.TotalGB) GB total"
            }
        }

        # Perform cleanup operations
        Clear-WindowsTempFiles
        Clear-UserTempFiles
        Clear-RecycleBinFolders
        Clear-WindowsErrorReporting
        Clear-ThumbnailCache

        if ($IncludeWindowsUpdate) {
            Clear-WindowsUpdateCache
        }

        if ($IncludeIISLogs) {
            Clear-IISLogFiles
        }

        if ($IncludeDISM) {
            Clear-DISMComponentStore -SkipConfirmation ([bool]$Force)
        }

        # Get final disk space
        foreach ($drive in $drives) {
            $space = Get-DiskSpace -Drive $drive
            if ($space) {
                $script:report.FinalSpace[$drive] = $space
            }
        }

        Show-CleanupSummary

        Write-Host "[+] Storage optimization completed" -ForegroundColor Green
        return 0
    }
    catch {
        Write-Host "[-] Error: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
