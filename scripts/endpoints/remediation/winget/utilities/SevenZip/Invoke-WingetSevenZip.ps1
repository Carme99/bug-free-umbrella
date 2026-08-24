<#
.SYNOPSIS
    Force-closes 7-Zip (7zFM) and updates it silently (winget id 7zip.7zip) for Intune Proactive Remediations.

.DESCRIPTION
    Remediation half of the 7-Zip update pair. Checks whether an update is available and, when the
    application is running, optionally notifies the logged-on user before force closing the process so the
    silent install can proceed (WARNING: force closing may cause data loss). Prefers the Microsoft.WinGet.Client
    PowerShell module because the winget CLI is not supported in the SYSTEM context that Intune Proactive
    Remediations use; when the module is unavailable it falls back to the winget.exe CLI through the
    Invoke-WingetWithRetry wrapper. Optional pre/post update hook script blocks can run custom actions around
    the update. Honors -WhatIf; the close and update mutations only run behind ShouldProcess gates.
    Exit codes:
    - 0: success - updated, already up to date, or package not installed.
    - 1: failure - the process could not be closed, verification failed after update, or an error occurred.
    Re-running on a converged system exits 0 without changes (idempotent).

.NOTES
    File Name: Invoke-WingetSevenZip.ps1
    Author: Bug-Free Umbrella
    Prerequisite: PowerShell 7.0
    Version: 1.0.0
    Date: 2026-08-23

.EXAMPLE
    PS C:\> .\Invoke-WingetSevenZip.ps1
    Force closes 7-Zip if running, then updates it silently; exits 0 on success or when already up to date.

.EXAMPLE
    PS C:\> .\Invoke-WingetSevenZip.ps1 -WhatIf
    Shows which close/update actions would run without performing them.
#>


[CmdletBinding(SupportsShouldProcess)]

# PSAvoidUsingWriteHost is intentionally accepted: prefixed, colored console output is the mandated
# output convention of docs/RELAUNCH-SPEC.md section 3.
$ErrorActionPreference = 'Stop'

#region Configuration
$ID = '7zip.7zip'

# Basic settings
$name = $null                   # Leave as $null to auto-detect from winget
$AppProcess = '7zFM'          # 7-Zip process

# Force close settings
$NotifyUserBeforeClose = $false     # Show notification to user before closing app
$UserNotificationSeconds = 60       # How long to show notification before closing (if enabled)
$GracePeriodSeconds = 2             # Time to wait after closing app before updating
$VerifyWaitSeconds = 5              # Time to wait after update to verify installation
$MaxProcessCloseAttempts = 3        # Number of attempts to close the process

# Advanced settings
$MaxRetries = 3                     # Number of retry attempts for winget operations
$RetryDelaySeconds = 2              # Initial delay between retries
$EnableLogging = $false             # Set to $true to enable file logging
$LogPath = "C:\ProgramData\IntuneScripts\Logs\WingetRemediation_$ID.log"

# Hooks for custom actions
$PreUpdateScriptBlock = $null       # Script block to run before update
$PostUpdateScriptBlock = $null      # Script block to run after update
#endregion

#region Functions

