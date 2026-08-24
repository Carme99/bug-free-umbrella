<#
.SYNOPSIS
    Remediate low disk space by cleaning temporary files.

.DESCRIPTION
    Frees up disk space by deleting stale temp files from the Windows temp folder,
    emptying the Recycle Bin and clearing the Windows Update download cache.
    Every deletion is gated behind -WhatIf/-Confirm via SupportsShouldProcess.
    Re-running on an already-converged system finds nothing to clean, changes
    nothing and still exits 0 (idempotent).
    Exit codes: 0 = cleanup completed successfully (with or without reclaimed
    space), 1 = an unexpected error occurred.
    Cleanup targets: %SystemRoot%\Temp (files older than 7 days), the Recycle Bin
    (all items) and %SystemRoot%\SoftwareDistribution\Download (Windows Update
    cache). For Intune Proactive Remediations.

.EXAMPLE
    PS C:\> .\Invoke-RemediationFixDiskSpace.ps1

    Deletes stale temp files, empties the Recycle Bin and clears the Windows
    Update download cache, reporting how much space was reclaimed.

.EXAMPLE
    PS C:\> .\Invoke-RemediationFixDiskSpace.ps1 -WhatIf

    Shows which cleanup operations would run without changing anything.

.NOTES
    File Name  : Invoke-RemediationFixDiskSpace.ps1
    Author     : Intune / Proactive Remediations
    Prerequisite: PowerShell 7.0
    Version    : 1.0.0
    Date       : 2026-08-23
#>

[CmdletBinding(SupportsShouldProcess)]
param()

$ErrorActionPreference = 'Stop'

function Get-FolderSizeBytes {
    # Sums file sizes below a folder; missing/empty folders count as zero bytes.
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $sum = (Get-ChildItem -LiteralPath $Path -Recurse -File -ErrorAction SilentlyContinue |
        Measure-Object -Property Length -Sum).Sum
    if ($null -eq $sum) {
        return 0
    }
    return $sum
}

function Main {
    # Advanced function so $PSCmdlet (and thus ShouldProcess) resolves inside Main.
    [CmdletBinding(SupportsShouldProcess)]
    param()

    try {
        Write-Host "[*] Freeing disk space..." -ForegroundColor Cyan

        # Configuration
        $tempFileAgeDays = 7  # Only remove temp files older than this

        $cleanedGb = 0

        # Clean Windows temp files
        $winTemp = "$env:SystemRoot\Temp"
        if (Test-Path $winTemp) {
            $beforeSize = Get-FolderSizeBytes -Path $winTemp
            $staleFiles = Get-ChildItem -LiteralPath $winTemp -Recurse -File -ErrorAction SilentlyContinue |
                Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-$tempFileAgeDays) }

            foreach ($file in $staleFiles) {
                if ($PSCmdlet.ShouldProcess($file.FullName, "Delete stale temp file")) {
                    Remove-Item -LiteralPath $file.FullName -Force -ErrorAction Stop
                }
            }

            $afterSize = Get-FolderSizeBytes -Path $winTemp
            $cleanedGb += [math]::Round(($beforeSize - $afterSize) / 1GB, 2)
        }

        # Empty recycle bin
        if ($PSCmdlet.ShouldProcess('Recycle Bin', 'Empty Recycle Bin')) {
            Clear-RecycleBin -Force -ErrorAction Stop
        }

        # Clean Windows Update cache
        $wuCache = "$env:SystemRoot\SoftwareDistribution\Download"
        if (Test-Path $wuCache) {
            if ($PSCmdlet.ShouldProcess($wuCache, 'Clear Windows Update download cache')) {
                Stop-Service wuauserv -Force -ErrorAction SilentlyContinue
                $beforeSize = Get-FolderSizeBytes -Path $wuCache
                Get-ChildItem -LiteralPath $wuCache -Recurse -ErrorAction SilentlyContinue |
                    Remove-Item -Force -Recurse -ErrorAction Stop
                $afterSize = Get-FolderSizeBytes -Path $wuCache
                $cleanedGb += [math]::Round(($beforeSize - $afterSize) / 1GB, 2)
                Start-Service wuauserv -ErrorAction SilentlyContinue
            }
        }

        if ($cleanedGb -gt 0) {
            Write-Host "[+] Cleaned $cleanedGb GB of disk space" -ForegroundColor Green
        }
        else {
            Write-Host "[+] Already clean: no reclaimable disk space found" -ForegroundColor Green
        }
        return 0
    }
    catch {
        Write-Host "[-] Error cleaning disk space: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
