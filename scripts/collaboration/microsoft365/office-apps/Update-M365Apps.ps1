<#
.SYNOPSIS
    M365 Apps Update Manager

.DESCRIPTION
    Checks for M365 Apps installation, detects available updates, downloads them locally,
    and optionally installs them. Designed for environments without Microsoft AutoUpdate.

.NOTES
    Requires: Administrator privileges
    ODT Path: C:\AVD\M365Apps\setup.exe
    Install Config: C:\AVD\M365Apps\install.xml
#>

#Requires -RunAsAdministrator

# Configuration
$script:Config = @{
    ODTPath = "C:\AVD\M365Apps\setup.exe"
    InstallXMLPath = "C:\AVD\M365Apps\install.xml"
    DownloadXMLPath = "C:\AVD\M365Apps\download.xml"
    UpdatesPath = "C:\AVD\M365Apps\OfficeUpdates"
    LogPath = "C:\AVD\M365Apps\Logs"
    MaxLogAge = 30  # Days to keep logs
    Channel = "Current"
    OfficeVersionURL = "https://clients.config.office.net/releases/v1.0/OfficeReleases"
}

# Initialize
$ErrorActionPreference = "Stop"
$script:LogFile = $null

#region Logging Functions
function Initialize-Logging {
    if (!(Test-Path $script:Config.LogPath)) {
        New-Item -ItemType Directory -Path $script:Config.LogPath -Force | Out-Null
    }

    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $script:LogFile = Join-Path $script:Config.LogPath "M365Update_$timestamp.log"

    Write-Log "=== M365 Apps Update Manager Started ===" -Color Cyan
    Write-Log "Script version: 1.0"
    Write-Log "Execution time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    Write-Log "User: $env:USERNAME on $env:COMPUTERNAME"
    Write-Log ""
}

function Write-Log {
    param(
        [string]$Message,
        [string]$Color = "White",
        [switch]$NoNewLine
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] $Message"

    # Write to console with color
    if ($NoNewLine) {
        Write-Host $Message -ForegroundColor $Color -NoNewline
    }
    else {
        Write-Host $Message -ForegroundColor $Color
    }

    # Write to log file
    if ($script:LogFile) {
        Add-Content -Path $script:LogFile -Value $logMessage
    }
}

function Write-Success {
    param([string]$Message)
    Write-Log "[OK] $Message" -Color Green
}

function Write-ErrorMsg {
    param([string]$Message)
    Write-Log "[ERROR] $Message" -Color Red
}

function Write-WarningMsg {
    param([string]$Message)
    Write-Log "[WARNING] $Message" -Color Yellow
}

function Write-InfoMsg {
    param([string]$Message)
    Write-Log "[INFO] $Message" -Color Cyan
}

function Write-ProgressMsg {
    param([string]$Message)
    Write-Log "[*] $Message" -Color Gray
}

function Cleanup-OldLogs {
    Write-ProgressMsg "Cleaning up old log files..."
    $cutoffDate = (Get-Date).AddDays(-$script:Config.MaxLogAge)

    Get-ChildItem -Path $script:Config.LogPath -Filter "M365Update_*.log" |
        Where-Object { $_.LastWriteTime -lt $cutoffDate } |
        ForEach-Object {
            Remove-Item $_.FullName -Force
            Write-ProgressMsg "Removed old log: $($_.Name)"
        }
}
#endregion

