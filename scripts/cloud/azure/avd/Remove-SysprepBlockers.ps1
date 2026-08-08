#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Detect and remove applications that block Windows Sysprep.

.DESCRIPTION
    This script automatically detects AppX packages that will block Sysprep from running successfully.
    It identifies apps that are installed for users but not provisioned in the image, then prompts
    for confirmation before removing them.

    The script:
    - Scans for potential Sysprep blockers
    - Displays detailed information about detected apps
    - Asks for confirmation before making changes
    - Logs all actions to a file
    - Provides a summary report

.PARAMETER Force
    Skip confirmation prompts and automatically remove detected blockers.

.PARAMETER LogPath
    Path where the log file will be created. Defaults to MyDocuments\Reports.

.PARAMETER ExportBlockersList
    Export the list of detected blockers to a CSV file before removal.

.EXAMPLE
    .\Remove-SysprepBlockers.ps1
    Run the script interactively with confirmation prompts.

.EXAMPLE
    .\Remove-SysprepBlockers.ps1 -Force
    Automatically remove all detected blockers without prompting.

.EXAMPLE
    .\Remove-SysprepBlockers.ps1 -ExportBlockersList
    Export detected blockers to CSV and prompt for removal.

.NOTES
    Author: Sysprep Blocker Removal Tool
    Version: 2.0
    Requires: Administrator privileges
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(HelpMessage = "Skip confirmation and remove all blockers automatically")]
    [switch]$Force,

    [Parameter(HelpMessage = "Path for log file")]
    [string]$LogPath = (Join-Path (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Reports') "SysprepBlockerRemoval_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"),

    [Parameter(HelpMessage = "Export list of blockers to CSV before removal")]
    [switch]$ExportBlockersList
)

# ==================== CONFIGURATION ====================

$script:LogPath = $LogPath
$script:BlockersRemoved = @()
$script:BlockersFailed = @()
$script:StartTime = Get-Date

$ReportDir = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Reports'
if ([string]::IsNullOrWhiteSpace($ReportDir) -or
    $ReportDir -match '(^|[\\/])\.\.([\\/]|$)' -or
    $ReportDir -match '^(\\\\|//)') {
    Write-Error "Unsafe report path: $ReportDir. Report path must be a local absolute path without '..' traversal."
    exit 1
}
$ReportDir = [System.IO.Path]::GetFullPath($ReportDir)
if (-not (Test-Path -LiteralPath $ReportDir -PathType Container)) {
    New-Item -ItemType Directory -Path $ReportDir -Force | Out-Null
}

# Services that may lock AppX packages
$servicesToStop = @('AppXSVC', 'ClipSVC')
$stoppedServices = @()

# Known system apps that should never be removed
$msSystemNameWhitelist = '^(?:
    Microsoft\.(?:AAD|AccountsControl|AsyncTextService|BioEnrollment|CredDialogHost|ECApp|LockApp
    |MicrosoftEdgeDevToolsClient
    |NET\.Native(?:\.Framework|\.Runtime)?(?:\.\d+\.\d+)?
    |Services\.Store\.Engagement
    |UI\.Xaml(?:\.CBS|\.2\.\d+)?
    |VCLibs(?:\.140\.00(?:\.UWPDesktop)?)?
    |Win32WebViewHost
    |Windows(?:\.Apprep\.ChxApp|\.AssignedAccessLockApp|\.CapturePicker|\.CloudExperienceHost
             |\.ContentDeliveryManager|\.NarratorQuickStart|\.OOBENetworkCaptivePortal
             |\.OOBENetworkConnectionFlow|\.ParentalControls|\.PeopleExperienceHost
             |\.PinningConfirmationDialog|\.PrintQueueActionCenter|\.SecureAssessmentBrowser
             |\.ShellExperienceHost|\.StartMenuExperienceHost|\.XGpuEjectDialog)
    |WindowsAppRuntime(?:\..+)?
    |WindowsClient
    )
    |windows\.immersivecontrolpanel
    |Windows\.PrintDialog
    |MicrosoftWindows\..+
)$'

