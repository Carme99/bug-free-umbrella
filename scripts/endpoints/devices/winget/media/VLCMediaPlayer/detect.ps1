<#
.SYNOPSIS
    Winget update detection script for VLC Media Player (V3).

.NOTES
    Package ID: VideoLAN.VLC
#>

#region Configuration
$ID = 'VideoLAN.VLC'
$MaxRetries = 3
$EnableLogging = $false
$CheckNetworkConnectivity = $true
#endregion

#region Functions
function Write-Log { param([string]$Message, [string]$Level = 'Info'); switch ($Level) { 'Error' { Write-Error $Message } 'Warning' { Write-Warning $Message } 'Info' { Write-Host $Message } } }
function Test-NetworkConnectivity { try { return (Test-Connection -ComputerName "www.microsoft.com" -Count 1 -Quiet -ErrorAction SilentlyContinue) } catch { return $false } }
function Invoke-WingetWithRetry { param([string]$Arguments, [int]$MaxAttempts = 3); $attempt = 1; while ($attempt -le $MaxAttempts) { try { $result = Invoke-Expression "sysget $Arguments 2>&1"; if ($result -and -not ($result -match "error|failed")) { return $result } } catch { }; if ($attempt -lt $MaxAttempts) { Start-Sleep -Seconds 2 }; $attempt++ }; throw "Failed after $MaxAttempts attempts" }
#endregion

#region Script
try {
    if ($CheckNetworkConnectivity -and -not (Test-NetworkConnectivity)) { exit 0 }
    $wingetexe = Resolve-Path "C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\winget.exe" -ErrorAction Stop
    $SystemContext = if ($wingetexe.Count -gt 1) { $wingetexe[-1].Path } else { $wingetexe.Path }
    
    $packageInfo = Invoke-WingetWithRetry -Arguments "list --accept-source-agreements --Id $ID"
    $nameMatch = $packageInfo | Select-String -Pattern "^($ID)\s+(.+?)\s+\d"
    $name = if ($nameMatch) { $nameMatch.Matches[0].Groups[2].Value.Trim() } else { $ID }
    if ($packageInfo -match "No installed package found") { Write-Host "$name is not installed."; exit 0 }
    if ($packageInfo -match '\bVersion\s+Available\b') {
        $verInstalled, $verAvailable = (-split $packageInfo[-1])[-3,-2]
        Write-Host "Update available for $name. Current: $verInstalled, Available: $verAvailable"
        [pscustomobject] @{ Name = $name; InstalledVersion = $verInstalled; AvailableVersion = $verAvailable }
        exit 1
    } else {
        if ($packageInfo -match '\d+(\.\d+)+') {
            $versionInstalled = (-split $packageInfo[-1])[-2]
            Write-Host "$name is up to date (version $versionInstalled)"
            exit 0
        }
    }
} catch { Write-Error "Detection failed: $($_.Exception.Message)"; exit 0 }
#endregion
