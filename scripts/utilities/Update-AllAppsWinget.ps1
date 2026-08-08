<#
.SYNOPSIS
    Updates all installed applications using winget in system context.

.DESCRIPTION
    This script performs a comprehensive update of all winget-managed applications running in SYSTEM context.
    It automatically checks for winget availability, installs required dependencies if missing, and updates all apps.

    Features:
    - Automatic winget configuration detection and setup
    - Installs VCLibs and UI.Xaml dependencies if needed
    - Downloads and installs latest winget if not configured for SYSTEM
    - Updates all installed applications
    - Comprehensive logging and error handling
    - Runs in SYSTEM context (suitable for scheduled tasks)

.PARAMETER LogPath
    Path where the log file will be created. Default: C:\ProgramData\WingetUpdates\update-all-apps.log

.PARAMETER MaxRetries
    Maximum number of retries for winget operations. Default: 3

.PARAMETER SkipDependencyCheck
    Skip automatic dependency installation. Use if dependencies are already configured.

.PARAMETER UpdateSource
    Winget source to update from. Default: winget (can also use msstore)

.EXAMPLE
    .\Update-AllAppsWinget.ps1

    Runs the update with default settings, installing dependencies if needed.

.EXAMPLE
    .\Update-AllAppsWinget.ps1 -LogPath "C:\Logs\winget-updates.log" -MaxRetries 5

    Runs the update with custom log path and increased retry count.

.EXAMPLE
    .\Update-AllAppsWinget.ps1 -SkipDependencyCheck

    Runs the update assuming dependencies are already configured.

.NOTES
    File Name      : Update-AllAppsWinget.ps1
    Author         : Bug-Free Umbrella
    Prerequisite   : PowerShell 5.1+, Administrator privileges
    Version        : 1.0.0
    Date           : 2025-12-30

    IMPORTANT: This script must run as SYSTEM or Administrator.
    Best used as a scheduled task running as SYSTEM.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$LogPath = "C:\ProgramData\WingetUpdates\update-all-apps.log",

    [Parameter(Mandatory = $false)]
    [int]$MaxRetries = 3,

    [Parameter(Mandatory = $false)]
    [switch]$SkipDependencyCheck,

    [Parameter(Mandatory = $false)]
    [ValidateSet('winget', 'msstore')]
    [string]$UpdateSource = 'winget'
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

#region Functions

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('Info', 'Warning', 'Error', 'Success')]
        [string]$Level = 'Info'
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"

    # Ensure log directory exists
    $logDir = Split-Path -Path $LogPath -Parent
    if (-not (Test-Path $logDir)) {
        New-Item -Path $logDir -ItemType Directory -Force | Out-Null
    }

    # Write to log file
    Add-Content -Path $LogPath -Value $logMessage

    # Write to console with color
    $color = switch ($Level) {
        'Info' { 'Cyan' }
        'Warning' { 'Yellow' }
        'Error' { 'Red' }
        'Success' { 'Green' }
    }
    Write-Host $logMessage -ForegroundColor $color
}

function Test-RunningAsSystem {
    $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
    return $currentIdentity.IsSystem
}

