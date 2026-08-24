<#
.SYNOPSIS
    Remediates outdated critical applications by running winget upgrades.

.DESCRIPTION
    Detects installed applications with pending winget upgrades and updates the security-critical
    subset: priority applications (browsers, VPN clients, development and security tools) plus the
    standard application allowlist. Updates run with retry logic, per-application timeouts,
    process detection and optional forced closing of running applications.
    Exit codes:
    - 0: remediation successful, or no critical applications required updates.
    - 1: remediation failed, or no application could be updated.

.PARAMETER EnableLogging
    Enable detailed logging to %TEMP%\WingetUpdateRemediation.log.

.PARAMETER MaxRetries
    Maximum retry attempts per application (default: 3).

.PARAMETER PriorityAppsOnly
    Only update priority applications (browsers, security tools).

.PARAMETER UpdateOnlyIfNotRunning
    Skip updates for applications that are currently running (default: true).

.PARAMETER ForceCloseApps
    Force close running applications before updating (use with caution).

.PARAMETER TimeoutPerAppMinutes
    Timeout per application update in minutes (default: 10).

.EXAMPLE
    PS C:\> .\Invoke-RemediationCheckOutdatedCriticalApps.ps1
    Standard remediation with default settings.

.EXAMPLE
    PS C:\> .\Invoke-RemediationCheckOutdatedCriticalApps.ps1 -PriorityAppsOnly $true
    Update only priority apps, skipping applications that are running.

.NOTES
    File Name: Invoke-RemediationCheckOutdatedCriticalApps.ps1
    Author: Bug-Free Umbrella
    Prerequisite: PowerShell 7.0
    Version: 1.0.0
    Date: 2026-08-23

    USAGE RECOMMENDATION:
    Deploy with the standard maintenance cadence for comprehensive updates. Use
    Invoke-RemediationCheckOutdatedCriticalAppsPriorityOnly.ps1 for rapid security response.
#>

[CmdletBinding(SupportsShouldProcess)]

param(
    [bool]$EnableLogging = $false,

    [ValidateRange(1, 10)]
    [int]$MaxRetries = 3,

    [bool]$PriorityAppsOnly = $false,
    [bool]$UpdateOnlyIfNotRunning = $true,
    [bool]$ForceCloseApps = $false,

    [ValidateRange(1, 60)]
    [int]$TimeoutPerAppMinutes = 10
)

$ErrorActionPreference = 'Stop'

# ========================= CONFIGURATION ========================= #

# Priority applications (security-critical, frequently patched)
$PriorityApps = @(
    # Browsers (high CVE frequency)
    'Google.Chrome',
    'Mozilla.Firefox',
    'Microsoft.Edge',
    'BraveSoftware.BraveBrowser',

    # VPN & Remote Access (security-critical)
    'Cisco.CiscoAnyConnect',
    'OpenVPN.OpenVPN',
    'WireGuard.WireGuard',

    # Development Tools (supply chain security)
    'Microsoft.VisualStudioCode',
    'Git.Git',
    'Python.Python.3.12',
    'Python.Python.3.11',

    # Security Tools
    'Microsoft.PowerShell',
    '1Password.1Password',
    'Bitwarden.Bitwarden'
)

# Additional important apps
$StandardApps = @(
    'Adobe.Acrobat.Reader.64-bit',
    'VideoLAN.VLC',
    'Zoom.Zoom',
    'Microsoft.Teams',
    'Notepad++.Notepad++',
    '7zip.7zip',
    'Microsoft.PowerToys'
)

# Process name mapping (for apps with different process names)
$ProcessNameMap = @{
    # Browsers
    'Google.Chrome' = 'chrome'
    'Mozilla.Firefox' = 'firefox'
    'Microsoft.Edge' = 'msedge'
    'BraveSoftware.BraveBrowser' = 'brave'

    # VPN & Remote Access
    'Cisco.CiscoAnyConnect' = 'vpnui'
    'OpenVPN.OpenVPN' = 'openvpn-gui'
    'WireGuard.WireGuard' = 'wireguard'

    # Development Tools
    'Microsoft.VisualStudioCode' = 'Code'
    'Git.Git' = 'git'
    'Python.Python.3.12' = 'python'
    'Python.Python.3.11' = 'python'

    # Security Tools
    'Microsoft.PowerShell' = 'pwsh'
    '1Password.1Password' = '1Password'
    'Bitwarden.Bitwarden' = 'Bitwarden'

    # Standard Apps
    'Adobe.Acrobat.Reader.64-bit' = 'AcroRd32'
    'VideoLAN.VLC' = 'vlc'
    'Zoom.Zoom' = 'Zoom'
    'Microsoft.Teams' = 'Teams'
    'Notepad++.Notepad++' = 'notepad++'
    '7zip.7zip' = '7zFM'
    'Microsoft.PowerToys' = 'PowerToys'
}

