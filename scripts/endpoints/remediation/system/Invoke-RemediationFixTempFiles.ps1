<#
.SYNOPSIS
    Clean temp files older than 7 days.

.DESCRIPTION
    Deletes temp files older than 7 days from the SYSTEM temp folder, the Windows
    temp folder and every per-user temp folder (enumerated from Win32_UserProfile).
    The deletion of each file is gated behind -WhatIf/-Confirm via SupportsShouldProcess.
    Re-running on an already-converged system finds no stale files, makes no changes
    and still exits 0 (idempotent).

.EXAMPLE
    PS C:\> .\Invoke-RemediationFixTempFiles.ps1

    Deletes every temp file older than 7 days across SYSTEM and per-user temp folders.

.EXAMPLE
    PS C:\> .\Invoke-RemediationFixTempFiles.ps1 -WhatIf

    Shows which temp files would be deleted without deleting anything.

.NOTES
    File Name  : Invoke-RemediationFixTempFiles.ps1
    Author     : Intune / Proactive Remediations
    Prerequisite: PowerShell 7.0
    Version    : 1.0.0
    Date       : 2026-08-23
#>

[CmdletBinding(SupportsShouldProcess)]
param()

$ErrorActionPreference = 'Stop'

function Main {
    # Advanced function so $PSCmdlet (and thus ShouldProcess) resolves inside Main.
    [CmdletBinding(SupportsShouldProcess)]
    param()

    try {
        Write-Host "[*] Cleaning temp files older than 7 days..." -ForegroundColor Cyan

        # In SYSTEM context $env:TEMP points at the SYSTEM profile temp folder - real
        # user temp folders must be enumerated explicitly or they are never cleaned.
        $cutoff = (Get-Date).AddDays(-7)
        $tempPaths = @("$env:TEMP", "$env:SystemRoot\Temp")

        # Per-user temp folders - every non-special profile is enumerated so temp files
        # of users who are not currently logged on are also covered.
        $userProfiles = Get-CimInstance -ClassName Win32_UserProfile -ErrorAction Stop |
            Where-Object { $_.Special -eq $false -and $_.LocalPath -notmatch 'systemprofile|defaultuser' }

        foreach ($userProfile in $userProfiles) {
            $userTemp = Join-Path $userProfile.LocalPath "AppData\Local\Temp"
            if (Test-Path $userTemp) {
                $tempPaths += $userTemp
            }
        }

        $cleanedCount = 0

        foreach ($path in $tempPaths) {
            if (-not (Test-Path $path)) {
                continue
            }

            $staleFiles = Get-ChildItem $path -Recurse -File -ErrorAction SilentlyContinue |
                Where-Object { $_.LastWriteTime -lt $cutoff }

            foreach ($file in $staleFiles) {
                if ($PSCmdlet.ShouldProcess($file.FullName, "Delete stale temp file")) {
                    Remove-Item -LiteralPath $file.FullName -Force -ErrorAction Stop
                    $cleanedCount++
                }
            }
        }

        if ($cleanedCount -eq 0) {
            Write-Host "[+] Already clean: no temp files older than 7 days found" -ForegroundColor Green
        }
        else {
            Write-Host "[+] Cleaned $cleanedCount stale temp file(s)" -ForegroundColor Green
        }
        return 0
    }
    catch {
        Write-Host "[-] Error cleaning temp files: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
