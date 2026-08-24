#Requires -Version 7.0

<#
.SYNOPSIS
    Installs or updates Microsoft Teams and WebView2 for Azure Virtual Desktop (AVD) gold images.

.DESCRIPTION
    This script installs and configures Microsoft Teams with the WebView2 Runtime, optimized for
    Azure Virtual Desktop environments. Key features:
    - Idempotent: safely runs multiple times; a converged system exits 0 with no further changes
    - Configures registry keys for AVD optimizations (IsWVDEnvironment)
    - Installs the WebView2 Runtime (required dependency)
    - Installs the Teams bootstrapper for machine-wide deployment
    - Optionally installs the Remote Desktop WebRTC Redirector Service (recommended for new Teams
      media optimization fallback, see -InstallWebRtcRedirector)
    - Cleans up old per-user Teams installations
    - Prevents users from manually updating Teams
    - Validates downloads with Authenticode signatures before executing them
    - Comprehensive logging and error handling with detailed status reporting

    The script is designed for AVD gold image preparation and automated deployment via Intune or
    other management tools, supporting both fresh installations and forced updates.

    Destructive operations (stopping Teams processes, removing old per-user installs, registry and
    policy changes) honor -WhatIf/-Confirm via SupportsShouldProcess. Administrator privileges are
    required and enforced at runtime.

    Exit codes:
    - 0 : Success (all requested components installed/configured and verified)
    - 1 : EULA not accepted, or administrator privileges missing
    - 3 : Installation failure (download, signature validation, installer error, or fatal error)
    - 4 : Registry configuration failure

.PARAMETER AcceptEULA
    Accept the Microsoft WebView2 Runtime EULA. Required for silent installation.
    Review EULA at: https://www.microsoft.com/en-us/legal/terms-of-use

.PARAMETER SkipUserCleanup
    Skip removal of old per-user Teams installations. Use when user profiles should be preserved.

.PARAMETER LogPath
    Path where the transcript log will be saved. Defaults to
    C:\ProgramData\Microsoft\IntuneManagementExtension\Logs.

.PARAMETER Force
    Force reinstallation even if current versions are already installed.

.PARAMETER SkipSignatureCheck
    Skip Authenticode signature verification of downloaded files. Use only in trusted environments.

.PARAMETER InstallWebRtcRedirector
    Also download and install the Remote Desktop WebRTC Redirector Service MSI
    (https://aka.ms/msrdcwebrtcsvc/msi). Recommended for new Teams on AVD so calls can fall back to
    WebRTC when SlimCore is unavailable. Default: not installed.
    See https://learn.microsoft.com/en-us/azure/virtual-desktop/teams-on-avd

.EXAMPLE
    PS C:\> .\Install-TeamsAVD.ps1 -AcceptEULA
    Installs Teams and WebView2 with default settings.

.EXAMPLE
    PS C:\> .\Install-TeamsAVD.ps1 -AcceptEULA -SkipUserCleanup
    Installs without removing old user-profile Teams installations.

.EXAMPLE
    PS C:\> .\Install-TeamsAVD.ps1 -AcceptEULA -Force
    Forces reinstallation even if current versions are already installed.

.EXAMPLE
    PS C:\> .\Install-TeamsAVD.ps1 -AcceptEULA -InstallWebRtcRedirector -WhatIf
    Shows what the installation would do, including the WebRTC Redirector, without changing anything.

.NOTES
    File Name    : Install-TeamsAVD.ps1
    Author       : AVD Gold Image Automation
    Prerequisite : PowerShell 7.0
    Version      : 1.0.0
    Date         : 2026-08-23

.LINK
    https://learn.microsoft.com/en-us/microsoftteams/teams-for-vdi
    https://learn.microsoft.com/en-us/azure/virtual-desktop/teams-on-avd
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(HelpMessage = "Accept WebView2 EULA to proceed with installation")]
    [switch]$AcceptEULA,

    [Parameter(HelpMessage = "Skip cleanup of old per-user Teams installations")]
    [switch]$SkipUserCleanup,

    [Parameter(HelpMessage = "Path for transcript log file")]
    [string]$LogPath = "C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\`
        TeamsAVD_Install_$(Get-Date -Format 'yyyyMMdd_HHmmss').log",

    [Parameter(HelpMessage = "Force reinstallation even if already installed")]
    [switch]$Force,

    [Parameter(HelpMessage = "Skip Authenticode signature verification (use only in trusted environments)")]
    [switch]$SkipSignatureCheck,

    [Parameter(HelpMessage = "Also install the Remote Desktop WebRTC Redirector Service")]
    [switch]$InstallWebRtcRedirector
)

