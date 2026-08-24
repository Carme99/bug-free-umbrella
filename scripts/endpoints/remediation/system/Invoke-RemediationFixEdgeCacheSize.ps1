<#
.SYNOPSIS
    Clears bloated Microsoft Edge browser cache for every user profile.

.DESCRIPTION
    Stops a running Microsoft Edge browser if present, then clears the Cache,
    Code Cache and GPUCache folders under every non-special user profile so disk
    space is freed and browser performance improves. Every mutation (stopping
    Edge, deleting cache content) is gated behind -WhatIf/-Confirm via
    SupportsShouldProcess. Re-running on an already-converged system finds no
    cache to clear, changes nothing and still exits 0 (idempotent).
    Exit codes: 0 = cleanup completed successfully (with or without reclaimed
    space), 1 = an unexpected error occurred.

.EXAMPLE
    PS C:\> .\Invoke-RemediationFixEdgeCacheSize.ps1

    Stops Edge if running and clears the per-user Edge cache folders.

.EXAMPLE
    PS C:\> .\Invoke-RemediationFixEdgeCacheSize.ps1 -WhatIf

    Shows which cache folders would be cleared without deleting anything.

.NOTES
    File Name  : Invoke-RemediationFixEdgeCacheSize.ps1
    Author     : Intune Admin
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
        Write-Host "[*] Clearing Microsoft Edge browser cache..." -ForegroundColor Cyan

        # Close Edge browser processes - files are locked while Edge runs.
        $edgeProcesses = Get-Process -Name "msedge" -ErrorAction SilentlyContinue
        if ($edgeProcesses) {
            if ($PSCmdlet.ShouldProcess('Microsoft Edge', 'Stop running Edge processes')) {
                Stop-Process -Name "msedge" -Force -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 3
                Write-Host "[+] Closed Microsoft Edge browser" -ForegroundColor Green
            }
        }

        # Per-user profiles - every non-special profile is enumerated so the cache of
        # users who are not currently logged on is also covered.
        $userProfiles = Get-CimInstance -ClassName Win32_UserProfile -ErrorAction Stop |
            Where-Object { $_.Special -eq $false -and $_.LocalPath -notmatch 'systemprofile|defaultuser' }

        $totalCleared = 0

        foreach ($userProfile in $userProfiles) {
            # Edge cache locations
            $edgeCachePaths = @(
                "$($userProfile.LocalPath)\AppData\Local\Microsoft\Edge\User Data\Default\Cache",
                "$($userProfile.LocalPath)\AppData\Local\Microsoft\Edge\User Data\Default\Code Cache",
                "$($userProfile.LocalPath)\AppData\Local\Microsoft\Edge\User Data\Default\GPUCache"
            )

            foreach ($cachePath in $edgeCachePaths) {
                if (Test-Path $cachePath) {
                    $cacheSize = (Get-ChildItem -LiteralPath $cachePath -Recurse -File -ErrorAction SilentlyContinue |
                        Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum

                    if ($PSCmdlet.ShouldProcess($cachePath, 'Clear Edge browser cache')) {
                        Remove-Item -Path "$cachePath\*" -Recurse -Force -ErrorAction Stop
                    }

                    if ($cacheSize) {
                        $totalCleared += $cacheSize
                    }
                }
            }
        }

        $totalClearedMB = [math]::Round($totalCleared / 1MB, 2)

        if ($totalClearedMB -gt 0) {
            Write-Host "[+] Cleared $totalClearedMB MB of Edge cache" -ForegroundColor Green
        }
        else {
            Write-Host "[+] Already clean: no Edge cache to clear" -ForegroundColor Green
        }

        return 0
    }
    catch {
        Write-Host "[-] Error during Edge cache remediation: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
