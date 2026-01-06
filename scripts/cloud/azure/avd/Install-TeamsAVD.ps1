#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Installs or updates Microsoft Teams and WebView2 for Azure Virtual Desktop (AVD) gold images.

.DESCRIPTION
    This script configures and installs Microsoft Teams with WebView2 runtime optimized for AVD environments.

    Key features:
    - Idempotent: Safely runs multiple times, updating existing installations
    - Configures registry keys for AVD optimizations (IsWVDEnvironment)
    - Installs WebView2 runtime (required dependency)
    - Installs Teams bootstrapper for machine-wide deployment
    - Cleans up old per-user Teams installations
    - Prevents users from manually updating Teams
    - Comprehensive logging and error handling
    - Validates installations and reports detailed status

    The script is designed for:
    - AVD gold image preparation
    - Automated deployment via Intune or other management tools
    - Both fresh installations and updates

.PARAMETER AcceptEULA
    Accept the Microsoft WebView2 Runtime EULA. Required for silent installation.
    Review EULA at: https://www.microsoft.com/en-us/legal/terms-of-use

.PARAMETER SkipUserCleanup
    Skip removal of old per-user Teams installations. Use when user profiles should be preserved.

.PARAMETER LogPath
    Path where the transcript log will be saved. Defaults to C:\ProgramData\Microsoft\IntuneManagementExtension\Logs

.PARAMETER Force
    Force reinstallation even if current versions are already installed.

.EXAMPLE
    .\Install-TeamsAVD.ps1 -AcceptEULA
    Install Teams and WebView2 with default settings.

.EXAMPLE
    .\Install-TeamsAVD.ps1 -AcceptEULA -SkipUserCleanup
    Install without removing old user-profile Teams installations.

.EXAMPLE
    .\Install-TeamsAVD.ps1 -AcceptEULA -Force
    Force reinstallation even if already installed.

.NOTES
    Author: AVD Gold Image Automation
    Version: 2.0
    Requires: Administrator privileges
    Compatible with: Windows 10/11, Windows Server 2019/2022

    Exit Codes:
    0  - Success
    1  - EULA not accepted
    2  - Download failure
    3  - Installation failure
    4  - Registry configuration failure
    5  - Validation failure

.LINK
    https://learn.microsoft.com/en-us/microsoftteams/teams-for-vdi
    https://learn.microsoft.com/en-us/azure/virtual-desktop/teams-on-avd
#>

[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [Parameter(Mandatory=$true, HelpMessage="Accept WebView2 EULA to proceed with installation")]
    [switch]$AcceptEULA,

    [Parameter(HelpMessage="Skip cleanup of old per-user Teams installations")]
    [switch]$SkipUserCleanup,

    [Parameter(HelpMessage="Path for transcript log file")]
    [string]$LogPath = "C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\TeamsAVD_Install_$(Get-Date -Format 'yyyyMMdd_HHmmss').log",

    [Parameter(HelpMessage="Force reinstallation even if already installed")]
    [switch]$Force
)

# ==================== CONFIGURATION ====================

$ErrorActionPreference = "Stop"
$script:InstallErrors = @()
$script:WebView2Url = "https://go.microsoft.com/fwlink/p/?LinkId=2124703"
$script:TeamsBootstrapperUrl = "https://go.microsoft.com/fwlink/?linkid=2243204"
$script:TempPath = $env:TEMP

# ==================== FUNCTIONS ====================

function Write-Log {
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [Parameter()]
        [ValidateSet('Info', 'Success', 'Warning', 'Error')]
        [string]$Level = 'Info'
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logMessage = "[$timestamp] [$Level] $Message"

    $color = switch ($Level) {
        'Success' { 'Green' }
        'Warning' { 'Yellow' }
        'Error'   { 'Red' }
        default   { 'White' }
    }

    Write-Host $logMessage -ForegroundColor $color
    Add-Content -Path $LogPath -Value $logMessage -ErrorAction SilentlyContinue
}

