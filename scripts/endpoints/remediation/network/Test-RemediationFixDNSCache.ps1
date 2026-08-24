<#
.SYNOPSIS
    Detects DNS resolution issues by testing connectivity to common domains.
.DESCRIPTION
    Resolves three common domains (microsoft.com, google.com, cloudflare.com) via Resolve-DnsName
    and counts how many fail. When two or more domains fail, DNS is considered broken and the
    paired cache-flush remediation should run; a single failure can be transient and does not
    trigger remediation. This is a read-only detection script: it never flushes or modifies the
    DNS cache itself, so re-running it on a converged system is safe (idempotent).
    Exit codes:
    - 0: compliant - DNS resolution is working correctly (fewer than two domain failures).
    - 1: non-compliant - two or more domains failed to resolve, triggering remediation, or the
      check failed outright.
.EXAMPLE
    PS C:\> .\Test-RemediationFixDNSCache.ps1
    Tests DNS resolution for the common domains and exits 0 when healthy, 1 when broken.
.EXAMPLE
    PS C:\> & 'C:\Program Files\Intune\ProactiveRemediations\Test-RemediationFixDNSCache.ps1'
    Runs the same check from the Intune Management Extension under the SYSTEM context.
.NOTES
    File Name: Test-RemediationFixDNSCache.ps1
    Author: Bug-Free Umbrella
    Prerequisite: PowerShell 7.0
    Version: 1.0.0
    Date: 2026-08-23
#>

[CmdletBinding()]

$ErrorActionPreference = 'Stop'

function Main {
    try {
        Write-Host "[*] Testing DNS resolution against common domains..." -ForegroundColor Cyan

        # Test domains.
        $testDomains = @(
            'microsoft.com',
            'google.com',
            'cloudflare.com'
        )

        $failedDomains = @()

        foreach ($domain in $testDomains) {
            try {
                $result = Resolve-DnsName -Name $domain -ErrorAction Stop -QuickTimeout
                if (-not $result) {
                    $failedDomains += $domain
                }
            }
            catch {
                $failedDomains += $domain
            }
        }

        # If more than 1 domain fails, likely a DNS issue worth remediating; a single
        # failure can be transient and must not trigger the cache-flush remediation.
        if ($failedDomains.Count -ge 2) {
            $msg = "[!] DNS resolution failed for $($failedDomains.Count) domain(s): $($failedDomains -join ', ')"
            Write-Host $msg -ForegroundColor Yellow
            return 1
        }

        Write-Host "[+] DNS resolution is working correctly" -ForegroundColor Green
        return 0
    }
    catch {
        Write-Host "[-] Error checking DNS resolution: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