# Known problematic packages that often block Sysprep
$explicitOffenders = @(
    'Microsoft.Winget.Source'
)

# ==================== FUNCTIONS ====================

function Write-Log {
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [ValidateSet('INFO', 'WARNING', 'ERROR', 'SUCCESS')]
        [string]$Level = 'INFO'
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logMessage = "[$timestamp] [$Level] $Message"

    # Write to log file
    Add-Content -Path $script:LogPath -Value $logMessage -ErrorAction SilentlyContinue

    # Write to console with color
    $color = switch ($Level) {
        'INFO' { 'White' }
        'WARNING' { 'Yellow' }
        'ERROR' { 'Red' }
        'SUCCESS' { 'Green' }
    }

    Write-Host $logMessage -ForegroundColor $color
}

function Write-Banner {
    param([string]$Text)

    $banner = "`n" + ("=" * 80) + "`n  $Text`n" + ("=" * 80)
    Write-Host $banner -ForegroundColor Cyan
    Write-Log -Message $Text -Level INFO
}

function Stop-AppXServices {
    <#
    .SYNOPSIS
    Stop services that may lock AppX packages.
    #>

    [CmdletBinding(SupportsShouldProcess)]
    param()

    Write-Log -Message "Stopping AppX-related services to prevent file locks..." -Level INFO

    foreach ($serviceName in $servicesToStop) {
        try {
            $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
            if ($service -and $service.Status -eq 'Running') {
                if ($PSCmdlet.ShouldProcess($serviceName, 'Stop service')) {
                    Stop-Service -Name $serviceName -Force -ErrorAction Stop
                    $script:stoppedServices += $serviceName
                    Write-Log -Message "Stopped service: $serviceName" -Level INFO
                }
            }
        }
        catch {
            Write-Log -Message "Could not stop service $serviceName : $($_.Exception.Message)" -Level WARNING
        }
    }

    # Kill processes that can hold AppX locks
    $processesToKill = @('WinGet', 'WinGetUtil', 'AppInstaller', 'WinStore.App', 'MicrosoftStore')

    foreach ($procName in $processesToKill) {
        try {
            $processes = Get-Process -Name $procName -ErrorAction SilentlyContinue
            if ($processes) {
                if ($PSCmdlet.ShouldProcess($procName, 'Stop process')) {
                    $processes | Stop-Process -Force -ErrorAction SilentlyContinue
                    Write-Log -Message "Terminated process: $procName" -Level INFO
                }
            }
        }
        catch {
            # Silently continue
        }
    }
}

function Start-AppXServices {
    <#
    .SYNOPSIS
    Restart services that were stopped.
    #>

    [CmdletBinding(SupportsShouldProcess)]
    param()

    if ($script:stoppedServices.Count -gt 0) {
        Write-Log -Message "Restarting stopped services..." -Level INFO

        foreach ($serviceName in ($script:stoppedServices | Select-Object -Unique)) {
            try {
                if ($PSCmdlet.ShouldProcess($serviceName, 'Start service')) {
                    Start-Service -Name $serviceName -ErrorAction SilentlyContinue
                    Write-Log -Message "Restarted service: $serviceName" -Level INFO
                }
            }
            catch {
                Write-Log -Message "Could not restart service $serviceName : $($_.Exception.Message)" -Level WARNING
            }
        }
    }
}