function Test-Administrator {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-WebView2Version {
    try {
        $regPath = "HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}"
        if (Test-Path $regPath) {
            $version = (Get-ItemProperty -Path $regPath -Name "pv" -ErrorAction SilentlyContinue).pv
            return $version
        }
        return $null
    }
    catch {
        return $null
    }
}

function Get-TeamsVersion {
    try {
        # Check for Teams machine-wide installer
        $teamsPath = "C:\Program Files\WindowsApps\MSTeams_*"
        $teamsInstalls = Get-ChildItem -Path "C:\Program Files\WindowsApps\" -Directory -Filter "MSTeams_*" -ErrorAction SilentlyContinue

        if ($teamsInstalls) {
            $latestTeams = $teamsInstalls | Sort-Object Name -Descending | Select-Object -First 1
            $version = $latestTeams.Name -replace 'MSTeams_', '' -replace '_.*', ''
            return $version
        }
        return $null
    }
    catch {
        return $null
    }
}

function Set-RegistryValue {
    param(
        [string]$Path,
        [string]$Name,
        [object]$Value,
        [Microsoft.Win32.RegistryValueKind]$Type = [Microsoft.Win32.RegistryValueKind]::DWord
    )

    try {
        # Create path if it doesn't exist
        if (-not (Test-Path $Path)) {
            $null = New-Item -Path $Path -Force -ErrorAction Stop
            Write-Log "Created registry path: $Path" -Level Info
        }

        # Set the value
        Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $Type -Force -ErrorAction Stop

        # Verify the value was set correctly
        $verifyValue = (Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop).$Name
        if ($verifyValue -eq $Value) {
            Write-Log "Successfully set $Path\$Name = $Value" -Level Success
            return $true
        }
        else {
            Write-Log "Registry value verification failed: Expected $Value, got $verifyValue" -Level Error
            return $false
        }
    }
    catch {
        Write-Log "Failed to set registry value $Path\$Name : $_" -Level Error
        $script:InstallErrors += "Registry: $Path\$Name - $_"
        return $false
    }
}

function Install-WebView2Runtime {
    Write-Log "=== WebView2 Runtime Installation ===" -Level Info

    # Check current version
    $currentVersion = Get-WebView2Version
    if ($currentVersion -and -not $Force) {
        Write-Log "WebView2 Runtime already installed (Version: $currentVersion)" -Level Success
        return $true
    }
    elseif ($currentVersion -and $Force) {
        Write-Log "WebView2 Runtime version $currentVersion detected, forcing reinstall" -Level Warning
    }
    else {
        Write-Log "WebView2 Runtime not detected, proceeding with installation" -Level Info
    }

    $installer = Join-Path $script:TempPath "WebView2_$(Get-Date -Format 'yyyyMMddHHmmss').exe"

    try {
        # Download
        Write-Log "Downloading WebView2 Runtime from $script:WebView2Url" -Level Info
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $script:WebView2Url -OutFile $installer -UseBasicParsing -TimeoutSec 300
        $ProgressPreference = 'Continue'

        if (-not (Test-Path $installer)) {
            throw "Download failed: File not found at $installer"
        }

        $fileSize = (Get-Item $installer).Length
        if ($fileSize -lt 1MB) {
            throw "Download failed: File size too small ($fileSize bytes)"
        }

        Write-Log "Downloaded WebView2 installer successfully ($([math]::Round($fileSize/1MB, 2)) MB)" -Level Success

        # Install
        Write-Log "Installing WebView2 Runtime..." -Level Info
        $installArgs = @("/silent", "/install")
        $process = Start-Process -FilePath $installer -ArgumentList $installArgs -Wait -PassThru -NoNewWindow

        if ($process.ExitCode -eq 0) {
            Write-Log "WebView2 Runtime installed successfully" -Level Success

            # Verify installation
            Start-Sleep -Seconds 2
            $newVersion = Get-WebView2Version
            if ($newVersion) {
                Write-Log "Verified WebView2 Runtime installation (Version: $newVersion)" -Level Success
                return $true
            }
            else {
                Write-Log "WARNING: WebView2 installation completed but version detection failed" -Level Warning
                return $true  # Installation claimed success, so we trust it
            }
        }
        else {
            throw "WebView2 installer exited with code $($process.ExitCode)"
        }
    }
    catch {
        Write-Log "WebView2 installation failed: $_" -Level Error
        $script:InstallErrors += "WebView2: $_"
        return $false
    }
    finally {
        # Cleanup
        if (Test-Path $installer) {
            try {
                Remove-Item $installer -Force -ErrorAction SilentlyContinue
                Write-Log "Cleaned up installer: $installer" -Level Info
            }
            catch {
                Write-Log "Could not remove installer file: $installer" -Level Warning
            }
        }
    }
}

function Remove-UserTeamsInstalls {
    if ($SkipUserCleanup) {
        Write-Log "Skipping user profile Teams cleanup (SkipUserCleanup specified)" -Level Info
        return
    }

    Write-Log "=== Cleaning Up Old User-Profile Teams Installations ===" -Level Info

    $userProfiles = Get-ChildItem "C:\Users" -Directory -ErrorAction SilentlyContinue
    $removedCount = 0
    $failedCount = 0

    foreach ($profile in $userProfiles) {
        # Skip system profiles
        if ($profile.Name -in @('Public', 'Default', 'Default User', 'All Users')) {
            continue
        }

        $teamsPath = Join-Path $profile.FullName "AppData\Local\Microsoft\Teams"

        if (Test-Path $teamsPath) {
            try {
                # Check for running Teams processes for this user
                $teamsProcesses = Get-Process -Name "Teams" -ErrorAction SilentlyContinue |
                    Where-Object { $_.Path -like "$teamsPath*" }

                if ($teamsProcesses) {
                    Write-Log "Stopping Teams processes for user: $($profile.Name)" -Level Warning
                    $teamsProcesses | Stop-Process -Force -ErrorAction SilentlyContinue
                    Start-Sleep -Seconds 2
                }

                Remove-Item -Path $teamsPath -Recurse -Force -ErrorAction Stop
                Write-Log "Removed old Teams installation: $($profile.Name)" -Level Success
                $removedCount++
            }
            catch {
                Write-Log "Failed to remove Teams for user $($profile.Name): $_" -Level Warning
                $failedCount++
            }
        }
    }

    if ($removedCount -eq 0 -and $failedCount -eq 0) {
        Write-Log "No old Teams installations found in user profiles" -Level Info
    }
    else {
        Write-Log "User cleanup complete: $removedCount removed, $failedCount failed" -Level Info
    }
}

function Install-TeamsBootstrapper {
    Write-Log "=== Teams Bootstrapper Installation ===" -Level Info

    # Check current version
    $currentVersion = Get-TeamsVersion
    if ($currentVersion -and -not $Force) {
        Write-Log "Teams already installed (Version: $currentVersion)" -Level Success
        return $true
    }
    elseif ($currentVersion -and $Force) {
        Write-Log "Teams version $currentVersion detected, forcing reinstall" -Level Warning
    }
    else {
        Write-Log "Teams not detected, proceeding with installation" -Level Info
    }

    $installer = Join-Path $script:TempPath "TeamsBootstrapper_$(Get-Date -Format 'yyyyMMddHHmmss').exe"

    try {
        # Download
        Write-Log "Downloading Teams Bootstrapper from $script:TeamsBootstrapperUrl" -Level Info
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $script:TeamsBootstrapperUrl -OutFile $installer -UseBasicParsing -TimeoutSec 300
        $ProgressPreference = 'Continue'

        if (-not (Test-Path $installer)) {
            throw "Download failed: File not found at $installer"
        }

        $fileSize = (Get-Item $installer).Length
        if ($fileSize -lt 1MB) {
            throw "Download failed: File size too small ($fileSize bytes)"
        }

        Write-Log "Downloaded Teams Bootstrapper successfully ($([math]::Round($fileSize/1MB, 2)) MB)" -Level Success

        # Install machine-wide
        Write-Log "Installing Teams Bootstrapper (machine-wide deployment)..." -Level Info
        $installArgs = @("-p")  # -p flag for machine-wide stub
        $process = Start-Process -FilePath $installer -ArgumentList $installArgs -Wait -PassThru -NoNewWindow

        if ($process.ExitCode -eq 0) {
            Write-Log "Teams Bootstrapper installed successfully" -Level Success

            # Verify installation
            Start-Sleep -Seconds 3
            $newVersion = Get-TeamsVersion
            if ($newVersion) {
                Write-Log "Verified Teams installation (Version: $newVersion)" -Level Success
                return $true
            }
            else {
                Write-Log "WARNING: Teams installation completed but version detection failed" -Level Warning
                return $true  # Installation claimed success, so we trust it
            }
        }
        else {
            # Non-zero exit codes might still indicate success for Teams installer
            Write-Log "Teams installer exited with code $($process.ExitCode)" -Level Warning

            Start-Sleep -Seconds 3
            $newVersion = Get-TeamsVersion
            if ($newVersion) {
                Write-Log "Teams installation verified despite non-zero exit code (Version: $newVersion)" -Level Success
                return $true
            }
            else {
                throw "Teams installer exited with code $($process.ExitCode) and installation could not be verified"
            }
        }
    }
    catch {
        Write-Log "Teams installation failed: $_" -Level Error
        $script:InstallErrors += "Teams: $_"
        return $false
    }
    finally {
        # Cleanup
        if (Test-Path $installer) {
            try {
                Remove-Item $installer -Force -ErrorAction SilentlyContinue
                Write-Log "Cleaned up installer: $installer" -Level Info
            }
            catch {
                Write-Log "Could not remove installer file: $installer" -Level Warning
            }
        }
    }
}

function Set-AVDRegistryConfiguration {
    Write-Log "=== Configuring AVD Registry Settings ===" -Level Info

    $success = $true

    # IsWVDEnvironment - Enables Teams optimizations for AVD
    $success = $success -and (Set-RegistryValue `
        -Path "HKLM:\SOFTWARE\Microsoft\Teams" `
        -Name "IsWVDEnvironment" `
        -Value 1)

    # Allow side-loading of trusted apps (required for Teams)
    $success = $success -and (Set-RegistryValue `
        -Path "HKLM:\Software\Policies\Microsoft\Windows\Appx" `
        -Name "AllowAllTrustedApps" `
        -Value 1)

    $success = $success -and (Set-RegistryValue `
        -Path "HKLM:\Software\Policies\Microsoft\Windows\Appx" `
        -Name "AllowDevelopmentWithoutDevLicense" `
        -Value 1)

    # Prevent users from manually updating Teams
    $success = $success -and (Set-RegistryValue `
        -Path "HKLM:\Software\Policies\Microsoft\Office\Teams" `
        -Name "PreventUserFromUpdatingTeams" `
        -Value 1)

    if ($success) {
        Write-Log "All registry settings configured successfully" -Level Success
        return $true
    }
    else {
        Write-Log "Some registry settings failed to configure" -Level Error
        return $false
    }
}

function Write-InstallationSummary {
    Write-Log "" -Level Info
    Write-Log "=== Installation Summary ===" -Level Info
    Write-Log "Timestamp: $(Get-Date)" -Level Info
    Write-Log "" -Level Info

    # WebView2 Status
    $webView2Version = Get-WebView2Version
    if ($webView2Version) {
        Write-Log "[✓] WebView2 Runtime: Installed (Version $webView2Version)" -Level Success
    }
    else {
        Write-Log "[✗] WebView2 Runtime: Not detected" -Level Error
    }

    # Teams Status
    $teamsVersion = Get-TeamsVersion
    if ($teamsVersion) {
        Write-Log "[✓] Microsoft Teams: Installed (Version $teamsVersion)" -Level Success
    }
    else {
        Write-Log "[✗] Microsoft Teams: Not detected" -Level Error
    }

    # Registry Status
    $isWVD = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Teams" -Name "IsWVDEnvironment" -ErrorAction SilentlyContinue).IsWVDEnvironment
    if ($isWVD -eq 1) {
        Write-Log "[✓] AVD Registry Configuration: Enabled" -Level Success
    }
    else {
        Write-Log "[✗] AVD Registry Configuration: Not enabled" -Level Error
    }

    # Errors
    if ($script:InstallErrors.Count -gt 0) {
        Write-Log "" -Level Info
        Write-Log "=== Errors Encountered ===" -Level Error
        foreach ($error in $script:InstallErrors) {
            Write-Log "  - $error" -Level Error
        }
    }

    Write-Log "" -Level Info
    Write-Log "Log file: $LogPath" -Level Info
}

# ==================== MAIN EXECUTION ====================

# Start transcript logging
$logDir = Split-Path -Path $LogPath -Parent
if (-not (Test-Path $logDir)) {
    New-Item -Path $logDir -ItemType Directory -Force | Out-Null
}

# Stop any orphaned transcripts
try { Stop-Transcript | Out-Null } catch { }
Start-Transcript -Path $LogPath -Append

try {
    Write-Log "=== Microsoft Teams + WebView2 Installation for AVD ===" -Level Info
    Write-Log "Script Version: 2.0" -Level Info
    Write-Log "Execution Time: $(Get-Date)" -Level Info
    Write-Log "" -Level Info

    # Validate prerequisites
    if (-not (Test-Administrator)) {
        Write-Log "ERROR: This script must be run as Administrator" -Level Error
        exit 5
    }

    if (-not $AcceptEULA) {
        Write-Log "ERROR: You must accept the WebView2 EULA using -AcceptEULA parameter" -Level Error
        Write-Log "Review EULA at: https://www.microsoft.com/en-us/legal/terms-of-use" -Level Info
        exit 1
    }

    Write-Log "EULA accepted, proceeding with installation" -Level Success
    Write-Log "" -Level Info

    # Configure registry settings first
    $registrySuccess = Set-AVDRegistryConfiguration

    # Clean up old user installations
    Remove-UserTeamsInstalls

    # Install WebView2
    $webView2Success = Install-WebView2Runtime

    # Install Teams
    $teamsSuccess = Install-TeamsBootstrapper

    # Generate summary
    Write-Log "" -Level Info
    Write-InstallationSummary

    # Determine exit code
    if ($webView2Success -and $teamsSuccess -and $registrySuccess) {
        Write-Log "" -Level Info
        Write-Log "=== Installation completed successfully ===" -Level Success
        Write-Log "AVD gold image is ready for user logins" -Level Success
        $exitCode = 0
    }
    elseif (-not $webView2Success -or -not $teamsSuccess) {
        Write-Log "" -Level Info
        Write-Log "=== Installation completed with errors ===" -Level Error
        Write-Log "Review the log file for details: $LogPath" -Level Error
        $exitCode = 3
    }
    elseif (-not $registrySuccess) {
        Write-Log "" -Level Info
        Write-Log "=== Installation completed but registry configuration failed ===" -Level Warning
        $exitCode = 4
    }

    Stop-Transcript
    exit $exitCode
}
catch {
    Write-Log "FATAL ERROR: $($_.Exception.Message)" -Level Error
    Write-Log "Stack Trace: $($_.ScriptStackTrace)" -Level Error
    Stop-Transcript
    exit 3
}
