<#
.SYNOPSIS
    Remediate low disk space by cleaning temporary files

.DESCRIPTION
    Frees up disk space by performing the following cleanup operations:
    - Removes Windows temp files older than 7 days
    - Empties the Recycle Bin
    - Clears Windows Update download cache

.NOTES
    For Intune Proactive Remediations
    Exit 0 = Remediation completed successfully

    Cleanup Targets:
    - %SystemRoot%\Temp (files older than 7 days)
    - Recycle Bin (all items)
    - %SystemRoot%\SoftwareDistribution\Download (Windows Update cache)
#>

[CmdletBinding()]
param()

# Configuration
$TEMP_FILE_AGE_DAYS = 7  # Only remove temp files older than this

$cleaned = 0

# Clean Windows temp files
$winTemp = "$env:SystemRoot\Temp"
$beforeSize = (Get-ChildItem $winTemp -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
Get-ChildItem $winTemp -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-$TEMP_FILE_AGE_DAYS) } | Remove-Item -Force -ErrorAction SilentlyContinue
$afterSize = (Get-ChildItem $winTemp -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
$cleaned += [math]::Round(($beforeSize - $afterSize) / 1GB, 2)

# Empty recycle bin
Clear-RecycleBin -Force -ErrorAction SilentlyContinue

# Clean Windows Update cache
$wuCache = "$env:SystemRoot\SoftwareDistribution\Download"
if (Test-Path $wuCache) {
    Stop-Service wuauserv -Force -ErrorAction SilentlyContinue
    $beforeSize = (Get-ChildItem $wuCache -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
    Get-ChildItem $wuCache -Recurse -ErrorAction SilentlyContinue | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
    $afterSize = (Get-ChildItem $wuCache -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
    $cleaned += [math]::Round(($beforeSize - $afterSize) / 1GB, 2)
    Start-Service wuauserv -ErrorAction SilentlyContinue
}

Write-Host "Cleaned $cleaned GB of disk space"
exit 0