function Get-SysprepBlockers {
    <#
    .SYNOPSIS
    Detect AppX packages that will block Sysprep.

    .DESCRIPTION
    Identifies packages that are:
    - Installed for users but not provisioned in the image
    - Not core Windows system components
    - Removable

    .OUTPUTS
    Array of AppX package objects that are potential Sysprep blockers.
    #>

    Write-Log -Message "Scanning for Sysprep blockers..." -Level INFO

    # Get provisioned packages (these won't block Sysprep)
    $provisionedPackages = (Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue).DisplayName

    # Get all user-installed packages
    $allPackages = Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue

    Write-Log -Message "Found $($allPackages.Count) total AppX packages installed" -Level INFO
    Write-Log -Message "Found $($provisionedPackages.Count) provisioned packages" -Level INFO

    # Filter to find potential blockers
    $blockers = $allPackages | Where-Object {
        # Not provisioned
        $provisionedPackages -notcontains $_.Name -and
        # Not a system-signed package
        $_.SignatureKind -ne 'System' -and
        # Is removable
        -not $_.NonRemovable -and
        # Not a framework
        -not $_.IsFramework -and
        # Has an install location
        $_.InstallLocation -and
        # Not in SystemApps
        ($_.InstallLocation -notlike "$env:WINDIR\SystemApps*") -and
        # Not in system whitelist
        ($_.Name -notmatch $msSystemNameWhitelist)
    }

    # Add explicit known offenders (collect first, then combine for performance)
    $explicitPackages = foreach ($offender in $explicitOffenders) {
        $package = Get-AppxPackage -AllUsers -Name $offender -ErrorAction SilentlyContinue
        if ($package -and $blockers.Name -notcontains $package.Name) {
            $package
        }
    }

    # Combine and remove duplicates
    $blockers = @($blockers) + @($explicitPackages) | Sort-Object Name -Unique

    Write-Log -Message "Detected $($blockers.Count) potential Sysprep blockers" -Level INFO

    return $blockers
}

function Show-BlockerDetails {
    param(
        [Parameter(Mandatory)]
        [array]$Blockers
    )

    Write-Host "`nDetected Sysprep Blockers:" -ForegroundColor Yellow
    Write-Host ("=" * 80) -ForegroundColor Yellow

    $displayData = $Blockers | Select-Object `
    @{Name = 'Package Name'; Expression = { $_.Name } },
    @{Name = 'Version'; Expression = { $_.Version } },
    @{Name = 'Publisher'; Expression = { $_.Publisher } },
    @{Name = 'Install Location'; Expression = {
            if ($_.InstallLocation.Length -gt 50) {
                "..." + $_.InstallLocation.Substring($_.InstallLocation.Length - 47)
            }
            else {
                $_.InstallLocation
            }
        }
    }

    $displayData | Format-Table -AutoSize -Wrap

    Write-Host "`nTotal blockers found: $($Blockers.Count)" -ForegroundColor Yellow
    Write-Host ("=" * 80) -ForegroundColor Yellow
}

function Export-BlockersList {
    param(
        [Parameter(Mandatory)]
        [array]$Blockers
    )

    $exportPath = Join-Path $ReportDir "SysprepBlockers_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"

    try {
        $Blockers | Select-Object Name, PackageFullName, Version, Publisher, InstallLocation, SignatureKind |
            Export-Csv -Path $exportPath -NoTypeInformation -ErrorAction Stop

        Write-Log -Message "Blockers list exported to: $exportPath" -Level SUCCESS
        return $exportPath
    }
    catch {
        Write-Log -Message "Failed to export blockers list: $($_.Exception.Message)" -Level ERROR
        return $null
    }
}

function Remove-AppxPackageEverywhere {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$PackageName,

        [Parameter(Mandatory)]
        [string]$PackageFullName
    )

    $success = $false
    $wild = "*$PackageName*"

    # Try to remove for all users
    $allPackages = Get-AppxPackage -AllUsers -Name $wild -ErrorAction SilentlyContinue

    foreach ($pkg in $allPackages) {
        try {
            # Try with -AllUsers first (Windows 10 1809+)
            if ($PSCmdlet.ShouldProcess($pkg.PackageFullName, 'Remove Appx package for all users')) {
                Remove-AppxPackage -Package $pkg.PackageFullName -AllUsers -ErrorAction Stop
                Write-Log -Message "Removed package for all users: $($pkg.PackageFullName)" -Level SUCCESS
                $success = $true
            }
        }
        catch {
            # Fallback without -AllUsers
            try {
                if ($PSCmdlet.ShouldProcess($pkg.PackageFullName, 'Remove Appx package')) {
                    Remove-AppxPackage -Package $pkg.PackageFullName -ErrorAction Stop
                    Write-Log -Message "Removed package: $($pkg.PackageFullName)" -Level SUCCESS
                    $success = $true
                }
            }
            catch {
                Write-Log -Message "Failed to remove package $($pkg.PackageFullName): $($_.Exception.Message)" -Level ERROR
            }
        }
    }

    # Try to deprovision if it's provisioned
    $provisionedMatches = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -like $wild -or $_.PackageName -like $wild }

    foreach ($provPkg in $provisionedMatches) {
        try {
            if ($PSCmdlet.ShouldProcess($provPkg.PackageName, 'Deprovision Appx package')) {
                Remove-AppxProvisionedPackage -Online -PackageName $provPkg.PackageName -ErrorAction Stop | Out-Null
                Write-Log -Message "Deprovisioned package: $($provPkg.PackageName)" -Level SUCCESS
                $success = $true
            }
        }
        catch {
            Write-Log -Message "Failed to deprovision $($provPkg.PackageName): $($_.Exception.Message)" -Level WARNING
        }
    }

    return $success
}

