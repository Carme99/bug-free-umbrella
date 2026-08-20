<#
.SYNOPSIS
    Detects time synchronization issues on Windows devices.

.DESCRIPTION
    Checks if Windows Time service is running and if time is properly synchronized.
    Critical for authentication (Kerberos) and certificate validation.

.NOTES
    Author: Intune Admin
    Version: 1.0
    Intune Context: SYSTEM
    Exit 0: Time sync is healthy
    Exit 1: Issues detected - remediation needed
#>

try {
    $issues = @()

    # Check if Windows Time service is running
    $w32timeService = Get-Service -Name "W32Time" -ErrorAction SilentlyContinue
    if ($w32timeService.Status -ne "Running") {
        $issues += "Windows Time service is not running"
    }

    # Check time sync status using w32tm
    $syncStatus = w32tm /query /status 2>&1
    if ($LASTEXITCODE -ne 0) {
        $issues += "Time sync status check failed - service may not be configured"
    }
    else {
        # Check if time source is configured
        if ($syncStatus -match "Source: Local CMOS Clock") {
            $issues += "Time source is set to Local CMOS Clock (should sync from network)"
        }

        # Check last successful sync
        if ($syncStatus -match "Last Successful Sync Time: (.+)") {
            $lastSync = $matches[1]
            if ($lastSync -notmatch "unspecified") {
                try {
                    $lastSyncDate = [DateTime]::Parse($lastSync)
                    $hoursSinceSync = ((Get-Date) - $lastSyncDate).TotalHours
                    if ($hoursSinceSync -gt 24) {
                        $issues += "Last successful sync was over 24 hours ago"
                    }
                }
                catch {
                    Write-Verbose "Handled exception: $($_.Exception.Message)" -Verbose:$false
                }
            }
        }
    }

    # Check service startup type (should be Automatic)
    if ($w32timeService.StartType -ne "Automatic") {
        $issues += "Windows Time service startup type is not set to Automatic"
    }

    if ($issues.Count -gt 0) {
        Write-Host "Time sync issues detected:"
        foreach ($issue in $issues) {
            Write-Host "  - $issue"
        }
        exit 1
    }

    Write-Host "Time synchronization is healthy"
    exit 0

}
catch {
    Write-Host "Error checking time sync status: $_"
    exit 1
}
