<#
.SYNOPSIS
    Force close winget update script for 7-Zip (V3).

.DESCRIPTION
    7-Zip can be safely force-closed during updates as it's a utility tool.
    This script uses the V3 enhanced force close template.

.NOTES
    Package ID: 7zip.7zip
    Application: 7-Zip
    Process: 7zFM (File Manager), 7zG (GUI)
#>

#region Configuration
$ID = '7zip.7zip'
$AppProcess = '7zFM'  # 7-Zip File Manager process

# Force Close Settings
$NotifyUserBeforeClose = $false
$GracePeriodSeconds = 2
$VerifyWaitSeconds = 5
$MaxProcessCloseAttempts = 3

# Advanced Settings
$MaxRetries = 3
$RetryDelaySeconds = 2
$EnableLogging = $false
$LogPath = "C:\ProgramData\IntuneScripts\Logs\WingetRemediation_$ID.log"
#endregion

#region Functions
function Write-Log {
    param([string]$Message, [ValidateSet('Info', 'Warning', 'Error')][string]$Level = 'Info')
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    switch ($Level) {
        'Error'   { Write-Error $Message }
        'Warning' { Write-Warning $Message }
        'Info'    { Write-Host $Message }
    }
    if ($EnableLogging) {
        try {
            $logDir = Split-Path -Path $LogPath -Parent
            if (-not (Test-Path $logDir)) { New-Item -Path $logDir -ItemType Directory -Force | Out-Null }
            Add-Content -Path $LogPath -Value $logMessage -ErrorAction SilentlyContinue
        } catch { }
    }
}

function Stop-ApplicationProcess {
    param([string]$ProcessName, [int]$MaxAttempts = $MaxProcessCloseAttempts)
    $attempt = 1
    while ($attempt -le $MaxAttempts) {
        $process = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue
        if (-not $process) {
            Write-Log "$ProcessName is not running" -Level Info
            return $true
        }
        Write-Log "Stopping $ProcessName (attempt $attempt/$MaxAttempts)..." -Level Info
        Stop-Process -Name $ProcessName -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        $attempt++
    }
    $process = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue
    if ($process) {
        Write-Log "Failed to stop $ProcessName after $MaxAttempts attempts" -Level Error
        return $false
    }
    return $true
}

function Invoke-WingetWithRetry {
    param([string]$Arguments, [int]$MaxAttempts = $MaxRetries)
    $attempt = 1
    $delay = $RetryDelaySeconds
    while ($attempt -le $MaxAttempts) {
        try {
            Write-Log "Executing: sysget $Arguments (Attempt $attempt/$MaxAttempts)" -Level Info
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
            $p.WaitForExit()
            if ($stdout) { return $stdout }
        } catch {
            Write-Verbose "Winget command failed on attempt $a: $($_.Exception.Message)" -Verbose:$false
        }
        Start-Sleep -Seconds 2
        $a++
    }
    throw "Failed after 3 attempts"
}
            if ($result -and -not ($result -match "error|failed|exception")) { return $result }
            Write-Log "Invalid result on attempt $attempt" -Level Warning
        } catch {
            Write-Log "Failed on attempt $attempt : $($_.Exception.Message)" -Level Warning
        }
        if ($attempt -lt $MaxAttempts) { Start-Sleep -Seconds $delay; $delay = $delay * 2 }
        $attempt++
    }
    throw "Winget command failed after $MaxAttempts attempts"
}
#endregion

#region Script
try {
    Write-Log "=== Starting 7-Zip update ===" -Level Info

    $wingetexe = Resolve-Path "C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\winget.exe" -ErrorAction Stop
    if ($wingetexe.Count -gt 1) { $SystemContext = $wingetexe[-1].Path } else { $SystemContext = $wingetexe.Path }
    
    Write-Log "Found winget: $SystemContext" -Level Info

    $packageInfo = Invoke-WingetWithRetry -Arguments "list --accept-source-agreements --Id $ID"

    $nameMatch = $packageInfo | Select-String -Pattern "^($ID)\s+(.+?)\s+\d"
    if ($nameMatch) { $name = $nameMatch.Matches[0].Groups[2].Value.Trim() } else { $name = $ID }

    if ($packageInfo -match "No installed package found matching input criteria") {
        Write-Log "$name is not installed." -Level Info
        Write-Host "$name is not installed on this device."
        exit 0
    }

    # Close 7-Zip if running
    $process = Get-Process -Name "$AppProcess" -ErrorAction SilentlyContinue
    if ($process) {
        Write-Host "$name is running. Force closing application..."
        $closedSuccessfully = Stop-ApplicationProcess -ProcessName $AppProcess
        if (-not $closedSuccessfully) {
            Write-Error "Failed to close $name. Cannot proceed with update."
            exit 1
        }
        Start-Sleep -Seconds $GracePeriodSeconds
    }

    if ($packageInfo -match '\bVersion\s+Available\b') {
        $verInstalled, $verAvailable = (-split $packageInfo[-1])[-3,-2]
        Write-Log "Update available: $verInstalled -> $verAvailable" -Level Info
        Write-Host "Installing $name update..."

        $upgradeResult = Invoke-WingetWithRetry -Arguments "upgrade -e --id $ID --silent --accept-package-agreements --accept-source-agreements"
        Start-Sleep -Seconds $VerifyWaitSeconds

        $verifyInfo = Invoke-WingetWithRetry -Arguments "list --accept-source-agreements --Id $ID"
        if ($verifyInfo -match '\d+(\.\d+)+') {
            $versionInstalled = (-split $verifyInfo[-1])[-2]
            Write-Log "$name updated successfully to $versionInstalled" -Level Info
            Write-Host "$name updated successfully to version $versionInstalled"
            [pscustomobject] @{ Name = $name; PreviousVersion = $verInstalled; InstalledVersion = $versionInstalled; Status = "Updated Successfully" }
            exit 0
        } else {
            Write-Error "Failed to verify installation."
            exit 1
        }
    } else {
        if ($packageInfo -match '\d+(\.\d+)+') {
            $versionInstalled = (-split $packageInfo[-1])[-2]
            Write-Host "$name is already up to date (version $versionInstalled)"
            [pscustomobject] @{ Name = $name; InstalledVersion = $versionInstalled; Status = "Up to Date" }
            exit 0
        }
    }
} catch {
    Write-Log "ERROR: $($_.Exception.Message)" -Level Error
    Write-Error "Failed to update $name : $($_.Exception.Message)"
    exit 1
} finally {
    Write-Log "=== Remediation completed ===" -Level Info
}
#endregion