#region Helper Functions
function Test-Prerequisites {
    Write-Log ""
    Write-Log "Checking prerequisites..." -Color Yellow

    # Check if ODT exists
    if (!(Test-Path $script:Config.ODTPath)) {
        Write-ErrorMsg "Office Deployment Tool not found at: $($script:Config.ODTPath)"
        return $false
    }
    Write-Success "ODT found: $($script:Config.ODTPath)"

    # Check if install.xml exists
    if (!(Test-Path $script:Config.InstallXMLPath)) {
        Write-ErrorMsg "Install configuration not found at: $($script:Config.InstallXMLPath)"
        return $false
    }
    Write-Success "Install config found: $($script:Config.InstallXMLPath)"

    # Ensure updates directory exists
    if (!(Test-Path $script:Config.UpdatesPath)) {
        New-Item -ItemType Directory -Path $script:Config.UpdatesPath -Force | Out-Null
        Write-Success "Created updates directory: $($script:Config.UpdatesPath)"
    }
    else {
        Write-Success "Updates directory exists: $($script:Config.UpdatesPath)"
    }

    # Check internet connectivity
    Write-ProgressMsg "Testing internet connectivity..."
    try {
        $null = Invoke-WebRequest -Uri "https://clients.config.office.net" -UseBasicParsing -TimeoutSec 10
        Write-Success "Internet connectivity verified"
    }
    catch {
        Write-ErrorMsg "No internet connectivity detected. Cannot check for updates."
        return $false
    }

    return $true
}

function Get-ChannelFriendlyName {
    param([string]$ChannelGuid)

    # Channel GUIDs and names per the official Microsoft channel table
    # (see "Manage Microsoft 365 Apps updates in Configuration Manager" - update channel rename table).
    $channelNames = @{
        '492350f6-3a01-4f97-b9c0-c7c6ddf67d60' = 'Current Channel'
        '64256afe-f5d9-4f86-8936-8840a6a4f5be' = 'Current Channel (Preview)'
        '55336b82-a18d-4dd6-b5f6-9e5095c314a6' = 'Monthly Enterprise'
        '7ffbc6bf-bc32-4f92-8982-f9dd17fd3114' = 'Semi-Annual Enterprise'
        'b8f9b850-328d-4355-9145-c59439a0c4cf' = 'Semi-Annual Enterprise (Preview)'
        '5440fd1f-7ecb-4221-8110-145efaa6372f' = 'Beta Channel'
        'f2e724c1-748f-4b47-8fb8-8e0d210e9208' = 'LTSC 2021'
        '2e148de9-61c8-4051-b103-4af54baffbb4' = 'LTSC 2024'
    }

    if ($channelNames.ContainsKey($ChannelGuid)) {
        return $channelNames[$ChannelGuid]
    }
    else {
        return "Unknown ($ChannelGuid)"
    }
}

function Get-InstalledOfficeInfo {
    Write-Log ""
    Write-Log "Checking for installed M365 Apps..." -Color Yellow

    # Check registry for Office installations
    $registryPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Office\ClickToRun\Configuration"
    )

    foreach ($path in $registryPaths) {
        if (Test-Path $path) {
            try {
                $versionInfo = Get-ItemProperty -Path $path -ErrorAction SilentlyContinue

                if ($versionInfo -and $versionInfo.VersionToReport) {
                    # Extract channel GUID from UpdateChannel or CDNBaseUrl
                    $channelGuid = ""
                    if ($versionInfo.UpdateChannel -match '([a-f0-9-]{36})') {
                        $channelGuid = $matches[1]
                    }
                    elseif ($versionInfo.CDNBaseUrl -match '([a-f0-9-]{36})') {
                        $channelGuid = $matches[1]
                    }

                    $channelFriendlyName = Get-ChannelFriendlyName -ChannelGuid $channelGuid

                    $info = @{
                        Installed = $true
                        Version = $versionInfo.VersionToReport
                        BuildVersion = $versionInfo.VersionToReport
                        Platform = $versionInfo.Platform
                        Channel = $channelGuid
                        ChannelName = $channelFriendlyName
                        ProductName = $versionInfo.ProductReleaseIds
                        UpdateChannel = $versionInfo.UpdateChannel
                        InstallPath = $versionInfo.InstallationPath
                    }

                    Write-Success "M365 Apps detected!"
                    Write-Log "  Product: $($info.ProductName)" -Color Cyan
                    Write-Log "  Version: $($info.Version)" -Color Cyan
                    Write-Log "  Platform: $($info.Platform)" -Color Cyan
                    Write-Log "  Channel: $($info.ChannelName)" -Color Cyan
                    Write-Log "  Install Path: $($info.InstallPath)" -Color Cyan

                    return $info
                }
            }
            catch {
                Write-ProgressMsg "Error reading registry path $path : $_"
            }
        }
    }

    Write-WarningMsg "M365 Apps not detected on this system"
    return @{ Installed = $false }
}