$ErrorActionPreference = 'Stop'

# ==================== CONFIGURATION ====================
$script:InstallErrors = @()
$script:WebView2Url = "https://go.microsoft.com/fwlink/p/?LinkId=2124703"
$script:TeamsBootstrapperUrl = "https://go.microsoft.com/fwlink/?linkid=2243204"
$script:WebRtcRedirectorUrl = "https://aka.ms/msrdcwebrtcsvc/msi"
$script:WebRtcRedirectorInstallPath = "C:\Program Files\Remote Desktop Services\TeamsWebRTC\TeamsWebRTCService.exe"
$script:TempPath = $env:TEMP

# Known successful exit codes for installers (0 = success, 3010 = success but reboot required)
$script:AcceptableExitCodes = @(0, 3010)
$script:TempPath = if ($env:TEMP) { $env:TEMP } else { [System.IO.Path]::GetTempPath() }

# Version detection retry configuration
$script:MaxRetries = 5
$script:InitialRetryDelay = 2  # seconds

# ==================== FUNCTIONS ====================

function Write-Banner {
    [CmdletBinding()]
    param()
    $banner = @"

 ==============================================================
   AVD Gold Image Installer v1.0.0
   Installing Microsoft Teams + WebView2 for Azure Virtual Desktop
   Production-ready error handling & validation
 ==============================================================

"@
    Write-Host $banner -ForegroundColor Cyan
}

function Write-Log {
    param(
        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$Message = "",

        [Parameter()]
        [ValidateSet('Info', 'Success', 'Warning', 'Error', 'Header')]
        [string]$Level = 'Info'
    )

    # Handle empty messages for blank lines
    if ([string]::IsNullOrEmpty($Message)) {
        Write-Host ""
        Add-Content -Path $LogPath -Value "" -ErrorAction SilentlyContinue
        return
    }

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logMessage = "[$timestamp] [$Level] $Message"

    $color = switch ($Level) {
        'Success' { 'Green' }
        'Warning' { 'Yellow' }
        'Error' { 'Red' }
        'Header' { 'Cyan' }
        default { 'Cyan' }
    }

    $prefix = switch ($Level) {
        'Success' { '[+]' }
        'Warning' { '[!]' }
        'Error' { '[-]' }
        'Header' { '[*]' }
        default { '[*]' }
    }

    $displayMessage = "$prefix $Message"
    Write-Host $displayMessage -ForegroundColor $color
    Add-Content -Path $LogPath -Value $logMessage -ErrorAction SilentlyContinue
}

function Test-FileSignature {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$FilePath
    )

    if ($SkipSignatureCheck) {
        Write-Log "Signature check skipped by user request" -Level Warning
        return $true
    }

    try {
        $signature = Get-AuthenticodeSignature -FilePath $FilePath -ErrorAction Stop

        if ($signature.Status -eq 'Valid') {
            Write-Log "Authenticode signature valid: $($signature.SignerCertificate.Subject)" -Level Success
            return $true
        }
        elseif ($signature.Status -eq 'NotSigned') {
            Write-Log "File is not digitally signed" -Level Warning
            Write-Log "File: $FilePath" -Level Warning
            Write-Log "Use -SkipSignatureCheck to bypass (not recommended)" -Level Warning
            return $false
        }
        else {
            Write-Log "Invalid signature status: $($signature.Status)" -Level Error
            Write-Log "Status message: $($signature.StatusMessage)" -Level Error
            return $false
        }
    }
    catch {
        Write-Log "Signature verification failed: $_" -Level Error
        return $false
    }
}

