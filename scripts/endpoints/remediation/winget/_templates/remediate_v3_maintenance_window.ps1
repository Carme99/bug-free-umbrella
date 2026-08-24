<#
.SYNOPSIS
    Maintenance window winget update template that only runs during specified hours (V3).

.DESCRIPTION
    This template checks if an app update is available and installs it ONLY during
    configured maintenance windows. Outside maintenance windows, the script warns and exits 0
    without action. When $ForceCloseInMaintenanceWindow is set and the app is running while an
    update is pending, the app process is stopped; stopping a running process is destructive, so
    every stop is gated behind ShouldProcess and honors -WhatIf.
    It prefers the Microsoft.WinGet.Client PowerShell module (the winget CLI is NOT
    supported in the SYSTEM context that Intune Proactive Remediations run in) and
    falls back to the winget.exe CLI only when the module is unavailable.
    Exit codes follow the Intune remediation convention: 0 = updated, already up to date,
    not installed, or outside the maintenance window (nothing to do); 1 = the upgrade failed,
    the update was skipped because force close is disabled while the app runs.
    V3 ENHANCEMENTS:
    - Configurable maintenance window (day of week + time range)
    - Option to force close app during maintenance window
    - Retry logic with exponential backoff
    - Better error handling and logging
    - Pre/post update hooks
    - All delays run through Start-Sleep and are mockable in tests
    Template note (docs/RELAUNCH-SPEC.md section 6): examples below show placeholder
    configuration, which makes some help rules inapplicable until placeholders are replaced.
    Configuration:
    1. Set the $ID variable to your winget package ID
    2. Configure maintenance window settings (days, start/end times)
    3. Choose whether to force close app during maintenance window

.EXAMPLE
    PS C:\> .\remediate_v3_maintenance_window.ps1

    Runs the template directly against the placeholder configuration.

.EXAMPLE
    PS C:\> pwsh -NoProfile -WhatIf -File .\remediate_v3_maintenance_window.ps1

    Previews the run in a clean PowerShell process; outside the configured window nothing runs,
    and inside it the destructive Stop-Process step is reported but not executed.

.NOTES
    REQUIRED: Configure winget ID and maintenance window schedule.
    BEST FOR: Critical apps that should only update during off-hours (databases, production tools).
    File Name  : remediate_v3_maintenance_window.ps1
    Author     : Bug-Free Umbrella
    Prerequisite: PowerShell 5.1+
    Version    : 1.0.0
    Date       : 2026-08-23
#>

[CmdletBinding(SupportsShouldProcess)]
param()

# PSAvoidUsingWriteHost is intentionally accepted: prefixed, colored console output is the mandated
# output convention of docs/RELAUNCH-SPEC.md section 3.
# PSUseOutputTypeCorrectly is intentionally accepted: internal helper functions return plain
# values (bool/string/object[]) by design; only Main's exit code (int) is a public contract.
$ErrorActionPreference = 'Stop'

#region Configuration
# ===== REQUIRED: Set your winget package ID =====
$ID = 'WINGETID'  # Example: 'Microsoft.SQLServerManagementStudio', 'OBSProject.OBSStudio'

# ===== REQUIRED: Maintenance Window Configuration =====
# Days when updates are allowed (Sunday, Monday, Tuesday, Wednesday, Thursday, Friday, Saturday)
$MaintenanceWindowDays = @('Saturday', 'Sunday')  # Update only on weekends

# Time range when updates are allowed (24-hour format)
$MaintenanceWindowStartHour = 2   # 2 AM
$MaintenanceWindowEndHour = 6     # 6 AM

# ===== OPTIONAL: Basic Settings =====
$name = $null                              # Leave as $null to auto-detect from winget
$AppProcess = $null                        # Leave as $null to auto-detect from package ID
$ForceCloseInMaintenanceWindow = $true     # Force close app if running during maintenance window

# ===== OPTIONAL: Advanced Settings =====
$MaxRetries = 3                            # Number of retry attempts for winget operations
$RetryDelaySeconds = 2                     # Initial delay between retries (mockable)
$GracePeriodSeconds = 5                    # Time to wait after closing app (mockable delay)
$VerifyWaitSeconds = 10                    # Time to wait after update to verify installation (mockable)
$EnableLogging = $false                    # Set to $true to enable file logging
$LogPath = "C:\ProgramData\IntuneScripts\Logs\WingetRemediation_$ID.log"