function Get-UserConfirmation {
    param(
        [Parameter(Mandatory)]
        [array]$Blockers
    )

    Write-Host "`n"
    Write-Host ("=" * 80) -ForegroundColor Yellow
    Write-Host "  CONFIRMATION REQUIRED" -ForegroundColor Yellow
    Write-Host ("=" * 80) -ForegroundColor Yellow
    Write-Host "`nThe script will remove $($Blockers.Count) application(s) that may block Sysprep." -ForegroundColor White
    Write-Host "`nThese applications will be removed for ALL users on this system." -ForegroundColor Yellow
    Write-Host "`nDo you want to proceed with removal?" -ForegroundColor White
    Write-Host "  [Y] Yes  [N] No  [L] List packages again  (default is 'N'): " -NoNewline -ForegroundColor Cyan

    $response = Read-Host

    return $response
}

function Remove-DetectedBlockers {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [array]$Blockers
    )

    Write-Banner "REMOVING SYSPREP BLOCKERS"

    $progressCounter = 0
    $totalBlockers = $Blockers.Count

    foreach ($blocker in $Blockers) {
        $progressCounter++
        Write-Progress -Activity "Removing Sysprep Blockers" `
            -Status "Processing $($blocker.Name) ($progressCounter of $totalBlockers)" `
            -PercentComplete (($progressCounter / $totalBlockers) * 100)

        Write-Host "`n[$progressCounter/$totalBlockers] Removing: $($blocker.Name)" -ForegroundColor Cyan

        if ($PSCmdlet.ShouldProcess($blocker.Name, 'Remove Appx package')) {
            $success = Remove-AppxPackageEverywhere -PackageName $blocker.Name -PackageFullName $blocker.PackageFullName

            if ($success) {
                $script:BlockersRemoved += $blocker
            }
            else {
                $script:BlockersFailed += $blocker
            }
        }
    }

    Write-Progress -Activity "Removing Sysprep Blockers" -Completed
}

function Show-Summary {
    Write-Banner "REMOVAL SUMMARY"

    $duration = (Get-Date) - $script:StartTime

    Write-Host "`nOperation completed in $([math]::Round($duration.TotalSeconds, 2)) seconds" -ForegroundColor White
    Write-Host "`nResults:" -ForegroundColor White
    Write-Host "  Successfully removed: $($script:BlockersRemoved.Count)" -ForegroundColor Green
    Write-Host "  Failed to remove:     $($script:BlockersFailed.Count)" -ForegroundColor $(if ($script:BlockersFailed.Count -gt 0) { 'Red' } else { 'Green' })

    if ($script:BlockersFailed.Count -gt 0) {
        Write-Host "`nPackages that could not be removed:" -ForegroundColor Red
        $script:BlockersFailed | ForEach-Object {
            Write-Host "  - $($_.Name)" -ForegroundColor Red
        }
        Write-Host "`nThese packages may be in use. Try:" -ForegroundColor Yellow
        Write-Host "  1. Rebooting the system" -ForegroundColor Yellow
        Write-Host "  2. Running this script again" -ForegroundColor Yellow
        Write-Host "  3. Removing them manually" -ForegroundColor Yellow
    }

    # Run final audit
    Write-Host "`nRunning final audit..." -ForegroundColor Cyan
    $remainingBlockers = Get-SysprepBlockers

    if ($remainingBlockers.Count -eq 0) {
        Write-Host "`n SUCCESS: No Sysprep blockers detected. System is ready for Sysprep." -ForegroundColor Green -BackgroundColor Black
        Write-Log -Message "System is ready for Sysprep" -Level SUCCESS
    }
    else {
        Write-Host "`n WARNING: $($remainingBlockers.Count) potential blocker(s) still remain." -ForegroundColor Yellow -BackgroundColor Black
        Write-Host "`nRemaining packages:" -ForegroundColor Yellow
        $remainingBlockers | ForEach-Object {
            Write-Host "  - $($_.Name)" -ForegroundColor Yellow
        }
        Write-Log -Message "$($remainingBlockers.Count) blockers still remain" -Level WARNING
    }

    Write-Host "`nLog file: $script:LogPath" -ForegroundColor Cyan
    Write-Host ("=" * 80) -ForegroundColor Cyan
}

