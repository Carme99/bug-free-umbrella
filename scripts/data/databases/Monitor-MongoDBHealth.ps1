<#
.SYNOPSIS
    Generate a MongoDB health monitoring JSON template (does not perform live monitoring).
.DESCRIPTION
    Generates a structured JSON template for MongoDB health monitoring containing server,
    port, and credential settings plus empty result sections.
    This script does NOT connect to or monitor a MongoDB instance; it only writes a template
    JSON file that can scaffold a real monitoring implementation (via mongosh or the
    MongoDB driver).
.PARAMETER MongoDBServer
    MongoDB server hostname or IP. Default: localhost
.PARAMETER Port
    MongoDB port. Default: 27017
.PARAMETER Database
    Specific database to analyze. Use '*' for all databases.
.PARAMETER Username
    MongoDB username for authentication
.PARAMETER Password
    MongoDB password as SecureString
.PARAMETER Credential
    PSCredential object containing username and password
.PARAMETER IncludeSlowQueries
    Reserved switch retained for compatibility; slow-query analysis is not yet implemented.
.PARAMETER OutputFormat
    Output format: 'Console', 'HTML', or 'JSON'. Default: 'HTML'
.PARAMETER OutputPath
    Path for output files. Default: MyDocuments\Reports. Must be a local absolute path
    without '..' traversal.
.EXAMPLE
    PS C:\> .\Monitor-MongoDBHealth.ps1 -MongoDBServer "localhost" -Database "*"
    Writes a template JSON for the local server using the default output path.

.EXAMPLE
    PS C:\> .\Monitor-MongoDBHealth.ps1 -MongoDBServer "mongo.example.com" `
        -Credential (Get-Credential) -Database "myapp"
    Builds an authenticated connection-string template for mongo.example.com.
.NOTES
    File Name   : Monitor-MongoDBHealth.ps1
    Author      : IT Operations
    Prerequisite: PowerShell 7.0
    Version     : 1.0.0
    Date        : 2026-08-23
    Template generation only; a real implementation would need mongosh or the MongoDB driver.

    WARNING: This script has not been thoroughly tested in production environments.
    Please test in a non-production environment first and validate results before relying on this data.
    Note: Invoke-ScriptAnalyzer PSAvoidUsingWriteHost warnings are intentional;
    RELAUNCH-SPEC section 3 mandates Write-Host-based [+] / [!] / [-] / [*] status output.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$MongoDBServer = "localhost",

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 65535)]
    [int]$Port = 27017,

    [Parameter(Mandatory = $false)]
    [string]$Database = "*",

    [Parameter(Mandatory = $false)]
    [string]$Username,

    [Parameter(Mandatory = $false)]
    [SecureString]$Password,

    [Parameter(Mandatory = $false)]
    [PSCredential]$Credential,

    [Parameter(Mandatory = $false)]
    [switch]$IncludeSlowQueries, # reserved; not yet implemented (justifies PSReviewUnusedParameter)

    [Parameter(Mandatory = $false)]
    [ValidateSet('Console', 'HTML', 'JSON')]
    [string]$OutputFormat = 'HTML', # reserved; JSON template always written (justifies PSReviewUnusedParameter)

    [Parameter(Mandatory = $false)]
    [string]$OutputPath = $(
        $myDocs = [Environment]::GetFolderPath('MyDocuments')
        if ([string]::IsNullOrWhiteSpace($myDocs)) {
            # Profile-less contexts (CI runners, SYSTEM services): MyDocuments resolves
            # empty; fall back so the default path degrades gracefully instead of crashing.
            $myDocs = [Environment]::GetFolderPath('UserProfile')
        }
        Join-Path $myDocs 'Reports'
    )
)

$ErrorActionPreference = 'Stop'

function Main {
    try {
        # Validate OutputPath: reject '..' traversal and UNC remote paths before resolution
        if ([string]::IsNullOrWhiteSpace($OutputPath) -or
            $OutputPath -match '(^|[\\/])\.\.([\\/]|$)' -or
            $OutputPath -match '^(\\\\|//)') {
            Write-Error ("Unsafe OutputPath: $OutputPath. OutputPath must be a local absolute " +
                "path without '..' traversal.")
            return 1
        }
        $OutputPath = [System.IO.Path]::GetFullPath($OutputPath)
        if (-not (Test-Path -LiteralPath $OutputPath -PathType Container)) {
            New-Item -ItemType Directory -Path $OutputPath -Force -ErrorAction Stop | Out-Null
        }

        $RunTimestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $RunId = [Guid]::NewGuid().ToString('N').Substring(0, 8)

        $results = @{
            Timestamp        = Get-Date
            Server           = $MongoDBServer
            Port             = $Port
            ServerStatus     = @{}
            Databases        = @()
            ReplicaSetStatus = @{}
            SlowQueries      = @()
        }

        Write-Host "[*] Monitoring MongoDB: ${MongoDBServer}:$Port" -ForegroundColor Cyan

        # Build connection string with secure password handling
        $connString = "mongodb://${MongoDBServer}:$Port"
        if ($Credential) {
            $username = $Credential.UserName
            $bstrPtr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Credential.Password)
            try {
                $password = [Runtime.InteropServices.Marshal]::PtrToStringUni($bstrPtr)
                $escUser = [Uri]::EscapeDataString($username)
                $escPass = [Uri]::EscapeDataString($password)
                $connString = "mongodb://${escUser}:${escPass}@${MongoDBServer}:$Port"
            }
            finally {
                [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstrPtr)
            }
        }
        elseif ($Username -and $Password) {
            $bstrPtr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password)
            try {
                $password = [Runtime.InteropServices.Marshal]::PtrToStringUni($bstrPtr)
                $escUser = [Uri]::EscapeDataString($Username)
                $escPass = [Uri]::EscapeDataString($password)
                $connString = "mongodb://${escUser}:${escPass}@${MongoDBServer}:$Port"
            }
            finally {
                [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstrPtr)
            }
        }

        # This script does NOT connect to MongoDB - it only generates a monitoring template.
        Write-Warning ("This script only generates a monitoring template. " +
            "It does NOT connect to or monitor a MongoDB instance.")
        Write-Warning ("Implement the checks (server status, replica set health, etc.) with " +
            "mongosh or the MongoDB driver before relying on the output.")

        $templateFile = Join-Path $OutputPath "MongoDB-Health-${RunTimestamp}_${RunId}.json"
        $results | ConvertTo-Json -Depth 10 | Out-File -Path $templateFile -ErrorAction Stop
        Write-Host "[+] Template JSON saved for MongoDB monitoring implementation" -ForegroundColor Green
        return 0
    }
    catch {
        Write-Host "[-] Error: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests) skips execution (RELAUNCH-SPEC §3).
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
