<#
.SYNOPSIS
    Remediates outdated critical applications using winget.

.DESCRIPTION
    Updates security-critical applications detected by the companion detect script.
    Includes retry logic, process detection, and comprehensive error handling.

    Supports both priority-only and full update modes, with optional process
    termination for applications that are running.

.NOTES
    Author: Bug-Free Umbrella
    Version: 1.0
    Intune Context: SYSTEM
    Exit 0: Remediation successful
    Exit 1: Remediation failed

.PARAMETER EnableLogging
    Enable detailed logging to %TEMP%\WingetUpdateRemediation.log

.PARAMETER MaxRetries
    Maximum retry attempts per application (default: 3)

.PARAMETER PriorityAppsOnly
    Only update priority applications (browsers, security tools)

.PARAMETER UpdateOnlyIfNotRunning
    Skip updates for applications that are currently running (default: true)

.PARAMETER ForceCloseApps
    Force close running applications before updating (use with caution)

.PARAMETER TimeoutPerAppMinutes
    Timeout per application update in minutes (default: 10)

.EXAMPLE
    .\remediate.ps1
    Standard remediation with default settings

.EXAMPLE
    .\remediate.ps1 -EnableLogging $true -PriorityAppsOnly $true
    Update only priority apps with logging

.EXAMPLE
    .\remediate.ps1 -ForceCloseApps $true -EnableLogging $true
    Force close running apps before updating (use in maintenance windows)
#>

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

$LogPath = "$env:TEMP\WingetUpdateRemediation.log"

# ========================= LOGGING ========================= #

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"

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
            $processes | ForEach-Object {
                $_.CloseMainWindow() | Out-Null
            }

            Start-Sleep -Seconds 3

            $remainingProcesses = Get-Process -Name $processName -ErrorAction SilentlyContinue
            if (-not $remainingProcesses) {
                Write-Log "Successfully closed $processName"
                return $true
            }

            # Force kill if last attempt
            if ($i -eq $MaxAttempts) {
                Write-Log "Force killing $processName" "WARN"
                Stop-Process -Name $processName -Force -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 2
                return $true
            }

        } catch {
            Write-Log "Error closing process: $_" "ERROR"
        }

        Start-Sleep -Seconds 2
    }

    return $false
}

# ========================= UPDATE FUNCTIONS ========================= #

function Update-Application {
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
            } else {
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
        Write-Log "Executing: winget upgrade --id $AppId --source winget --silent --accept-source-agreements --accept-package-agreements"

        $timeoutSeconds = $TimeoutPerAppMinutes * 60
        $job = Start-Job -ScriptBlock {
            param($id)
            & winget upgrade --id $id --source winget --silent --accept-source-agreements --accept-package-agreements 2>&1
        } -ArgumentList $AppId

        $completed = Wait-Job -Job $job -Timeout $timeoutSeconds

        if ($completed) {
            $output = Receive-Job -Job $job
            Remove-Job -Job $job -Force

            # Check actual winget output for success indicators
            $outputString = $output -join "`n"
            $isSuccess = $outputString -match 'Successfully installed' -or
                         $outputString -match 'No applicable update found' -or
                         $outputString -match 'No available upgrade found'

            if ($isSuccess) {
                Write-Log "Successfully updated $AppName" "SUCCESS"
                return [PSCustomObject]@{
                    AppId = $AppId
                    AppName = $AppName
                    Success = $true
                    Message = "Update completed successfully"
                }
            } else {
                $errorMessage = $output -join "`n"
                Write-Log "Update failed for $AppName : $errorMessage" "ERROR"

                # Retry logic
                if ($RetryCount -lt ($MaxRetries - 1)) {
                    Write-Log "Retrying update (attempt $($RetryCount + 2)/$MaxRetries)..."
                    Start-Sleep -Seconds ([Math]::Pow(2, $RetryCount))
                    return Update-Application -AppId $AppId -AppName $AppName -IsPriority $IsPriority -RetryCount ($RetryCount + 1)
                }

                return [PSCustomObject]@{
                    AppId = $AppId
                    AppName = $AppName
                    Success = $false
                    Message = "Update failed after $MaxRetries attempts"
                }
            }
        } else {
            # Timeout occurred
            Stop-Job -Job $job
            Remove-Job -Job $job -Force

            Write-Log "Update timed out for $AppName after $TimeoutPerAppMinutes minutes" "ERROR"
            return [PSCustomObject]@{
                AppId = $AppId
                AppName = $AppName
                Success = $false
                Message = "Update timed out"
            }
        }

    } catch {
        Write-Log "Error updating $AppName : $_" "ERROR"

        if ($RetryCount -lt ($MaxRetries - 1)) {
            Write-Log "Retrying update (attempt $($RetryCount + 2)/$MaxRetries)..."
            Start-Sleep -Seconds ([Math]::Pow(2, $RetryCount))
            return Update-Application -AppId $AppId -AppName $AppName -IsPriority $IsPriority -RetryCount ($RetryCount + 1)
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
        $wingetOutput = & winget list --upgrade-available --source winget 2>&1 | Out-String
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
    } catch {
        Write-Log "Error detecting outdated apps: $_" "ERROR"
        return @()
    }
}

# ========================= MAIN REMEDIATION LOGIC ========================= #

try {
    Write-Log "=== Winget Critical App Update Remediation Started ==="
    Write-Log "Priority Apps Only: $PriorityAppsOnly"
    Write-Log "Update Only If Not Running: $UpdateOnlyIfNotRunning"
    Write-Log "Force Close Apps: $ForceCloseApps"

    # Get outdated applications
    $outdatedApps = Get-OutdatedApps

    if ($outdatedApps.Count -eq 0) {
        Write-Log "No outdated applications found"
        exit 0
    }

    # Filter apps to update
    if ($PriorityAppsOnly) {
        $appsToUpdate = $outdatedApps | Where-Object { $_.IsPriority -eq $true }
    } else {
        $appsToCheck = $PriorityApps + $StandardApps
        $appsToUpdate = $outdatedApps | Where-Object { $_.Id -in $appsToCheck }
    }

    if ($appsToUpdate.Count -eq 0) {
        Write-Log "No critical applications require updates"
        exit 0
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
        } elseif ($result.Message -match "running") {
            $skippedCount++
        } else {
            $failCount++
        }

        Write-Log ""
    }

    # Summary
    Write-Log "=== Remediation Complete ==="
    Write-Log "Total Applications: $($appsToUpdate.Count)"
    Write-Log "Successfully Updated: $successCount"
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
        Write-Log "Remediation completed successfully (some apps may require restart)"
        exit 0
    } else {
        Write-Log "No applications were successfully updated" "WARN"
        exit 1
    }

} catch {
    Write-Log "Unexpected error during remediation: $_" "ERROR"
    Write-Log "Stack trace: $($_.ScriptStackTrace)" "ERROR"
    exit 1
}
