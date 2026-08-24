<#
.SYNOPSIS
    Enhanced standard winget update template with retry logic and logging (V3).

.DESCRIPTION
    This template checks if an app update is available and installs it.
    If the app is running, it will skip the update and retry later.
    It prefers the Microsoft.WinGet.Client PowerShell module (the winget CLI is NOT
    supported in the SYSTEM context that Intune Proactive Remediations run in) and
    falls back to the winget.exe CLI only when the module is unavailable.
    Exit codes follow the Intune remediation convention: 0 = updated, already up to date,
    or not installed; 1 = application running (update skipped) or the upgrade failed.
    V3 ENHANCEMENTS:
    - Retry logic with exponential backoff
    - Optional logging to file
    - Better error handling and status reporting
    - Configurable wait times (all delays run through Start-Sleep and are mockable in tests)
    - Pre/post update hooks
    - Microsoft.WinGet.Client module preferred over the winget.exe CLI (SYSTEM context safe)
    Template note (docs/RELAUNCH-SPEC.md section 6): examples below show placeholder
    configuration, which makes some help rules inapplicable until placeholders are replaced.
    Configuration:
    1. Set the $ID variable to your winget package ID
    2. (Optional) Enable logging and customize retry settings
    3. (Optional) Define pre/post update hooks for custom actions

.EXAMPLE
    PS C:\> .\remediate_v3_standard.ps1

    Runs the template directly against the placeholder configuration.

.EXAMPLE
    PS C:\> pwsh -NoProfile -File .\remediate_v3_standard.ps1

    Runs the template in a clean PowerShell process with retry and logging defaults;
    behavior and exit codes are unchanged.

.NOTES
    REQUIRED: Only the winget ID is required. The script will auto-detect app name and process.
    File Name  : remediate_v3_standard.ps1
    Author     : Bug-Free Umbrella
    Prerequisite: PowerShell 5.1+
    Version    : 1.0.0
    Date       : 2026-08-23
#>

[CmdletBinding()]
param()

# PSAvoidUsingWriteHost is intentionally accepted: prefixed, colored console output is the mandated
# output convention of docs/RELAUNCH-SPEC.md section 3.
# PSUseOutputTypeCorrectly is intentionally accepted: internal helper functions return plain
# values (bool/string/object[]) by design; only Main's exit code (int) is a public contract.
$ErrorActionPreference = 'Stop'

#region Configuration
# ===== REQUIRED: Set your winget package ID =====
$ID = 'WINGETID'  # Example: 'Google.Chrome', 'Microsoft.Teams', 'Slack.Slack'

# ===== OPTIONAL: Basic Settings =====
$name = $null           # Leave as $null to auto-detect from winget
$AppProcess = $null     # Leave as $null to auto-detect from package ID

# ===== OPTIONAL: Advanced Settings =====
$MaxRetries = 3                    # Number of retry attempts for winget operations
$RetryDelaySeconds = 2             # Initial delay between retries (doubles each retry; mockable)
$VerifyWaitSeconds = 5             # Time to wait after update before verification (mockable)
$EnableLogging = $false            # Set to $true to enable file logging
$LogPath = "C:\ProgramData\IntuneScripts\Logs\WingetRemediation_$ID.log"  # Log file path

# ===== OPTIONAL: Hooks for Custom Actions =====
$PreUpdateScriptBlock = $null      # Script block to run before update (e.g., { Stop-Service MyService })
$PostUpdateScriptBlock = $null     # Script block to run after update (e.g., { Start-Service MyService })
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

    # Check if app is running
    $process = Get-Process -Name $AppProcess -ErrorAction SilentlyContinue
    if ($process) {
        Write-TemplateLog "$name is currently running. Skipping update - will retry later." -Level Warning
        Write-Host "[!] $name is currently running. Will try again later." -ForegroundColor Yellow
        return 1
    }

    Write-TemplateLog "$name is not running. Proceeding with update..." -Level Info

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

        # Check if app is running
        $process = Get-Process -Name $AppProcess -ErrorAction SilentlyContinue
        if ($process) {
            Write-TemplateLog "$name is currently running. Skipping update - will retry later." -Level Warning
            Write-Host "[!] $name is currently running. Will try again later." -ForegroundColor Yellow
            return 1
        }

        Write-TemplateLog "$name is not running. Proceeding with update..." -Level Info

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
        Write-TemplateLog "=== Starting winget remediation for package: $ID ===" -Level Info

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