# ===== OPTIONAL: Hooks for Custom Actions =====
$PreUpdateScriptBlock = $null              # Script block to run before update
$PostUpdateScriptBlock = $null             # Script block to run after update
#endregion

#region Functions
function Write-TemplateLog {
    # Writes a timestamped console line (prefixed and colored per spec section 3) and optionally a
    # file log entry when $EnableLogging is set.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [ValidateSet('Info', 'Warning', 'Error')]
        [string]$Level = 'Info'
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logMessage = "[$timestamp] [$Level] $Message"

    switch ($Level) {
        'Error' { Write-Host "[-] $Message" -ForegroundColor Red }
        'Warning' { Write-Host "[!] $Message" -ForegroundColor Yellow }
        default { Write-Host "[*] $Message" -ForegroundColor Cyan }
    }

    if ($EnableLogging) {
        try {
            $logDir = Split-Path -Path $LogPath -Parent
            if (-not (Test-Path -Path $logDir)) {
                New-Item -Path $logDir -ItemType Directory -Force | Out-Null
            }
            Add-Content -Path $LogPath -Value $logMessage -ErrorAction SilentlyContinue
        }
        catch {
            Write-Verbose "Handled exception: $($_.Exception.Message)" -Verbose:$false
        }
    }
}

function Test-MaintenanceWindow {
    # Mockable gate: derives the current day/hour via Get-Date and compares against the configured
    # maintenance window. Returns $true only when updates are currently allowed.
    [CmdletBinding()]
    param()

    $now = Get-Date
    $currentDay = $now.DayOfWeek.ToString()
    $currentHour = $now.Hour

    $clock = $now.ToString('yyyy-MM-dd HH:mm:ss')
    Write-TemplateLog "Current time: $clock | Day: $currentDay | Hour: $currentHour" -Level Info

    # Check if current day is in maintenance window
    if ($MaintenanceWindowDays -notcontains $currentDay) {
        Write-TemplateLog "Current day ($currentDay) is not in maintenance window." -Level Info
        Write-TemplateLog "Allowed days: $($MaintenanceWindowDays -join ', ')" -Level Info
        return $false
    }

    # Check if current hour is in maintenance window
    if ($currentHour -lt $MaintenanceWindowStartHour -or $currentHour -ge $MaintenanceWindowEndHour) {
        Write-TemplateLog "Current hour ($currentHour) is outside maintenance window" -Level Info
        Write-TemplateLog "Maintenance window hours: $MaintenanceWindowStartHour-$MaintenanceWindowEndHour" -Level Info
        return $false
    }

    Write-TemplateLog "Currently IN maintenance window: $currentDay $currentHour`:00" -Level Info
    return $true
}

function Get-WingetExecutable {
    # Thin wrapper seam: locates the winget.exe CLI bundled with App Installer; tests mock this function.
    [CmdletBinding()]
    param()

    $wingetGlob = 'C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\winget.exe'
    $resolved = Resolve-Path -Path $wingetGlob -ErrorAction Stop
    if (@($resolved).Count -gt 1) {
        return @($resolved)[-1].Path
    }
    return $resolved.Path
}

function Invoke-WingetCommand {
    # Thin wrapper seam: EVERY native winget.exe invocation (the sysget alias target) routes through
    # this function so Pester can mock the wrapper; the executable is never called elsewhere.
    # docs/RELAUNCH-SPEC.md section 3: check $LASTEXITCODE and translate non-zero into failure handling.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string[]]$Arguments
    )

    $wingetPath = Get-WingetExecutable
    $output = & $wingetPath @Arguments 2>$null
    $exitCode = $LASTEXITCODE

    # Success codes: 0 (S_OK), 0x8A150014 (no installed package found), 0x8A150109 (reboot required).
    # Reference: https://github.com/microsoft/winget-cli/blob/master/doc/windows/package-manager/winget/returnCodes.md
    if ($exitCode -ne 0 -and $exitCode -ne 0x8A150014 -and $exitCode -ne 0x8A150109) {
        throw "winget exited with code 0x$('{0:X8}' -f $exitCode) for arguments: $($Arguments -join ' ')"
    }

    return @($output)
}

