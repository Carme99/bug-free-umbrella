<#
.SYNOPSIS
    Detects corrupted Start Menu layout.

.DESCRIPTION
    Checks for corrupted Start Menu or tile database that can cause
    Start Menu to not open or function properly.

.NOTES
    Author: Intune Admin
    Version: 1.0
    Intune Context: SYSTEM
    Exit 0: Start Menu is healthy
    Exit 1: Start Menu issues detected
#>

try {
    $issues = @()

    # Get all user profiles
    $userProfiles = Get-ChildItem -Path "C:\Users" -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notmatch "Public|Default|All Users" }

    foreach ($profile in $userProfiles) {
        # Check for Start Menu tile database
        $tileDataPath = "$($profile.FullName)\AppData\Local\TileDataLayer\Database"

        if (Test-Path $tileDataPath) {
            # Check if database is accessible
            try {
                $dbFiles = Get-ChildItem -Path $tileDataPath -File -ErrorAction Stop
                # Database exists and is accessible
            }
            catch {
                $issues += "Start Menu database is corrupted or inaccessible for user: $($profile.Name)"
            }
        }

        # Check for Start Menu cache
        $startMenuCache = "$($profile.FullName)\AppData\Local\Packages\Microsoft.Windows.StartMenuExperienceHost_cw5n1h2txyewy"

        if (Test-Path $startMenuCache) {
            # Check if cache folder has issues
            try {
                $cacheFiles = Get-ChildItem -Path $startMenuCache -ErrorAction Stop
            }
            catch {
                $issues += "Start Menu cache is corrupted for user: $($profile.Name)"
            }
        }
    }

    # Check if Start Menu process is running (indicates it may be working)
    $startMenuProcess = Get-Process -Name "StartMenuExperienceHost" -ErrorAction SilentlyContinue

    if ($issues.Count -gt 0) {
        Write-Host "Start Menu issues detected:"
        foreach ($issue in $issues) {
            Write-Host "  - $issue"
        }
        exit 1
    }

    Write-Host "Start Menu appears to be healthy"
    exit 0

}
catch {
    Write-Host "Error checking Start Menu health: $_"
    exit 1
}
