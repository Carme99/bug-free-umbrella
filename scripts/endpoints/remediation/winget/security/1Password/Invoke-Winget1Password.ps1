<#
.SYNOPSIS
    Silently updates 1Password via winget (skips while running) for Intune Proactive Remediations.

.DESCRIPTION
    Remediation half of the 1Password update pair. Checks whether an update is available and installs it
    silently through the Microsoft.WinGet.Client module, falling back to the winget.exe CLI through the
    Invoke-WingetWithRetry wrapper when the module is unavailable. When the application process is running
    the update is skipped and exit code 1 is returned so Intune retries later. Optional pre/post update
    hook script blocks can run custom actions around the update. Honors -WhatIf; the silent update only
    runs behind a ShouldProcess gate.
    Exit codes:
    - 0: success - updated, already up to date, or package not installed.
    - 1: skipped because the application is running, verification failed after update, or an error occurred.
    Re-running on a converged system exits 0 without changes (idempotent).

.NOTES
    File Name: Invoke-Winget1Password.ps1
    Author: Bug-Free Umbrella
    Prerequisite: PowerShell 7.0
    Version: 1.0.0
    Date: 2026-08-23

.EXAMPLE
    PS C:\> .\Invoke-Winget1Password.ps1
    Updates 1Password silently unless the application is running; exits 0 on success or when already up to date.

.EXAMPLE
    PS C:\> .\Invoke-Winget1Password.ps1 -WhatIf
    Shows which update actions would run without performing them.
#>


[CmdletBinding(SupportsShouldProcess)]

# PSAvoidUsingWriteHost is intentionally accepted: prefixed, colored console output is the mandated
# output convention of docs/RELAUNCH-SPEC.md section 3.
$ErrorActionPreference = 'Stop'

#region Configuration
$ID = 'AgileBits.1Password'

# Basic settings
$name = $null                   # Leave as $null to auto-detect from winget
$AppProcess = $null             # Leave as $null to auto-detect from package ID

# Advanced settings
$MaxRetries = 3                     # Number of retry attempts for winget operations
$RetryDelaySeconds = 2              # Initial delay between retries
$VerifyWaitSeconds = 5              # Time to wait after update before verification
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
        $outputMsg = "=== Starting winget remediation for package: $ID ==="
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

                # Check if update is available
                if ($package.IsUpdateAvailable) {
                    $verInstalled = $package.InstalledVersion
                    $verAvailable = $package.AvailableVersions | Select-Object -Last 1
                    $outputMsg = "Update available for $name ($verInstalled -> $verAvailable)"
                    Write-Log $outputMsg -Level Info

                    # Skip while the application is running; Intune will retry later.
                    $process = Get-Process -Name "$AppProcess" -ErrorAction SilentlyContinue
                    if ($process) {
                        $outputMsg = "$name is currently running. Skipping update - will retry later."
                        Write-Log $outputMsg -Level Warning
                        Write-Host "[*] $name is currently running. Will try again later." -ForegroundColor Cyan

                        [pscustomobject] @{
                            Name = $name
                            InstalledVersion = $verInstalled
                            AvailableVersion = $verAvailable
                            Status = "Skipped - App Running"
                        }

                        return 1
                    }

                    $outputMsg = "$name is not running. Proceeding with update..."
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
                            Status = "Updated Successfully"
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

        # Check if update is available
        if ($packageInfo -match '\bVersion\s+Available\b') {
            $verInstalled, $verAvailable = (-split $packageInfo[-1])[-3, -2]
            $outputMsg = "Update available for $name ($verInstalled -> $verAvailable)"
            Write-Log $outputMsg -Level Info

            # Auto-detect process name if not provided
            if (-not $AppProcess) {
                $AppProcess = ($ID -split '\.')[-1]
            }

            # Skip while the application is running; Intune will retry later.
            $process = Get-Process -Name "$AppProcess" -ErrorAction SilentlyContinue
            if ($process) {
                $outputMsg = "$name is currently running. Skipping update - will retry later."
                Write-Log $outputMsg -Level Warning
                Write-Host "[*] $name is currently running. Will try again later." -ForegroundColor Cyan

                [pscustomobject] @{
                    Name = $name
                    InstalledVersion = $verInstalled
                    AvailableVersion = $verAvailable
                    Status = "Skipped - App Running"
                }

                return 1
            }

            $outputMsg = "$name is not running. Proceeding with update..."
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
                    Status = "Updated Successfully"
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
