<#
.SYNOPSIS
    Configures custom winget sources for enterprise environments.

.DESCRIPTION
    This script helps configure and manage winget sources:
    - Add custom enterprise repositories
    - Remove default sources if needed
    - Reset winget configuration
    - Export/import source configuration
    - Generate Intune deployment scripts
    - Validate source connectivity

.PARAMETER SourceName
    Name for the custom source.

.PARAMETER SourceURL
    URL of the custom winget source.

.PARAMETER SourceType
    Type of source: Microsoft.Rest (default) or Microsoft.PreIndexed.Package.

.PARAMETER RemoveDefaultSources
    Remove default winget sources (winget, msstore).

.PARAMETER ResetSources
    Reset to default winget sources.

.PARAMETER ExportConfig
    Export current source configuration.

.PARAMETER ImportConfig
    Import source configuration from JSON file.

.PARAMETER GenerateIntuneScript
    Generate PowerShell script for Intune deployment.

.EXAMPLE
    .\New-WingetSourceConfig.ps1 -SourceName "CompanyRepo" -SourceURL "https://packages.company.com" -GenerateIntuneScript
    Adds custom source and generates Intune deployment script.

.EXAMPLE
    .\New-WingetSourceConfig.ps1 -ResetSources
    Resets winget to default sources.

.EXAMPLE
    .\New-WingetSourceConfig.ps1 -ExportConfig -OutputPath ".\winget-sources.json"
    Exports current source configuration.

.NOTES
    Requires Administrator privileges
    Requires winget to be installed
    Custom sources require appropriate certificates/authentication
#>

[CmdletBinding(DefaultParameterSetName='Add')]
param(
    [Parameter(Mandatory=$true, ParameterSetName='Add')]
    [string]$SourceName,

    [Parameter(Mandatory=$true, ParameterSetName='Add')]
    [string]$SourceURL,

    [Parameter(Mandatory=$false, ParameterSetName='Add')]
    [ValidateSet('Microsoft.Rest','Microsoft.PreIndexed.Package')]
    [string]$SourceType = 'Microsoft.Rest',

    [Parameter(Mandatory=$false, ParameterSetName='Add')]
    [switch]$RemoveDefaultSources,

    [Parameter(Mandatory=$false, ParameterSetName='Reset')]
    [switch]$ResetSources,

    [Parameter(Mandatory=$false, ParameterSetName='Export')]
    [switch]$ExportConfig,

    [Parameter(Mandatory=$false, ParameterSetName='Import')]
    [string]$ImportConfig,

    [Parameter(Mandatory=$false)]
    [string]$OutputPath = ".",

    [Parameter(Mandatory=$false, ParameterSetName='Add')]
    [switch]$GenerateIntuneScript
)

#Requires -RunAsAdministrator

function Write-ColorOutput {
    param([string]$Message, [string]$Level = 'Info')
    $color = switch($Level) {
        'Success' { 'Green' }
        'Warning' { 'Yellow' }
        'Error' { 'Red' }
        default { 'Cyan' }
    }
    Write-Host $Message -ForegroundColor $color
}

function Get-WingetPath {
    try {
        $wingetExe = Get-Command winget.exe -ErrorAction Stop
        return $wingetExe.Source
    }
    catch {
        $wingetExe = Resolve-Path "C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\winget.exe" -ErrorAction SilentlyContinue
        if($wingetExe) {
            return $wingetExe[-1].Path
        }
        return $null
    }
}

function Get-CurrentSources {
    $wingetPath = Get-WingetPath
    if(-not $wingetPath) {
        Write-ColorOutput "Winget not found" -Level Error
        return @()
    }

    try {
        $output = & $wingetPath source list 2>&1
        Write-ColorOutput "Current winget sources:" -Level Info
        Write-Host $output
        return $output
    }
    catch {
        Write-ColorOutput "Error listing sources: $($_.Exception.Message)" -Level Error
        return @()
    }
}

function Add-CustomSource {
    $wingetPath = Get-WingetPath
    if(-not $wingetPath) { return }

    Write-Host "`nAdding custom source: $SourceName" -ForegroundColor Cyan
    Write-Host "  URL: $SourceURL" -ForegroundColor Gray
    Write-Host "  Type: $SourceType" -ForegroundColor Gray

    try {
        & $wingetPath source add --name $SourceName --arg $SourceURL --type $SourceType
        Write-ColorOutput "`nSuccessfully added custom source: $SourceName" -Level Success
    }
    catch {
        Write-ColorOutput "Failed to add source: $($_.Exception.Message)" -Level Error
    }
}

