<#
.SYNOPSIS
    Repairs corrupted Start Menu layout.

.DESCRIPTION
    Rebuilds the Start Menu tile database and cache by removing corrupted files
    and allowing Windows to recreate them.

.NOTES
    Author: Intune Admin
    Version: 1.0
    Intune Context: SYSTEM
    Exit 0: Remediation successful
#>

try {
    $remediationActions = @()

    # Stop Start Menu related processes
    $processesToStop = @("StartMenuExperienceHost", "ShellExperienceHost")

    foreach ($processName in $processesToStop) {
        $process = Get-Process -Name $processName -ErrorAction SilentlyContinue
        if ($process) {
            Stop-Process -Name $processName -Force -ErrorAction SilentlyContinue
            $remediationActions += "Stopped $processName process"
        }
    }

    Start-Sleep -Seconds 2

    # Get all user profiles
    $userProfiles = Get-ChildItem -Path "C:\Users" -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notmatch "Public|Default|All Users" }

    foreach ($profile in $userProfiles) {
        # Remove Start Menu tile database
        $tileDataPath = "$($profile.FullName)\AppData\Local\TileDataLayer"

        if (Test-Path $tileDataPath) {
            try {
                Remove-Item -Path $tileDataPath -Recurse -Force -ErrorAction Stop
                $remediationActions += "Removed corrupted tile database for user: $($profile.Name)"
            }
            catch {
                Write-Host "Warning: Could not remove tile database for $($profile.Name): $_"
            }
        }

        # Clear Start Menu cache
        $startMenuCache = "$($profile.FullName)\AppData\Local\Packages\Microsoft.Windows.StartMenuExperienceHost_cw5n1h2txyewy\LocalState"

        if (Test-Path $startMenuCache) {
            try {
                Remove-Item -Path "$startMenuCache\*" -Recurse -Force -ErrorAction Stop
                $remediationActions += "Cleared Start Menu cache for user: $($profile.Name)"
            }
            catch {
                Write-Host "Warning: Could not clear Start Menu cache for $($profile.Name): $_"
            }
        }
    }

    # Restart Explorer to rebuild Start Menu
    Stop-Process -Name "explorer" -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    Start-Process "explorer.exe" -ErrorAction SilentlyContinue
    $remediationActions += "Restarted Windows Explorer"

    if ($remediationActions.Count -gt 0) {
        Write-Host "Start Menu remediation completed:"
        foreach ($action in $remediationActions) {
            Write-Host "  - $action"
        }
        Write-Host ""
        Write-Host "Note: Users may need to sign out and sign back in for changes to take full effect"
    }
    else {
        Write-Host "No Start Menu remediation was necessary"
    }

    exit 0

}
catch {
    Write-Host "Error during Start Menu remediation: $_"
    exit 1
}
