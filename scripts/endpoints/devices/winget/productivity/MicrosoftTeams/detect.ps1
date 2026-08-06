<#
.SYNOPSIS
    Winget update detection script for Microsoft Teams (V3).

.DESCRIPTION
    Enhanced detection script with retry logic and better error handling.

.NOTES
    Package ID: Microsoft.Teams
    Application: Microsoft Teams
#>

#region Configuration
$ID = 'Microsoft.Teams'
$MaxRetries = 3
$RetryDelaySeconds = 2
$EnableLogging = $false
$LogPath = "C:\ProgramData\IntuneScripts\Logs\WingetDetection_$ID.log"
$CheckNetworkConnectivity = $true
#endregion

#region Functions
function Write-Log {
    param([string]$Message, [ValidateSet('Info', 'Warning', 'Error')][string]$Level = 'Info')
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"; $logMessage = "[$timestamp] [$Level] $Message"
    switch ($Level) { 'Error' { Write-Error $Message } 'Warning' { Write-Warning $Message } 'Info' { Write-Host $Message } }
    if ($EnableLogging) { try { $logDir = Split-Path -Path $LogPath -Parent; if (-not (Test-Path $logDir)) { New-Item -Path $logDir -ItemType Directory -Force | Out-Null }; Add-Content -Path $LogPath -Value $logMessage -ErrorAction SilentlyContinue } catch { } }
}

function Test-NetworkConnectivity { try { return (Test-Connection -ComputerName "www.microsoft.com" -Count 1 -Quiet -ErrorAction SilentlyContinue) } catch { return $false } }

function Invoke-WingetWithRetry {
    param([string]$Arguments, [int]$MaxAttempts = $MaxRetries)
    $attempt = 1; $delay = $RetryDelaySeconds
    $wingetexe = Resolve-Path "C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\winget.exe" -ErrorAction Stop
    $wingetPath = if ($wingetexe.Count -gt 1) { $wingetexe[-1].Path } else { $wingetexe.Path }
    while ($attempt -le $MaxAttempts) {
        try {
            Write-Log "Executing: sysget $Arguments (Attempt $attempt/$MaxAttempts)" -Level Info
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
            $p.WaitForExit()
            $result = $stdout

            if ($result -and -not ($result -match "error|failed|exception")) { Write-Log "Command succeeded" -Level Info; return $result }
            Write-Log "Invalid result on attempt $attempt" -Level Warning
        } catch { Write-Log "Failed: $($_.Exception.Message)" -Level Warning }
        if ($attempt -lt $MaxAttempts) { Start-Sleep -Seconds $delay; $delay = $delay * 2 }
        $attempt++
    }
    throw "Winget command failed after $MaxAttempts attempts"
}
#endregion

#region Script
try {
    Write-Log "=== Starting detection for $ID ===" -Level Info
    if ($CheckNetworkConnectivity -and -not (Test-NetworkConnectivity)) { Write-Log "No network connectivity" -Level Warning; exit 0 }

    $wingetexe = Resolve-Path "C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\winget.exe" -ErrorAction Stop
    $SystemContext = if ($wingetexe.Count -gt 1) { $wingetexe[-1].Path } else { $wingetexe.Path }
    

    $packageInfo = Invoke-WingetWithRetry -Arguments "list --accept-source-agreements --Id $ID"
    $nameMatch = $packageInfo | Select-String -Pattern "^($ID)\s+(.+?)\s+\d"
    $name = if ($nameMatch) { $nameMatch.Matches[0].Groups[2].Value.Trim() } else { $ID }

    if ($packageInfo -match "No installed package found matching input criteria") {
        Write-Host "$name is not installed on this device."; exit 0
    }

    if ($packageInfo -match '\bVersion\s+Available\b') {
        $verInstalled, $verAvailable = (-split $packageInfo[-1])[-3,-2]
        Write-Host "Application update available for $name. Current: $verInstalled, Available: $verAvailable"
        [pscustomobject] @{ Name = $name; InstalledVersion = $verInstalled; AvailableVersion = $verAvailable; Status = "UpdateAvailable" }
        exit 1
    } else {
        if ($packageInfo -match '\d+(\.\d+)+') {
            $versionInstalled = (-split $packageInfo[-1])[-2]
            Write-Host "$name is already up to date (version $versionInstalled)"
            [pscustomobject] @{ Name = $name; InstalledVersion = $versionInstalled; Status = "UpToDate" }
            exit 0
        }
    }
} catch {
    Write-Log "ERROR: $($_.Exception.Message)" -Level Error; exit 0
} finally {
    Write-Log "=== Detection completed ===" -Level Info
}
#endregion
