<#
.SYNOPSIS
    Standard update script for SQL Server Management Studio (V3).
.DESCRIPTION
    Checks if app is running and skips update if so (will retry later).
.NOTES
    Package ID: Microsoft.SQLServerManagementStudio
    Process: ssms.exe
#>

#region Configuration
$ID = 'Microsoft.SQLServerManagementStudio'
$AppProcess = 'ssms.exe'
$MaxRetries = 3
$VerifyWaitSeconds = 5
#endregion

#region Functions
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
    $wingetexe = Resolve-Path "C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\winget.exe" -ErrorAction Stop
    

    $packageInfo = Invoke-WingetWithRetry -Arguments "list --accept-source-agreements --Id $ID"
    $name = if ($packageInfo | Select-String -Pattern "^($ID)\s+(.+?)\s+\d") { $Matches[2].Trim() } else { "SQL Server Management Studio" }

    if ($packageInfo -match "No installed package found") { Write-Host "$name not installed."; exit 0 }

    if ($packageInfo -match '\bVersion\s+Available\b') {
        $v = (-split $packageInfo[-1])[-3,-2]
        $process = Get-Process -Name "$AppProcess" -ErrorAction SilentlyContinue

        if ($process) {
            Write-Host "$name is running. Will retry later."
            exit 1
        }

        Write-Host "Installing $name update ($($v[0]) -> $($v[1]))..."
        Invoke-WingetWithRetry -Arguments "upgrade --accept-package-agreements --accept-source-agreements -e --id $ID --silent --accept-package-agreements --accept-source-agreements" | Out-Null
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