function Invoke-WingetWithRetry {
    # Retry-with-backoff harness around the Invoke-WingetCommand wrapper seam. Delays are driven by
    # the user-editable $RetryDelaySeconds configuration value via Start-Sleep (mockable in tests).
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string[]]$Arguments,

        [ValidateRange(1, 2147483647)]
        [int]$MaxAttempts = $MaxRetries
    )

    $attempt = 1
    $delay = $RetryDelaySeconds

    while ($true) {
        try {
            $output = Invoke-WingetCommand -Arguments $Arguments -ErrorAction Stop
            Write-TemplateLog "Winget command succeeded on attempt $attempt." -Level Info
            return $output
        }
        catch {
            Write-TemplateLog "Winget command failed on attempt $attempt : $($_.Exception.Message)" -Level Warning
        }

        if ($attempt -ge $MaxAttempts) {
            throw "Winget command failed after $MaxAttempts attempts"
        }

        Write-TemplateLog "Waiting $delay seconds before retry..." -Level Info
        Start-Sleep -Seconds $delay
        $delay = $delay * 2  # Exponential backoff
        $attempt++
    }
}

function Stop-ApplicationProcess {
    # Stopping a running application process is destructive: every Stop-Process call is gated behind
    # ShouldProcess and this advanced function honors -WhatIf (including inherited preference).
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ProcessName
    )

    if ($PSCmdlet.ShouldProcess($ProcessName, 'Stop process')) {
        Stop-Process -Name $ProcessName -Force -ErrorAction SilentlyContinue
    }
    Start-Sleep -Seconds $GracePeriodSeconds

    # Verify process was closed; retry once before giving up.
    if (Get-Process -Name $ProcessName -ErrorAction SilentlyContinue) {
        Write-TemplateLog "$ProcessName still running after force close attempt. Retrying..." -Level Warning
        if ($PSCmdlet.ShouldProcess($ProcessName, 'Stop process')) {
            Stop-Process -Name $ProcessName -Force -ErrorAction SilentlyContinue
        }
        Start-Sleep -Seconds 2
    }

    if (Get-Process -Name $ProcessName -ErrorAction SilentlyContinue) {
        throw "Failed to close '$ProcessName' process. Cannot proceed with update."
    }

    Write-TemplateLog "$ProcessName closed successfully." -Level Info
}
#endregion

#region Script
function Invoke-Hook {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [scriptblock]$Hook,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$HookName
    )

    try {
        & $Hook
        Write-TemplateLog "$HookName hook completed successfully." -Level Info
    }
    catch {
        Write-TemplateLog "$HookName hook failed: $($_.Exception.Message)" -Level Warning
    }
}

