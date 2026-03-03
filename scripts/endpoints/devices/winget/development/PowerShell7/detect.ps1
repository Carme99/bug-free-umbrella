<#
.SYNOPSIS
    Winget update detection for PowerShell 7 (V3).
.NOTES
    Package ID: Microsoft.PowerShell
    Maintenance window recommended for production environments
#>

#region Configuration
$ID = 'Microsoft.PowerShell'
$MaxRetries = 3
$CheckNetworkConnectivity = $true
#endregion

#region Functions
function Test-NetworkConnectivity { try { return (Test-Connection -ComputerName "www.microsoft.com" -Count 1 -Quiet -ErrorAction SilentlyContinue) } catch { return $false } }
function Invoke-WingetWithRetry {
    param([string]$Arguments)
    $wingetexe = Resolve-Path "C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\winget.exe" -ErrorAction Stop
    $wingetPath = if ($wingetexe.Count -gt 1) { $wingetexe[-1].Path } else { $wingetexe.Path }
    $a = 1
    while ($a -le 3) {
        try {
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = $wingetPath
            $psi.Arguments = $Arguments
            $psi.RedirectStandardOutput = $true
            $psi.RedirectStandardError = $true
            $psi.UseShellExecute = $false
            $psi.CreateNoWindow = $true
            $p = New-Object System.Diagnostics.Process
            $p.StartInfo = $psi
            $p.Start() | Out-Null
            $stdout = $p.StandardOutput.ReadToEnd()
            $stderr = $p.StandardError.ReadToEnd()
            $p.WaitForExit()
            if ($stdout) { return $stdout }
        } catch { }
        Start-Sleep -Seconds 2
        $a++
    }
    throw "Failed after 3 attempts"
}
#endregion

#region Script
try {
    if (-not (Test-NetworkConnectivity)) { exit 0 }
    $wingetexe = Resolve-Path "C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\winget.exe" -ErrorAction Stop
    
    $packageInfo = Invoke-WingetWithRetry -Arguments "list --accept-source-agreements --Id $ID"
    $name = "PowerShell 7"
    if ($packageInfo -match "No installed package found") { Write-Host "$name not installed."; exit 0 }
    if ($packageInfo -match '\bVersion\s+Available\b') { $v = (-split $packageInfo[-1])[-3,-2]; Write-Host "Update available: $($v[0]) -> $($v[1])"; exit 1 }
    Write-Host "$name is up to date."; exit 0
} catch { exit 0 }
#endregion