function Test-IsAdministrator {
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-WingetPath {
    try {
        # Try to find winget in WindowsApps
        $wingetPaths = Resolve-Path "C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\winget.exe" -ErrorAction SilentlyContinue

        if ($wingetPaths) {
            if ($wingetPaths.Count -gt 1) {
                # Return the latest version
                return ($wingetPaths | Sort-Object -Descending)[0].Path
            }
            else {
                return $wingetPaths.Path
            }
        }

        return $null
    }
    catch {
        return $null
    }
}

function Install-WingetDependency {
    param(
        [string]$PackageName,
        [string]$DownloadUrl,
        [string]$Description
    )

    Write-Log "Installing dependency: $Description" -Level Info

    $tempPath = Join-Path $env:TEMP "$PackageName.appx"

    try {
        # Download package
        Write-Log "Downloading $PackageName..." -Level Info
        Invoke-WebRequest -Uri $DownloadUrl -OutFile $tempPath

        # Install package
        Write-Log "Installing $PackageName..." -Level Info
        Add-AppxPackage -Path $tempPath -ErrorAction Stop

        Write-Log "$Description installed successfully" -Level Success

        # Cleanup
        Remove-Item -Path $tempPath -Force -ErrorAction SilentlyContinue

        return $true
    }
    catch {
        Write-Log "Failed to install ${Description}: $($_.Exception.Message)" -Level Error
        Remove-Item -Path $tempPath -Force -ErrorAction SilentlyContinue
        return $false
    }
}

function Install-WingetForSystem {
    Write-Log "Winget not configured for SYSTEM context. Installing dependencies..." -Level Warning

    # Install VCLibs
    $vcLibsUrl = "https://aka.ms/Microsoft.VCLibs.x64.14.00.Desktop.appx"
    $vcLibsResult = Install-WingetDependency -PackageName "VCLibs" -DownloadUrl $vcLibsUrl -Description "Visual C++ Runtime Libraries"

    if (-not $vcLibsResult) {
        Write-Log "Failed to install VCLibs. Cannot proceed." -Level Error
        return $false
    }

    # Install UI.Xaml (required for winget)
    $uiXamlUrl = "https://github.com/microsoft/microsoft-ui-xaml/releases/download/v2.8.6/Microsoft.UI.Xaml.2.8.x64.appx"
    $uiXamlResult = Install-WingetDependency -PackageName "UIXaml" -DownloadUrl $uiXamlUrl -Description "Microsoft UI Xaml"

    if (-not $uiXamlResult) {
        Write-Log "Failed to install UI.Xaml. Cannot proceed." -Level Error
        return $false
    }

    # Install winget (Desktop App Installer)
    Write-Log "Installing Windows Package Manager (winget)..." -Level Info

    $wingetUrl = "https://github.com/microsoft/winget-cli/releases/latest/download/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle"
    $tempWinget = Join-Path $env:TEMP "DesktopAppInstaller.msixbundle"

    try {
        # Download winget
        Write-Log "Downloading winget..." -Level Info
        Invoke-WebRequest -Uri $wingetUrl -OutFile $tempWinget

        # Install winget
        Write-Log "Installing winget..." -Level Info
        Add-AppxPackage -Path $tempWinget -ErrorAction Stop

        Write-Log "Winget installed successfully" -Level Success

        # Cleanup
        Remove-Item -Path $tempWinget -Force -ErrorAction SilentlyContinue

        # Wait for installation to complete
        Start-Sleep -Seconds 5

        return $true
    }
    catch {
        Write-Log "Failed to install winget: $($_.Exception.Message)" -Level Error
        Remove-Item -Path $tempWinget -Force -ErrorAction SilentlyContinue
        return $false
    }
}

function Test-WingetConfiguration {
    $wingetPath = Get-WingetPath

    if (-not $wingetPath) {
        return $false
    }

    try {
        # Test if winget works
        $testResult = & $wingetPath --version 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Log "Winget found at: $wingetPath" -Level Info
            Write-Log "Winget version: $testResult" -Level Info
            return $true
        }
    }
    catch {
        return $false
    }

    return $false
}

function Split-CommandLine {
    param(
        [string]$CommandLine
    )

    # Quote-aware tokenizer: splits on spaces, but keeps quoted segments intact
    $tokens = [System.Collections.Generic.List[string]]::new()
    $current = [System.Text.StringBuilder]::new()
    $inQuotes = $false
    $quoteChar = ''

    for ($i = 0; $i -lt $CommandLine.Length; $i++) {
        $c = $CommandLine[$i]
        if ($inQuotes) {
            if ($c -eq $quoteChar) {
                $inQuotes = $false
            }
            else {
                [void]$current.Append($c)
            }
        }
        elseif ($c -eq '"' -or $c -eq "'") {
            $inQuotes = $true
            $quoteChar = $c
        }
        elseif ($c -eq ' ') {
            if ($current.Length -gt 0) {
                $tokens.Add($current.ToString())
                [void]$current.Clear()
            }
        }
        else {
            [void]$current.Append($c)
        }
    }

    if ($current.Length -gt 0) {
        $tokens.Add($current.ToString())
    }

    return $tokens
}

function Invoke-WingetWithRetry {
    param(
        [string]$Arguments,
        [int]$Retries = $MaxRetries
    )

    $wingetPath = Get-WingetPath
    if (-not $wingetPath) {
        throw "Winget executable not found"
    }

    $attempt = 1
    while ($attempt -le $Retries) {
        try {
            Write-Log "Executing: winget $Arguments (Attempt $attempt/$Retries)" -Level Info

            $result = & $wingetPath (Split-CommandLine $Arguments) 2>&1

            if ($LASTEXITCODE -eq 0) {
                return $result
            }
            else {
                Write-Log "Winget command failed with exit code $LASTEXITCODE" -Level Warning
            }
        }
        catch {
            Write-Log "Exception during winget execution: $($_.Exception.Message)" -Level Warning
        }

        if ($attempt -lt $Retries) {
            $waitTime = [Math]::Pow(2, $attempt)
            Write-Log "Retrying in $waitTime seconds..." -Level Warning
            Start-Sleep -Seconds $waitTime
        }

        $attempt++
    }

    throw "Winget command failed after $Retries attempts"
}

