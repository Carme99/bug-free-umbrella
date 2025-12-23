<#
.SYNOPSIS
    Force close update for Git (V3).
.DESCRIPTION
    Git can be safely force-closed as it's a background tool.
.NOTES
    Package ID: Git.Git
    Process: git (CLI operations typically short-lived)
#>

#region Configuration
$ID = 'Git.Git'
$AppProcess = 'git'  # Git CLI processes
$MaxRetries = 3
$GracePeriodSeconds = 2
$VerifyWaitSeconds = 5
#endregion

#region Functions
function Invoke-WingetWithRetry { param([string]$Arguments); $a = 1; while ($a -le 3) { try { $r = Invoke-Expression "sysget $Arguments 2>&1"; if ($r) { return $r } } catch { }; Start-Sleep -Seconds 2; $a++ }; throw "Failed" }
#endregion

#region Script
try {
    $wingetexe = Resolve-Path "C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\winget.exe" -ErrorAction Stop
    New-Alias -Name sysget -Value $(if ($wingetexe.Count -gt 1) { $wingetexe[-1].Path } else { $wingetexe.Path }) -Force

    $packageInfo = Invoke-WingetWithRetry -Arguments "list --accept-source-agreements --Id $ID"
    $name = if ($packageInfo | Select-String -Pattern "^($ID)\s+(.+?)\s+\d") { $Matches[2].Trim() } else { "Git" }

    if ($packageInfo -match "No installed package found") { Write-Host "$name not installed."; exit 0 }

    # Close any running git processes (usually safe as operations are quick)
    $process = Get-Process -Name "$AppProcess" -ErrorAction SilentlyContinue
    if ($process) {
        Write-Host "Closing git processes..."
        Stop-Process -Name "$AppProcess" -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds $GracePeriodSeconds
    }

    if ($packageInfo -match '\bVersion\s+Available\b') {
        $v = (-split $packageInfo[-1])[-3,-2]
        Write-Host "Installing Git update ($($v[0]) -> $($v[1]))..."

        Invoke-WingetWithRetry -Arguments "upgrade -e --id $ID --silent --accept-package-agreements --accept-source-agreements" | Out-Null
        Start-Sleep -Seconds $VerifyWaitSeconds

        $verify = Invoke-WingetWithRetry -Arguments "list --accept-source-agreements --Id $ID"
        if ($verify -match '\d+(\.\d+)+') {
            $ver = (-split $verify[-1])[-2]
            Write-Host "Git updated to version $ver"
            exit 0
        }
        Write-Error "Verification failed"; exit 1
    }
    Write-Host "$name is up to date."; exit 0
} catch { Write-Error "Failed: $_"; exit 1 }
#endregion
