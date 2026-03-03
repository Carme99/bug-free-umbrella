<#
.SYNOPSIS
    Winget update detection script for Mozilla Firefox (V3).
.NOTES
    Package ID: Mozilla.Firefox
#>

#region Configuration
$ID = 'Mozilla.Firefox'
$MaxRetries = 3
$CheckNetworkConnectivity = $true
#endregion

#region Functions
function Test-NetworkConnectivity { try { return (Test-Connection -ComputerName "www.microsoft.com" -Count 1 -Quiet -ErrorAction SilentlyContinue) } catch { return $false } }

function Invoke-WingetWithRetry {
    param([string]$Arguments)
    $wingetexe = Resolve-Path "C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\winget.exe" -ErrorAction Stop
    $wingetPath = if ($wingetexe.Count -gt 1) { $wingetexe[-1].Path } else { $wingetexe.Path }
    $attempt = 1
    while ($attempt -le $MaxRetries) {
        try {
            $processInfo = New-Object System.Diagnostics.ProcessStartInfo
            $processInfo.FileName = $wingetPath
            $processInfo.Arguments = $Arguments
            $processInfo.RedirectStandardOutput = $true
            $processInfo.RedirectStandardError = $true
            $processInfo.UseShellExecute = $false
            $processInfo.CreateNoWindow = $true
            $process = New-Object System.Diagnostics.Process
            $process.StartInfo = $processInfo
            $process.Start() | Out-Null
            $stdout = $process.StandardOutput.ReadToEnd()
            $stderr = $process.StandardError.ReadToEnd()
            $process.WaitForExit()
            if ($stdout) { return $stdout }
        } catch { }
        Start-Sleep -Seconds 2
        $attempt++
    }
    throw "Failed to execute winget after $MaxRetries attempts"
}
#endregion

#region Script
try {
    if (-not (Test-NetworkConnectivity)) { exit 0 }
    $packageInfo = Invoke-WingetWithRetry -Arguments "list --accept-source-agreements --Id $ID"
    $name = if ($packageInfo | Select-String -Pattern "^($ID)\s+(.+?)\s+\d") { $Matches[2].Trim() } else { $ID }
    if ($packageInfo -match "No installed package found") { Write-Host "$name not installed."; exit 0 }
    if ($packageInfo -match '\bVersion\s+Available\b') { $v = (-split $packageInfo[-1])[-3,-2]; Write-Host "Update available: $($v[0]) -> $($v[1])"; exit 1 }
    Write-Host "$name is up to date."; exit 0
} catch { exit 0 }
#endregion
