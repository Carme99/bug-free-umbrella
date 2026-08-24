<#
.SYNOPSIS
    Flushes the DNS cache and resets the DNS Client service.

.DESCRIPTION
    Flushes the Windows DNS resolver cache with Clear-DnsClientCache and then resets the DNS
    Client (Dnscache) service: the service is started when it is not running and restarted when
    it already is. Flushing the cache and restarting the service change local DNS client state,
    so both steps honor -WhatIf/-Confirm via SupportsShouldProcess. Exit codes:
    - 0: DNS cache flushed and DNS Client service reset successfully.
    - 1: the flush or the service reset failed.

.EXAMPLE
    PS C:\> .\Invoke-RemediationFixDNSCache.ps1
    Flushes the DNS cache and recycles the Dnscache service, exiting 0 on success.

.EXAMPLE
    PS C:\> .\Invoke-RemediationFixDNSCache.ps1 -WhatIf
    Reports what would be flushed and restarted without touching the system.

.NOTES
    File Name: Invoke-RemediationFixDNSCache.ps1
    Author: Bug-Free Umbrella
    Prerequisite: PowerShell 7.0
    Version: 1.0.0
    Date: 2026-08-23
#>

[CmdletBinding(SupportsShouldProcess)]

$ErrorActionPreference = 'Stop'

function Main {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    try {
        Write-Host "[*] Flushing DNS cache and resetting DNS Client service..." -ForegroundColor Cyan

        if (-not $PSCmdlet.ShouldProcess("DNS client", "Flush DNS cache and reset Dnscache service")) {
            return 0
        }

        # Flush DNS cache.
        Clear-DnsClientCache -ErrorAction Stop

        # Restart DNS client service if needed.
        $dnsClient = Get-Service -Name "Dnscache" -ErrorAction SilentlyContinue

        if ($dnsClient.Status -ne "Running") {
            Start-Service -Name "Dnscache" -ErrorAction Stop
        }
        else {
            Restart-Service -Name "Dnscache" -Force -ErrorAction Stop
        }

        Write-Host "[+] Successfully flushed DNS cache and restarted DNS Client service" -ForegroundColor Green
        return 0
    }
    catch {
        Write-Host "[-] Failed to flush DNS cache: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