function Get-LatestOfficeVersion {
    param([string]$ChannelGuid)

    Write-ProgressMsg "Querying Microsoft for latest Office build..."

    try {
        $response = Invoke-RestMethod -Uri $script:Config.OfficeVersionURL -UseBasicParsing

        # Map common channel GUIDs to channel IDs
        $channelMap = @{
            '492350f6-3a01-4f97-b9c0-c7c6ddf67d60' = 'Current'            # Current Channel
            '64256afe-f5d9-4f86-8936-8840a6a4f5be' = 'CurrentPreview'     # Current Channel (Preview)
            '55336b82-a18d-4dd6-b5f6-9e5095c314a6' = 'MonthlyEnterprise'  # Monthly Enterprise
            '7ffbc6bf-bc32-4f92-8982-f9dd17fd3114' = 'SemiAnnual'         # Semi-Annual Enterprise
            'b8f9b850-328d-4355-9145-c59439a0c4cf' = 'SemiAnnualPreview'  # Semi-Annual Enterprise (Preview)
            '5440fd1f-7ecb-4221-8110-145efaa6372f' = 'BetaChannel'        # Beta Channel
            'f2e724c1-748f-4b47-8fb8-8e0d210e9208' = 'PerpetualVL2021'    # LTSC 2021
            '2e148de9-61c8-4051-b103-4af54baffbb4' = 'PerpetualVL2024'    # LTSC 2024
        }

        # Try to match the channel
        $targetChannelId = $channelMap[$ChannelGuid]

        if (!$targetChannelId) {
            # Default to Current channel if GUID not found
            Write-ProgressMsg "Unknown channel GUID, defaulting to Current Channel"
            $targetChannelId = 'Current'
        }

        # Find the matching channel in the response
        $channelData = $response | Where-Object {
            $_.channelId -eq $targetChannelId -or
            $_.channel -eq $targetChannelId
        } | Select-Object -First 1

        if ($channelData -and $channelData.latestVersion) {
            $latestVersion = $channelData.latestVersion
            $channelName = $channelData.channel
            Write-Success "Latest available version: $latestVersion (Channel: $channelName)"
            return @{
                Version = $latestVersion
                Channel = $channelName
            }
        }
        else {
            Write-WarningMsg "Could not find channel data for: $targetChannelId"
            return $null
        }
    }
    catch {
        Write-ErrorMsg "Failed to query Microsoft version endpoint: $_"
        Write-Log "Error details: $($_.Exception.Message)"
        return $null
    }
}

function Compare-OfficeVersions {
    param(
        [string]$InstalledVersion,
        [string]$LatestVersion
    )

    if (!$LatestVersion) {
        return $null
    }

    # Remove build metadata and compare
    $installedParts = $InstalledVersion -split '\.'
    $latestParts = $LatestVersion -split '\.'

    for ($i = 0; $i -lt [Math]::Min($installedParts.Count, $latestParts.Count); $i++) {
        $installedNum = [int]$installedParts[$i]
        $latestNum = [int]$latestParts[$i]

        if ($latestNum -gt $installedNum) {
            return $true  # Update available
        }
        elseif ($latestNum -lt $installedNum) {
            return $false  # Installed is newer (shouldn't happen)
        }
    }

    return $false  # Versions are equal
}

function New-DownloadConfiguration {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    Write-ProgressMsg "Creating download configuration XML..."

    # Read the install XML and modify it for download-only mode
    [xml]$installXml = Get-Content $script:Config.InstallXMLPath

    # Clone the configuration
    [xml]$downloadXml = $installXml.Clone()

    # Modify the Add element to download mode
    $addNode = $downloadXml.Configuration.Add
    if ($addNode) {
        # Set download path
        $addNode.SourcePath = $script:Config.UpdatesPath

        # Remove RemoveMSI element for download-only
        $removeMSI = $downloadXml.Configuration.SelectSingleNode("//RemoveMSI")
        if ($removeMSI) {
            $null = $downloadXml.Configuration.RemoveChild($removeMSI)
        }

        # Keep all other settings (Products, ExcludeApps, etc.)
    }

    # Save the download configuration
    if ($PSCmdlet.ShouldProcess($script:Config.DownloadXMLPath, 'Save download configuration')) {
        $downloadXml.Save($script:Config.DownloadXMLPath)
        Write-Success "Download configuration created: $($script:Config.DownloadXMLPath)"
    }
}

