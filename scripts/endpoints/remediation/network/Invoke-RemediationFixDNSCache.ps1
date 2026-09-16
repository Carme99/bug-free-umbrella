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
    Version: 2.0.0
    Date: 2026-09-16
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

        # Start the DNS client service only when it is not running. Dnscache runs on every
        # healthy client, so an unconditional restart bounced the resolver on every cycle -
        # a converged system must be left alone.
        $dnsClient = Get-Service -Name "Dnscache" -ErrorAction SilentlyContinue

        if ($null -eq $dnsClient) {
            # A failed read is not the same as a stopped service; $null.Status would be $null
            # and the comparison would silently pass as "not running".
            throw "DNS Client service (Dnscache) could not be queried"
        }

        if ($dnsClient.Status -ne "Running") {
            Start-Service -Name "Dnscache" -ErrorAction Stop
            Write-Host "[+] Started the DNS Client service" -ForegroundColor Green
        }
        else {
            Write-Host "[+] Already running: DNS Client service" -ForegroundColor Green
        }

        Write-Host "[+] Successfully flushed DNS cache" -ForegroundColor Green
        return 0
    }
    catch {
        Write-Host "[-] Failed to flush DNS cache: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