function Get-WebView2Version {
    [OutputType([string])]
    param()

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
    [OutputType([string])]
    param()

    try {
        $teamsInstalls = Get-ChildItem -Path "C:\Program Files\WindowsApps\" -Directory `
            -Filter "MSTeams_*" -ErrorAction SilentlyContinue

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

function Wait-ForVersionDetection {
    param(
        [Parameter(Mandatory)]
        [scriptblock]$VersionCheck,

        [Parameter(Mandatory)]
        [string]$ComponentName
    )

    Write-Log "Waiting for $ComponentName version detection..." -Level Info

    $retryCount = 0
    $delay = $script:InitialRetryDelay

    while ($retryCount -lt $script:MaxRetries) {
        Start-Sleep -Seconds $delay

        $version = & $VersionCheck
        if ($version) {
            Write-Log "Detected $ComponentName version: $version" -Level Success
            return $version
        }

        $retryCount++
        if ($retryCount -lt $script:MaxRetries) {
            Write-Log "Version not detected yet, retrying in $delay seconds... `
                (Attempt $($retryCount + 1)/$script:MaxRetries)" -Level Warning
            $delay = [math]::Min($delay * 2, 30)  # Exponential backoff, max 30 seconds
        }
    }

    Write-Log "Version detection failed after $script:MaxRetries attempts" -Level Warning
    return $null
}

function Set-RegistryValue {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$Path,
        [string]$Name,
        [object]$Value
    )

    try {
        # Idempotency: skip mutation when the desired value is already present
        $existing = (Get-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue).$Name
        if ($existing -eq $Value) {
            Write-Log "Already configured: $Path\$Name = $Value" -Level Success
            return $true
        }

        # Create path if it doesn't exist
        if (-not (Test-Path $Path)) {
            if ($PSCmdlet.ShouldProcess($Path, 'Create registry path')) {
                $null = New-Item -Path $Path -Force -ErrorAction Stop
                Write-Log "Created registry path: $Path" -Level Info
            }
        }

        # Set the value
        if ($PSCmdlet.ShouldProcess("$Path\$Name", 'Set registry value')) {
            Set-ItemProperty -Path $Path -Name $Name -Value $Value -Force -ErrorAction Stop

            # Verify the value was set correctly
            $verifyValue = (Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop).$Name
            if ($verifyValue -eq $Value) {
                Write-Log "Registry: $Path\$Name = $Value" -Level Success
                return $true
            }
            else {
                Write-Log "Registry verification failed: Expected $Value, got $verifyValue" -Level Error
                return $false
            }
        }
        else {
            return $false
        }
    }
    catch {
        Write-Log "Failed to set registry value $Path\$Name : $_" -Level Error
        $script:InstallErrors += "Registry: $Path\$Name - $_"
        return $false
    }
}

function Stop-TeamsProcessGracefully {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [System.Diagnostics.Process[]]$Processes,

        [Parameter(Mandatory)]
        [string]$UserName
    )

    Write-Log "Found $($Processes.Count) Teams process(es) for user: $UserName" -Level Warning

    foreach ($userProcess in $Processes) {
        try {
            Write-Log "Requesting graceful shutdown of Teams (PID: $($userProcess.Id))..." -Level Info

            # Try CloseMainWindow first (graceful shutdown)
            if ($userProcess.CloseMainWindow()) {
                Write-Log "Sent close request to Teams process" -Level Info
                $waitResult = $userProcess.WaitForExit(10000)  # Wait up to 10 seconds

                if ($waitResult) {
                    Write-Log "Teams process closed gracefully" -Level Success
                    continue
                }
                else {
                    Write-Log "Process did not exit after 10 seconds, forcing termination" -Level Warning
                }
            }

            # If graceful shutdown failed, force kill
            if ($PSCmdlet.ShouldProcess("Teams process (PID: $($userProcess.Id))", 'Stop process')) {
                Write-Log "Force terminating Teams process (PID: $($userProcess.Id))" -Level Warning
                $userProcess.Kill()
                $userProcess.WaitForExit(5000)
                Write-Log "Teams process terminated" -Level Info
            }
        }
        catch {
            Write-Log "Failed to stop Teams process: $_" -Level Warning
        }
    }

    # Final wait to ensure file locks are released
    Start-Sleep -Seconds 2
}

