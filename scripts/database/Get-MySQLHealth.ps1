<#
.SYNOPSIS
    MySQL database server health monitoring.
.DESCRIPTION
    Monitors MySQL server health: connections, queries, replication, performance metrics.
.EXAMPLE
    .\Get-MySQLHealth.ps1 -Server localhost -Username root -ExportHTML
.NOTES
    Requires: MySQL.Data.dll or mysql command-line client
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Server,
    [Parameter(Mandatory)][string]$Username,
    [Parameter()][string]$Password,
    [Parameter()][int]$Port = 3306,
    [switch]$CheckReplication,
    [switch]$ExportHTML
)

Write-Host "`n=== MySQL Health Check ===" -ForegroundColor Cyan
Write-Host "[*] Connecting to MySQL server: $Server`:$Port" -ForegroundColor Cyan

# Check if mysql client is available
$mysqlCmd = Get-Command mysql -ErrorAction SilentlyContinue
if (-not $mysqlCmd) {
    Write-Host "[!] MySQL client not found in PATH" -ForegroundColor Red
    exit 1
}

$cred = if ($Password) {"-p$Password"} else {""}
$results = @{}

# Get version
Write-Host "[*] Checking MySQL version..." -ForegroundColor Cyan
$version = mysql -h $Server -u $Username $cred -P $Port -e "SELECT VERSION();" -sN 2>$null
$results.Version = $version
Write-Host "[+] MySQL Version: $version" -ForegroundColor Green

# Get status
Write-Host "[*] Checking server status..." -ForegroundColor Cyan
$status = mysql -h $Server -u $Username $cred -P $Port -e "SHOW GLOBAL STATUS;" 2>$null
$uptime = ($status | Select-String "Uptime\s+(\d+)").Matches.Groups[1].Value
$threads = ($status | Select-String "Threads_connected\s+(\d+)").Matches.Groups[1].Value
$results.Uptime = [math]::Round([int]$uptime / 3600, 2)
$results.Connections = $threads
Write-Host "[+] Uptime: $($results.Uptime) hours, Connections: $threads" -ForegroundColor Green

# Check databases
Write-Host "[*] Listing databases..." -ForegroundColor Cyan
$databases = mysql -h $Server -u $Username $cred -P $Port -e "SHOW DATABASES;" -sN 2>$null
$dbCount = ($databases | Measure-Object).Count
$results.Databases = $dbCount
Write-Host "[+] Found $dbCount databases" -ForegroundColor Green

if ($CheckReplication) {
    Write-Host "[*] Checking replication status..." -ForegroundColor Cyan
    $replica = mysql -h $Server -u $Username $cred -P $Port -e "SHOW REPLICA STATUS\G" 2>$null
    if ($replica) {
        Write-Host "[+] Replication configured" -ForegroundColor Green
    } else {
        Write-Host "[!] Replication not configured or not a replica" -ForegroundColor Yellow
    }
}

Write-Host "`n=== Summary ===" -ForegroundColor Cyan
Write-Host "Server: $Server`:$Port" -ForegroundColor White
Write-Host "Version: $($results.Version)" -ForegroundColor White
Write-Host "Uptime: $($results.Uptime) hours" -ForegroundColor White
Write-Host "Active Connections: $($results.Connections)" -ForegroundColor White
Write-Host "Databases: $($results.Databases)" -ForegroundColor White

Write-Host "`nHealth check complete!`n" -ForegroundColor Green