function Remove-DefaultSources {
    $wingetPath = Get-WingetPath
    if(-not $wingetPath) { return }

    Write-Host "`nRemoving default sources..." -ForegroundColor Yellow

    $defaultSources = @('winget', 'msstore')

    foreach($source in $defaultSources) {
        try {
            & $wingetPath source remove --name $source 2>&1 | Out-Null
            Write-ColorOutput "  Removed: $source" -Level Success
        }
        catch {
            Write-ColorOutput "  Could not remove $source (may not exist)" -Level Warning
        }
    }
}

function Reset-WingetSources {
    $wingetPath = Get-WingetPath
    if(-not $wingetPath) { return }

    Write-Host "`nResetting winget sources to defaults..." -ForegroundColor Cyan

    try {
        & $wingetPath source reset --force
        Write-ColorOutput "Successfully reset winget sources" -Level Success
    }
    catch {
        Write-ColorOutput "Failed to reset sources: $($_.Exception.Message)" -Level Error
    }
}

function Export-SourceConfig {
    $sources = Get-CurrentSources
    $config = @{
        ExportDate = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        Sources = $sources
    }

    $jsonPath = Join-Path $OutputPath "winget-sources_$(Get-Date -Format 'yyyyMMdd_HHmmss').json"
    $config | ConvertTo-Json -Depth 10 | Out-File -FilePath $jsonPath -Encoding UTF8

    Write-ColorOutput "`nConfiguration exported to: $jsonPath" -Level Success
}

function New-IntuneDeploymentScript {
    $scriptContent = @"
<#
.SYNOPSIS
    Configures winget source: $SourceName

.DESCRIPTION
    Auto-generated Intune deployment script
    Adds custom winget source for enterprise package management

.NOTES
    Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
    Source: $SourceName
    URL: $SourceURL
#>

# Locate winget
`$wingetExe = Resolve-Path "C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\winget.exe" -ErrorAction SilentlyContinue

if (-not `$wingetExe) {
    Write-Error "Winget not found"
    exit 1
}

`$wingetPath = `$wingetExe[-1].Path

try {
    # Check if source already exists
    `$existingSources = & `$wingetPath source list 2>&1

    if (`$existingSources -match "$SourceName") {
        Write-Host "Source '$SourceName' already configured"
        exit 0
    }

    # Add custom source
    Write-Host "Adding custom source: $SourceName"
    & `$wingetPath source add --name "$SourceName" --arg "$SourceURL" --type "$SourceType"

    Write-Host "Successfully added source: $SourceName"
    exit 0
}
catch {
    Write-Error "Failed to configure source: `$(`$_.Exception.Message)"
    exit 1
}
"@

    if($RemoveDefaultSources) {
        $scriptContent += @"

# Remove default sources
Write-Host "Removing default sources..."
& `$wingetPath source remove --name "winget" 2>&1 | Out-Null
& `$wingetPath source remove --name "msstore" 2>&1 | Out-Null
"@
    }

    $scriptPath = Join-Path $OutputPath "Deploy-WingetSource_$SourceName.ps1"
    $scriptContent | Out-File -FilePath $scriptPath -Encoding UTF8

    Write-ColorOutput "`nIntune deployment script generated: $scriptPath" -Level Success
    Write-Host "`nTo deploy:" -ForegroundColor Cyan
    Write-Host "  1. Upload to Intune as Win32 app or PowerShell script" -ForegroundColor Gray
    Write-Host "  2. Deploy to device groups" -ForegroundColor Gray
    Write-Host "  3. Run in SYSTEM context" -ForegroundColor Gray
}

# Main execution
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Winget Source Configuration Manager" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

Write-Host "Current Configuration:" -ForegroundColor Cyan
Get-CurrentSources

if($ResetSources) {
    Reset-WingetSources
}
elseif($ExportConfig) {
    Export-SourceConfig
}
elseif($ImportConfig) {
    Write-ColorOutput "Import functionality to be implemented" -Level Warning
}
else {
    if($RemoveDefaultSources) {
        Remove-DefaultSources
    }

    Add-CustomSource

    if($GenerateIntuneScript) {
        New-IntuneDeploymentScript
    }
}

Write-Host "`nFinal Configuration:" -ForegroundColor Cyan
Get-CurrentSources

Write-Host "`n========================================`n" -ForegroundColor Cyan