function Write-Log {
    <#
    .SYNOPSIS
        Writes a timestamped message to the console and, optionally, to a log file.
    #>
    param(
        [string]$Message,
        [ValidateSet('Info', 'Warning', 'Error')]
        [string]$Level = 'Info'
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"

    switch ($Level) {
        'Error' { Write-Host "[-] $Message" -ForegroundColor Red }
        'Warning' { Write-Host "[!] $Message" -ForegroundColor Yellow }
        'Info' { Write-Host $Message }
    }

    if ($EnableLogging) {
        try {
            $logDir = Split-Path -Path $LogPath -Parent
            if (-not (Test-Path $logDir)) {
                New-Item -Path $logDir -ItemType Directory -Force | Out-Null
            }
            Add-Content -Path $LogPath -Value $logMessage -ErrorAction SilentlyContinue
        }
        catch {
            Write-Verbose "Handled exception: $($_.Exception.Message)"
        }
    }
}


function Get-LoggedOnUserSession {
    <#
    .SYNOPSIS
        Thin wrapper around the native query.exe user command; returns raw session lines.
    #>
    try {
        return @(query user 2>$null | Select-Object -Skip 1)
    }
    catch {
        return @()
    }
}

function Send-UserMessage {
    <#
    .SYNOPSIS
        Thin wrapper around the native msg.exe command used to notify a logged-on user.
    #>
    param(
        [string]$UserName,
        [int]$Seconds,
        [string]$Title,
        [string]$Body
    )

    msg.exe $UserName /TIME:$Seconds "$Title`n`n$Body" 2>$null
}

function Show-UserNotification {
    <#
    .SYNOPSIS
        Notifies every logged-on user that the application will close for an update.
    #>
    param(
        [string]$AppName,
        [int]$Seconds
    )

    try {
        $notificationTitle = "Application Update Required"
        $notificationMessage = "$AppName will be closed in $Seconds seconds for an important update. " +
            "Please save your work."

        # Use msg.exe via its wrapper to show notification (works in SYSTEM context)
        $users = Get-LoggedOnUserSession
        foreach ($user in $users) {
            if ($user -match '^\s*(\S+)') {
                Send-UserMessage -UserName $Matches[1] -Seconds $Seconds -Title $notificationTitle `
                    -Body $notificationMessage
            }
        }

        $outputMsg = "User notification sent: $AppName will close in $Seconds seconds"
        Write-Log $outputMsg -Level Info
    }
    catch {
        $outputMsg = "Failed to send user notification: $($_.Exception.Message)"
        Write-Log $outputMsg -Level Warning
    }
}


function Stop-ApplicationProcess {
    <#
    .SYNOPSIS
        Stops the application process within a bounded number of attempts; honors -WhatIf.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$ProcessName,
        [int]$MaxAttempts = $MaxProcessCloseAttempts
    )

    $attempt = 1
    while ($attempt -le $MaxAttempts) {
        $process = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue

        if (-not $process) {
            $outputMsg = "$ProcessName is not running (attempt $attempt)"
            Write-Log $outputMsg -Level Info
            return $true
        }

        $outputMsg = "Stopping $ProcessName process (attempt $attempt/$MaxAttempts)..."
        Write-Log $outputMsg -Level Info
        if ($PSCmdlet.ShouldProcess($ProcessName, 'Stop application process')) {
            Stop-Process -Name $ProcessName -Force -ErrorAction SilentlyContinue
        }
        Start-Sleep -Seconds 2

        $attempt++
    }

    # Final check
    $process = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue
    if ($process) {
        $outputMsg = "Failed to stop $ProcessName after $MaxAttempts attempts"
        Write-Log $outputMsg -Level Error
        return $false
    }

    return $true
}


function Invoke-WingetWithRetry {
    <#
    .SYNOPSIS
        Thin wrapper around the native winget.exe CLI with bounded retries and exponential backoff.
    #>
    param(
        [string]$Arguments,
        [int]$MaxAttempts = $MaxRetries
    )

    $wingetPathFilter = 'C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\winget.exe'
    $wingetexe = Resolve-Path -Path $wingetPathFilter -ErrorAction Stop
    $wingetPath = if ($wingetexe.Count -gt 1) { $wingetexe[-1].Path } else { $wingetexe.Path }

    $attempt = 1
    $delay = $RetryDelaySeconds

    while ($attempt -le $MaxAttempts) {
        try {
            $outputMsg = "Executing winget command (Attempt $attempt/$MaxAttempts): $wingetPath $Arguments"
            Write-Log $outputMsg -Level Info

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

            # Drain BOTH output streams before waiting so a full stderr pipe cannot deadlock the child.
            $stdout = $p.StandardOutput.ReadToEnd()
            $stderr = $p.StandardError.ReadToEnd()
            $p.WaitForExit()

            # Base success on the process exit code, not on a grep of stdout.
            # Success: 0 (S_OK), 0x8A150014 (no packages found - "not installed" for list),
            # 0x8A150109 (install succeeded, reboot required).
            # Reference: https://github.com/microsoft/winget-cli/blob/master/doc/
            # windows/package-manager/winget/returnCodes.md
            if ($p.ExitCode -eq 0 -or $p.ExitCode -eq 0x8A150014 -or $p.ExitCode -eq 0x8A150109) {
                $outputMsg = "Winget command succeeded on attempt $attempt (exit code 0x$($p.ExitCode.ToString('X8')))"
                Write-Log $outputMsg -Level Info
                if ($stderr) { Write-Log "Winget stderr: $stderr" -Level Warning }
                return $stdout
            }

            $outputMsg = "Winget command exited with code 0x$($p.ExitCode.ToString('X8')) on attempt $attempt"
            Write-Log $outputMsg -Level Warning
            if ($stderr) { Write-Log "Winget stderr: $stderr" -Level Warning }
        }
        catch {
            $outputMsg = "Winget command failed on attempt $attempt : $($_.Exception.Message)"
            Write-Log $outputMsg -Level Warning
        }

        if ($attempt -lt $MaxAttempts) {
            $outputMsg = "Waiting $delay seconds before retry..."
            Write-Log $outputMsg -Level Info
            Start-Sleep -Seconds $delay
            $delay = $delay * 2  # Exponential backoff
        }

        $attempt++
    }

    throw "Winget command failed after $MaxAttempts attempts"
}

function Main {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    try {
        $outputMsg = "=== Starting winget force close remediation for package: $ID ==="
        Write-Log $outputMsg -Level Info

        # Prefer the Microsoft.WinGet.Client PowerShell module - the winget CLI is NOT supported in
        # the SYSTEM context (Intune Proactive Remediations run as SYSTEM). Only fall back to the
        # winget.exe CLI when the module is unavailable.
        # Reference: https://learn.microsoft.com/en-us/windows/package-manager/winget/troubleshooting
        if (Get-Module -ListAvailable -Name Microsoft.WinGet.Client) {
            try { Import-Module Microsoft.WinGet.Client -ErrorAction Stop }
            catch { Write-Verbose "Handled exception: $($_.Exception.Message)" }
            if (Get-Command Get-WinGetPackage -ErrorAction SilentlyContinue) {
                $outputMsg = "Using Microsoft.WinGet.Client module"
                Write-Log $outputMsg -Level Info

                $package = Get-WinGetPackage -Id $ID -MatchOption EqualsCaseInsensitive -ErrorAction SilentlyContinue

                # Auto-detect name if not provided
                if (-not $name) {
                    $name = if ($package.Name) { $package.Name } else { $ID }
                }

                # Check if package is installed
                if (-not $package) {
                    Write-Host "[+] $name is not installed on this device." -ForegroundColor Green
                    return 0
                }

                # Auto-detect process name if not provided
                if (-not $AppProcess) {
                    $AppProcess = ($ID -split '\.')[-1]
                }

                # Check if app is running and handle accordingly
                $process = Get-Process -Name "$AppProcess" -ErrorAction SilentlyContinue
                if ($process) {
                    $outputMsg = "$name is currently running (PID: $($process.Id -join ', '))"
                    Write-Log $outputMsg -Level Info

                    # Send user notification if enabled
                    if ($NotifyUserBeforeClose) {
                        $outputMsg = "Sending user notification before closing $name..."
                        Write-Log $outputMsg -Level Info
                        Show-UserNotification -AppName $name -Seconds $UserNotificationSeconds
                        Write-Host "[*] $name will be closed in $UserNotificationSeconds seconds. Notifying users..." `
                            -ForegroundColor Cyan
                        Start-Sleep -Seconds $UserNotificationSeconds
                    }

                    # Force close the application
                    Write-Host "[*] $name is running. Force closing application..." -ForegroundColor Cyan
                    $closedSuccessfully = Stop-ApplicationProcess -ProcessName $AppProcess

                    if (-not $closedSuccessfully) {
                        Write-Host "[-] Failed to close $name process. Aborting update." -ForegroundColor Red
                        return 1
                    }

                    $outputMsg = "$name closed successfully. Waiting $GracePeriodSeconds seconds..."
                    Write-Log $outputMsg -Level Info
                    Start-Sleep -Seconds $GracePeriodSeconds
                }
                else {
                    $outputMsg = "$name is not currently running."
                    Write-Log $outputMsg -Level Info
                }

                # Check if update is available
                if ($package.IsUpdateAvailable) {
                    $verInstalled = $package.InstalledVersion
                    $verAvailable = $package.AvailableVersions | Select-Object -Last 1
                    $outputMsg = "Update available for $name ($verInstalled -> $verAvailable)"
                    Write-Log $outputMsg -Level Info

                    # Execute pre-update hook if defined
                    if ($PreUpdateScriptBlock) {
                        $outputMsg = "Executing pre-update hook..."
                        Write-Log $outputMsg -Level Info
                        try {
                            & $PreUpdateScriptBlock
                        }
                        catch {
                            $outputMsg = "Pre-update hook failed: $($_.Exception.Message)"
                            Write-Log $outputMsg -Level Warning
                        }
                    }

                    # Perform upgrade via the module
                    Write-Host "[*] Installing $name update ($verInstalled -> $verAvailable)..." -ForegroundColor Cyan
                    if ($PSCmdlet.ShouldProcess($name, "Update package $ID silently")) {
                        Update-WinGetPackage -Id $ID -MatchOption EqualsCaseInsensitive `
                            -Mode Silent -Force -ErrorAction Stop
                    }

                    # Wait for installation to complete
                    $outputMsg = "Waiting $VerifyWaitSeconds seconds for installation to complete..."
                    Write-Log $outputMsg -Level Info
                    Start-Sleep -Seconds $VerifyWaitSeconds

                    # Execute post-update hook if defined
                    if ($PostUpdateScriptBlock) {
                        $outputMsg = "Executing post-update hook..."
                        Write-Log $outputMsg -Level Info
                        try {
                            & $PostUpdateScriptBlock
                        }
                        catch {
                            $outputMsg = "Post-update hook failed: $($_.Exception.Message)"
                            Write-Log $outputMsg -Level Warning
                        }
                    }

                    # Verify installation
                    $outputMsg = "Verifying installation..."
                    Write-Log $outputMsg -Level Info
                    $verifyPackage = Get-WinGetPackage -Id $ID -MatchOption EqualsCaseInsensitive `
                        -ErrorAction SilentlyContinue

                    if ($verifyPackage) {
                        $versionInstalled = $verifyPackage.InstalledVersion
                        Write-Host "[+] $name updated successfully to version $versionInstalled" -ForegroundColor Green

                        [pscustomobject] @{
                            Name = $name
                            PreviousVersion = $verInstalled
                            InstalledVersion = $versionInstalled
                            Status = "Force Updated Successfully"
                        }

                        return 0
                    }

                    Write-Host "[-] Failed to verify $name installation after update." -ForegroundColor Red
                    return 1
                }
                else {
                    # No update available
                    $versionInstalled = $package.InstalledVersion
                    $outputMsg = "$name is already up to date (version $versionInstalled)"
                    Write-Log $outputMsg -Level Info
                    Write-Host "[+] $name is already up to date (version $versionInstalled)." -ForegroundColor Green

                    [pscustomobject] @{
                        Name = $name
                        InstalledVersion = $versionInstalled
                        Status = "Up to Date"
                    }

                    return 0
                }
            }
        }

        # Fallback: winget.exe CLI path via the wrapper function.
        $outputMsg = "Microsoft.WinGet.Client module unavailable, falling back to winget.exe CLI"
        Write-Log $outputMsg -Level Warning

        $packageInfo = Invoke-WingetWithRetry -Arguments "list --exact --id $ID --accept-source-agreements"

        # Auto-detect name if not provided
        if (-not $name) {
            $nameMatch = $packageInfo | Select-String -Pattern "^($ID)\s+(.+?)\s+\d"
            $name = if ($nameMatch) { $nameMatch.Matches[0].Groups[2].Value.Trim() } else { $ID }
        }

        # Check if package is installed
        if ($packageInfo -match "No installed package found matching input criteria") {
            Write-Host "[+] $name is not installed on this device." -ForegroundColor Green
            return 0
        }

        # Auto-detect process name if not provided
        if (-not $AppProcess) {
            $AppProcess = ($ID -split '\.')[-1]
        }

        # Check if app is running and handle accordingly
        $process = Get-Process -Name "$AppProcess" -ErrorAction SilentlyContinue
        if ($process) {
            $outputMsg = "$name is currently running (PID: $($process.Id -join ', '))"
            Write-Log $outputMsg -Level Info

            # Send user notification if enabled
            if ($NotifyUserBeforeClose) {
                $outputMsg = "Sending user notification before closing $name..."
                Write-Log $outputMsg -Level Info
                Show-UserNotification -AppName $name -Seconds $UserNotificationSeconds
                Write-Host "[*] $name will be closed in $UserNotificationSeconds seconds. Notifying users..." `
                    -ForegroundColor Cyan
                Start-Sleep -Seconds $UserNotificationSeconds
            }

            # Force close the application
            Write-Host "[*] $name is running. Force closing application..." -ForegroundColor Cyan
            $closedSuccessfully = Stop-ApplicationProcess -ProcessName $AppProcess

            if (-not $closedSuccessfully) {
                Write-Host "[-] Failed to close $name process. Aborting update." -ForegroundColor Red
                return 1
            }

            $outputMsg = "$name closed successfully. Waiting $GracePeriodSeconds seconds..."
            Write-Log $outputMsg -Level Info
            Start-Sleep -Seconds $GracePeriodSeconds
        }
        else {
            $outputMsg = "$name is not currently running."
            Write-Log $outputMsg -Level Info
        }

        # Check if update is available
        if ($packageInfo -match '\bVersion\s+Available\b') {
            $verInstalled, $verAvailable = (-split $packageInfo[-1])[-3, -2]
            $outputMsg = "Update available for $name ($verInstalled -> $verAvailable)"
            Write-Log $outputMsg -Level Info

            # Execute pre-update hook if defined
            if ($PreUpdateScriptBlock) {
                $outputMsg = "Executing pre-update hook..."
                Write-Log $outputMsg -Level Info
                try {
                    & $PreUpdateScriptBlock
                }
                catch {
                    $outputMsg = "Pre-update hook failed: $($_.Exception.Message)"
                    Write-Log $outputMsg -Level Warning
                }
            }

            # Perform upgrade via the winget CLI wrapper
            Write-Host "[*] Installing $name update ($verInstalled -> $verAvailable)..." -ForegroundColor Cyan
            if ($PSCmdlet.ShouldProcess($name, "Update package $ID via winget CLI")) {
                $upgradeArgs = "upgrade -e --id $ID --silent --accept-package-agreements --accept-source-agreements"
                Invoke-WingetWithRetry -Arguments $upgradeArgs | Out-Null
            }

            # Wait for installation to complete
            $outputMsg = "Waiting $VerifyWaitSeconds seconds for installation to complete..."
            Write-Log $outputMsg -Level Info
            Start-Sleep -Seconds $VerifyWaitSeconds

            # Execute post-update hook if defined
            if ($PostUpdateScriptBlock) {
                $outputMsg = "Executing post-update hook..."
                Write-Log $outputMsg -Level Info
                try {
                    & $PostUpdateScriptBlock
                }
                catch {
                    $outputMsg = "Post-update hook failed: $($_.Exception.Message)"
                    Write-Log $outputMsg -Level Warning
                }
            }

            # Verify installation
            $outputMsg = "Verifying installation..."
            Write-Log $outputMsg -Level Info
            $verifyInfo = Invoke-WingetWithRetry -Arguments "list --exact --id $ID --accept-source-agreements"

            if ($verifyInfo -match '\d+(\.\d+)+') {
                $versionInstalled = (-split $verifyInfo[-1])[-2]
                Write-Host "[+] $name updated successfully to version $versionInstalled" -ForegroundColor Green

                [pscustomobject] @{
                    Name = $name
                    PreviousVersion = $verInstalled
                    InstalledVersion = $versionInstalled
                    Status = "Force Updated Successfully"
                }

                return 0
            }

            Write-Host "[-] Failed to verify $name installation after update." -ForegroundColor Red
            return 1
        }
        elseif ($packageInfo -match '\d+(\.\d+)+') {
            # No update available
            $versionInstalled = (-split $packageInfo[-1])[-2]
            $outputMsg = "$name is already up to date (version $versionInstalled)"
            Write-Log $outputMsg -Level Info
            Write-Host "[+] $name is already up to date (version $versionInstalled)." -ForegroundColor Green
            return 0
        }
        else {
            Write-Host "[!] $name appears to be installed but version info could not be parsed." -ForegroundColor Yellow
            return 0
        }
    }
    catch {
        Write-Host "[-] Failed to update $name : $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
    finally {
        $outputMsg = "=== Remediation script completed ==="
        Write-Log $outputMsg -Level Info
    }
}

#endregion

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