$LogPath = Join-Path $env:TEMP 'WingetUpdateRemediation.log'

# ========================= WINGET WRAPPER ========================= #

function Invoke-Winget {
    param([string[]]$ArgumentList)

    $output = & winget.exe @ArgumentList 2>&1
    $exitCode = $LASTEXITCODE

    return [PSCustomObject]@{
        Output = @($output)
        ExitCode = $exitCode
    }
}

# ========================= LOGGING ========================= #

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $levelPrefixes = @{
        "SUCCESS" = "[+]"
        "WARN" = "[!]"
        "ERROR" = "[-]"
    }
    $prefix = $levelPrefixes[$Level]
    if (-not $prefix) { $prefix = "[*]" }
    $logMessage = "$prefix [$timestamp] [$Level] $Message"

    if ($EnableLogging) {
        Add-Content -Path $LogPath -Value $logMessage -ErrorAction SilentlyContinue
    }

    Write-Host $logMessage
}

# ========================= PROCESS MANAGEMENT ========================= #

function Get-AppProcessName {
    param([string]$AppId)

    # Check custom mapping first
    if ($ProcessNameMap.ContainsKey($AppId)) {
        return $ProcessNameMap[$AppId]
    }

    # Extract process name from App ID (last part after dot)
    $parts = $AppId -split '\.'
    if ($parts.Count -gt 0) {
        return $parts[-1]
    }

    return $null
}

function Test-AppRunning {
    param([string]$AppId)

    $processName = Get-AppProcessName -AppId $AppId
    if (-not $processName) {
        return $false
    }

    $process = Get-Process -Name $processName -ErrorAction SilentlyContinue
    return ($null -ne $process)
}

function Stop-AppProcess {
    [CmdletBinding(SupportsShouldProcess)]
    param([string]$AppId, [int]$MaxAttempts = 3)

    $processName = Get-AppProcessName -AppId $AppId
    if (-not $processName) {
        Write-Log "Cannot determine process name for $AppId" "WARN"
        return $false
    }

    for ($i = 1; $i -le $MaxAttempts; $i++) {
        $processes = Get-Process -Name $processName -ErrorAction SilentlyContinue
        if (-not $processes) {
            Write-Log "Process $processName is not running"
            return $true
        }

        Write-Log "Attempting to close $processName (attempt $i/$MaxAttempts)"

        try {
            if ($PSCmdlet.ShouldProcess($processName, 'Close application process')) {
                $processes | ForEach-Object {
                    $_.CloseMainWindow() | Out-Null
                }
            }

            Start-Sleep -Seconds 3

            $remainingProcesses = Get-Process -Name $processName -ErrorAction SilentlyContinue
            if (-not $remainingProcesses) {
                Write-Log "Successfully closed $processName" "SUCCESS"
                return $true
            }

            # Force kill if last attempt
            if ($i -eq $MaxAttempts) {
                Write-Log "Force killing $processName" "WARN"
                if ($PSCmdlet.ShouldProcess($processName, 'Force kill application process')) {
                    Stop-Process -Name $processName -Force -ErrorAction SilentlyContinue
                }
                Start-Sleep -Seconds 2

                # Verify the process was actually terminated
                $stillRunning = Get-Process -Name $processName -ErrorAction SilentlyContinue
                if ($stillRunning) {
                    Write-Log "Failed to terminate $processName after force kill" "ERROR"
                    return $false
                }
                Write-Log "Successfully force-killed $processName" "SUCCESS"
                return $true
            }

        }
        catch {
            Write-Log "Error closing process: $_" "ERROR"
        }

        Start-Sleep -Seconds 2
    }

    return $false
}

# ========================= UPDATE FUNCTIONS ========================= #

