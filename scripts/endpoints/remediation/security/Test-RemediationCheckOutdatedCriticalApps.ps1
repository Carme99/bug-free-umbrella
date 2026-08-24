<#
.SYNOPSIS
    Detects outdated security-critical applications using winget.

.DESCRIPTION
    Scans for available updates to security-critical applications (browsers, VPN clients,
    development tools) using winget and prioritizes applications that commonly have CVEs
    and need rapid patching. Supports configurable priority lists, retry logic, and
    optional logging. This is a read-only detection script: it never installs or modifies
    anything, so re-running it on a fully patched device converges to exit 0 (idempotent).
    Exit codes:
    - 0: compliant - no critical updates needed.
    - 1: non-compliant - critical updates are available, winget/network is unavailable, or the check failed.

.PARAMETER EnableLogging
    Enable detailed logging to %TEMP%\WingetUpdateDetection.log.

.PARAMETER MaxRetries
    Maximum retry attempts for winget operations (default: 3).

.PARAMETER PriorityAppsOnly
    Only check priority applications (browsers, security tools).

.EXAMPLE
    PS C:\> .\Test-RemediationCheckOutdatedCriticalApps.ps1
    Standard detection with default settings; exits 1 when critical updates are available.

.EXAMPLE
    PS C:\> .\Test-RemediationCheckOutdatedCriticalApps.ps1 -EnableLogging $true -PriorityAppsOnly $true
    Check only priority apps with logging enabled to %TEMP%\WingetUpdateDetection.log.

.NOTES
    File Name: Test-RemediationCheckOutdatedCriticalApps.ps1
    Author: Bug-Free Umbrella
    Prerequisite: PowerShell 7.0
    Version: 1.0.0
    Date: 2026-08-23
#>

[CmdletBinding()]
param(
    [bool]$EnableLogging = $false,

    [ValidateRange(1, 10)]
    [int]$MaxRetries = 3,

    [bool]$PriorityAppsOnly = $false
)

$ErrorActionPreference = 'Stop'

function Main {
    try {
        Write-Log "=== Winget Critical App Update Detection Started ==="
        Write-Log "Priority Apps Only: $PriorityAppsOnly"

        # Validate winget is available
        if (-not (Test-WingetAvailable)) {
            Write-Log "Winget is not available on this system" "ERROR"
            return 1
        }

        # Check network connectivity
        if (-not (Test-NetworkConnectivity)) {
            Write-Log "Network connectivity required for update detection" "ERROR"
            return 1
        }

        # Get outdated applications
        $outdatedApps = Get-OutdatedApps

        if ($outdatedApps.Count -eq 0) {
            Write-Log "No outdated applications detected" "OK"
            return 0
        }

        # Filter for priority apps if configured
        if ($PriorityAppsOnly) {
            $criticalUpdates = @($outdatedApps | Where-Object { $_.IsPriority -eq $true })
        }
        else {
            # Include priority and standard apps
            $appsToCheck = $PriorityApps + $StandardApps
            $criticalUpdates = @($outdatedApps | Where-Object { $_.Id -in $appsToCheck })
        }

        if ($criticalUpdates.Count -eq 0) {
            Write-Log "No critical application updates detected" "OK"
            Write-Log "($($outdatedApps.Count) non-critical updates available)" "OK"
            return 0
        }

        # Log details of critical updates
        Write-Log "CRITICAL UPDATES DETECTED: $($criticalUpdates.Count) applications"
        Write-Log ""
        Write-Log "Applications requiring updates:"

        $priorityCount = @($criticalUpdates | Where-Object { $_.IsPriority }).Count
        $standardCount = $criticalUpdates.Count - $priorityCount

        foreach ($app in ($criticalUpdates | Sort-Object -Property IsPriority -Descending)) {
            $priorityTag = if ($app.IsPriority) { "[PRIORITY]" } else { "[STANDARD]" }
            Write-Log "  $priorityTag $($app.Name) ($($app.Id))"
            Write-Log "    Current: $($app.CurrentVersion) -> Available: $($app.AvailableVersion)"
        }

        Write-Log ""
        Write-Log "Summary: $priorityCount priority, $standardCount standard updates needed"
        Write-Log "=== Detection Complete - Remediation Required ==="

        return 1
    }
    catch {
        Write-Log "Unexpected error during detection: $($_.Exception.Message)" "ERROR"
        Write-Log "Stack trace: $($_.ScriptStackTrace)" "ERROR"
        return 1
    }
}

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

# Additional important apps (checked if PriorityAppsOnly = $false)
$StandardApps = @(
    'Adobe.Acrobat.Reader.64-bit',
    'VideoLAN.VLC',
    'Zoom.Zoom',
    'Microsoft.Teams',
    'Notepad++.Notepad++',
    '7zip.7zip',
    'Microsoft.PowerToys'
)

# GetTempPath resolves %TEMP% under Windows and stays safe when TEMP is unset.
$LogPath = Join-Path ([System.IO.Path]::GetTempPath()) 'WingetUpdateDetection.log'

# ========================= LOGGING ========================= #

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    switch ($Level) {
        "WARN"  { $prefix = "[!]"; $color = 'Yellow' }
        "ERROR" { $prefix = "[-]"; $color = 'Red' }
        "OK"    { $prefix = "[+]"; $color = 'Green' }
        default { $prefix = "[*]"; $color = 'Cyan' }
    }
    $logMessage = "[$timestamp] [$Level] $prefix $Message"

    if ($EnableLogging) {
        Add-Content -Path $LogPath -Value $logMessage -ErrorAction SilentlyContinue
    }

    Write-Host $logMessage -ForegroundColor $color
}

