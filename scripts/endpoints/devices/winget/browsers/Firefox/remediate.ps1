<#
.SYNOPSIS
    Standard update script for Mozilla Firefox (V3).
.DESCRIPTION
    Checks if app is running and skips update if so (will retry later).
.NOTES
    Package ID: Mozilla.Firefox
    Process: Firefox
#>

#region Configuration
$ID = 'Mozilla.Firefox'
$AppProcess = 'Firefox'
$MaxRetries = 3
$VerifyWaitSeconds = 5
#endregion

#region Functions
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
        } catch { }
        Start-Sleep -Seconds 2
        $attempt++
    }
    throw "Failed to execute winget after $MaxRetries attempts"
}
#endregion

#region Script
try {
    # Prefer the Microsoft.WinGet.Client PowerShell module - the winget CLI is NOT supported in
    # the SYSTEM context (Intune Proactive Remediations run as SYSTEM). Only fall back to the
    # winget.exe CLI when the module is unavailable.
    # Reference: https://learn.microsoft.com/en-us/windows/package-manager/winget/troubleshooting
    if (Get-Module -ListAvailable -Name Microsoft.WinGet.Client) {
        try { Import-Module Microsoft.WinGet.Client -ErrorAction Stop } catch { }
        if (Get-Command Get-WinGetPackage -ErrorAction SilentlyContinue) {
            $package = Get-WinGetPackage -Id $ID -MatchOption EqualsCaseInsensitive -ErrorAction SilentlyContinue
            if (-not $package) { Write-Host "$ID is not installed on this device."; exit 0 }
            $name = if ($package.Name) { $package.Name } else { $ID }
            if ($package.IsUpdateAvailable) {
                $process = Get-Process -Name "$AppProcess" -ErrorAction SilentlyContinue
                if ($process) {
                    Write-Host "$name is currently running, will try again later."
                    exit 1
                }
                $verInstalled = $package.InstalledVersion
                $verAvailable = $package.AvailableVersions | Select-Object -Last 1
                Write-Host "Installing $name update ($verInstalled -> $verAvailable)..."
                Update-WinGetPackage -Id $ID -MatchOption EqualsCaseInsensitive -Mode Silent -Force -ErrorAction Stop
                Start-Sleep -Seconds $VerifyWaitSeconds
                $verify = Get-WinGetPackage -Id $ID -MatchOption EqualsCaseInsensitive -ErrorAction SilentlyContinue
                if ($verify) {
                    Write-Host "$name updated successfully to version $($verify.InstalledVersion)"
                    [pscustomobject] @{ Name = $name; InstalledVersion = $verify.InstalledVersion; Status = "Updated Successfully" }
                    exit 0
                }
                Write-Error "Failed to verify $name installation after update."
                exit 1
            }
            Write-Host "$name is already up to date."
            exit 0
        }
    }
    $packageInfo = Invoke-WingetWithRetry -Arguments "list --exact --id $ID --accept-source-agreements"
    $name = if ($packageInfo | Select-String -Pattern "^($ID)\s+(.+?)\s+\d") { $Matches[2].Trim() } else { "Mozilla Firefox" }

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

        $verify = Invoke-WingetWithRetry -Arguments "list --exact --id $ID --accept-source-agreements"
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
