<#
.SYNOPSIS
    Standard update script for VLC Media Player (V3).

.DESCRIPTION
    Uses standard remediation - waits for VLC to close before updating.
    Good for user-facing media player to avoid interrupting playback.

.NOTES
    Package ID: VideoLAN.VLC
    Process: vlc
#>

#region Configuration
$ID = 'VideoLAN.VLC'
$AppProcess = 'vlc'
$MaxRetries = 3
$VerifyWaitSeconds = 5
#endregion

#region Functions
function Invoke-WingetWithRetry { param([string]$Arguments, [int]$MaxAttempts = 3); $attempt = 1; while ($attempt -le $MaxAttempts) { try { $result = Invoke-Expression "sysget $Arguments 2>&1"; if ($result -and -not ($result -match "error|failed")) { return $result } } catch { }; if ($attempt -lt $MaxAttempts) { Start-Sleep -Seconds 2 }; $attempt++ }; throw "Failed" }
#endregion

#region Script
try {
    $wingetexe = Resolve-Path "C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\winget.exe" -ErrorAction Stop
    $SystemContext = if ($wingetexe.Count -gt 1) { $wingetexe[-1].Path } else { $wingetexe.Path }
    

    $packageInfo = Invoke-WingetWithRetry -Arguments "list --accept-source-agreements --Id $ID"
    $nameMatch = $packageInfo | Select-String -Pattern "^($ID)\s+(.+?)\s+\d"
    $name = if ($nameMatch) { $nameMatch.Matches[0].Groups[2].Value.Trim() } else { $ID }

    if ($packageInfo -match "No installed package found") { Write-Host "$name is not installed."; exit 0 }

    if ($packageInfo -match '\bVersion\s+Available\b') {
        $verInstalled, $verAvailable = (-split $packageInfo[-1])[-3,-2]

        # Check if VLC is playing - don't interrupt user
        $process = Get-Process -Name "$AppProcess" -ErrorAction SilentlyContinue
        if ($process) {
            Write-Host "$name is currently running. Will try again later."
            exit 1
        }

        Write-Host "Installing $name update ($verInstalled -> $verAvailable)..."
        $upgradeResult = Invoke-WingetWithRetry -Arguments "upgrade --accept-package-agreements --accept-source-agreements -e --id $ID --silent --accept-package-agreements --accept-source-agreements"
        Start-Sleep -Seconds $VerifyWaitSeconds

        $verifyInfo = Invoke-WingetWithRetry -Arguments "list --accept-source-agreements --Id $ID"
        if ($verifyInfo -match '\d+(\.\d+)+') {
            $versionInstalled = (-split $verifyInfo[-1])[-2]
            Write-Host "$name updated successfully to version $versionInstalled"
            exit 0
        } else {
            Write-Error "Failed to verify installation."; exit 1
        }
    } else {
        if ($packageInfo -match '\d+(\.\d+)+') {
            $versionInstalled = (-split $packageInfo[-1])[-2]
            Write-Host "$name is up to date (version $versionInstalled)"
            exit 0
        }
    }
} catch {
    Write-Error "Update failed: $($_.Exception.Message)"; exit 1
}
#endregion