function Invoke-OfficeDownload {
    Write-Log ""
    Write-Log "Downloading Office updates..." -Color Yellow

    try {
        $arguments = "/download `"$($script:Config.DownloadXMLPath)`""
        Write-ProgressMsg "Executing: $($script:Config.ODTPath) $arguments"

        $process = Start-Process -FilePath $script:Config.ODTPath -ArgumentList $arguments -Wait -PassThru -NoNewWindow

        if ($process.ExitCode -eq 0) {
            Write-Success "Download completed successfully"
            return $true
        }
        else {
            Write-ErrorMsg "Download failed with exit code: $($process.ExitCode)"
            return $false
        }
    }
    catch {
        Write-ErrorMsg "Download error: $_"
        return $false
    }
}

function Invoke-OfficeInstall {
    param([bool]$IsUpdate = $true)

    $action = if ($IsUpdate) { "Installing updates" } else { "Installing M365 Apps" }
    Write-Log ""
    Write-Log "$action..." -Color Yellow

    try {
        $arguments = "/configure `"$($script:Config.InstallXMLPath)`""
        Write-ProgressMsg "Executing: $($script:Config.ODTPath) $arguments"

        Write-WarningMsg "This may take several minutes. Office applications will be closed automatically."

        $process = Start-Process -FilePath $script:Config.ODTPath -ArgumentList $arguments -Wait -PassThru -NoNewWindow

        if ($process.ExitCode -eq 0) {
            Write-Success "$action completed successfully!"
            return $true
        }
        else {
            Write-ErrorMsg "$action failed with exit code: $($process.ExitCode)"
            return $false
        }
    }
    catch {
        Write-ErrorMsg "Installation error: $_"
        return $false
    }
}

function Show-Banner {
    Write-Host ""
    Write-Host "=======================================================" -ForegroundColor Cyan
    Write-Host "        M365 Apps Update Manager" -ForegroundColor White
    Write-Host "=======================================================" -ForegroundColor Cyan
    Write-Host ""
}

function Get-UserConfirmation {
    param(
        [string]$Message,
        [string]$DefaultChoice = "Y"
    )

    $choices = if ($DefaultChoice -eq "Y") { "[Y/n]" } else { "[y/N]" }
    Write-Host "$Message $choices " -ForegroundColor Yellow -NoNewline

    $response = Read-Host

    if ([string]::IsNullOrWhiteSpace($response)) {
        return $DefaultChoice -eq "Y"
    }

    return $response -match '^[Yy]'
}

function Get-ChannelSelection {
    Write-Log ""
    Write-Log "Available Update Channels:" -Color Cyan
    Write-Log ""

    # Define channels with descriptions. GUIDs and names per the official Microsoft channel table
    # (see "Manage Microsoft 365 Apps updates in Configuration Manager" - update channel rename table).
    # Semi-Annual Enterprise (Preview) (GUID b8f9b850-328d-4355-9145-c59439a0c4cf) is a legacy
    # preview variant and is intentionally not offered for new selections.
    $channels = @(
        @{
            Number = 1
            Name = "Current Channel"
            Guid = "492350f6-3a01-4f97-b9c0-c7c6ddf67d60"
            Description = "Latest features monthly. Recommended for most users."
        },
        @{
            Number = 2
            Name = "Monthly Enterprise"
            Guid = "55336b82-a18d-4dd6-b5f6-9e5095c314a6"
            Description = "Monthly updates, validated for enterprise. More predictable."
        },
        @{
            Number = 3
            Name = "Semi-Annual Enterprise"
            Guid = "7ffbc6bf-bc32-4f92-8982-f9dd17fd3114"
            Description = "Monthly feature and security updates since July 2026 (channel unification). For devices requiring extensive testing before new features."
        },
        @{
            Number = 4
            Name = "Beta Channel"
            Guid = "5440fd1f-7ecb-4221-8110-145efaa6372f"
            Description = "Cutting edge features. May be unstable."
        }
    )

    foreach ($channel in $channels) {
        Write-Host "  [$($channel.Number)] " -ForegroundColor White -NoNewline
        Write-Host "$($channel.Name)" -ForegroundColor Green
        Write-Host "      $($channel.Description)" -ForegroundColor Gray
    }

    Write-Log ""
    Write-Host "Select channel [1-4] or press Enter to keep current: " -ForegroundColor Yellow -NoNewline
    $selection = Read-Host

    if ([string]::IsNullOrWhiteSpace($selection)) {
        return $null  # Keep current channel
    }

    $selectedNumber = 0
    if ([int]::TryParse($selection, [ref]$selectedNumber) -and $selectedNumber -ge 1 -and $selectedNumber -le 4) {
        $selectedChannel = $channels | Where-Object { $_.Number -eq $selectedNumber }
        return $selectedChannel
    }
    else {
        Write-WarningMsg "Invalid selection. Keeping current channel."
        return $null
    }
}