# ==================== MAIN SCRIPT ====================

try {
    # Initialize log
    Write-Banner "SYSPREP BLOCKER DETECTION AND REMOVAL TOOL"
    Write-Log -Message "Script started by $env:USERNAME on $env:COMPUTERNAME" -Level INFO
    Write-Log -Message "PowerShell Version: $($PSVersionTable.PSVersion)" -Level INFO
    Write-Log -Message "Force mode: $Force" -Level INFO

    # Detect blockers
    $blockers = Get-SysprepBlockers

    if ($blockers.Count -eq 0) {
        Write-Host "`n SUCCESS: No Sysprep blockers detected!" -ForegroundColor Green -BackgroundColor Black
        Write-Host "`nYour system appears to be ready for Sysprep." -ForegroundColor Green
        Write-Log -Message "No blockers detected - system ready for Sysprep" -Level SUCCESS
        exit 0
    }

    # Show detected blockers
    Show-BlockerDetails -Blockers $blockers

    # Export if requested
    if ($ExportBlockersList) {
        $exportedPath = Export-BlockersList -Blockers $blockers
        if ($exportedPath) {
            Write-Host "`nBlockers list has been exported to:" -ForegroundColor Green
            Write-Host "  $exportedPath" -ForegroundColor Cyan
        }
    }

    # Get confirmation unless -Force is specified
    if (-not $Force) {
        do {
            $confirmation = Get-UserConfirmation -Blockers $blockers

            switch ($confirmation.ToUpper()) {
                'Y' {
                    Write-Log -Message "User confirmed removal of $($blockers.Count) blocker(s)" -Level INFO
                    $proceedWithRemoval = $true
                    break
                }
                'L' {
                    Show-BlockerDetails -Blockers $blockers
                    $proceedWithRemoval = $false
                    continue
                }
                default {
                    Write-Host "`nOperation cancelled by user." -ForegroundColor Yellow
                    Write-Log -Message "Operation cancelled by user" -Level INFO
                    exit 0
                }
            }
        } while (-not $proceedWithRemoval)
    }
    else {
        Write-Log -Message "Force mode enabled - proceeding without confirmation" -Level INFO
    }

    # Stop services that may lock packages
    Stop-AppXServices

    # Remove blockers
    Remove-DetectedBlockers -Blockers $blockers

    # Show summary
    Show-Summary

    # Exit code based on results
    if ($script:BlockersFailed.Count -gt 0) {
        exit 1
    }
    else {
        exit 0
    }
}
catch {
    Write-Log -Message "FATAL ERROR: $($_.Exception.Message)" -Level ERROR
    Write-Log -Message "Stack Trace: $($_.ScriptStackTrace)" -Level ERROR
    Write-Host "`n FATAL ERROR occurred. Check log file for details." -ForegroundColor Red -BackgroundColor Black
    Write-Host "  $script:LogPath" -ForegroundColor Red
    exit 2
}
finally {
    # Always restart services
    Start-AppXServices
    Write-Log -Message "Script completed" -Level INFO
}