function Update-Application {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$AppId,
        [string]$AppName,
        [bool]$IsPriority,
        [int]$RetryCount = 0
    )

    $priorityTag = if ($IsPriority) { "[PRIORITY]" } else { "[STANDARD]" }
    Write-Log "$priorityTag Updating: $AppName ($AppId)"

    # Check if app is running
    if ($UpdateOnlyIfNotRunning -or $ForceCloseApps) {
        $isRunning = Test-AppRunning -AppId $AppId

        if ($isRunning) {
            if ($ForceCloseApps) {
                Write-Log "Application is running, attempting to close..."
                $closed = Stop-AppProcess -AppId $AppId
                if (-not $closed) {
                    Write-Log "Failed to close $AppName, skipping update" "WARN"
                    return [PSCustomObject]@{
                        AppId = $AppId
                        AppName = $AppName
                        Success = $false
                        Message = "Application is running and could not be closed"
                    }
                }
            }
            else {
                Write-Log "$AppName is currently running, skipping update" "WARN"
                return [PSCustomObject]@{
                    AppId = $AppId
                    AppName = $AppName
                    Success = $false
                    Message = "Application is running (use ForceCloseApps to override)"
                }
            }
        }
    }

    # Validate AppId format for security
    if ($AppId -notmatch '^[a-zA-Z0-9\.\-_]+$') {
        Write-Log "Invalid AppId format: $AppId" "ERROR"
        return [PSCustomObject]@{
            AppId = $AppId
            AppName = $AppName
            Success = $false
            Message = "Invalid AppId format - security validation failed"
        }
    }

    try {
        # Execute winget upgrade with timeout
        Write-Log "Executing: winget upgrade --id $AppId (source winget, silent, agreements accepted)"

        $timeoutSeconds = $TimeoutPerAppMinutes * 60
        if (-not $PSCmdlet.ShouldProcess($AppId, 'Run winget upgrade')) {
            return [PSCustomObject]@{
                AppId = $AppId
                AppName = $AppName
                Success = $false
                Message = "Update skipped (WhatIf)"
            }
        }
        $job = Start-Job -ScriptBlock {
            param($id)
            function Invoke-WingetUpgradeJob {
                param([string[]]$ArgumentList)
                & winget.exe @ArgumentList 2>&1
                return $LASTEXITCODE
            }
            Invoke-WingetUpgradeJob -ArgumentList @(
                'upgrade', '--id', $id, '--source', 'winget', '--silent',
                '--accept-source-agreements', '--accept-package-agreements'
            ) | Out-Null
        } -ArgumentList $AppId

        $completed = Wait-Job -Job $job -Timeout $timeoutSeconds

        if ($completed) {
            $output = Receive-Job -Job $job
            Remove-Job -Job $job -Force

            # Check actual winget output for success indicators
            $outputString = $output -join "`n"

            # Differentiate between actually updated, already up-to-date, and failed
            $wasUpdated = $outputString -match 'Successfully installed'
            $alreadyUpToDate = $outputString -match 'No applicable update found' -or
            $outputString -match 'No available upgrade found'

            if ($wasUpdated) {
                Write-Log "Successfully updated $AppName" "SUCCESS"
                return [PSCustomObject]@{
                    AppId = $AppId
                    AppName = $AppName
                    Success = $true
                    Message = "Update installed successfully"
                }
            }
            elseif ($alreadyUpToDate) {
                Write-Log "$AppName is already up-to-date (no update needed)" "INFO"
                return [PSCustomObject]@{
                    AppId = $AppId
                    AppName = $AppName
                    Success = $true
                    Message = "Already up-to-date"
                }
            }
            else {
                $errorMessage = $output -join "`n"
                Write-Log "Update failed for $AppName : $errorMessage" "ERROR"

                # Retry logic
                if ($RetryCount -lt ($MaxRetries - 1)) {
                    Write-Log "Retrying update (attempt $($RetryCount + 2)/$MaxRetries)..."
                    Start-Sleep -Seconds ([Math]::Pow(2, $RetryCount))
                    return Update-Application -AppId $AppId -AppName $AppName `
                        -IsPriority $IsPriority -RetryCount ($RetryCount + 1)
                }

                return [PSCustomObject]@{
                    AppId = $AppId
                    AppName = $AppName
                    Success = $false
                    Message = "Update failed after $MaxRetries attempts"
                }
            }
        }
        else {
            # Timeout occurred - clean up the job before reporting failure
            try {
                Stop-Job -Job $job -ErrorAction SilentlyContinue
                Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
            }
            catch {
                Write-Log "Error cleaning up timed out job: $_" "WARN"
            }

            Write-Log "Update timed out for $AppName after $TimeoutPerAppMinutes minutes" "ERROR"
            return [PSCustomObject]@{
                AppId = $AppId
                AppName = $AppName
                Success = $false
                Message = "Update timed out"
            }
        }

    }
    catch {
        Write-Log "Error updating $AppName : $_" "ERROR"

        if ($RetryCount -lt ($MaxRetries - 1)) {
            Write-Log "Retrying update (attempt $($RetryCount + 2)/$MaxRetries)..."
            Start-Sleep -Seconds ([Math]::Pow(2, $RetryCount))
            return Update-Application -AppId $AppId -AppName $AppName `
                -IsPriority $IsPriority -RetryCount ($RetryCount + 1)
        }

        return [PSCustomObject]@{
            AppId = $AppId
            AppName = $AppName
            Success = $false
            Message = $_.Exception.Message
        }
    }
}

function Get-OutdatedApps {
    try {
        $wingetResult = Invoke-Winget -ArgumentList @('list', '--upgrade-available', '--source', 'winget')
        if ($wingetResult.ExitCode -ne 0) {
            Write-Log "winget list exited with code $($wingetResult.ExitCode)" "ERROR"
            return @()
        }
        $wingetOutput = $wingetResult.Output | Out-String
        $lines = $wingetOutput -split "`n" | Where-Object { $_ -match '\S' }
        $outdatedApps = @()

        foreach ($line in $lines) {
            if ($line -match '^Name\s+Id\s+' -or $line -match '^-+' -or $line -match '^\d+ upgrades available') {
                continue
            }

            if ($line -match '^\s*(.+?)\s{2,}([^\s]+\.[^\s]+)\s+([^\s]+)\s+([^\s]+)') {
                $appName = $matches[1].Trim()
                $appId = $matches[2].Trim()

                $outdatedApps += [PSCustomObject]@{
                    Name = $appName
                    Id = $appId
                    IsPriority = ($appId -in $PriorityApps)
                }
            }
        }

        return $outdatedApps
    }
    catch {
        Write-Log "Error detecting outdated apps: $_" "ERROR"
        return @()
    }
}

# ========================= MAIN REMEDIATION LOGIC ========================= #

function Main {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    try {
        Write-Log "=== Winget Critical App Update Remediation Started ==="
        Write-Log "Priority Apps Only: $PriorityAppsOnly"
        Write-Log "Update Only If Not Running: $UpdateOnlyIfNotRunning"
        Write-Log "Force Close Apps: $ForceCloseApps"

        # Get outdated applications
        $outdatedApps = Get-OutdatedApps

        if ($outdatedApps.Count -eq 0) {
            Write-Log "No outdated applications found"
            return 0
        }

        # Filter apps to update
        if ($PriorityAppsOnly) {
            $appsToUpdate = $outdatedApps | Where-Object { $_.IsPriority -eq $true }
        }
        else {
            $appsToCheck = $PriorityApps + $StandardApps
            $appsToUpdate = $outdatedApps | Where-Object { $_.Id -in $appsToCheck }
        }

        if ($appsToUpdate.Count -eq 0) {
            Write-Log "No critical applications require updates"
            return 0
        }

        Write-Log "Updating $($appsToUpdate.Count) applications..."
        Write-Log ""

        # Update applications
        $results = @()
        $successCount = 0
        $failCount = 0
        $skippedCount = 0

        foreach ($app in ($appsToUpdate | Sort-Object -Property IsPriority -Descending)) {
            $result = Update-Application -AppId $app.Id -AppName $app.Name -IsPriority $app.IsPriority
            $results += $result

            if ($result.Success) {
                $successCount++
            }
            elseif ($result.Message -match "running") {
                $skippedCount++
            }
            else {
                $failCount++
            }

            Write-Log ""
        }

        # Summary
        Write-Log "=== Remediation Complete ==="
        Write-Log "Total Applications: $($appsToUpdate.Count)"
        Write-Log "Successfully Updated: $successCount" "SUCCESS"
        Write-Log "Skipped (Running): $skippedCount"
        Write-Log "Failed: $failCount"

        if ($failCount -gt 0) {
            Write-Log ""
            Write-Log "Failed updates:"
            foreach ($result in ($results | Where-Object { -not $_.Success -and $_.Message -notmatch "running" })) {
                Write-Log "  - $($result.AppName): $($result.Message)"
            }
        }

        # Exit with appropriate code
        if ($successCount -gt 0) {
            Write-Log "Remediation completed successfully (some apps may require restart)" "SUCCESS"
            return 0
        }
        else {
            Write-Log "No applications were successfully updated" "WARN"
            return 1
        }

    }
    catch {
        Write-Log "Unexpected error during remediation: $_" "ERROR"
        Write-Log "Stack trace: $($_.ScriptStackTrace)" "ERROR"
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
