<#
.SYNOPSIS
    Updates PowerShell 7 (winget id Microsoft.PowerShell) only during configured maintenance windows.

.DESCRIPTION
    Maintenance-window remediation for the PowerShell 7 update pair. The script first checks
    whether the current day of week and hour fall inside the configured maintenance window
    (Test-MaintenanceWindow); outside the window it exits 0 without action so Intune never
    falsely triggers remediation. Inside the window it prefers the Microsoft.WinGet.Client
    PowerShell module (the winget CLI is NOT supported in the SYSTEM context that Intune
    Proactive Remediations run in) and falls back to the winget.exe CLI through the
    Invoke-WingetWithRetry wrapper (exponential backoff between attempts) only when the
    module is unavailable. When ForceCloseInMaintenanceWindow is enabled, a running pwsh
    process is force-closed (with one retry) before updating; otherwise the update is skipped.
    Optional pre/post-update script blocks are executed around the upgrade when defined.
    Exit codes:
    - 0: success - updated, already up to date, package not installed, or outside the
      maintenance window (deliberately compliant so remediation is not retriggered).
    - 1: failure or skip - app still running with force close disabled, verification failed,
      or an error occurred.

.EXAMPLE
    PS C:\> .\Invoke-WingetPowerShell7MaintenanceWindow.ps1
    Updates PowerShell 7 only if the current time is inside the configured maintenance window.

.EXAMPLE
    PS C:\> .\Invoke-WingetPowerShell7MaintenanceWindow.ps1 -WhatIf
    Shows which package update would run without performing it; outside the window it exits 0 unchanged.

.NOTES
    File Name: Invoke-WingetPowerShell7MaintenanceWindow.ps1
    Author: Bug-Free Umbrella
    Prerequisite: PowerShell 7.0
    Version: 1.0.0
    Date: 2026-08-23
    Configure $ID, $MaintenanceWindowDays, $MaintenanceWindowStartHour,
    $MaintenanceWindowEndHour and optionally $ForceCloseInMaintenanceWindow in the
    Configuration region of this script before deployment.
#>

[CmdletBinding(SupportsShouldProcess)]

$ErrorActionPreference = 'Stop'

#region Configuration
$ID = 'Microsoft.PowerShell'

# Maintenance window: days (day-of-week names) plus a 24-hour start/end hour range.
$MaintenanceWindowDays = @('Saturday', 'Sunday')
$MaintenanceWindowStartHour = 2   # 2 AM
$MaintenanceWindowEndHour = 6     # 6 AM

$name = 'PowerShell 7'
$AppProcess = 'pwsh'
$ForceCloseInMaintenanceWindow = $true     # Force close app if running during maintenance window

$MaxRetries = 3                            # Number of retry attempts for winget operations
$RetryDelaySeconds = 2                     # Initial delay between retries (doubles each attempt)
$GracePeriodSeconds = 5                    # Time to wait after closing app (if force close enabled)
$VerifyWaitSeconds = 10                    # Time to wait after update to verify installation
$EnableLogging = $true                     # Set to $false to disable file logging
$LogPath = "C:\ProgramData\IntuneScripts\Logs\PowerShell7_Maintenance.log"

# Optional hooks for custom actions around the upgrade.
$PreUpdateScriptBlock = $null              # Script block to run before update
$PostUpdateScriptBlock = $null             # Script block to run after update
#endregion

#region Functions

