<#
.SYNOPSIS
    Check for, download, and install Microsoft 365 Apps updates via the Office Deployment Tool.

.DESCRIPTION
    Checks for a Click-to-Run M365 Apps installation, detects available updates for the configured
    channel from the Office configuration service, downloads them locally, and optionally installs
    them. Designed for environments without Microsoft AutoUpdate.

    The script is check-then-act and idempotent: when the installed build already matches the latest
    published build it reports success without downloading or installing anything. Interactive
    prompts gate every mutation, and all mutations additionally honor -WhatIf/-Confirm.

    Exit codes: 0 = up to date, update flow completed (or was declined/cancelled by the user);
    1 = prerequisites failed or an unexpected error occurred.

.PARAMETER InstallPath
    Base directory for the M365 Apps update files (ODT setup.exe, configuration XMLs, OfficeUpdates
    folder, and Logs folder). Default: C:\AVD\M365Apps

.EXAMPLE
    PS C:\> .\Update-M365Apps.ps1
    Run the update manager against the default C:\AVD\M365Apps layout.

.EXAMPLE
    PS C:\> .\Update-M365Apps.ps1 -InstallPath "D:\ODT\M365Apps"
    Run the update manager against an alternate ODT directory.

.NOTES
    File Name   : Update-M365Apps.ps1
    Author      : Bug-Free Umbrella
    Prerequisite: PowerShell 7.0
    Version     : 1.0.0
    Date        : 2026-08-23
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(HelpMessage = 'Base directory for ODT files, configs, updates, and logs')]
    [ValidateNotNullOrEmpty()]
    [string]$InstallPath = 'C:\AVD\M365Apps'
)

$ErrorActionPreference = 'Stop'

# Configuration
$script:Config = @{
    ODTPath          = [IO.Path]::Combine($InstallPath, 'setup.exe')
    InstallXMLPath   = [IO.Path]::Combine($InstallPath, 'install.xml')
    DownloadXMLPath  = [IO.Path]::Combine($InstallPath, 'download.xml')
    UpdatesPath      = [IO.Path]::Combine($InstallPath, 'OfficeUpdates')
    LogPath          = [IO.Path]::Combine($InstallPath, 'Logs')
    MaxLogAge        = 30  # Days to keep logs
    Channel          = 'Current'
    OfficeVersionURL = 'https://clients.config.office.net/releases/v1.0/OfficeReleases'
}

# Initialize
$script:LogFile = $null

#region Logging Functions
function Start-Logging {
    if (!(Test-Path $script:Config.LogPath)) {
        New-Item -ItemType Directory -Path $script:Config.LogPath -Force | Out-Null
    }

    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $script:LogFile = [IO.Path]::Combine($script:Config.LogPath, "M365Update_$timestamp.log")

    Write-Log '=== M365 Apps Update Manager Started ===' -Color Cyan
    Write-Log 'Script version: 1.0.0'
    Write-Log "Execution time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    Write-Log "User: $env:USERNAME on $env:COMPUTERNAME"
    Write-Log ''
}

function Write-Log {
    param(
        [string]$Message,
        [string]$Color = 'White',
        [switch]$NoNewLine
    )

    $logMessage = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message"

    # Write to console with color
    if ($NoNewLine) {
        Write-Host $Message -ForegroundColor $Color -NoNewline
    }
    else {
        Write-Host $Message -ForegroundColor $Color
    }

    # Write to log file
    if ($script:LogFile) {
        Add-Content -Path $script:LogFile -Value $logMessage -ErrorAction SilentlyContinue
    }
}

function Write-Success {
    param([string]$Message)
    Write-Log "[+] $Message" -Color Green
}

function Write-ErrorMsg {
    param([string]$Message)
    Write-Log "[-] $Message" -Color Red
}

function Write-WarningMsg {
    param([string]$Message)
    Write-Log "[!] $Message" -Color Yellow
}

function Write-InfoMsg {
    param([string]$Message)
    Write-Log "[*] $Message" -Color Cyan
}

function Write-ProgressMsg {
    param([string]$Message)
    Write-Log "[*] $Message" -Color Cyan
}

