<#
.SYNOPSIS
    Winget update detection script for Microsoft.VCRedist.2013.x64 (V3).
.NOTES
    Package ID: Microsoft.VCRedist.2013.x64
#>

#region Configuration
$ID = 'Microsoft.VCRedist.2013.x64'
$MaxRetries = 3
$CheckNetworkConnectivity = $true
#endregion

#region Functions
function Test-NetworkConnectivity { try { return (Test-Connection -ComputerName "www.microsoft.com" -Count 1 -Quiet -ErrorAction SilentlyContinue) } catch { return $false } }
function Invoke-WingetWithRetry { param([string]$Arguments); $attempt = 1; while ($attempt -le 3) { try { $result = Invoke-Expression "sysget $Arguments 2>&1"; if ($result) { return $result } } catch { }; Start-Sleep -Seconds 2; $attempt++ }; throw "Failed" }
#endregion

#region Script
try {
    if (-not (Test-NetworkConnectivity)) { exit 0 }
    $wingetexe = Resolve-Path "C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\winget.exe" -ErrorAction Stop
    
    $packageInfo = Invoke-WingetWithRetry -Arguments "list --accept-source-agreements --Id $ID"
    $name = if ($packageInfo | Select-String -Pattern "^($ID)\s+(.+?)\s+\d") { $Matches[2].Trim() } else { $ID }
    if ($packageInfo -match "No installed package found") { Write-Host "$name not installed."; exit 0 }
    if ($packageInfo -match '\bVersion\s+Available\b') { $v = (-split $packageInfo[-1])[-3,-2]; Write-Host "Update available: $($v[0]) -> $($v[1])"; exit 1 }
    Write-Host "$name is up to date."; exit 0
} catch { exit 0 }
#endregion
