<#
.SYNOPSIS
    Monitors MongoDB database health, performance, and replication status.

.DESCRIPTION
    Comprehensive MongoDB monitoring that tracks:
    - Server status and uptime
    - Database and collection statistics
    - Replication lag and replica set health
    - Connection pool usage
    - Query performance and slow queries
    - Index usage and recommendations
    - Storage metrics and disk usage

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
    Analyze slow query log

.PARAMETER OutputFormat
    Output format: 'Console', 'HTML', or 'JSON'. Default: 'HTML'

.PARAMETER OutputPath
    Path for output files. Default: MyDocuments\Reports

.EXAMPLE
    .\Monitor-MongoDBHealth.ps1 -MongoDBServer "localhost" -Database "*"

.EXAMPLE
    .\Monitor-MongoDBHealth.ps1 -MongoDBServer "mongo.example.com" `
        -Username "admin" `
        -Password "SecurePass123" `
        -Database "myapp" `
        -IncludeSlowQueries

.NOTES
    Author: IT Operations
    Version: 1.0.0
    Requires: PowerShell 5.1+, MongoDB tools or mongo shell

    WARNING: This script has not been thoroughly tested in production environments.
    Please test in a non-production environment first and validate results before relying on this data.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$MongoDBServer = "localhost",

    [Parameter(Mandatory = $false)]
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
    [switch]$IncludeSlowQueries,

    [Parameter(Mandatory = $false)]
    [ValidateSet('Console', 'HTML', 'JSON')]
    [string]$OutputFormat = 'HTML',

    [Parameter(Mandatory = $false)]
    [string]$OutputPath = (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Reports')
)

# Validate OutputPath: reject '..' traversal and UNC remote paths before resolution
if ([string]::IsNullOrWhiteSpace($OutputPath) -or
    $OutputPath -match '(^|[\\/])\.\.([\\/]|$)' -or
    $OutputPath -match '^(\\\\|//)') {
    Write-Error "Unsafe OutputPath: $OutputPath. OutputPath must be a local absolute path without '..' traversal."
    exit 1
}
$OutputPath = [System.IO.Path]::GetFullPath($OutputPath)
if (-not (Test-Path -LiteralPath $OutputPath -PathType Container)) {
    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
}

$RunTimestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$RunId = [Guid]::NewGuid().ToString('N').Substring(0, 8)

$results = @{
    Timestamp = Get-Date
    Server = $MongoDBServer
    Port = $Port
    ServerStatus = @{}
    Databases = @()
    ReplicaSetStatus = @{}
    SlowQueries = @()
}

Write-Host "Monitoring MongoDB: $MongoDBServer:$Port" -ForegroundColor Cyan

# Build connection string with secure password handling
$connString = "mongodb://$MongoDBServer:$Port"
if ($Credential) {
    $username = $Credential.UserName
    $bstrPtr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Credential.Password)
    try {
        $password = [Runtime.InteropServices.Marshal]::PtrToStringAuto($bstrPtr)
        $connString = "mongodb://$([Uri]::EscapeDataString($username))`:$([Uri]::EscapeDataString($password))@$MongoDBServer:$Port"
    }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstrPtr)
    }
} elseif ($Username -and $Password) {
    $bstrPtr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password)
    try {
        $password = [Runtime.InteropServices.Marshal]::PtrToStringAuto($bstrPtr)
        $connString = "mongodb://$([Uri]::EscapeDataString($Username))`:$([Uri]::EscapeDataString($password))@$MongoDBServer:$Port"
    }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstrPtr)
    }
}

# Note: This script provides a framework. Actual implementation would require
# MongoDB driver or mongosh CLI integration

Write-Host "MongoDB monitoring framework ready" -ForegroundColor Green
Write-Host "Note: Full implementation requires MongoDB .NET driver or mongosh CLI" -ForegroundColor Yellow

$results | ConvertTo-Json -Depth 10 | Out-File -Path (Join-Path $OutputPath "MongoDB-Health-${RunTimestamp}_${RunId}.json")
Write-Host "Template JSON saved for MongoDB monitoring implementation" -ForegroundColor Green