function Remove-OldLogs {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    Write-ProgressMsg 'Cleaning up old log files...'
    $cutoffDate = (Get-Date).AddDays(-$script:Config.MaxLogAge)

    Get-ChildItem -Path $script:Config.LogPath -Filter 'M365Update_*.log' -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -lt $cutoffDate } |
        ForEach-Object {
            if ($PSCmdlet.ShouldProcess($_.FullName, 'Delete old log file')) {
                Remove-Item $_.FullName -Force -ErrorAction Stop
                Write-ProgressMsg "Removed old log: $($_.Name)"
            }
        }
}
#endregion

#region Helper Functions
function Test-Elevation {
    <#
    .SYNOPSIS
    Returns $true when the current session is elevated.
    #>

    [CmdletBinding()]
    param()

    if ($IsWindows) {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        return [Security.Principal.WindowsPrincipal]::new($identity).IsInRole(
            [Security.Principal.WindowsBuiltInRole]::Administrator)
    }

    return $false
}

function Test-Prerequisites {
    Write-Log ''
    Write-Log 'Checking prerequisites...' -Color Yellow

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
    Write-ProgressMsg 'Testing internet connectivity...'
    try {
        $null = Invoke-WebRequest -Uri 'https://clients.config.office.net' -UseBasicParsing `
            -TimeoutSec 10 -ErrorAction Stop
        Write-Success 'Internet connectivity verified'
    }
    catch {
        Write-ErrorMsg 'No internet connectivity detected. Cannot check for updates.'
        return $false
    }

    return $true
}

function Get-ChannelFriendlyName {
    param([string]$ChannelGuid)

    $channelNames = @{
        '492350f6-3a01-4f97-b9c0-c7c6ddf67d60' = 'Current Channel'
        '64256afe-f5d9-4f86-8936-8840a6a4f5be' = 'Current Channel (Preview)'
        '55336b82-a18d-4dd6-b5f6-9e5095c314a6' = 'Monthly Enterprise Channel'
        '7ffbc6bf-bc32-4f92-8982-f9dd17fd3114' = 'Semi-Annual Enterprise Channel'
        'b8f9b850-328d-4355-9145-c59439a0c4cf' = 'Semi-Annual Enterprise Channel (Preview)'
        '5440fd1f-7ecb-4221-8110-145efaa6372f' = 'Beta (Insider)'
        'f2e724c1-748f-4b47-8fb8-8e0d210e9208' = 'LTSB 2021'
        '2e148de9-61c8-4051-b103-4af54baffbb4' = 'LTSB 2024'
    }

    if ($channelNames.ContainsKey($ChannelGuid)) {
        return $channelNames[$ChannelGuid]
    }
    else {
        return "Unknown ($ChannelGuid)"
    }
}

function Get-InstalledOfficeInfo {
    Write-Log ''
    Write-Log 'Checking for installed M365 Apps...' -Color Yellow

    # Check registry for Office installations
    $registryPaths = @(
        'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Office\ClickToRun\Configuration'
    )

    foreach ($path in $registryPaths) {
        if (Test-Path -LiteralPath $path -ErrorAction SilentlyContinue) {
            try {
                $versionInfo = Get-ItemProperty -Path $path -ErrorAction SilentlyContinue

                if ($versionInfo -and $versionInfo.VersionToReport) {
                    # Extract channel GUID from UpdateChannel or CDNBaseUrl
                    $channelGuid = ''
                    if ($versionInfo.UpdateChannel -match '([a-f0-9-]{36})') {
                        $channelGuid = $matches[1]
                    }
                    elseif ($versionInfo.CDNBaseUrl -match '([a-f0-9-]{36})') {
                        $channelGuid = $matches[1]
                    }

                    $channelFriendlyName = Get-ChannelFriendlyName -ChannelGuid $channelGuid

                    $info = @{
                        Installed    = $true
                        Version      = $versionInfo.VersionToReport
                        BuildVersion = $versionInfo.VersionToReport
                        Platform     = $versionInfo.Platform
                        Channel      = $channelGuid
                        ChannelName  = $channelFriendlyName
                        ProductName  = $versionInfo.ProductReleaseIds
                        UpdateChannel = $versionInfo.UpdateChannel
                        InstallPath  = $versionInfo.InstallationPath
                    }

                    Write-Success 'M365 Apps detected!'
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

    Write-WarningMsg 'M365 Apps not detected on this system'
    return @{ Installed = $false }
}

function Get-LatestOfficeVersion {
    param([string]$ChannelGuid)

    Write-ProgressMsg 'Querying Microsoft for latest Office build...'

    try {
        $response = Invoke-RestMethod -Uri $script:Config.OfficeVersionURL -UseBasicParsing `
            -TimeoutSec 30 -ErrorAction Stop

        # Map common channel GUIDs to channel IDs
        $channelMap = @{
            '492350f6-3a01-4f97-b9c0-c7c6ddf67d60' = 'Current'           # Current Channel
            '64256afe-f5d9-4f86-8936-8840a6a4f5be' = 'CurrentPreview'    # Current Channel (Preview)
            '55336b82-a18d-4dd6-b5f6-9e5095c314a6' = 'MonthlyEnterprise' # Monthly Enterprise Channel
            '7ffbc6bf-bc32-4f92-8982-f9dd17fd3114' = 'SemiAnnual'        # Semi-Annual Enterprise Channel
            'b8f9b850-328d-4355-9145-c59439a0c4cf' = 'SemiAnnualPreview' # Semi-Annual Enterprise Channel (Preview)
            '5440fd1f-7ecb-4221-8110-145efaa6372f' = 'BetaChannel'       # Beta Channel
            'f2e724c1-748f-4b47-8fb8-8e0d210e9208' = 'PerpetualVL2021'   # LTSC 2021
            '2e148de9-61c8-4051-b103-4af54baffbb4' = 'PerpetualVL2024'   # LTSC 2024
        }

        # Try to match the channel
        $targetChannelId = $channelMap[$ChannelGuid]

        if (!$targetChannelId) {
            # Default to Current channel if GUID not found
            Write-ProgressMsg 'Unknown channel GUID, defaulting to Current Channel'
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

    # Pad both versions to the same segment count so that e.g. 16.0.10000 vs
    # 16.0.10000.1 are not incorrectly reported as equal
    $maxSegments = [Math]::Max($installedParts.Count, $latestParts.Count)
    while ($installedParts.Count -lt $maxSegments) { $installedParts += '0' }
    while ($latestParts.Count -lt $maxSegments) { $latestParts += '0' }

    for ($i = 0; $i -lt $maxSegments; $i++) {
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

function Invoke-OdtSetup {
    <#
    .SYNOPSIS
    Thin wrapper around the native Office Deployment Tool executable.

    .DESCRIPTION
    All native setup.exe invocations MUST go through this wrapper so tests can mock it by name.
    Returns the process exit code.
    #>

    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('download', 'configure')]
        [string]$Mode,

        [Parameter(Mandatory)]
        [string]$ConfigurationPath
    )

    $arguments = '/{0} "{1}"' -f $Mode, $ConfigurationPath
    $process = Start-Process -FilePath $script:Config.ODTPath -ArgumentList $arguments `
        -Wait -PassThru -NoNewWindow
    return $process.ExitCode
}

function New-DownloadConfiguration {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    Write-ProgressMsg 'Creating download configuration XML...'

    # Read the install XML and modify it for download-only mode
    [xml]$installXml = Get-Content -Path $script:Config.InstallXMLPath -ErrorAction Stop

    # Clone the configuration
    [xml]$downloadXml = $installXml.Clone()

    # Modify the Add element to download mode
    $addNode = $downloadXml.Configuration.Add
    if ($addNode) {
        # Set download path
        $addNode.SourcePath = $script:Config.UpdatesPath

        # Remove RemoveMSI element for download-only
        $removeMSI = $downloadXml.Configuration.SelectSingleNode('//RemoveMSI')
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
    Write-Log ''
    Write-Log 'Downloading Office updates...' -Color Yellow

    try {
        Write-ProgressMsg "Executing: $($script:Config.ODTPath) /download `"$($script:Config.DownloadXMLPath)`""

        $exitCode = Invoke-OdtSetup -Mode 'download' -ConfigurationPath $script:Config.DownloadXMLPath

        if ($exitCode -eq 0) {
            Write-Success 'Download completed successfully'
            return $true
        }
        else {
            Write-ErrorMsg "Download failed with exit code: $exitCode"
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

    $action = if ($IsUpdate) { 'Installing updates' } else { 'Installing M365 Apps' }
    Write-Log ''
    Write-Log "$action..." -Color Yellow

    try {
        Write-ProgressMsg "Executing: $($script:Config.ODTPath) /configure `"$($script:Config.InstallXMLPath)`""

        Write-WarningMsg 'This may take several minutes. Office applications will be closed automatically.'

        $exitCode = Invoke-OdtSetup -Mode 'configure' -ConfigurationPath $script:Config.InstallXMLPath

        if ($exitCode -eq 0) {
            Write-Success "$action completed successfully!"
            return $true
        }
        else {
            Write-ErrorMsg "$action failed with exit code: $exitCode"
            return $false
        }
    }
    catch {
        Write-ErrorMsg "Installation error: $_"
        return $false
    }
}

function Show-Banner {
    Write-Host ''
    Write-Host '=======================================================' -ForegroundColor Cyan
    Write-Host '        M365 Apps Update Manager' -ForegroundColor White
    Write-Host '=======================================================' -ForegroundColor Cyan
    Write-Host ''
}

function Get-UserConfirmation {
    param(
        [string]$Message,
        [string]$DefaultChoice = 'Y'
    )

    $choices = if ($DefaultChoice -eq 'Y') { '[Y/n]' } else { '[y/N]' }
    Write-Host "$Message $choices " -ForegroundColor Yellow -NoNewline

    $response = Read-Host

    if ([string]::IsNullOrWhiteSpace($response)) {
        return $DefaultChoice -eq 'Y'
    }

    return $response -match '^[Yy]'
}

function Get-ChannelSelection {
    Write-Log ''
    Write-Log 'Available Update Channels:' -Color Cyan
    Write-Log ''

    # Define channels with descriptions
    $channels = @(
        @{
            Number      = 1
            Name        = 'Current Channel'
            Guid        = '492350f6-3a01-4f97-b9c0-c7c6ddf67d60'
            Description = 'Latest features monthly. Recommended for most users.'
        },
        @{
            Number      = 2
            Name        = 'Monthly Enterprise Channel'
            Guid        = '55336b82-a18d-4dd6-b5f6-9e5095c314a6'
            Description = 'Monthly updates, validated for enterprise. More predictable.'
        },
        @{
            Number      = 3
            Name        = 'Semi-Annual Enterprise Channel (Preview)'
            Guid        = 'b8f9b850-328d-4355-9145-c59439a0c4cf'
            Description = 'Preview of Semi-Annual updates. For testing.'
        },
        @{
            Number      = 4
            Name        = 'Semi-Annual Enterprise Channel'
            Guid        = '7ffbc6bf-bc32-4f92-8982-f9dd17fd3114'
            Description = 'Updates twice yearly. Most stable for enterprise.'
        },
        @{
            Number      = 5
            Name        = 'Beta (Insider)'
            Guid        = '5440fd1f-7ecb-4221-8110-145efaa6372f'
            Description = 'Cutting edge features. May be unstable.'
        }
    )

    foreach ($channel in $channels) {
        Write-Host "  [$($channel.Number)] " -ForegroundColor White -NoNewline
        Write-Host "$($channel.Name)" -ForegroundColor Green
        Write-Host "      $($channel.Description)" -ForegroundColor Gray
    }

    Write-Log ''
    Write-Host 'Select channel [1-5] or press Enter to keep current: ' -ForegroundColor Yellow -NoNewline
    $selection = Read-Host

    if ([string]::IsNullOrWhiteSpace($selection)) {
        return $null  # Keep current channel
    }

    $selectedNumber = 0
    if ([int]::TryParse($selection, [ref]$selectedNumber) -and $selectedNumber -ge 1 -and $selectedNumber -le 5) {
        $selectedChannel = $channels | Where-Object { $_.Number -eq $selectedNumber }
        return $selectedChannel
    }
    else {
        Write-WarningMsg 'Invalid selection. Keeping current channel.'
        return $null
    }
}

function Set-OfficeUpdateChannel {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$ChannelGuid,
        [string]$ChannelName
    )

    Write-Log ''
    Write-Log "Changing update channel to: $ChannelName" -Color Yellow

    try {
        # Update registry settings
        $regPath = 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration'

        if ($PSCmdlet.ShouldProcess($regPath, 'Change Office update channel')) {
            $newCDNUrl = "http://officecdn.microsoft.com/pr/$ChannelGuid"

            Set-ItemProperty -Path $regPath -Name 'CDNBaseUrl' -Value $newCDNUrl -ErrorAction Stop
            Set-ItemProperty -Path $regPath -Name 'UpdateChannel' -Value $newCDNUrl -ErrorAction Stop

            Write-Success 'Update channel changed successfully!'
            Write-InfoMsg 'Channel will take effect on next update check.'
            Write-InfoMsg 'You may need to download and install updates to switch channels.'
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
    [CmdletBinding(SupportsShouldProcess)]
    param()

    Write-Log ''
    Write-Log 'Cleaning up update files...' -Color Yellow

    try {
        if (Test-Path $script:Config.UpdatesPath) {
            # Get folder size before cleanup
            $folderSize = (Get-ChildItem -Path $script:Config.UpdatesPath -Recurse -File `
                    -ErrorAction SilentlyContinue |
                    Measure-Object -Property Length -Sum).Sum

            if ($folderSize -gt 0) {
                $sizeMB = [math]::Round($folderSize / 1MB, 2)
                Write-ProgressMsg "Found $sizeMB MB of update files to remove..."

                # Remove all files and subdirectories in the updates folder
                if ($PSCmdlet.ShouldProcess($script:Config.UpdatesPath, 'Remove downloaded update files')) {
                    Get-ChildItem -Path $script:Config.UpdatesPath -Recurse -ErrorAction SilentlyContinue |
                        Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
                }

                Write-Success "Cleaned up $sizeMB MB of update files"
                Write-InfoMsg "Updates folder cleared: $($script:Config.UpdatesPath)"
            }
            else {
                Write-InfoMsg 'No update files to clean up'
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
function Main {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    try {
        if (-not (Test-Elevation)) {
            Write-Host ('[-] This script requires administrator privileges. ' +
                'Run from an elevated session.') -ForegroundColor Red
            return 1
        }

        Show-Banner
        Start-Logging
        Remove-OldLogs

        # Step 1: Prerequisites
        if (!(Test-Prerequisites)) {
            Write-ErrorMsg 'Prerequisites check failed. Cannot continue.'
            return 1
        }

        # Step 2: Check installation status
        $officeInfo = Get-InstalledOfficeInfo

        if (!$officeInfo.Installed) {
            Write-Log ''
            Write-WarningMsg 'M365 Apps are not installed on this system.'

            if (Get-UserConfirmation 'Would you like to install M365 Apps now?') {
                Write-InfoMsg 'Starting fresh installation...'

                # Download installation files
                if ($PSCmdlet.ShouldProcess('M365 Apps', 'Download installation files')) {
                    New-DownloadConfiguration

                    if (Invoke-OfficeDownload) {
                        # Install Office
                        if (Invoke-OfficeInstall -IsUpdate $false) {
                            Write-Log ''
                            Write-Success 'M365 Apps installation completed successfully!'
                            Write-InfoMsg 'Please restart any Office applications.'

                            # Clean up installation files after successful install
                            if (Get-UserConfirmation `
                                    'Would you like to clean up the downloaded installation files to save space?') {
                                if ($PSCmdlet.ShouldProcess($script:Config.UpdatesPath,
                                        'Clean up installation files')) {
                                    Clear-UpdateFiles
                                }
                            }
                        }
                        else {
                            return 1
                        }
                    }
                    else {
                        return 1
                    }
                }
            }
            else {
                Write-InfoMsg 'Installation cancelled by user.'
            }
            return 0
        }

        # Step 3: Ask about changing update channel
        Write-Log ''
        if (Get-UserConfirmation 'Would you like to change the update channel?' 'N') {
            $newChannel = Get-ChannelSelection

            if ($newChannel) {
                Write-Log ''
                Write-Host '[*] You selected: ' -ForegroundColor Cyan -NoNewline
                Write-Host "$($newChannel.Name)" -ForegroundColor Green

                if (Get-UserConfirmation 'Confirm channel change?') {
                    if (Set-OfficeUpdateChannel -ChannelGuid $newChannel.Guid -ChannelName $newChannel.Name) {
                        # Update the office info with the new channel
                        $officeInfo.Channel = $newChannel.Guid
                        Write-InfoMsg 'Note: After downloading updates, you''ll switch to the new channel.'
                    }
                }
                else {
                    Write-InfoMsg 'Channel change cancelled.'
                }
            }
        }

        # Step 4: Check for updates
        Write-Log ''
        Write-Log 'Checking for available updates...' -Color Yellow

        $latestVersionInfo = Get-LatestOfficeVersion -ChannelGuid $officeInfo.Channel

        if ($latestVersionInfo) {
            $updateAvailable = Compare-OfficeVersions -InstalledVersion $officeInfo.Version `
                -LatestVersion $latestVersionInfo.Version

            if ($updateAvailable) {
                Write-Log ''
                Write-WarningMsg 'Update available!'
                Write-InfoMsg "  Installed version: $($officeInfo.Version)"
                Write-InfoMsg "  Latest version:    $($latestVersionInfo.Version)"
                Write-Log ''

                if (Get-UserConfirmation 'Would you like to download the update?') {
                    # Create download configuration
                    if ($PSCmdlet.ShouldProcess('M365 Apps', 'Download update')) {
                        New-DownloadConfiguration

                        # Download updates
                        if (Invoke-OfficeDownload) {
                            Write-Log ''
                            Write-Success "Updates downloaded to: $($script:Config.UpdatesPath)"

                            # Prompt for installation
                            if (Get-UserConfirmation 'Would you like to install the updates now?') {
                                if ($PSCmdlet.ShouldProcess('M365 Apps', 'Install updates')) {
                                    if (Invoke-OfficeInstall -IsUpdate $true) {
                                        Write-Log ''
                                        Write-Success 'Update installation completed!'

                                        # Verify new version
                                        Start-Sleep -Seconds 3
                                        $newInfo = Get-InstalledOfficeInfo
                                        if ($newInfo.Version -eq $latestVersionInfo.Version) {
                                            Write-Success ("Successfully updated to version " +
                                                "$($latestVersionInfo.Version)")
                                        }
                                        else {
                                            Write-WarningMsg 'Installation completed but version verification unclear.'
                                            Write-InfoMsg "Installed version now shows: $($newInfo.Version)"
                                        }

                                        # Clean up update files after successful installation
                                            if (Get-UserConfirmation `
                                                    ('Would you like to clean up the downloaded update ' +
                                                        'files to save space?')) {
                                                if ($PSCmdlet.ShouldProcess($script:Config.UpdatesPath,
                                                        'Clean up update files')) {
                                                Clear-UpdateFiles
                                            }
                                        }
                                    }
                                    else {
                                        return 1
                                    }
                                }
                            }
                            else {
                                Write-InfoMsg 'Updates downloaded but not installed.'
                                Write-InfoMsg 'Run this script again to install, or use install.xml manually.'
                            }
                        }
                        else {
                            return 1
                        }
                    }
                }
                else {
                    Write-InfoMsg 'Download cancelled by user.'
                }
            }
            else {
                # Idempotent converged state: already current, nothing to mutate.
                Write-Log ''
                Write-Success 'M365 Apps are up to date!'
                Write-InfoMsg "  Current version: $($officeInfo.Version)"
                Write-InfoMsg "  Latest version:  $($latestVersionInfo.Version)"
            }
        }
        else {
            Write-WarningMsg 'Could not determine if updates are available.'
            Write-InfoMsg 'You can still download updates using the ODT configuration.'

            if (Get-UserConfirmation 'Would you like to download anyway?') {
                if ($PSCmdlet.ShouldProcess('M365 Apps', 'Download update files')) {
                    New-DownloadConfiguration
                    if (-not (Invoke-OfficeDownload)) {
                        return 1
                    }
                }
            }
        }

        return 0
    }
    catch {
        Write-ErrorMsg "Unexpected error: $_"
        Write-Log "Stack trace: $($_.ScriptStackTrace)"
        return 1
    }
    finally {
        Write-Log ''
        Write-Log '=== Script execution completed ===' -Color Cyan
        Write-Log "Log file saved: $script:LogFile" -Color Gray
        Write-Log ''
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
#endregion
