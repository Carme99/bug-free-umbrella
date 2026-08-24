<#
.SYNOPSIS
    Detect and remove AppX packages that block Windows Sysprep preparation.

.DESCRIPTION
    This script automatically detects AppX packages that will block Sysprep from running successfully.
    It identifies apps that are installed for users but not provisioned in the image, then asks for
    confirmation before removing them.

    The script:
    - Scans for potential Sysprep blockers (check-then-act; converged systems are left untouched)
    - Displays detailed information about detected apps
    - Asks for confirmation before making changes (-Force skips the prompt)
    - Stops services that may lock AppX packages, and always restarts them afterwards
    - Logs all actions to a file and provides a summary report

    Exit codes: 0 = no blockers found, removal succeeded, or user cancelled; 1 = one or more blockers
    could not be removed, an unsafe report path was supplied, or a fatal error occurred.

.PARAMETER Force
    Skip confirmation prompts and automatically remove detected blockers.

.PARAMETER LogPath
    Path where the log file will be created. Defaults to a timestamped file under MyDocuments\Reports.

.PARAMETER ExportBlockersList
    Export the list of detected blockers to a CSV file before removal.

.EXAMPLE
    PS C:\> .\Remove-SysprepBlockers.ps1
    Run the script interactively with confirmation prompts.

.EXAMPLE
    PS C:\> .\Remove-SysprepBlockers.ps1 -Force
    Automatically remove all detected blockers without prompting.

.EXAMPLE
    PS C:\> .\Remove-SysprepBlockers.ps1 -ExportBlockersList
    Export detected blockers to CSV and prompt for removal.

.NOTES
    File Name   : Remove-SysprepBlockers.ps1
    Author      : Sysprep Blocker Removal Tool
    Prerequisite: PowerShell 7.0
    Version     : 1.0.0
    Date        : 2026-08-23
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(HelpMessage = 'Skip confirmation and remove all blockers automatically')]
    [switch]$Force,

    [Parameter(HelpMessage = 'Path for log file')]
    [string]$LogPath,

    [Parameter(HelpMessage = 'Export list of blockers to CSV before removal')]
    [switch]$ExportBlockersList
)

$ErrorActionPreference = 'Stop'

# ==================== CONFIGURATION ====================

# Services that may lock AppX packages
$script:ServicesToStop = @('AppXSVC', 'ClipSVC')

# Known problematic packages that often block Sysprep
$script:ExplicitOffenders = @('Microsoft.Winget.Source')

# Known system apps that should never be removed
$script:MsSystemNameWhitelist =
    '^(?:' +
    'Microsoft\.(?:AAD|AccountsControl|AsyncTextService|BioEnrollment|CredDialogHost|ECApp|LockApp|' +
    'MicrosoftEdgeDevToolsClient|NET\.Native(?:\.Framework|\.Runtime)?(?:\.\d+\.\d+)?|' +
    'Services\.Store\.Engagement|UI\.Xaml(?:\.CBS|\.2\.\d+)?|VCLibs(?:\.140\.00(?:\.UWPDesktop)?)?|' +
    'Win32WebViewHost|Windows(?:\.(?:Apprep\.ChxApp|AssignedAccessLockApp|CapturePicker|' +
    'CloudExperienceHost|ContentDeliveryManager|NarratorQuickStart|OOBENetworkCaptivePortal|' +
    'OOBENetworkConnectionFlow|ParentalControls|PeopleExperienceHost|PinningConfirmationDialog|' +
    'PrintQueueActionCenter|SecureAssessmentBrowser|ShellExperienceHost|StartMenuExperienceHost|' +
    'XGpuEjectDialog))|WindowsAppRuntime(?:\..+)?|WindowsClient)' +
    '|windows\.immersivecontrolpanel|Windows\.PrintDialog|MicrosoftWindows\..+' +
    ')$'

# Mutable run state (initialized per run by Initialize-ScriptState)
$script:StoppedServices = @()

