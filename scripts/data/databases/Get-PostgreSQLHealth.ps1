<#
.SYNOPSIS
    Check PostgreSQL server health and report version, databases, and connections.
.DESCRIPTION
    Connects to a PostgreSQL server with the psql command-line client and reports the server
    version, total database count, active connection count, and long-running queries.
    The password is read as a SecureString, exported to PGPASSWORD for the psql child process,
    and the BSTR pointer is zero-freed immediately after use.
    All psql invocations are routed through the Invoke-PsqlCommand wrapper, whose
    $LASTEXITCODE is checked; any non-zero result aborts the check with exit code 1.
    This script is read-only and safe to re-run against the same server.
.PARAMETER Server
    PostgreSQL server hostname or IP address to check.
.PARAMETER Database
    Database to connect to for the health queries. Default: postgres.
.PARAMETER Username
    PostgreSQL role used to authenticate.
.PARAMETER Port
    TCP port the server listens on. Default: 5432.
.PARAMETER CheckReplication
    Reserved switch retained for compatibility; replication checks are not yet performed.
.PARAMETER ExportHTML
    Reserved switch retained for compatibility; no HTML export is currently performed.
.EXAMPLE
    PS C:\> .\Get-PostgreSQLHealth.ps1 -Server localhost -Database postgres -Username postgres
    Runs a basic health check against the local PostgreSQL server.

.EXAMPLE
    PS C:\> .\Get-PostgreSQLHealth.ps1 -Server pg01 -Username monitor -Port 5433
    Checks pg01 on port 5433 using the monitor role.
.NOTES
    File Name   : Get-PostgreSQLHealth.ps1
    Author      : Bug-Free Umbrella
    Prerequisite: PowerShell 7.0
    Version     : 1.0.0
    Date        : 2026-08-23
    Requires the psql command-line client (or Npgsql library).
    Note: Invoke-ScriptAnalyzer PSAvoidUsingWriteHost warnings are intentional;
    RELAUNCH-SPEC section 3 mandates Write-Host-based [+] / [!] / [-] / [*] status output.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$Server,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$Database = 'postgres',

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$Username,

    [Parameter()]
    [ValidateRange(1, 65535)]
    [int]$Port = 5432,

    [switch]$CheckReplication,

    [switch]$ExportHTML
)

$ErrorActionPreference = 'Stop'

function Invoke-PsqlCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$ArgumentList
    )

    # Thin wrapper around the native psql CLI; the mock seam for Pester tests (RELAUNCH-SPEC §3/§5).
    $output = & psql @ArgumentList 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[-] psql exited with code $LASTEXITCODE" -ForegroundColor Red
        return $null
    }
    return $output
}

function Main {
    try {
        Write-Host "`n=== PostgreSQL Health Check ===" -ForegroundColor Cyan

        # Check psql availability
        if (-not (Get-Command psql -ErrorAction SilentlyContinue)) {
            Write-Host "[-] psql client not found in PATH" -ForegroundColor Red
            return 1
        }

        # SecureString handling - get BSTR pointer once, use it, then free the SAME pointer
        $SecurePassword = Read-Host 'Enter password' -AsSecureString -ErrorAction Stop
        $bstrPtr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecurePassword)
        try {
            # Convert to plain text
            $Password = [Runtime.InteropServices.Marshal]::PtrToStringUni($bstrPtr)

            # Export to environment variable for psql
            # Note: This exposes password to other processes - acknowledge this security trade-off
            $env:PGPASSWORD = $Password
        }
        finally {
            # Zero and free the BSTR - THIS is the same pointer we've been using
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstrPtr)
        }

        Write-Host "[*] Connecting to PostgreSQL: ${Server}:$Port/$Database" -ForegroundColor Cyan

        $psqlArgs = @('-h', $Server, '-p', "$Port", '-U', $Username, '-d', $Database, '-t')

        # Get version
        Write-Host "[*] Checking PostgreSQL version..." -ForegroundColor Cyan
        $version = Invoke-PsqlCommand -ArgumentList ($psqlArgs + @('-c', 'SELECT version();')) -ErrorAction Stop
        if ($null -eq $version) { return 1 }
        Write-Host "[+] PostgreSQL Version: $($version.Trim())" -ForegroundColor Green

        # Get database stats
        Write-Host "[*] Collecting database statistics..." -ForegroundColor Cyan
        $dbStatsArgs = $psqlArgs + @('-c', 'SELECT count(*) FROM pg_database;')
        $dbStats = Invoke-PsqlCommand -ArgumentList $dbStatsArgs -ErrorAction Stop
        if ($null -eq $dbStats) { return 1 }
        Write-Host "[+] Total databases: $($dbStats.Trim())" -ForegroundColor Green

        # Check connections
        $connArgs = $psqlArgs + @('-c', 'SELECT count(*) FROM pg_stat_activity;')
        $connections = Invoke-PsqlCommand -ArgumentList $connArgs -ErrorAction Stop
        if ($null -eq $connections) { return 1 }
        Write-Host "[+] Active connections: $($connections.Trim())" -ForegroundColor Green

        # Check for long-running queries
        $longQuerySql = "SELECT count(*) FROM pg_stat_activity WHERE state = 'active' " +
            "AND now() - query_start > interval '5 minutes';"
        $longQueries = Invoke-PsqlCommand -ArgumentList ($psqlArgs + @('-c', $longQuerySql)) -ErrorAction Stop
        if ($null -eq $longQueries) { return 1 }
        if ([int]$longQueries.Trim() -gt 0) {
            Write-Host "[!] Warning: $($longQueries.Trim()) long-running queries detected" -ForegroundColor Yellow
        }

        Write-Host "`nHealth check complete!`n" -ForegroundColor Green
        return 0
    }
    catch {
        Write-Host "[-] Error: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests) skips execution (RELAUNCH-SPEC §3).
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