function Get-UserProfilesList {
    # Thin wrapper around Get-ChildItem for C:\Users discovery; mock seam for tests.
    [CmdletBinding()]
    [OutputType([System.IO.DirectoryInfo])]
    param()

    return Get-ChildItem "C:\Users" -Directory -ErrorAction SilentlyContinue
}

function Invoke-InstallerDownload {
    # Thin wrapper around Invoke-WebRequest for installer downloads; mock seam for tests.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Uri,

        [Parameter(Mandatory)]
        [string]$OutFile
    )

    # PowerShell 7.4 renamed -TimeoutSec to -ConnectionTimeoutSeconds
    $timeoutParam = if ((Get-Command Invoke-WebRequest).Parameters.ContainsKey('ConnectionTimeoutSeconds')) {
        @{ ConnectionTimeoutSeconds = 300 }
    }
    else {
        @{ TimeoutSec = 300 }
    }

    Invoke-WebRequest -Uri $Uri -OutFile $OutFile -UseBasicParsing @timeoutParam -ErrorAction Stop
}

function Start-InstallerProcess {
    # Thin wrapper around Start-Process for native installers (MSI packages, bootstrapper EXEs).
    # Exists as the mock seam for Pester: tests mock this function, never the native executable.
    [CmdletBinding()]
    [OutputType([System.Diagnostics.Process])]
    param(
        [Parameter(Mandatory)]
        [string]$FilePath,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]]$ArgumentList
    )

    return Start-Process -FilePath $FilePath -ArgumentList $ArgumentList -Wait -PassThru -NoNewWindow -ErrorAction Stop
}

