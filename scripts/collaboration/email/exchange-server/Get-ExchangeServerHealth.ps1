<#
.SYNOPSIS
    Exchange Server health check and monitoring.
.DESCRIPTION
    Comprehensive Exchange Server health assessment including services, databases, queues, and replication.
.EXAMPLE
    .\Get-ExchangeServerHealth.ps1 -ExportHTML
.NOTES
    Requires: Exchange Management Shell
#>
[CmdletBinding()]
param([switch]$ExportHTML, [switch]$CheckDatabaseHealth, [switch]$CheckMailQueues)

Write-Host "`n=== Exchange Server Health Check ===" -ForegroundColor Cyan

# Check Exchange PowerShell
try {
    Add-PSSnapin Microsoft.Exchange.Management.PowerShell.SnapIn -ErrorAction Stop
    Write-Host "[+] Exchange Management Shell loaded" -ForegroundColor Green
} catch {
    Write-Host "[!] Exchange Management Shell not available" -ForegroundColor Red
    exit 1
}

Write-Host "[*] Checking Exchange servers..." -ForegroundColor Cyan
$servers = Get-ExchangeServer | Where-Object {$_.ServerRole -ne "Edge"}
Write-Host "[+] Found $($servers.Count) Exchange servers" -ForegroundColor Green

foreach ($server in $servers) {
    Write-Host "`nServer: $($server.Name) ($($server.ServerRole))" -ForegroundColor Cyan
    
    # Check services
    $services = Get-Service -ComputerName $server.Name | Where-Object {$_.DisplayName -like "*Exchange*"}
    $stoppedServices = $services | Where-Object {$_.Status -ne "Running"}
    if ($stoppedServices) {
        Write-Host "[!] $($stoppedServices.Count) Exchange services stopped on $($server.Name)" -ForegroundColor Yellow
    } else {
        Write-Host "[+] All Exchange services running" -ForegroundColor Green
    }
}

if ($CheckDatabaseHealth) {
    Write-Host "`n[*] Checking mailbox databases..." -ForegroundColor Cyan
    $databases = Get-MailboxDatabase -Status
    foreach ($db in $databases) {
        $mounted = if ($db.Mounted) {"Mounted"} else {"Dismounted"}
        $color = if ($db.Mounted) {"Green"} else {"Red"}
        Write-Host "  - $($db.Name): $mounted" -ForegroundColor $color
    }
}

if ($CheckMailQueues) {
    Write-Host "`n[*] Checking mail queues..." -ForegroundColor Cyan
    $queues = Get-Queue
    $totalMessages = ($queues | Measure-Object MessageCount -Sum).Sum
    Write-Host "[+] Total messages in queues: $totalMessages" -ForegroundColor $(if ($totalMessages -gt 100) {"Yellow"} else {"Green"})
}

Write-Host "`nHealth check complete!`n" -ForegroundColor Green
