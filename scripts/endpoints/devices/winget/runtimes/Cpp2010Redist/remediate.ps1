<#
.SYNOPSIS
    Standard update script for Microsoft.VCRedist.2010.x86 (V3).
.DESCRIPTION
    Checks if app is running and skips update if so (will retry later).
.NOTES
    Package ID: Microsoft.VCRedist.2010.x86
    Process: Microsoft.VCRedist.2010.x86
#>

#region Configuration
$ID = 'Microsoft.VCRedist.2010.x86'
$AppProcess = 'Microsoft.VCRedist.2010.x86'
$MaxRetries = 3
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
    $name = if ($packageInfo | Select-String -Pattern "^($ID)\s+(.+?)\s+\d") { $Matches[2].Trim() } else { "Microsoft.VCRedist.2010.x86" }

    if ($packageInfo -match "No installed package found") { Write-Host "$name not installed."; exit 0 }

    if ($packageInfo -match '\bVersion\s+Available\b') {
        $v = (-split $packageInfo[-1])[-3,-2]
        $process = Get-Process -Name "$AppProcess" -ErrorAction SilentlyContinue

        if ($process) {
            Write-Host "$name is running. Will retry later."
            exit 1
        }

        Write-Host "Installing $name update ($($v[0]) -> $($v[1]))..."
        Invoke-WingetWithRetry -Arguments "upgrade -e --id $ID --silent --accept-package-agreements --accept-source-agreements" | Out-Null
        Start-Sleep -Seconds $VerifyWaitSeconds

        $verify = Invoke-WingetWithRetry -Arguments "list --accept-source-agreements --Id $ID"
        if ($verify -match '\d+(\.\d+)+') {
            $ver = (-split $verify[-1])[-2]
            Write-Host "$name updated to version $ver"
            exit 0
        }
        Write-Error "Verification failed"; exit 1
    }
    Write-Host "$name is up to date."; exit 0
} catch { Write-Error "Failed: $_"; exit 1 }
#endregion