function Install-WebView2Runtime {
    [CmdletBinding()]
    param()
    Write-Log ""
    Write-Log "=== WebView2 Runtime Installation ===" -Level Header

    # Check current version
    $currentVersion = Get-WebView2Version
    if ($currentVersion -and -not $Force) {
        Write-Log "WebView2 Runtime already installed (Version: $currentVersion)" -Level Success
        Write-Log "Use -Force to reinstall" -Level Info
        return $true
    }
    elseif ($currentVersion -and $Force) {
        Write-Log "Current version: $currentVersion - forcing reinstall" -Level Warning
    }
    else {
        Write-Log "WebView2 Runtime not detected, proceeding with installation" -Level Info
    }

    $installer = Join-Path $script:TempPath "WebView2_$(Get-Date -Format 'yyyyMMddHHmmss').exe"
    $progressPreference = $ProgressPreference

    try {
        # Download
        Write-Log "Downloading WebView2 Runtime..." -Level Info
        $ProgressPreference = 'SilentlyContinue'
        Invoke-InstallerDownload -Uri $script:WebView2Url -OutFile $installer

        if (-not (Test-Path $installer)) {
            throw "Download failed: File not found at $installer"
        }

        $fileSize = (Get-Item $installer).Length
        if ($fileSize -lt 1MB) {
            throw "Download failed: File size too small ($fileSize bytes)"
        }

        Write-Log "Downloaded successfully ($([math]::Round($fileSize/1MB, 2)) MB)" -Level Success

        # Verify signature
        Write-Log "Verifying Authenticode signature..." -Level Info
        if (-not (Test-FileSignature -FilePath $installer)) {
            throw "Signature verification failed - file may be compromised"
        }

        # Install
        Write-Log "Installing WebView2 Runtime (silent mode)..." -Level Info
        $installArgs = @("/silent", "/install")
        $process = Start-InstallerProcess -FilePath $installer -ArgumentList $installArgs

        if ($process.ExitCode -in $script:AcceptableExitCodes) {
            Write-Log "Installer completed with exit code: $($process.ExitCode)" -Level Success

            # Verify installation with retry logic
            $newVersion = Wait-ForVersionDetection -VersionCheck ${function:Get-WebView2Version} `
                -ComponentName "WebView2"

            if ($newVersion) {
                Write-Log "WebView2 Runtime installation verified" -Level Success
                return $true
            }
            else {
                Write-Log "Installation may have succeeded but version detection failed" -Level Warning
                return $true  # Trust installer exit code
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
        # Always restore ProgressPreference
        $ProgressPreference = $progressPreference

        # Cleanup
        if (Test-Path $installer) {
            try {
                Remove-Item $installer -Force -ErrorAction SilentlyContinue
                Write-Log "Cleaned up installer file" -Level Info
            }
            catch {
                Write-Log "Could not remove installer: $installer" -Level Warning
            }
        }
    }
}

function Remove-UserTeamsInstalls {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    if ($SkipUserCleanup) {
        Write-Log "User profile cleanup skipped (SkipUserCleanup parameter)" -Level Info
        return
    }

    Write-Log ""
    Write-Log "=== Cleaning Up User-Profile Teams ===" -Level Header

    $userProfiles = Get-UserProfilesList
    $removedCount = 0
    $failedCount = 0

    foreach ($userProfile in $userProfiles) {
        # Skip system profiles
        if ($userProfile.Name -in @('Public', 'Default', 'Default User', 'All Users')) {
            continue
        }

        $teamsPath = Join-Path $userProfile.FullName "AppData\Local\Microsoft\Teams"

        if (Test-Path $teamsPath) {
            try {
                # Check for running Teams processes
                $teamsProcesses = Get-Process -Name "Teams" -ErrorAction SilentlyContinue |
                    Where-Object { $_.Path -like "$teamsPath*" }

                if ($teamsProcesses) {
                    Stop-TeamsProcessGracefully -Processes $teamsProcesses -UserName $userProfile.Name
                }

                if ($PSCmdlet.ShouldProcess($teamsPath, 'Remove Teams installation')) {
                    Remove-Item -Path $teamsPath -Recurse -Force -ErrorAction Stop
                    Write-Log "Removed Teams from user: $($userProfile.Name)" -Level Success
                    $removedCount++
                }
            }
            catch {
                Write-Log "Failed to remove Teams for user $($userProfile.Name): $_" -Level Warning
                $failedCount++
            }
        }
    }

    if ($removedCount -eq 0 -and $failedCount -eq 0) {
        Write-Log "No old Teams installations found" -Level Success
    }
    else {
        Write-Log "Cleanup complete: $removedCount removed, $failedCount failed" -Level Info
    }
}

function Install-TeamsBootstrapper {
    [CmdletBinding()]
    param()
    Write-Log ""
    Write-Log "=== Teams Bootstrapper Installation ===" -Level Header

    # Check current version
    $currentVersion = Get-TeamsVersion
    if ($currentVersion -and -not $Force) {
        Write-Log "Teams already installed (Version: $currentVersion)" -Level Success
        Write-Log "Use -Force to reinstall" -Level Info
        return $true
    }
    elseif ($currentVersion -and $Force) {
        Write-Log "Current version: $currentVersion - forcing reinstall" -Level Warning
    }
    else {
        Write-Log "Teams not detected, proceeding with installation" -Level Info
    }

    $installer = Join-Path $script:TempPath "TeamsBootstrapper_$(Get-Date -Format 'yyyyMMddHHmmss').exe"
    $progressPreference = $ProgressPreference

    try {
        # Download
        Write-Log "Downloading Teams Bootstrapper..." -Level Info
        $ProgressPreference = 'SilentlyContinue'
        Invoke-InstallerDownload -Uri $script:TeamsBootstrapperUrl -OutFile $installer

        if (-not (Test-Path $installer)) {
            throw "Download failed: File not found at $installer"
        }

        $fileSize = (Get-Item $installer).Length
        if ($fileSize -lt 1MB) {
            throw "Download failed: File size too small ($fileSize bytes)"
        }

        Write-Log "Downloaded successfully ($([math]::Round($fileSize/1MB, 2)) MB)" -Level Success

        # Verify signature
        Write-Log "Verifying Authenticode signature..." -Level Info
        if (-not (Test-FileSignature -FilePath $installer)) {
            throw "Signature verification failed - file may be compromised"
        }

        # Install machine-wide
        Write-Log "Installing Teams (machine-wide deployment)..." -Level Info
        $installArgs = @("-p")  # -p flag for machine-wide stub
        $process = Start-InstallerProcess -FilePath $installer -ArgumentList $installArgs

        # Teams installer sometimes returns non-zero codes even on success
        if ($process.ExitCode -in $script:AcceptableExitCodes) {
            Write-Log "Installer completed with exit code: $($process.ExitCode)" -Level Success
        }
        else {
            Write-Log "Installer exited with code $($process.ExitCode) - verifying installation" -Level Warning
        }

        # Verify installation with retry logic
        $newVersion = Wait-ForVersionDetection -VersionCheck ${function:Get-TeamsVersion} -ComponentName "Teams"

        if ($newVersion) {
            Write-Log "Teams installation verified successfully" -Level Success
            return $true
        }
        elseif ($process.ExitCode -in $script:AcceptableExitCodes) {
            Write-Log "Installer reported success but version not detected" -Level Warning
            return $true  # Trust installer
        }
        else {
            throw "Teams installer exited with code $($process.ExitCode) and installation could not be verified"
        }
    }
    catch {
        Write-Log "Teams installation failed: $_" -Level Error
        $script:InstallErrors += "Teams: $_"
        return $false
    }
    finally {
        # Always restore ProgressPreference
        $ProgressPreference = $progressPreference

        # Cleanup
        if (Test-Path $installer) {
            try {
                Remove-Item $installer -Force -ErrorAction SilentlyContinue
                Write-Log "Cleaned up installer file" -Level Info
            }
            catch {
                Write-Log "Could not remove installer: $installer" -Level Warning
            }
        }
    }
}

function Install-WebRtcRedirectorService {
    [CmdletBinding()]
    param()
    Write-Log ""
    Write-Log "=== WebRTC Redirector Service Installation ===" -Level Header

    # Check if already installed
    if (Test-Path $script:WebRtcRedirectorInstallPath) {
        Write-Log "WebRTC Redirector Service already installed" -Level Success
        return $true
    }

    $installer = Join-Path $script:TempPath "WebRtcRedirector_$(Get-Date -Format 'yyyyMMddHHmmss').msi"
    $progressPreference = $ProgressPreference

    try {
        # Download
        Write-Log "Downloading WebRTC Redirector Service MSI..." -Level Info
        $ProgressPreference = 'SilentlyContinue'
        Invoke-InstallerDownload -Uri $script:WebRtcRedirectorUrl -OutFile $installer

        if (-not (Test-Path $installer)) {
            throw "Download failed: File not found at $installer"
        }

        $fileSize = (Get-Item $installer).Length
        if ($fileSize -lt 100KB) {
            throw "Download failed: File size too small ($fileSize bytes)"
        }

        Write-Log "Downloaded successfully ($([math]::Round($fileSize/1KB, 2)) KB)" -Level Success

        # Verify signature
        Write-Log "Verifying Authenticode signature..." -Level Info
        if (-not (Test-FileSignature -FilePath $installer)) {
            throw "Signature verification failed - file may be compromised"
        }

        # Install silently via the msiexec wrapper
        Write-Log "Installing WebRTC Redirector Service (silent mode)..." -Level Info
        $installArgs = @("/i", "`"$installer`"", "/qn", "/norestart")
        $process = Start-InstallerProcess -FilePath "msiexec.exe" -ArgumentList $installArgs

        if ($process.ExitCode -in $script:AcceptableExitCodes) {
            Write-Log "Installer completed with exit code: $($process.ExitCode)" -Level Success

            # Verify installation
            if (Test-Path $script:WebRtcRedirectorInstallPath) {
                Write-Log "WebRTC Redirector Service installation verified" -Level Success
                return $true
            }
            else {
                Write-Log "Installer reported success but service file not detected" -Level Warning
                return $true  # Trust installer exit code
            }
        }
        else {
            throw "WebRTC Redirector installer exited with code $($process.ExitCode)"
        }
    }
    catch {
        Write-Log "WebRTC Redirector installation failed: $_" -Level Error
        $script:InstallErrors += "WebRTC Redirector: $_"
        return $false
    }
    finally {
        # Always restore ProgressPreference
        $ProgressPreference = $progressPreference

        # Cleanup
        if (Test-Path $installer) {
            try {
                Remove-Item $installer -Force -ErrorAction SilentlyContinue
                Write-Log "Cleaned up installer file" -Level Info
            }
            catch {
                Write-Log "Could not remove installer: $installer" -Level Warning
            }
        }
    }
}

function Set-AVDRegistryConfiguration {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    Write-Log ""
    Write-Log "=== Configuring AVD Registry Settings ===" -Level Header

    $success = $true

    # IsWVDEnvironment - Enables Teams optimizations for AVD
    if ($PSCmdlet.ShouldProcess('HKLM:\SOFTWARE\Microsoft\Teams', 'Configure AVD registry settings')) {
        Write-Log "Configuring AVD environment marker..." -Level Info
        $success = $success -and (Set-RegistryValue `
                -Path "HKLM:\SOFTWARE\Microsoft\Teams" `
                -Name "IsWVDEnvironment" `
                -Value 1)

        # Allow side-loading of trusted apps (required for Teams)
        Write-Log "Enabling trusted app side-loading..." -Level Info
        $success = $success -and (Set-RegistryValue `
                -Path "HKLM:\Software\Policies\Microsoft\Windows\Appx" `
                -Name "AllowAllTrustedApps" `
                -Value 1)

        $success = $success -and (Set-RegistryValue `
                -Path "HKLM:\Software\Policies\Microsoft\Windows\Appx" `
                -Name "AllowDevelopmentWithoutDevLicense" `
                -Value 1)

        # Prevent users from manually updating Teams
        Write-Log "Configuring Teams update policy..." -Level Info
        $success = $success -and (Set-RegistryValue `
                -Path "HKLM:\Software\Policies\Microsoft\Office\Teams" `
                -Name "PreventUserFromUpdatingTeams" `
                -Value 1)
    }
    else {
        return $false
    }

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
    Write-Log ""
    Write-Log "=== INSTALLATION SUMMARY ===" -Level Header
    Write-Log ""
    Write-Log "Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -Level Info

    # WebView2 Status
    $webView2Version = Get-WebView2Version
    if ($webView2Version) {
        Write-Log "WebView2 Runtime: Installed (v$webView2Version)" -Level Success
    }
    else {
        Write-Log "WebView2 Runtime: NOT DETECTED" -Level Error
    }

    # Teams Status
    $teamsVersion = Get-TeamsVersion
    if ($teamsVersion) {
        Write-Log "Microsoft Teams: Installed (v$teamsVersion)" -Level Success
    }
    else {
        Write-Log "Microsoft Teams: NOT DETECTED" -Level Error
    }

    # WebRTC Redirector Status
    if (Test-Path $script:WebRtcRedirectorInstallPath) {
        Write-Log "WebRTC Redirector Service: Installed" -Level Success
    }
    else {
        Write-Log "WebRTC Redirector Service: NOT INSTALLED" -Level Warning
    }

    # Registry Status
    $isWVD = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Teams" -Name "IsWVDEnvironment" `
            -ErrorAction SilentlyContinue).IsWVDEnvironment
    if ($isWVD -eq 1) {
        Write-Log "AVD Optimizations: ENABLED" -Level Success
    }
    else {
        Write-Log "AVD Optimizations: NOT ENABLED" -Level Error
    }

    # Errors
    if ($script:InstallErrors.Count -gt 0) {
        Write-Log ""
        Write-Log "Errors Encountered:" -Level Error
        foreach ($err in $script:InstallErrors) {
            Write-Log "$err" -Level Error
        }
    }

    Write-Log ""
    Write-Log "Log file: $LogPath" -Level Info
    Write-Log ""
}

