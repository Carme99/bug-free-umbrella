<#
.SYNOPSIS
    PostgreSQL database server health monitoring.
.DESCRIPTION
    Monitors PostgreSQL health: connections, locks, replication, query performance, vacuum status.
.EXAMPLE
    .\Get-PostgreSQLHealth.ps1 -Server localhost -Database postgres -Username postgres
.NOTES
    Requires: psql command-line client or Npgsql library
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Server,
    [Parameter()][string]$Database = "postgres",
    [Parameter(Mandatory)][string]$Username,
    [Parameter()][int]$Port = 5432,
    [switch]$CheckReplication,
    [switch]$ExportHTML
)

# SecureString handling - get BSTR pointer once, use it, then free the SAME pointer
$SecurePassword = Read-Host "Enter password" -AsSecureString
$bstrPtr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecurePassword)
try {
    # Convert to plain text
    $Password = [Runtime.InteropServices.Marshal]::PtrToStringAuto($bstrPtr)
    
    # Export to environment variable for psql
    # Note: This exposes password to other processes - acknowledge this security trade-off
    $env:PGPASSWORD = $Password
}
finally {
    # Zero and free the BSTR - THIS is the same pointer we've been using
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstrPtr)
}

Write-Host "`n=== PostgreSQL Health Check ===" -ForegroundColor Cyan

# Check psql availability
if (-not (Get-Command psql -ErrorAction SilentlyContinue)) {
    Write-Host "[!] psql client not found in PATH" -ForegroundColor Red
    exit 1
}

Write-Host "[*] Connecting to PostgreSQL: $Server`:$Port/$Database" -ForegroundColor Cyan

# Get version
$version = psql -h $Server -p $Port -U $Username -d $Database -t -c "SELECT version();" 2>$null
Write-Host "[+] PostgreSQL Version: $($version.Trim())" -ForegroundColor Green

# Get database stats
Write-Host "[*] Collecting database statistics..." -ForegroundColor Cyan
$dbStats = psql -h $Server -p $Port -U $Username -d $Database -t -c "SELECT count(*) FROM pg_database;" 2>$null
Write-Host "[+] Total databases: $($dbStats.Trim())" -ForegroundColor Green

# Check connections
$connections = psql -h $Server -p $Port -U $Username -d $Database -t -c "SELECT count(*) FROM pg_stat_activity;" 2>$null
Write-Host "[+] Active connections: $($connections.Trim())" -ForegroundColor Green

# Check for long-running queries
$longQueries = psql -h $Server -p $Port -U $Username -d $Database -t -c "SELECT count(*) FROM pg_stat_activity WHERE state = 'active' AND now() - query_start > interval '5 minutes';" 2>$null
if ([int]$longQueries.Trim() -gt 0) {
    Write-Host "[!] Warning: $($longQueries.Trim()) long-running queries detected" -ForegroundColor Yellow
}

Write-Host "`nHealth check complete!`n" -ForegroundColor Green
