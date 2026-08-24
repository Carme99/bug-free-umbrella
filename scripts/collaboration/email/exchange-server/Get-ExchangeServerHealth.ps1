<#
.SYNOPSIS
    Check Exchange Server health across services, mailbox databases, and mail queues.

.DESCRIPTION
    Loads the Exchange Management Shell snap-in, enumerates all Exchange servers except Edge
    role servers, and verifies that Exchange-related Windows services are running on each one.
    Optionally reports mailbox database mount status (-CheckDatabaseHealth) and total mail
    queue message counts (-CheckMailQueues). Returns exit code 0 when the check completes and
    exit code 1 when the Exchange Management Shell is unavailable or a data-gathering call fails.

.PARAMETER ExportHTML
    Reserved switch retained for interface compatibility; results are reported to the console
    only and no HTML file is written.

.PARAMETER CheckDatabaseHealth
    Additionally report the mount status (Mounted/Dismounted) of every mailbox database.

.PARAMETER CheckMailQueues
    Additionally report the total number of messages across all mail queues.

.EXAMPLE
    PS C:\> .\Get-ExchangeServerHealth.ps1

    Runs a basic health check of all Exchange servers and their Exchange services.

.EXAMPLE
    PS C:\> .\Get-ExchangeServerHealth.ps1 -CheckDatabaseHealth -CheckMailQueues

    Runs a full health check including database mount status and mail queue totals.

.NOTES
    File Name  : Get-ExchangeServerHealth.ps1
    Author     : Bug-Free Umbrella
    Prerequisite: PowerShell 7.0
    Version    : 1.0.0
    Date       : 2026-08-23

    Requires: Exchange Management Shell (run on an Exchange server or management host).
    Note: Exchange Server 2019 reached end of extended support on 2025-10-15. This script operates
    against an out-of-support platform.
    Lifecycle: https://learn.microsoft.com/en-us/lifecycle/products/exchange-server-2019
#>

[CmdletBinding()]
param(
    [switch]$ExportHTML,

    [switch]$CheckDatabaseHealth,

    [switch]$CheckMailQueues
)

$ErrorActionPreference = 'Stop'

# Write-Host is intentional throughout: AGENTS.md requires user-facing colored [+] [!] [-] [*] console output.
function Main {
    [CmdletBinding()]
    param(
        [switch]$ExportHTML,

        [switch]$CheckDatabaseHealth,

        [switch]$CheckMailQueues
    )

    try {
        Write-Host "`n=== Exchange Server Health Check ===" -ForegroundColor Cyan

        # Check Exchange PowerShell
        try {
            Add-PSSnapin Microsoft.Exchange.Management.PowerShell.SnapIn -ErrorAction Stop
            Write-Host "[+] Exchange Management Shell loaded" -ForegroundColor Green
        }
        catch {
            Write-Host "[-] Exchange Management Shell not available" -ForegroundColor Red
            return 1
        }

        Write-Host "[*] Checking Exchange servers..." -ForegroundColor Cyan
        $servers = Get-ExchangeServer -ErrorAction Stop | Where-Object { $_.ServerRole -ne "Edge" }
        Write-Host "[+] Found $($servers.Count) Exchange servers" -ForegroundColor Green

        foreach ($server in $servers) {
            Write-Host "`nServer: $($server.Name) ($($server.ServerRole))" -ForegroundColor Cyan

            # Check services
            $services = Get-Service -ComputerName $server.Name -ErrorAction Stop |
                Where-Object { $_.DisplayName -like "*Exchange*" }
            $stoppedServices = @($services | Where-Object { $_.Status -ne "Running" })
            if ($stoppedServices.Count -gt 0) {
                $stoppedMsg = "[!] $($stoppedServices.Count) Exchange services stopped on $($server.Name)"
                Write-Host $stoppedMsg -ForegroundColor Yellow
            }
            else {
                Write-Host "[+] All Exchange services running" -ForegroundColor Green
            }
        }

        if ($CheckDatabaseHealth) {
            Write-Host "`n[*] Checking mailbox databases..." -ForegroundColor Cyan
            $databases = Get-MailboxDatabase -Status -ErrorAction Stop
            foreach ($db in $databases) {
                $mounted = if ($db.Mounted) { "Mounted" } else { "Dismounted" }
                $color = if ($db.Mounted) { "Green" } else { "Red" }
                Write-Host "  - $($db.Name): $mounted" -ForegroundColor $color
            }
        }

        if ($CheckMailQueues) {
            Write-Host "`n[*] Checking mail queues..." -ForegroundColor Cyan
            $queues = Get-Queue -ErrorAction Stop
            $totalMessages = ($queues | Measure-Object MessageCount -Sum).Sum
            $queueColor = if ($totalMessages -gt 100) { "Yellow" } else { "Green" }
            Write-Host "[+] Total messages in queues: $totalMessages" -ForegroundColor $queueColor
        }

        Write-Host "`n[+] Health check complete!" -ForegroundColor Green
        return 0
    }
    catch {
        Write-Host "[-] Error: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main @PSBoundParameters) }
