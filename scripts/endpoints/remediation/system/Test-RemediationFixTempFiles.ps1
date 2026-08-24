<#
.SYNOPSIS
    Detects excessive temp files across SYSTEM, Windows and per-user temp folders.

.DESCRIPTION
    Measures the total size of temp files older than 7 days across the SYSTEM temp folder, the
    Windows temp folder and every per-user temp folder (enumerated from Win32_UserProfile so users
    who are not currently logged on are also covered). This is a read-only detection script: it
    never deletes or modifies anything, so re-running it on a converged system is safe (idempotent).
    Exit codes:
    - 0: compliant - total stale temp size is at or below 1 GB.
    - 1: non-compliant - stale temp files exceed 1 GB, or the check failed.

.EXAMPLE
    PS C:\> .\Test-RemediationFixTempFiles.ps1
    Measures stale temp files and exits 0 when the total is within threshold, 1 when over 1 GB.

.EXAMPLE
    PS C:\> & 'C:\Program Files\Intune\ProactiveRemediations\Test-RemediationFixTempFiles.ps1'
    Runs the same check from the Intune Management Extension under the SYSTEM context.

.NOTES
    File Name: Test-RemediationFixTempFiles.ps1
    Author: Intune / Proactive Remediations
    Prerequisite: PowerShell 7.0
    Version: 1.0.0
    Date: 2026-08-23
#>

[CmdletBinding()]

$ErrorActionPreference = 'Stop'

function Main {
    try {
        $outputMsg = "[*] Checking for excessive temp files..."
        Write-Host $outputMsg -ForegroundColor Cyan

        # Detect excessive temp files (> 1GB).
        # In SYSTEM context $env:TEMP points at the SYSTEM profile temp folder - real
        # user temp folders must be enumerated explicitly or they are never cleaned.
        $threshold = 1GB
        $cutoff = (Get-Date).AddDays(-7)
        $tempPaths = @("$env:TEMP", "$env:SystemRoot\Temp")

        # Per-user temp folders - every non-special profile is enumerated so temp files
        # of users who are not currently logged on are also covered.
        $userProfiles = Get-CimInstance Win32_UserProfile -ErrorAction Stop | Where-Object {
            $_.Special -eq $false -and $_.LocalPath -notmatch 'systemprofile|defaultuser'
        }

        foreach ($userProfile in $userProfiles) {
            $userTemp = Join-Path $userProfile.LocalPath "AppData\Local\Temp"
            if (Test-Path $userTemp) {
                $tempPaths += $userTemp
            }
        }

        $totalSize = 0

        foreach ($path in $tempPaths) {
            if (Test-Path $path) {
                $size = (Get-ChildItem $path -Recurse -File -ErrorAction SilentlyContinue |
                    Where-Object { $_.LastWriteTime -lt $cutoff } |
                    Measure-Object -Property Length -Sum).Sum
                $totalSize += $size
            }
        }

        $totalGB = [math]::Round($totalSize / 1GB, 2)

        if ($totalSize -gt $threshold) {
            $outputMsg = "[!] Excessive temp files: $totalGB GB"
            Write-Host $outputMsg -ForegroundColor Yellow
            return 1
        }

        $outputMsg = "[+] Temp files normal: $totalGB GB"

        Write-Host $outputMsg -ForegroundColor Green
        return 0
    }
    catch {
        $outputMsg = "[-] Error checking temp files: $($_.Exception.Message)"
        Write-Host $outputMsg -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