function Write-Log {
    <#
    .SYNOPSIS
        Writes a timestamped message to the console (and optional log file).
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

function Test-MaintenanceWindow {
    <#
    .SYNOPSIS
        Returns $true when the current day and hour are inside the configured maintenance window.
    #>
    $now = Get-Date
    $currentDay = $now.DayOfWeek.ToString()
    $currentHour = $now.Hour

    $outputMsg = "Current time: $($now.ToString('yyyy-MM-dd HH:mm:ss')) | Day: $currentDay | Hour: $currentHour"

    Write-Log $outputMsg -Level Info

    # Check if current day is in maintenance window
    if ($MaintenanceWindowDays -notcontains $currentDay) {
        $allowedDays = $MaintenanceWindowDays -join ", "
        Write-Log "Current day ($currentDay) is not in maintenance window. Allowed days: $allowedDays" -Level Info
        return $false
    }

    # Check if current hour is in maintenance window
    if ($currentHour -lt $MaintenanceWindowStartHour -or $currentHour -ge $MaintenanceWindowEndHour) {
        $windowText = "($MaintenanceWindowStartHour-$MaintenanceWindowEndHour)"
        Write-Log "Current hour ($currentHour) is outside maintenance window $windowText" -Level Info
        return $false
    }

    Write-Log "Currently IN maintenance window: $currentDay $currentHour`:00" -Level Info
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

            # Base success on the process exit code, not on stdout content.
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

function Close-AppProcessForMaintenance {
    <#
    .SYNOPSIS
        Force-closes the app process during the maintenance window, retrying once if it survives.
    #>
    $outputMsg = "$name is running. Force closing during maintenance window..."
    Write-Log $outputMsg -Level Info
    $outputMsg = "[*] $name is running. Force closing application during maintenance window..."
    Write-Host $outputMsg -ForegroundColor Cyan

    Stop-Process -Name "$AppProcess" -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds $GracePeriodSeconds

    # Verify process was closed
    $process = Get-Process -Name "$AppProcess" -ErrorAction SilentlyContinue
    if ($process) {
        $outputMsg = "$name process still running after force close attempt. Retrying..."
        Write-Log $outputMsg -Level Warning
        Stop-Process -Name "$AppProcess" -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    }

    $outputMsg = "$name closed successfully."

    Write-Log $outputMsg -Level Info
}

#endregion

#region Script

function Main {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    try {
        $outputMsg = "=== Starting winget maintenance window remediation for package: $ID ==="
        Write-Log $outputMsg -Level Info

        # Check if we're in maintenance window
        if (-not (Test-MaintenanceWindow)) {
            $outputMsg = "Outside maintenance window. Update will not be performed."
            Write-Log $outputMsg -Level Info
                        Write-Host "[*] Outside maintenance window. Updates only run during: $($MaintenanceWindowDays `
                -join ', ') between $MaintenanceWindowStartHour`:00-$MaintenanceWindowEndHour`:00" `
                -ForegroundColor Cyan
            return 0  # Don't trigger remediation outside maintenance window
        }

        $outputMsg = "[*] Inside maintenance window. Proceeding with update check..."

        Write-Host $outputMsg -ForegroundColor Cyan

        # Prefer the Microsoft.WinGet.Client PowerShell module - the winget CLI is NOT supported in
        # the SYSTEM context (Intune Proactive Remediations run as SYSTEM). Only fall back to the
        # winget.exe CLI when the module is unavailable.
        # Reference: https://learn.microsoft.com/en-us/windows/package-manager/winget/troubleshooting
        if (Get-Module -ListAvailable -Name Microsoft.WinGet.Client) {
            try { Import-Module Microsoft.WinGet.Client -ErrorAction Stop }
            catch { Write-Verbose \"Handled exception: $($_.Exception.Message)\" }
            if (Get-Command Get-WinGetPackage -ErrorAction SilentlyContinue) {
                $outputMsg = "Using Microsoft.WinGet.Client module"
                Write-Log $outputMsg -Level Info

                $package = Get-WinGetPackage -Id $ID -MatchOption EqualsCaseInsensitive -ErrorAction SilentlyContinue

                # Check if package is installed
                if (-not $package) {
                    $outputMsg = "$name is not installed on this device."
                    Write-Log $outputMsg -Level Info
                    $outputMsg = "[+] $name is not installed on this device."
                    Write-Host $outputMsg -ForegroundColor Green
                    return 0
                }

                # Check if update is available
                if ($package.IsUpdateAvailable) {
                    $verInstalled = $package.InstalledVersion
                    $verAvailable = $package.AvailableVersions | Select-Object -Last 1
                    $outputMsg = "Update available for $name | Installed: $verInstalled | Available: $verAvailable"
                    Write-Log $outputMsg -Level Info

                    # Handle running processes
                    $process = Get-Process -Name "$AppProcess" -ErrorAction SilentlyContinue
                    if ($process) {
                        if ($ForceCloseInMaintenanceWindow) {
                            Close-AppProcessForMaintenance
                        }
                        else {
                            $outputMsg = "$name is running. Skipping update (force close disabled)."
                            Write-Log $outputMsg -Level Warning
                            $outputMsg = "[!] $name is currently running. Skipping update."
                            Write-Host $outputMsg -ForegroundColor Yellow
                            return 1
                        }
                    }
                    else {
                        $outputMsg = "$name is not currently running."
                        Write-Log $outputMsg -Level Info
                    }

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
                    $outputMsg = "Installing $name update ($verInstalled -> $verAvailable)..."
                    Write-Log $outputMsg -Level Info
                    $outputMsg = "[*] Installing $name update..."
                    Write-Host $outputMsg -ForegroundColor Cyan
                    if ($PSCmdlet.ShouldProcess($name, "Update package $ID silently during maintenance window")) {
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
                        $outputMsg = "$name updated successfully to version $versionInstalled"
                        Write-Log $outputMsg -Level Info
                        $outputMsg = "[+] $name updated successfully to version $versionInstalled"
                        Write-Host $outputMsg -ForegroundColor Green

                        [pscustomobject] @{
                            Name = $name
                            PreviousVersion = $verInstalled
                            InstalledVersion = $versionInstalled
                            Status = "Updated During Maintenance Window"
                                                        MaintenanceWindow = "$($MaintenanceWindowDays -join ', ') `
                                $MaintenanceWindowStartHour-$MaintenanceWindowEndHour"
                        }

                        return 0
                    }
                    $outputMsg = "Failed to verify $name installation after update"
                    Write-Log $outputMsg -Level Error
                    $outputMsg = "[-] Failed to verify $name installation after update."
                    Write-Host $outputMsg -ForegroundColor Red
                    return 1
                }

                # No update available
                $versionInstalled = $package.InstalledVersion
                $outputMsg = "$name is already up to date (version $versionInstalled)"
                Write-Log $outputMsg -Level Info
                $outputMsg = "[+] $name is already up to date (version $versionInstalled)"
                Write-Host $outputMsg -ForegroundColor Green

                [pscustomobject] @{
                    Name = $name
                    InstalledVersion = $versionInstalled
                    Status = "Up to Date"
                }

                return 0
            }
        }

        # Fallback: winget.exe CLI (only reached when the Microsoft.WinGet.Client module is unavailable)
        $outputMsg = "Microsoft.WinGet.Client module unavailable, falling back to winget.exe CLI"
        Write-Log $outputMsg -Level Warning

        # Get package information (exact ID match) via the wrapper function
        $packageInfo = Invoke-WingetWithRetry -Arguments "list --exact --id $ID --accept-source-agreements"

        # Auto-detect name if not provided
        if (-not $name) {
            $nameMatch = $packageInfo | Select-String -Pattern "^($ID)\s+(.+?)\s+\d"
            if ($nameMatch) {
                $name = $nameMatch.Matches[0].Groups[2].Value.Trim()
            }
            else {
                $name = $ID
            }
        }

        # Check if package is installed
        if ($packageInfo -match "No installed package found matching input criteria") {
            $outputMsg = "$name is not installed on this device."
            Write-Log $outputMsg -Level Info
            $outputMsg = "[+] $name is not installed on this device."
            Write-Host $outputMsg -ForegroundColor Green
            return 0
        }

        # Check if update is available
        if ($packageInfo -match '\bVersion\s+Available\b') {
            $verInstalled, $verAvailable = (-split $packageInfo[-1])[-3, -2]
            $outputMsg = "Update available for $name | Installed: $verInstalled | Available: $verAvailable"
            Write-Log $outputMsg -Level Info

            # Handle running processes
            $process = Get-Process -Name "$AppProcess" -ErrorAction SilentlyContinue
            if ($process) {
                if ($ForceCloseInMaintenanceWindow) {
                    Close-AppProcessForMaintenance
                }
                else {
                    $outputMsg = "$name is running. Skipping update (force close disabled)."
                    Write-Log $outputMsg -Level Warning
                    $outputMsg = "[!] $name is currently running. Skipping update."
                    Write-Host $outputMsg -ForegroundColor Yellow
                    return 1
                }
            }
            else {
                $outputMsg = "$name is not currently running."
                Write-Log $outputMsg -Level Info
            }

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

            # Perform upgrade via the wrapper function
            $outputMsg = "Installing $name update ($verInstalled -> $verAvailable)..."
            Write-Log $outputMsg -Level Info
            $outputMsg = "[*] Installing $name update..."
            Write-Host $outputMsg -ForegroundColor Cyan
            if ($PSCmdlet.ShouldProcess($name, "Update package $ID via winget CLI during maintenance window")) {
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
                $outputMsg = "$name updated successfully to version $versionInstalled"
                Write-Log $outputMsg -Level Info
                $outputMsg = "[+] $name updated successfully to version $versionInstalled"
                Write-Host $outputMsg -ForegroundColor Green

                [pscustomobject] @{
                    Name = $name
                    PreviousVersion = $verInstalled
                    InstalledVersion = $versionInstalled
                    Status = "Updated During Maintenance Window"
                                        MaintenanceWindow = "$($MaintenanceWindowDays -join ', ') `
                        $MaintenanceWindowStartHour-$MaintenanceWindowEndHour"
                }

                return 0
            }
            $outputMsg = "Failed to verify $name installation after update"
            Write-Log $outputMsg -Level Error
            $outputMsg = "[-] Failed to verify $name installation after update."
            Write-Host $outputMsg -ForegroundColor Red
            return 1
        }

        # No update available
        if ($packageInfo -match '\d+(\.\d+)+') {
            $versionInstalled = (-split $packageInfo[-1])[-2]
            $outputMsg = "$name is already up to date (version $versionInstalled)"
            Write-Log $outputMsg -Level Info
            $outputMsg = "[+] $name is already up to date (version $versionInstalled)"
            Write-Host $outputMsg -ForegroundColor Green

            [pscustomobject] @{
                Name = $name
                InstalledVersion = $versionInstalled
                Status = "Up to Date"
            }
        }

        return 0
    }
    catch {
        $outputMsg = "ERROR: Failed to update $name : $($_.Exception.Message)"
        Write-Log $outputMsg -Level Error
        $outputMsg = "[-] Failed to update $name : $($_.Exception.Message)"
        Write-Host $outputMsg -ForegroundColor Red
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