function Main {
    [CmdletBinding()]
    param()
    $script:InstallErrors = @()

    try {
        Write-Banner

        # ---- Early validation: throw/return before doing any work ----
        if (-not $AcceptEULA) {
            Write-Host ""
            Write-Host "[-] You must accept the WebView2 EULA using -AcceptEULA parameter" -ForegroundColor Red
            Write-Host "[*] Review EULA at: https://www.microsoft.com/en-us/legal/terms-of-use" -ForegroundColor Cyan
            return 1
        }

        if ($IsWindows) {
            $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
            $principal = New-Object Security.Principal.WindowsPrincipal($identity)
            if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
                Write-Host "[-] Administrator privileges are required to install system components" `
                    -ForegroundColor Red
                return 1
            }
        }

        # ---- Transcript logging ----
        $logDir = Split-Path -Path $LogPath -Parent
        if (-not (Test-Path $logDir)) {
            $null = New-Item -Path $logDir -ItemType Directory -Force -ErrorAction Stop
        }

        # Stop any orphaned transcripts, then start ours
        try { Stop-Transcript | Out-Null } catch { }
        Start-Transcript -Path $LogPath -Append -ErrorAction Stop

        Write-Log "Script Version: 1.0.0" -Level Info
        Write-Log "Execution Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -Level Info
        Write-Log "Log Path: $LogPath" -Level Info
        Write-Log ""

        Write-Log "EULA accepted, proceeding with installation" -Level Success
        Write-Log ""

        # Configure registry settings first
        $registrySuccess = Set-AVDRegistryConfiguration

        # Clean up old user installations
        Remove-UserTeamsInstalls

        # Install WebView2
        $webView2Success = Install-WebView2Runtime

        # Install Teams
        $teamsSuccess = Install-TeamsBootstrapper

        # Install WebRTC Redirector Service (optional, new Teams media optimization fallback)
        $webrtcSuccess = $true
        if ($InstallWebRtcRedirector) {
            $webrtcSuccess = Install-WebRtcRedirectorService
        }

        # Generate summary
        Write-InstallationSummary

        # Determine exit code
        if ($webView2Success -and $teamsSuccess -and $registrySuccess -and $webrtcSuccess) {
            Write-Log "Installation completed successfully - AVD gold image is ready for user logins" -Level Success
            $exitCode = 0
        }
        elseif (-not $registrySuccess) {
            Write-Log "Installation completed but registry configuration failed - `
                Teams may not be optimized for AVD" -Level Warning
            $exitCode = 4
        }
        else {
            Write-Log "Installation completed with errors - review the log file for details" -Level Error
            $exitCode = 3
        }

        Stop-Transcript
        return $exitCode
    }
    catch {
        Write-Host ""
        Write-Host "[-] FATAL ERROR: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "[-] Stack: $($_.ScriptStackTrace)" -ForegroundColor Red
        try { Stop-Transcript } catch { }
        return 3
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips
# execution -- including dot-sources that pass arguments, where InvocationName alone
# cannot be relied upon under test harnesses.
if (-not ($MyInvocation.InvocationName -eq '.' -or $MyInvocation.Line -match '^\s*\.\s')) { exit (Main) }
