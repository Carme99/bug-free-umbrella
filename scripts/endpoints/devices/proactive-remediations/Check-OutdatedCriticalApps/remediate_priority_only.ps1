<#
.SYNOPSIS
    Remediates ONLY priority/security-critical applications using winget.

.DESCRIPTION
    Streamlined remediation variant that updates only the highest-priority applications
    (browsers, VPN clients, security tools). Designed for rapid security patching.

    This variant is optimized for:
    - Emergency security updates (zero-day patches)
    - Maintenance windows where apps can be force-closed
    - Minimal disruption to users

.NOTES
    Author: Bug-Free Umbrella
    Version: 1.0
    Intune Context: SYSTEM
    Exit 0: Remediation successful
    Exit 1: Remediation failed

    USAGE RECOMMENDATION:
    Deploy this variant with higher frequency (hourly/every 4 hours) for rapid
    security response. Use standard remediate.ps1 for comprehensive updates.

.PARAMETER EnableLogging
    Enable detailed logging to %TEMP%\WingetUpdateRemediation_Priority.log

.PARAMETER ForceCloseApps
    Force close running applications before updating (recommended for maintenance windows)

.EXAMPLE
    .\remediate_priority_only.ps1
    Update priority apps only (skip if running)

.EXAMPLE
    .\remediate_priority_only.ps1 -ForceCloseApps $true
    Force close and update priority apps (use in maintenance windows)
#>

param(
    [bool]$EnableLogging = $true,  # Default to enabled for priority updates
    [bool]$ForceCloseApps = $false
)

# ========================= PRIORITY CONFIGURATION ========================= #

# PRIORITY ONLY - Security-critical applications
$PriorityApps = @(
    # Browsers (highest CVE frequency)
    'Google.Chrome',
    'Mozilla.Firefox',
    'Microsoft.Edge',
    'BraveSoftware.BraveBrowser',

    # VPN & Remote Access (security-critical)
    'Cisco.CiscoAnyConnect',
    'OpenVPN.OpenVPN',
    'WireGuard.WireGuard',

    # Security Tools
    'Microsoft.PowerShell',
    '1Password.1Password',
    'Bitwarden.Bitwarden'
)

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

    # Security Tools
    'Microsoft.PowerShell' = 'pwsh'
    '1Password.1Password' = '1Password'
    'Bitwarden.Bitwarden' = 'Bitwarden'
}

$LogPath = "$env:TEMP\WingetUpdateRemediation_Priority.log"
$MaxRetries = 2  # Faster failure for priority updates
$TimeoutMinutes = 5  # Shorter timeout for priority updates

# ========================= LOGGING ========================= #

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [PRIORITY] [$Level] $Message"

    if ($EnableLogging) {
        Add-Content -Path $LogPath -Value $logMessage -ErrorAction SilentlyContinue
    }

    Write-Host $logMessage
}

# ========================= PROCESS MANAGEMENT ========================= #

function Get-AppProcessName {
    param([string]$AppId)

    if ($ProcessNameMap.ContainsKey($AppId)) {
        return $ProcessNameMap[$AppId]
    }

    $parts = $AppId -split '\.'
    if ($parts.Count -gt 0) {
        return $parts[-1]
    }

    return $null
}

function Stop-AppProcess {
    param([string]$AppId)

    $processName = Get-AppProcessName -AppId $AppId
    if (-not $processName) {
        # FIX: Return false when process name cannot be determined (safer default)
        Write-Log "Cannot determine process name for $AppId - skipping process close" "WARN"
        return $false
    }

    $processes = Get-Process -Name $processName -ErrorAction SilentlyContinue
    if (-not $processes) {
        return $true
    }

    Write-Log "Force closing $processName..."

    try {
        $processes | ForEach-Object {
            $_.CloseMainWindow() | Out-Null
        }

        Start-Sleep -Seconds 2

        $remainingProcesses = Get-Process -Name $processName -ErrorAction SilentlyContinue
        if ($remainingProcesses) {
            Stop-Process -Name $processName -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 1

            # FIX: Verify process was actually terminated after force kill
            $stillRunning = Get-Process -Name $processName -ErrorAction SilentlyContinue
            if ($stillRunning) {
                Write-Log "Failed to terminate $processName after force kill" "ERROR"
                return $false
            }
        }

        Write-Log "Successfully closed $processName"
        return $true

    } catch {
        Write-Log "Error closing process: $_" "ERROR"
        return $false
    }
}

