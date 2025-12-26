<#
.SYNOPSIS
    Flushes DNS cache and resets DNS client to resolve connectivity issues.

.DESCRIPTION
    This remediation script flushes the DNS cache and resets DNS client settings
    to resolve DNS resolution problems.

.NOTES
    Exit 0: Successfully flushed DNS cache
    Exit 1: Failed to flush DNS cache
#>

$ErrorActionPreference = "Stop"

try {
    # Flush DNS cache
    Clear-DnsClientCache

    # Restart DNS client service if needed
    $dnsClient = Get-Service -Name "Dnscache" -ErrorAction SilentlyContinue

    if ($dnsClient.Status -ne "Running") {
        Start-Service -Name "Dnscache"
    }
    else {
        Restart-Service -Name "Dnscache" -Force
    }

    Write-Output "Successfully flushed DNS cache and restarted DNS Client service"
    exit 0  # Success
}
catch {
    Write-Output "Failed to flush DNS cache: $($_.Exception.Message)"
    exit 1  # Failure
}