# ==================== FUNCTIONS ====================

function Test-IsAdministrator {
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

function Initialize-ScriptState {
    <#
    .SYNOPSIS
    Resolves the log path, validates the report directory, and resets run counters.
    #>

    [CmdletBinding()]
    param()

    if ([string]::IsNullOrWhiteSpace($LogPath)) {
        $documentsDir = [Environment]::GetFolderPath('MyDocuments')
        $script:LogPath = Join-Path (Join-Path $documentsDir 'Reports') `
            "SysprepBlockerRemoval_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
    }
    else {
        $script:LogPath = $LogPath
    }

    $script:StartTime = Get-Date
    $script:BlockersRemoved = @()
    $script:BlockersFailed = @()

    $reportDir = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Reports'
    if ([string]::IsNullOrWhiteSpace($reportDir) -or
        $reportDir -match '(^|[\\/])\.\.([\\/]|$)' -or
        $reportDir -match '^(\\\\|//)') {
        throw "Unsafe report path: $reportDir. Report path must be a local absolute path without '..' traversal."
    }

    $reportDir = [System.IO.Path]::GetFullPath($reportDir)
    if (-not (Test-Path -LiteralPath $reportDir -PathType Container)) {
        New-Item -ItemType Directory -Path $reportDir -Force | Out-Null
    }

    $script:ReportDir = $reportDir
}

function Write-Log {
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [ValidateSet('INFO', 'WARNING', 'ERROR', 'SUCCESS')]
        [string]$Level = 'INFO'
    )

    $logMessage = "[{0}] [{1}] {2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message

    # Write to log file
    Add-Content -Path $script:LogPath -Value $logMessage -ErrorAction SilentlyContinue

    # Write to console with relaunch prefixes and colors
    switch ($Level) {
        'SUCCESS' { Write-Host "[+] $Message" -ForegroundColor Green }
        'WARNING' { Write-Host "[!] $Message" -ForegroundColor Yellow }
        'ERROR' { Write-Host "[-] $Message" -ForegroundColor Red }
        default { Write-Host "[*] $Message" -ForegroundColor Cyan }
    }
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

    foreach ($serviceName in $script:ServicesToStop) {
        try {
            $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
            if ($service -and $service.Status -eq 'Running') {
                if ($PSCmdlet.ShouldProcess($serviceName, 'Stop service')) {
                    Stop-Service -Name $serviceName -Force -ErrorAction Stop
                    $script:StoppedServices += $serviceName
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
            Write-Verbose "Handled exception: $($_.Exception.Message)"
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

    if ($script:StoppedServices.Count -gt 0) {
        Write-Log -Message "Restarting stopped services..." -Level INFO

        foreach ($serviceName in ($script:StoppedServices | Select-Object -Unique)) {
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

        $script:StoppedServices = @()
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
        ($_.Name -notmatch $script:MsSystemNameWhitelist)
    }

    # Add explicit known offenders (collect first, then combine for performance)
    $explicitPackages = foreach ($offender in $script:ExplicitOffenders) {
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

    $exportPath = Join-Path $script:ReportDir "SysprepBlockers_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"

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
                Write-Log -Message ("Failed to remove package $($pkg.PackageFullName): " +
                    "$($_.Exception.Message)") -Level ERROR
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
    Write-Host ("`nThe script will remove $($Blockers.Count) application(s) that may " +
        "block Sysprep.") -ForegroundColor White
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

        Write-Host "`n[*] [$progressCounter/$totalBlockers] Removing: $($blocker.Name)" -ForegroundColor Cyan

        if ($PSCmdlet.ShouldProcess($blocker.Name, 'Remove Appx package')) {
            $success = Remove-AppxPackageEverywhere -PackageName $blocker.Name `
                -PackageFullName $blocker.PackageFullName

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
    $failedColor = if ($script:BlockersFailed.Count -gt 0) { 'Red' } else { 'Green' }
    Write-Host "  Failed to remove:     $($script:BlockersFailed.Count)" -ForegroundColor $failedColor

    if ($script:BlockersFailed.Count -gt 0) {
        Write-Host "`n[-] Packages that could not be removed:" -ForegroundColor Red
        $script:BlockersFailed | ForEach-Object {
            Write-Host "  - $($_.Name)" -ForegroundColor Red
        }
        Write-Host "`nThese packages may be in use. Try:" -ForegroundColor Yellow
        Write-Host "  1. Rebooting the system" -ForegroundColor Yellow
        Write-Host "  2. Running this script again" -ForegroundColor Yellow
        Write-Host "  3. Removing them manually" -ForegroundColor Yellow
    }

    # Run final audit
    Write-Host "`n[*] Running final audit..." -ForegroundColor Cyan
    $remainingBlockers = @(Get-SysprepBlockers)

    if ($remainingBlockers.Count -eq 0) {
        Write-Host "`n[+] SUCCESS: No Sysprep blockers detected. System is ready for Sysprep." -ForegroundColor Green
        Write-Log -Message "System is ready for Sysprep" -Level SUCCESS
    }
    else {
        Write-Host ("`n[!] WARNING: $($remainingBlockers.Count) potential blocker(s) " +
            "still remain.") -ForegroundColor Yellow
        Write-Host "`nRemaining packages:" -ForegroundColor Yellow
        $remainingBlockers | ForEach-Object {
            Write-Host "  - $($_.Name)" -ForegroundColor Yellow
        }
        Write-Log -Message "$($remainingBlockers.Count) blockers still remain" -Level WARNING
    }

    Write-Host "`nLog file: $script:LogPath" -ForegroundColor Cyan
    Write-Host ("=" * 80) -ForegroundColor Cyan
}

# ==================== MAIN ====================

function Main {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    try {
        if (-not (Test-IsAdministrator)) {
            Write-Host ('[-] This script requires administrator privileges. ' +
                'Run from an elevated session.') -ForegroundColor Red
            return 1
        }

        Initialize-ScriptState

        Write-Banner "SYSPREP BLOCKER DETECTION AND REMOVAL TOOL"
        Write-Log -Message "Script started by $env:USERNAME on $env:COMPUTERNAME" -Level INFO
        Write-Log -Message "PowerShell Version: $($PSVersionTable.PSVersion)" -Level INFO
        Write-Log -Message "Force mode: $Force" -Level INFO

        # Detect blockers (check-then-act)
        $blockers = @(Get-SysprepBlockers)

        if ($blockers.Count -eq 0) {
            Write-Host "`n[+] SUCCESS: No Sysprep blockers detected!" -ForegroundColor Green
            Write-Host "[+] Your system appears to be ready for Sysprep." -ForegroundColor Green
            Write-Log -Message "No blockers detected - system ready for Sysprep" -Level SUCCESS
            return 0
        }

        # Show detected blockers
        Show-BlockerDetails -Blockers $blockers

        # Export if requested
        if ($ExportBlockersList) {
            $exportedPath = Export-BlockersList -Blockers $blockers
            if ($exportedPath) {
                Write-Host "[+] Blockers list has been exported to: $exportedPath" -ForegroundColor Green
            }
        }

        # Get confirmation unless -Force is specified
        if (-not $Force) {
            $proceedWithRemoval = $false
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
                        Write-Host "[!] Operation cancelled by user." -ForegroundColor Yellow
                        Write-Log -Message "Operation cancelled by user" -Level INFO
                        return 0
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
            return 1
        }

        return 0
    }
    catch {
        Write-Log -Message "FATAL ERROR: $($_.Exception.Message)" -Level ERROR
        Write-Log -Message "Stack Trace: $($_.ScriptStackTrace)" -Level ERROR
        Write-Host "`n[-] FATAL ERROR occurred: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "[-] Check log file for details: $script:LogPath" -ForegroundColor Red
        return 1
    }
    finally {
        # Always restart services
        Start-AppXServices
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
