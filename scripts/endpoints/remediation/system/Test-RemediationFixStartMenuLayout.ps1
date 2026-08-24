<#
.SYNOPSIS
    Detects corrupted Start Menu layouts for Intune Proactive Remediations.

.DESCRIPTION
    Checks each user profile for a corrupted or inaccessible Start Menu tile database and
    Start Menu cache, and notes whether the StartMenuExperienceHost process is running as a
    health indicator. This is a read-only detection script; it makes no changes to the system.
    Exit codes:
    - 0: the Start Menu appears healthy (no inaccessible databases or caches).
    - 1: Start Menu issues were detected, or the check itself failed; triggers remediation.
    Re-running against an unchanged system yields the same result (idempotent).

.NOTES
    File Name: Test-RemediationFixStartMenuLayout.ps1
    Author: Intune Admin
    Prerequisite: PowerShell 7.0
    Version: 1.0.0
    Date: 2026-08-23

.EXAMPLE
    PS C:\> .\Test-RemediationFixStartMenuLayout.ps1
    Checks all user profiles; exits 0 when the Start Menu is healthy, 1 on issues.

.EXAMPLE
    PS C:\> .\Test-RemediationFixStartMenuLayout.ps1; $LASTEXITCODE
    Runs the checks and prints the resulting exit code for pipeline consumption.
#>

[CmdletBinding()]

$ErrorActionPreference = 'Stop'

function Main {
    try {
        $outputMsg = "[*] Checking Start Menu health for all user profiles..."
        Write-Host $outputMsg -ForegroundColor Cyan

        $issues = @()

        # Get all user profiles
        $userProfiles = Get-ChildItem -Path 'C:\Users' -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -notmatch 'Public|Default|All Users' }

        foreach ($userProfile in $userProfiles) {
            # Check for Start Menu tile database
            $tileDataPath = "$($userProfile.FullName)\AppData\Local\TileDataLayer\Database"

            if (Test-Path $tileDataPath) {
                # Check if database is accessible
                try {
                    Get-ChildItem -Path $tileDataPath -File -ErrorAction Stop | Out-Null
                }
                catch {
                    $issues += "Start Menu database is corrupted for user: $($userProfile.Name)"
                }
            }

            # Check for Start Menu cache
            $packagesDir = "$($userProfile.FullName)\AppData\Local\Packages"
            $startMenuCache = "$packagesDir\Microsoft.Windows.StartMenuExperienceHost_cw5n1h2txyewy"

            if (Test-Path $startMenuCache) {
                # Check if cache folder has issues
                try {
                    Get-ChildItem -Path $startMenuCache -ErrorAction Stop | Out-Null
                }
                catch {
                    $issues += "Start Menu cache is corrupted for user: $($userProfile.Name)"
                }
            }
        }

        # Check if Start Menu process is running (indicates it may be working)
        $startMenuProcess = Get-Process -Name 'StartMenuExperienceHost' -ErrorAction SilentlyContinue

        if ($issues.Count -gt 0) {
            $outputMsg = "[!] Start Menu issues detected:"
            Write-Host $outputMsg -ForegroundColor Yellow
            foreach ($issue in $issues) {
                $outputMsg = "  - $issue"
                Write-Host $outputMsg -ForegroundColor Yellow
            }
            return 1
        }

        $outputMsg = "[+] Start Menu appears to be healthy"

        Write-Host $outputMsg -ForegroundColor Green
        return 0
    }
    catch {
        $outputMsg = "[-] Error checking Start Menu health: $($_.Exception.Message)"
        Write-Host $outputMsg -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
