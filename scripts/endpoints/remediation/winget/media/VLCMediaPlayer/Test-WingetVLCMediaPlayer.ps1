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

            # Drain BOTH output streams before waiting so a full stderr pipe cannot deadlock the child.
            $stdout = $process.StandardOutput.ReadToEnd()
            $stderr = $process.StandardError.ReadToEnd()
            $process.WaitForExit()

            # Base success on the process exit code, not on stdout content.
            # Success: 0 (S_OK), 0x8A150014 (no packages found - "not installed" for list),
            # 0x8A150109 (install succeeded, reboot required).
            # Reference: https://github.com/microsoft/winget-cli/blob/master/doc/windows/package-manager/winget/returnCodes.md
            if ($process.ExitCode -eq 0 -or $process.ExitCode -eq 0x8A150014 -or $process.ExitCode -eq 0x8A150109) {
                if ($stderr) { Write-Verbose "Winget stderr: $stderr" -Verbose:$false }
                return $stdout
            }

            Write-Verbose "Winget exited with code 0x$($process.ExitCode.ToString('X8')) on attempt $attempt" -Verbose:$false
            if ($stderr) { Write-Verbose "Winget stderr: $stderr" -Verbose:$false }
        }
        catch {
            Write-Verbose "Handled exception: $($_.Exception.Message)" -Verbose:$false
        }
        Start-Sleep -Seconds 2
        $attempt++
    }
    throw "Failed to execute winget after $MaxRetries attempts"
}
#endregion

#region Script
try {
    if ($CheckNetworkConnectivity -and -not (Test-NetworkConnectivity)) { exit 0 }
    # Prefer the Microsoft.WinGet.Client PowerShell module - the winget CLI is NOT supported in
    # the SYSTEM context (Intune Proactive Remediations run as SYSTEM). Only fall back to the
    # winget.exe CLI when the module is unavailable.
    # Reference: https://learn.microsoft.com/en-us/windows/package-manager/winget/troubleshooting
    if (Get-Module -ListAvailable -Name Microsoft.WinGet.Client) {
        try { Import-Module Microsoft.WinGet.Client -ErrorAction Stop } catch { Write-Verbose "Handled exception: $($_.Exception.Message)" -Verbose:$false }
        if (Get-Command Get-WinGetPackage -ErrorAction SilentlyContinue) {
            $package = Get-WinGetPackage -Id $ID -MatchOption EqualsCaseInsensitive -ErrorAction SilentlyContinue
            if (-not $package) { Write-Host "$ID is not installed on this device."; exit 0 }
            if ($package.IsUpdateAvailable) {
                $verInstalled = $package.InstalledVersion
                $verAvailable = $package.AvailableVersions | Select-Object -Last 1
                Write-Host "Application update available for $($package.Name). Current: $verInstalled, Available: $verAvailable"
                [pscustomobject] @{ Name = $package.Name; InstalledVersion = $verInstalled; AvailableVersion = $verAvailable }
                exit 1
            }
            Write-Host "$($package.Name) is already up to date (version $($package.InstalledVersion))."
            exit 0
        }
    }
    $wingetexe = Resolve-Path "C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\winget.exe" -ErrorAction Stop
    $SystemContext = if ($wingetexe.Count -gt 1) { $wingetexe[-1].Path } else { $wingetexe.Path }
    
    $packageInfo = Invoke-WingetWithRetry -Arguments "list --exact --id $ID --accept-source-agreements"
    $nameMatch = $packageInfo | Select-String -Pattern "^($ID)\s+(.+?)\s+\d"
    $name = if ($nameMatch) { $nameMatch.Matches[0].Groups[2].Value.Trim() } else { $ID }
    if ($packageInfo -match "No installed package found") { Write-Host "$name is not installed."; exit 0 }
    if ($packageInfo -match '\bVersion\s+Available\b') {
        $verInstalled, $verAvailable = (-split $packageInfo[-1])[-3, -2]
        Write-Host "Update available for $name. Current: $verInstalled, Available: $verAvailable"
        [pscustomobject] @{ Name = $name; InstalledVersion = $verInstalled; AvailableVersion = $verAvailable }
        exit 1
    }
    else {
        if ($packageInfo -match '\d+(\.\d+)+') {
            $versionInstalled = (-split $packageInfo[-1])[-2]
            Write-Host "$name is up to date (version $versionInstalled)"
            exit 0
        }
    }
}
catch { Write-Error "Detection failed: $($_.Exception.Message)"; exit 0 }
#endregion