function Get-ODTChannelName {
    param([string]$ChannelGuid)

    # Maps channel GUIDs to the documented Office Deployment Tool Channel attribute values.
    # See "Configuration options for the Office Deployment Tool" (Channel attribute).
    $odtChannels = @{
        '492350f6-3a01-4f97-b9c0-c7c6ddf67d60' = 'Current'            # Current Channel
        '64256afe-f5d9-4f86-8936-8840a6a4f5be' = 'CurrentPreview'     # Current Channel (Preview)
        '55336b82-a18d-4dd6-b5f6-9e5095c314a6' = 'MonthlyEnterprise'  # Monthly Enterprise
        '7ffbc6bf-bc32-4f92-8982-f9dd17fd3114' = 'SemiAnnual'         # Semi-Annual Enterprise
        'b8f9b850-328d-4355-9145-c59439a0c4cf' = 'SemiAnnualPreview'  # Semi-Annual Enterprise (Preview)
        '5440fd1f-7ecb-4221-8110-145efaa6372f' = 'BetaChannel'        # Beta Channel
        'f2e724c1-748f-4b47-8fb8-8e0d210e9208' = 'PerpetualVL2021'    # LTSC 2021
        '2e148de9-61c8-4051-b103-4af54baffbb4' = 'PerpetualVL2024'    # LTSC 2024
    }

    if ($odtChannels.ContainsKey($ChannelGuid)) {
        return $odtChannels[$ChannelGuid]
    }
    return $null
}