function Invoke-ModuleRemediation {
    # Microsoft.WinGet.Client path: the winget CLI is NOT supported in the SYSTEM context that Intune
    # Proactive Remediations run in.
    [CmdletBinding()]
    param()

    Write-TemplateLog 'Using Microsoft.WinGet.Client module.' -Level Info
    $package = Get-WinGetPackage -Id $ID -MatchOption EqualsCaseInsensitive -ErrorAction SilentlyContinue

    # Auto-detect name if not provided
    if (-not $name) {
        $name = if ($package -and $package.Name) { $package.Name } else { $ID }
    }

    # Check if package is installed
    if (-not $package) {
        Write-TemplateLog "$name is not installed on this device." -Level Info
        Write-Host "[+] $name is not installed on this device." -ForegroundColor Green
        return 0
    }

    # Auto-detect process name if not provided
    if (-not $AppProcess) {
        $AppProcess = ($ID -split '\.')[-1]
    }

    # Check if update is available (idempotent converged path)
    if (-not $package.IsUpdateAvailable) {
        Write-TemplateLog "$name is already up to date (version $($package.InstalledVersion))." -Level Info
        Write-Host "[+] Already up to date: $name (version $($package.InstalledVersion))." -ForegroundColor Green
        return 0
    }

    $verInstalled = $package.InstalledVersion
    $verAvailable = @($package.AvailableVersions)[-1]
    Write-TemplateLog "Update available for $name | Installed: $verInstalled | Available: $verAvailable" -Level Info

    # Handle running processes
    $process = Get-Process -Name $AppProcess -ErrorAction SilentlyContinue
    if ($process) {
        if ($ForceCloseInMaintenanceWindow) {
            Write-TemplateLog "$name is running. Force closing during maintenance window..." -Level Info
            Stop-ApplicationProcess -ProcessName $AppProcess
        }
        else {
            Write-TemplateLog "$name is running. Skipping update (force close disabled)." -Level Warning
            Write-Host "[!] $name is currently running. Skipping update." -ForegroundColor Yellow
            return 1
        }
    }
    else {
        Write-TemplateLog "$name is not currently running." -Level Info
    }

    # Execute pre-update hook if defined
    if ($PreUpdateScriptBlock) {
        Invoke-Hook -Hook $PreUpdateScriptBlock -HookName 'Pre-update'
    }

    # Perform upgrade via the module
    Write-TemplateLog "Installing $name update ($verInstalled -> $verAvailable)..." -Level Info
    Update-WinGetPackage -Id $ID -MatchOption EqualsCaseInsensitive -Mode Silent -Force -ErrorAction Stop

    # Wait for installation to complete (configurable, mockable delay)
    Write-TemplateLog "Waiting $VerifyWaitSeconds seconds for installation to complete..." -Level Info
    Start-Sleep -Seconds $VerifyWaitSeconds

    # Execute post-update hook if defined
    if ($PostUpdateScriptBlock) {
        Invoke-Hook -Hook $PostUpdateScriptBlock -HookName 'Post-update'
    }

    # Verify installation
    Write-TemplateLog 'Verifying installation...' -Level Info
    $verifyPackage = Get-WinGetPackage -Id $ID -MatchOption EqualsCaseInsensitive -ErrorAction SilentlyContinue
    if (-not $verifyPackage) {
        Write-TemplateLog "Failed to verify $name installation after update." -Level Error
        throw "Failed to verify $name installation after update."
    }

    Write-TemplateLog "$name updated successfully to version $($verifyPackage.InstalledVersion)." -Level Info
    Write-Host "[+] $name updated successfully to version $($verifyPackage.InstalledVersion)." -ForegroundColor Green
    return 0
}

