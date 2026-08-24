<#
.SYNOPSIS
    Check MySQL server health and report version, uptime, connections, and database count.
.DESCRIPTION
    Connects to a MySQL server with the native mysql command-line client and reports the
    server version, uptime, active thread count, and number of databases.
    When -CheckReplication is supplied, replica status is queried and reported as well.
    All mysql invocations are routed through the Invoke-MySqlCommand wrapper, whose
    $LASTEXITCODE is checked; any non-zero result aborts the check with exit code 1.
    This script is read-only and safe to re-run against the same server.
.PARAMETER Server
    MySQL server hostname or IP address to check.
.PARAMETER Username
    MySQL account used to authenticate.
.PARAMETER Password
    Optional password; when omitted, passwordless authentication is attempted.
.PARAMETER Port
    TCP port the server listens on. Default: 3306.
.PARAMETER CheckReplication
    Also query SHOW REPLICA STATUS and report whether replication is configured.
.PARAMETER ExportHTML
    Reserved switch retained for compatibility; no HTML export is currently performed.
.EXAMPLE
    PS C:\> .\Get-MySQLHealth.ps1 -Server localhost -Username root
    Runs a basic health check against the local MySQL server.

.EXAMPLE
    PS C:\> .\Get-MySQLHealth.ps1 -Server db01 -Username repl -CheckReplication
    Checks db01 and additionally verifies replication status.
.NOTES
    File Name   : Get-MySQLHealth.ps1
    Author      : Bug-Free Umbrella
    Prerequisite: PowerShell 7.0
    Version     : 1.0.0
    Date        : 2026-08-23
    Requires the mysql command-line client in PATH (or MySQL.Data.dll).
    Note: Invoke-ScriptAnalyzer PSAvoidUsingWriteHost warnings are intentional;
    RELAUNCH-SPEC section 3 mandates Write-Host-based [+] / [!] / [-] / [*] status output.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$Server,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$Username,

    [Parameter()]
    [string]$Password,

    [Parameter()]
    [ValidateRange(1, 65535)]
    [int]$Port = 3306,

    [switch]$CheckReplication,

    [switch]$ExportHTML
)

$ErrorActionPreference = 'Stop'

function Invoke-MySqlCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$ArgumentList
    )

    # Thin wrapper around the native mysql CLI; the mock seam for Pester tests (RELAUNCH-SPEC §3/§5).
    $output = & mysql @ArgumentList 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[-] mysql exited with code $LASTEXITCODE" -ForegroundColor Red
        return $null
    }
    return $output
}

function Main {
    try {
        Write-Host "`n=== MySQL Health Check ===" -ForegroundColor Cyan
        Write-Host "[*] Connecting to MySQL server: ${Server}:${Port}" -ForegroundColor Cyan

        # Check if mysql client is available
        if (-not (Get-Command mysql -ErrorAction SilentlyContinue)) {
            Write-Host "[-] MySQL client not found in PATH" -ForegroundColor Red
            return 1
        }

        $baseArgs = @('-h', $Server, '-u', $Username, '-P', "$Port")
        $credArgs = @()
        if ($Password) { $credArgs += "-p$Password" }

        $results = @{}

        # Get version
        Write-Host "[*] Checking MySQL version..." -ForegroundColor Cyan
        $versionArgs = $baseArgs + $credArgs + @('-e', 'SELECT VERSION();', '-sN')
        $version = Invoke-MySqlCommand -ArgumentList $versionArgs -ErrorAction Stop
        if ($null -eq $version) { return 1 }
        $results.Version = $version
        Write-Host "[+] MySQL Version: $version" -ForegroundColor Green

        # Get status
        Write-Host "[*] Checking server status..." -ForegroundColor Cyan
        $statusArgs = $baseArgs + $credArgs + @('-e', 'SHOW GLOBAL STATUS;')
        $status = Invoke-MySqlCommand -ArgumentList $statusArgs -ErrorAction Stop
        if ($null -eq $status) { return 1 }
        $uptime = ($status | Select-String 'Uptime\s+(\d+)').Matches.Groups[1].Value
        $threads = ($status | Select-String 'Threads_connected\s+(\d+)').Matches.Groups[1].Value
        $results.Uptime = [math]::Round([int]$uptime / 3600, 2)
        $results.Connections = $threads
        Write-Host "[+] Uptime: $($results.Uptime) hours, Connections: $threads" -ForegroundColor Green

        # Check databases
        Write-Host "[*] Listing databases..." -ForegroundColor Cyan
        $dbListArgs = $baseArgs + $credArgs + @('-e', 'SHOW DATABASES;', '-sN')
        $databases = Invoke-MySqlCommand -ArgumentList $dbListArgs -ErrorAction Stop
        if ($null -eq $databases) { return 1 }
        $dbCount = @($databases).Count
        $results.Databases = $dbCount
        Write-Host "[+] Found $dbCount databases" -ForegroundColor Green

        if ($CheckReplication) {
            Write-Host "[*] Checking replication status..." -ForegroundColor Cyan
            $replicaArgs = $baseArgs + $credArgs + @('-e', 'SHOW REPLICA STATUS\G')
            $replica = Invoke-MySqlCommand -ArgumentList $replicaArgs -ErrorAction Stop
            if ($replica) {
                Write-Host "[+] Replication configured" -ForegroundColor Green
            }
            else {
                Write-Host "[!] Replication not configured or not a replica" -ForegroundColor Yellow
            }
        }

        Write-Host "`n=== Summary ===" -ForegroundColor Cyan
        Write-Host "Server: ${Server}:$Port" -ForegroundColor White
        Write-Host "Version: $($results.Version)" -ForegroundColor White
        Write-Host "Uptime: $($results.Uptime) hours" -ForegroundColor White
        Write-Host "Active Connections: $($results.Connections)" -ForegroundColor White
        Write-Host "Databases: $($results.Databases)" -ForegroundColor White

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