# ========================= UPDATE FUNCTION ========================= #

function Update-PriorityApp {
    param([string]$AppId, [string]$AppName, [int]$RetryCount = 0)

    Write-Log "[PRIORITY] Updating: $AppName ($AppId)"

    # Force close if configured
    if ($ForceCloseApps) {
        $closed = Stop-AppProcess -AppId $AppId
        if (-not $closed) {
            Write-Log "Failed to close $AppName" "WARN"
        }
    }

    # Validate AppId format for security
    if ($AppId -notmatch '^[a-zA-Z0-9\.\-_]+$') {
        Write-Log "Invalid AppId format: $AppId" "ERROR"
        return $false
    }

    try {
        Write-Log "Executing: winget upgrade --id $AppId --silent"

        $job = Start-Job -ScriptBlock {
            param($id)
            & winget upgrade --id $id --silent --accept-source-agreements --accept-package-agreements 2>&1
        } -ArgumentList $AppId

        $completed = Wait-Job -Job $job -Timeout ($TimeoutMinutes * 60)

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
                return $true
            } else {
                Write-Log "Update failed for $AppName" "ERROR"

                if ($RetryCount -lt ($MaxRetries - 1)) {
                    Write-Log "Retrying (attempt $($RetryCount + 2)/$MaxRetries)..."
                    Start-Sleep -Seconds 5
                    return Update-PriorityApp -AppId $AppId -AppName $AppName -RetryCount ($RetryCount + 1)
                }

                return $false
            }
        } else {
            Stop-Job -Job $job
            Remove-Job -Job $job -Force
            Write-Log "Update timed out for $AppName" "ERROR"
            return $false
        }

    } catch {
        Write-Log "Error updating $AppName : $_" "ERROR"

        if ($RetryCount -lt ($MaxRetries - 1)) {
            Start-Sleep -Seconds 5
            return Update-PriorityApp -AppId $AppId -AppName $AppName -RetryCount ($RetryCount + 1)
        }

        return $false
    }
}

# ========================= MAIN LOGIC ========================= #

try {
    Write-Log "=== PRIORITY App Update Remediation Started ==="
    Write-Log "Force Close: $ForceCloseApps"
    Write-Log "Priority Apps: $($PriorityApps.Count)"

    # Get outdated priority apps
    $wingetOutput = & winget list --upgrade-available 2>&1 | Out-String
    $lines = $wingetOutput -split "`n" | Where-Object { $_ -match '\S' }

    $outdatedPriorityApps = @()

    foreach ($line in $lines) {
        if ($line -match '^Name\s+Id\s+' -or $line -match '^-+' -or $line -match '^\d+ upgrades available') {
            continue
        }

        if ($line -match '^\s*(.+?)\s{2,}([^\s]+\.[^\s]+)\s+') {
            $appName = $matches[1].Trim()
            $appId = $matches[2].Trim()

            if ($appId -in $PriorityApps) {
                $outdatedPriorityApps += [PSCustomObject]@{
                    Name = $appName
                    Id = $appId
                }
            }
        }
    }

    if ($outdatedPriorityApps.Count -eq 0) {
        Write-Log "No priority applications require updates"
        exit 0
    }

    Write-Log "Found $($outdatedPriorityApps.Count) priority apps to update"
    Write-Log ""

    # Update each priority app
    $successCount = 0
    $failCount = 0

    foreach ($app in $outdatedPriorityApps) {
        $success = Update-PriorityApp -AppId $app.Id -AppName $app.Name

        if ($success) {
            $successCount++
        } else {
            $failCount++
        }

        Write-Log ""
    }

    # Summary
    Write-Log "=== PRIORITY Remediation Complete ==="
    Write-Log "Successfully Updated: $successCount"
    Write-Log "Failed: $failCount"

    if ($successCount -gt 0) {
        Write-Log "Priority security updates completed successfully"
        exit 0
    } else {
        Write-Log "No priority applications were updated" "WARN"
        exit 1
    }

} catch {
    Write-Log "Unexpected error: $_" "ERROR"
    exit 1
}