function Update-AllApplications {
    [CmdletBinding(SupportsShouldProcess)]
    param()
    Write-Log "Starting application update process..." -Level Info

    try {
        # First, update winget sources
        Write-Log "Updating winget sources..." -Level Info
        Invoke-WingetWithRetry -Arguments "source update" | Out-Null
        Write-Log "Winget sources updated" -Level Success

        # Get list of upgradeable packages
        Write-Log "Checking for available updates..." -Level Info
        $listOutput = Invoke-WingetWithRetry -Arguments "list --upgrade-available --source $UpdateSource --accept-source-agreements"

        # Parse the output to count updates
        $updateCount = 0
        $upgradableApps = @()

        foreach ($line in $listOutput) {
            if ($line -match '^\S+\s+\S+.*\s+\d+\.\d+.*\s+\d+\.\d+') {
                $updateCount++
                $upgradableApps += $line
            }
        }

        if ($updateCount -eq 0) {
            Write-Log "No updates available. All applications are up to date." -Level Success
            return $true
        }

        Write-Log "Found $updateCount application(s) with available updates:" -Level Info
        foreach ($app in $upgradableApps) {
            Write-Log "  $app" -Level Info
        }

        # Update all applications
        Write-Log "Starting update of all applications..." -Level Info

        if ($PSCmdlet.ShouldProcess("all applications (source: $UpdateSource)", "Run winget upgrade --all")) {
            $updateOutput = Invoke-WingetWithRetry -Arguments "upgrade --all --silent --accept-package-agreements --accept-source-agreements --source $UpdateSource"

            # Log the output
            foreach ($line in $updateOutput) {
                Write-Log $line -Level Info
            }

            Write-Log "Application update process completed" -Level Success
        }

        # Verify updates
        Write-Log "Verifying updates..." -Level Info
        Start-Sleep -Seconds 5

        $verifyOutput = Invoke-WingetWithRetry -Arguments "list --upgrade-available --source $UpdateSource --accept-source-agreements"

        $remainingUpdates = 0
        foreach ($line in $verifyOutput) {
            if ($line -match '^\S+\s+\S+.*\s+\d+\.\d+.*\s+\d+\.\d+') {
                $remainingUpdates++
            }
        }

        if ($remainingUpdates -eq 0) {
            Write-Log "All applications updated successfully!" -Level Success
        }
        else {
            Write-Log "$remainingUpdates application(s) still have pending updates (may require manual intervention)" -Level Warning
        }

        return $true

    }
    catch {
        Write-Log "Error during application update: $($_.Exception.Message)" -Level Error
        return $false
    }
}

#endregion

#region Main Script

try {
    Write-Log "========================================" -Level Info
    Write-Log "Winget System Update Script Started" -Level Info
    Write-Log "========================================" -Level Info

    # Check if running as Administrator or SYSTEM
    if (-not (Test-IsAdministrator)) {
        Write-Log "This script must be run as Administrator or SYSTEM" -Level Error
        exit 1
    }

    $isSystem = Test-RunningAsSystem
    if ($isSystem) {
        Write-Log "Running as SYSTEM" -Level Info
    }
    else {
        Write-Log "Running as Administrator" -Level Info
    }

    # Check winget configuration
    Write-Log "Checking winget configuration..." -Level Info

    if (-not (Test-WingetConfiguration)) {
        if ($SkipDependencyCheck) {
            Write-Log "Winget not configured and dependency check skipped. Cannot proceed." -Level Error
            exit 1
        }

        Write-Log "Winget not configured for current context" -Level Warning

        # Install winget and dependencies
        $installResult = Install-WingetForSystem

        if (-not $installResult) {
            Write-Log "Failed to configure winget. Cannot proceed with updates." -Level Error
            exit 1
        }

        # Verify installation
        if (-not (Test-WingetConfiguration)) {
            Write-Log "Winget installation verification failed" -Level Error
            exit 1
        }

        Write-Log "Winget configured successfully" -Level Success
    }
    else {
        Write-Log "Winget is already configured and ready" -Level Success
    }

    # Update all applications
    $updateResult = Update-AllApplications

    if ($updateResult) {
        Write-Log "========================================" -Level Success
        Write-Log "Update process completed successfully" -Level Success
        Write-Log "========================================" -Level Success
        exit 0
    }
    else {
        Write-Log "Update process completed with errors" -Level Warning
        exit 1
    }

}
catch {
    Write-Log "Critical error: $($_.Exception.Message)" -Level Error
    Write-Log "Stack trace: $($_.ScriptStackTrace)" -Level Error
    exit 1
}

#endregion