function Invoke-CliFallbackRemediation {
    # Fallback path: winget.exe CLI, reached only when the Microsoft.WinGet.Client module is unavailable.
    [CmdletBinding()]
    param()

    Write-TemplateLog 'Microsoft.WinGet.Client module unavailable, falling back to winget.exe CLI.' -Level Warning

    # Get package information (exact ID match) through the retry harness + wrapper seam
    $packageInfo = Invoke-WingetWithRetry -Arguments @('list', '--exact', '--id', $ID,
        '--accept-source-agreements')

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
    if ($packageInfo -match 'No installed package found matching input criteria') {
        Write-TemplateLog "$name is not installed on this device." -Level Info
        Write-Host "[+] $name is not installed on this device." -ForegroundColor Green
        return 0
    }

    # Auto-detect process name if not provided
    if (-not $AppProcess) {
        $AppProcess = ($ID -split '\.')[-1]
    }

    # Check if update is available (idempotent converged path)
    if ($packageInfo -match '\bVersion\s+Available\b') {
        $verInstalled, $verAvailable = @(-split $packageInfo[-1])[-3, -2]
        Write-TemplateLog "Update available for $name | Installed: $verInstalled | Available: $verAvailable" -Level Info

        # Handle running processes
        $process = Get-Process -Name $AppProcess -ErrorAction SilentlyContinue
        if ($process) {
            if ($ForceCloseInMaintenanceWindow) {
                Write-TemplateLog "$name is running. Force closing during maintenance window..." -Level Info
                Stop-ApplicationProcess -ProcessName $AppProcess
            }
            else {
                Write-TemplateLog "$name is running. Skipping update (force close disabled)." -Level Warning
                Write-Host "[!] $name is currently running. Skipping update." -ForegroundColor Yellow
                return 1
            }
        }
        else {
            Write-TemplateLog "$name is not currently running." -Level Info
        }

        # Execute pre-update hook if defined
        if ($PreUpdateScriptBlock) {
            Invoke-Hook -Hook $PreUpdateScriptBlock -HookName 'Pre-update'
        }

        # Perform upgrade through the retry harness + wrapper seam
        Write-TemplateLog "Installing $name update ($verInstalled -> $verAvailable)..." -Level Info
        $null = Invoke-WingetWithRetry -Arguments @('upgrade', '-e', '--id', $ID, '--silent',
            '--accept-package-agreements', '--accept-source-agreements')

        # Wait for installation to complete (configurable, mockable delay)
        Write-TemplateLog "Waiting $VerifyWaitSeconds seconds for installation to complete..." -Level Info
        Start-Sleep -Seconds $VerifyWaitSeconds

        # Execute post-update hook if defined
        if ($PostUpdateScriptBlock) {
            Invoke-Hook -Hook $PostUpdateScriptBlock -HookName 'Post-update'
        }

        # Verify installation
        Write-TemplateLog 'Verifying installation...' -Level Info
        $verifyInfo = Invoke-WingetWithRetry -Arguments @('list', '--exact', '--id', $ID,
            '--accept-source-agreements')
        if ($verifyInfo -match '\d+(\.\d+)+') {
            $versionInstalled = @(-split $verifyInfo[-1])[-2]
            Write-TemplateLog "$name updated successfully to version $versionInstalled." -Level Info
            Write-Host "[+] $name updated successfully to version $versionInstalled." -ForegroundColor Green
            return 0
        }

        Write-TemplateLog "Failed to verify $name installation after update." -Level Error
        throw "Failed to verify $name installation after update."
    }

    if ($packageInfo -match '\d+(\.\d+)+') {
        $versionInstalled = @(-split $packageInfo[-1])[-2]
        Write-TemplateLog "$name is already up to date (version $versionInstalled)." -Level Info
        Write-Host "[+] Already up to date: $name (version $versionInstalled)." -ForegroundColor Green
        return 0
    }

    throw "Unable to determine the winget state of $name."
}

function Main {
    try {
        Write-TemplateLog "=== Starting winget maintenance window remediation for package: $ID ===" -Level Info

        # Gate the entire remediation on the maintenance-window check (mockable function).
        if (-not (Test-MaintenanceWindow)) {
            Write-TemplateLog 'Outside maintenance window. Update will not be performed.' -Level Info
            $windowDays = $MaintenanceWindowDays -join ', '
            $hours = "$MaintenanceWindowStartHour`:00-$MaintenanceWindowEndHour`:00"
            $windowText = "$windowDays between $hours"
            Write-Host "[!] Outside maintenance window. Updates only run during: $windowText" -ForegroundColor Yellow
            return 0
        }

        # Prefer the Microsoft.WinGet.Client module - the winget CLI is NOT supported in the SYSTEM
        # context (Intune Proactive Remediations run as SYSTEM). Only fall back to the winget.exe CLI
        # when the module is unavailable.
        # Reference: https://learn.microsoft.com/en-us/windows/package-manager/winget/troubleshooting
        if (Get-Module -ListAvailable -Name Microsoft.WinGet.Client) {
            try {
                Import-Module Microsoft.WinGet.Client -ErrorAction Stop
            }
            catch {
                Write-Verbose "Handled exception: $($_.Exception.Message)" -Verbose:$false
            }
            if (Get-Command Get-WinGetPackage -ErrorAction SilentlyContinue) {
                return Invoke-ModuleRemediation
            }
        }

        return Invoke-CliFallbackRemediation
    }
    catch {
        Write-Host "[-] Error: $($_.Exception.Message)" -ForegroundColor Red
        Write-TemplateLog "ERROR: Failed to update ${name} : $($_.Exception.Message)" -Level Warning
        return 1
    }
    finally {
        Write-TemplateLog '=== Remediation script completed ===' -Level Info
    }
}
#endregion

# Execute only when run as a script; dot-sourcing (Pester tests) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