function Set-OfficeUpdateChannel {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$ChannelGuid,
        [string]$ChannelName
    )

    Write-Log ""
    Write-Log "Changing update channel to: $ChannelName" -Color Yellow

    try {
        # Channel changes are applied through the documented Office Deployment Tool flow: generate a
        # configuration.xml with an <Updates Channel="..." /> element and run setup.exe /configure.
        # Writing CDNBaseUrl/UpdateChannel directly under
        # HKLM\SOFTWARE\Microsoft\Office\ClickToRun\Configuration is not a documented channel-change
        # method. See "Change the Microsoft 365 Apps update channel" on Microsoft Learn.
        $odtChannel = Get-ODTChannelName -ChannelGuid $ChannelGuid
        if (-not $odtChannel) {
            Write-ErrorMsg "No Office Deployment Tool channel name is known for GUID $ChannelGuid. Channel change aborted."
            return $false
        }

        $channelConfigPath = Join-Path (Split-Path -Parent $script:Config.InstallXMLPath) "channel-change.xml"
        $channelConfig = @"
<Configuration>
  <Updates Channel="$odtChannel" />
</Configuration>
"@
        if ($PSCmdlet.ShouldProcess($channelConfigPath, 'Change Office update channel')) {
            $channelConfig | Out-File -FilePath $channelConfigPath -Encoding UTF8

            $arguments = "/configure `"$channelConfigPath`""
            Write-ProgressMsg "Executing: $($script:Config.ODTPath) $arguments"

            $process = Start-Process -FilePath $script:Config.ODTPath -ArgumentList $arguments -Wait -PassThru -NoNewWindow

            if ($process.ExitCode -ne 0) {
                Write-ErrorMsg "Channel change failed with exit code: $($process.ExitCode)"
                return $false
            }

            Write-Success "Update channel changed successfully!"
            Write-InfoMsg "The 'Office Automatic Updates 2.0' scheduled task must be enabled for the channel change to take effect."
            Write-InfoMsg "You may need to download and install updates to switch channels."
        }
        else {
            return $false
        }

        return $true
    }
    catch {
        Write-ErrorMsg "Failed to change update channel: $_"
        return $false
    }
}

function Clear-UpdateFiles {
    Write-Log ""
    Write-Log "Cleaning up update files..." -Color Yellow

    try {
        if (Test-Path $script:Config.UpdatesPath) {
            # Get folder size before cleanup
            $folderSize = (Get-ChildItem -Path $script:Config.UpdatesPath -Recurse -File -ErrorAction SilentlyContinue |
                    Measure-Object -Property Length -Sum).Sum

            if ($folderSize -gt 0) {
                $sizeMB = [math]::Round($folderSize / 1MB, 2)
                Write-ProgressMsg "Found $sizeMB MB of update files to remove..."

                # Remove all files and subdirectories in the updates folder
                Get-ChildItem -Path $script:Config.UpdatesPath -Recurse -ErrorAction SilentlyContinue |
                    Remove-Item -Force -Recurse -ErrorAction SilentlyContinue

                Write-Success "Cleaned up $sizeMB MB of update files"
                Write-InfoMsg "Updates folder cleared: $($script:Config.UpdatesPath)"
            }
            else {
                Write-InfoMsg "No update files to clean up"
            }
        }
        else {
            Write-InfoMsg "Updates folder doesn't exist, nothing to clean"
        }

        return $true
    }
    catch {
        Write-WarningMsg "Failed to clean up some update files: $_"
        Write-InfoMsg "You may need to manually delete files from: $($script:Config.UpdatesPath)"
        return $false
    }
}
#endregion

#region Main Script
function Start-M365UpdateManager {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    try {
        Show-Banner
        Initialize-Logging
        Cleanup-OldLogs

        # Step 1: Prerequisites
        if (!(Test-Prerequisites)) {
            Write-ErrorMsg "Prerequisites check failed. Cannot continue."
            return
        }

        # Step 2: Check installation status
        $officeInfo = Get-InstalledOfficeInfo

        if (!$officeInfo.Installed) {
            Write-Log ""
            Write-WarningMsg "M365 Apps are not installed on this system."

            if (Get-UserConfirmation "Would you like to install M365 Apps now?") {
                Write-InfoMsg "Starting fresh installation..."

                # Download installation files
                if ($PSCmdlet.ShouldProcess('M365 Apps', 'Download installation files')) {
                    New-DownloadConfiguration
                    if (Invoke-OfficeDownload) {
                        # Install Office
                        if (Invoke-OfficeInstall -IsUpdate $false) {
                            Write-Log ""
                            Write-Success "M365 Apps installation completed successfully!"
                            Write-InfoMsg "Please restart any Office applications."

                            # Clean up installation files after successful install
                            if (Get-UserConfirmation "Would you like to clean up the downloaded installation files to save space?") {
                                if ($PSCmdlet.ShouldProcess($script:Config.UpdatesPath, 'Clean up installation files')) {
                                    Clear-UpdateFiles
                                }
                            }
                        }
                    }
                }
            }
            else {
                Write-InfoMsg "Installation cancelled by user."
            }
            return
        }

        # Step 3: Ask about changing update channel
        Write-Log ""
        if (Get-UserConfirmation "Would you like to change the update channel?" "N") {
            $newChannel = Get-ChannelSelection

            if ($newChannel) {
                Write-Log ""
                Write-Host "You selected: " -ForegroundColor Cyan -NoNewline
                Write-Host "$($newChannel.Name)" -ForegroundColor Green

                if (Get-UserConfirmation "Confirm channel change?") {
                    if (Set-OfficeUpdateChannel -ChannelGuid $newChannel.Guid -ChannelName $newChannel.Name) {
                        # Update the office info with the new channel
                        $officeInfo.Channel = $newChannel.Guid
                        Write-InfoMsg "Note: After downloading updates, you'll switch to the new channel."
                    }
                }
                else {
                    Write-InfoMsg "Channel change cancelled."
                }
            }
        }

        # Step 4: Check for updates
        Write-Log ""
        Write-Log "Checking for available updates..." -Color Yellow

        $latestVersionInfo = Get-LatestOfficeVersion -ChannelGuid $officeInfo.Channel

        if ($latestVersionInfo) {
            $updateAvailable = Compare-OfficeVersions -InstalledVersion $officeInfo.Version -LatestVersion $latestVersionInfo.Version

            if ($updateAvailable) {
                Write-Log ""
                Write-WarningMsg "Update available!"
                Write-InfoMsg "  Installed version: $($officeInfo.Version)"
                Write-InfoMsg "  Latest version:    $($latestVersionInfo.Version)"
                Write-Log ""

                if (Get-UserConfirmation "Would you like to download the update?") {
                    # Create download configuration
                    if ($PSCmdlet.ShouldProcess('M365 Apps', 'Download update')) {
                        New-DownloadConfiguration

                        # Download updates
                        if (Invoke-OfficeDownload) {
                            Write-Log ""
                            Write-Success "Updates downloaded to: $($script:Config.UpdatesPath)"

                            # Prompt for installation
                            if (Get-UserConfirmation "Would you like to install the updates now?") {
                                if ($PSCmdlet.ShouldProcess('M365 Apps', 'Install updates')) {
                                    if (Invoke-OfficeInstall -IsUpdate $true) {
                                        Write-Log ""
                                        Write-Success "Update installation completed!"

                                        # Verify new version
                                        Start-Sleep -Seconds 3
                                        $newInfo = Get-InstalledOfficeInfo
                                        if ($newInfo.Version -eq $latestVersionInfo.Version) {
                                            Write-Success "Successfully updated to version $($latestVersionInfo.Version)"
                                        }
                                        else {
                                            Write-WarningMsg "Installation completed but version verification unclear."
                                            Write-InfoMsg "Installed version now shows: $($newInfo.Version)"
                                        }

                                        # Clean up update files after successful installation
                                        if (Get-UserConfirmation "Would you like to clean up the downloaded update files to save space?") {
                                            if ($PSCmdlet.ShouldProcess($script:Config.UpdatesPath, 'Clean up update files')) {
                                                Clear-UpdateFiles
                                            }
                                        }
                                    }
                                }
                            }
                            else {
                                Write-InfoMsg "Updates downloaded but not installed."
                                Write-InfoMsg "Run this script again to install, or use install.xml manually."
                            }
                        }
                    }
                }
                else {
                    Write-InfoMsg "Download cancelled by user."
                }
            }
            else {
                Write-Log ""
                Write-Success "M365 Apps are up to date!"
                Write-InfoMsg "  Current version: $($officeInfo.Version)"
                Write-InfoMsg "  Latest version:  $($latestVersionInfo.Version)"
            }
        }
        else {
            Write-WarningMsg "Could not determine if updates are available."
            Write-InfoMsg "You can still download updates using the ODT configuration."

            if (Get-UserConfirmation "Would you like to download anyway?") {
                if ($PSCmdlet.ShouldProcess('M365 Apps', 'Download update files')) {
                    New-DownloadConfiguration
                    Invoke-OfficeDownload
                }
            }
        }

    }
    catch {
        Write-ErrorMsg "Unexpected error: $_"
        Write-Log "Stack trace: $($_.ScriptStackTrace)"
    }
    finally {
        Write-Log ""
        Write-Log "=== Script execution completed ===" -Color Cyan
        Write-Log "Log file saved: $script:LogFile" -Color Gray
        Write-Log ""
        Write-Host "Press any key to exit..." -ForegroundColor Gray
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    }
}

# Execute
Start-M365UpdateManager
#endregion