# ========================= WINGET VALIDATION ========================= #

function Test-WingetAvailable {
    try {
        $wingetPath = Get-Command winget -ErrorAction Stop
        Write-Log "Winget found at: $($wingetPath.Source)"
        return $true
    }
    catch {
        # Include exception details in log
        Write-Log "Winget not found or not accessible: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

function Test-NetworkConnectivity {
    try {
        $testConnection = Test-NetConnection -ComputerName "www.microsoft.com" -Port 443 `
            -InformationLevel Quiet -WarningAction SilentlyContinue -ErrorAction Stop
        if ($testConnection) {
            Write-Log "Network connectivity verified" "OK"
            return $true
        }
    }
    catch {
        Write-Log "Network connectivity check failed: $($_.Exception.Message)" "WARN"
    }
    return $false
}

# ========================= UPDATE DETECTION ========================= #

function Invoke-Winget {
    # Thin wrapper for the native winget executable; returns output plus its exit code.
    param([string[]]$ArgumentList)
    $output = & winget @ArgumentList 2>&1 | Out-String
    return [pscustomobject]@{ Output = $output; ExitCode = $LASTEXITCODE }
}

function Get-OutdatedApps {
    param([int]$RetryCount = 0)

    Write-Log "Checking for available updates (attempt $($RetryCount + 1)/$MaxRetries)"

    try {
        # Run winget list with upgrade filter (explicitly use Microsoft source)
        $wingetResult = Invoke-Winget -ArgumentList @('list', '--upgrade-available', '--source', 'winget')
        $wingetOutput = $wingetResult.Output

        if ($wingetResult.ExitCode -ne 0 -and $RetryCount -lt ($MaxRetries - 1)) {
            Write-Log "Winget command failed (exit code: $($wingetResult.ExitCode)), retrying..." "WARN"
            Start-Sleep -Seconds ([Math]::Pow(2, $RetryCount))  # Exponential backoff
            return Get-OutdatedApps -RetryCount ($RetryCount + 1)
        }

        # Parse winget output to find outdated apps
        $lines = $wingetOutput -split "`n" | Where-Object { $_ -match '\S' }
        $outdatedApps = @()
        $failedParseCount = 0
        $dataLineCount = 0

        foreach ($line in $lines) {
            # Skip header lines and non-data lines
            if ($line -match '^Name\s+Id\s+' -or $line -match '^-+' -or $line -match '^\d+ upgrades available') {
                continue
            }

            # Count potential data lines (lines that aren't obviously headers/footers)
            if ($line -match '[a-zA-Z]' -and $line -notmatch '^\s*$') {
                $dataLineCount++
            }

            # Match lines with package information
            # Format: Name  Id  Version  Available
            if ($line -match '^\s*(.+?)\s{2,}([^\s]+\.[^\s]+)\s+([^\s]+)\s+([^\s]+)') {
                $appName = $matches[1].Trim()
                $appId = $matches[2].Trim()
                $currentVersion = $matches[3].Trim()
                $availableVersion = $matches[4].Trim()

                # Defense-in-depth validation at parsing stage
                if ([string]::IsNullOrWhiteSpace($appId) -or -not ($appId -match '\.')) {
                    Write-Log "Regex matched but captured invalid App ID from line: $line" "WARN"
                    $failedParseCount++
                    continue
                }

                # Additional security validation: AppId format check (defense-in-depth)
                if ($appId -notmatch '^[a-zA-Z0-9\.\-_]+$') {
                    Write-Log "AppId contains invalid characters (security check): $appId" "WARN"
                    $failedParseCount++
                    continue
                }

                if ([string]::IsNullOrWhiteSpace($appName)) {
                    Write-Log "Regex matched but captured empty App Name from line: $line" "WARN"
                    $failedParseCount++
                    continue
                }

                $outdatedApps += [PSCustomObject]@{
                    Name = $appName
                    Id = $appId
                    CurrentVersion = $currentVersion
                    AvailableVersion = $availableVersion
                    IsPriority = ($appId -in $PriorityApps)
                }
            }
            elseif ($line -match '[a-zA-Z]' -and $line -notmatch '^\s*$' -and $dataLineCount -gt 0) {
                # Log lines that look like data but failed to parse
                Write-Log "Failed to parse potential data line: $line" "WARN"
                $failedParseCount++
            }
        }

        # Warn if significant parsing failures occurred
        if ($failedParseCount -gt 0) {
            $failureRate = [math]::Round(($failedParseCount / [math]::Max($dataLineCount, 1)) * 100, 1)
            Write-Log "Warning: $failedParseCount of $dataLineCount lines failed to parse ($failureRate%)" "WARN"

            # Exit with error when failure rate is critically high
            if ($failureRate -gt 75) {
                Write-Log ("CRITICAL: Parse failure rate exceeds 75% - winget output format may have " +
                    "changed. This may indicate security updates are not being detected properly.") "ERROR"
                return @()  # Return empty array to trigger remediation failure
            }
            elseif ($failureRate -gt 50) {
                Write-Log ("High parse failure rate suggests winget output format may have changed. " +
                    "Consider investigating.") "ERROR"
            }
        }

        Write-Log "Found $($outdatedApps.Count) total outdated applications" "OK"
        return $outdatedApps

    }
    catch {
        Write-Log "Error detecting updates: $($_.Exception.Message)" "ERROR"
        if ($RetryCount -lt ($MaxRetries - 1)) {
            Start-Sleep -Seconds ([Math]::Pow(2, $RetryCount))
            return Get-OutdatedApps -RetryCount ($RetryCount + 1)
        }
        return @()
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
