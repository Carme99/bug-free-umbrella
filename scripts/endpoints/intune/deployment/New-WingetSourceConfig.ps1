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
    Import source configuration from a JSON file. The file must contain a
    "Sources" array of objects with Name, Arg (URL) and optional Type
    (Microsoft.Rest or Microsoft.PreIndexed.Package), e.g.:
    {"Sources": [{"Name": "CompanyRepo", "Arg": "https://packages.company.com", "Type": "Microsoft.Rest"}]}
    An optional "RemoveSources" array of {Name} objects removes sources first.

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

.EXAMPLE
    .\New-WingetSourceConfig.ps1 -ImportConfig ".\winget-sources.json"
    Imports source configuration from JSON file.

.NOTES
    Requires Administrator privileges
    Requires winget to be installed
    Custom sources require appropriate certificates/authentication
#>

[CmdletBinding(DefaultParameterSetName = 'Add')]
param(
    [Parameter(Mandatory = $true, ParameterSetName = 'Add')]
    [string]$SourceName,

    [Parameter(Mandatory = $true, ParameterSetName = 'Add')]
    [string]$SourceURL,

    [Parameter(Mandatory = $false, ParameterSetName = 'Add')]
    [ValidateSet('Microsoft.Rest', 'Microsoft.PreIndexed.Package')]
    [string]$SourceType = 'Microsoft.Rest',

    [Parameter(Mandatory = $false, ParameterSetName = 'Add')]
    [switch]$RemoveDefaultSources,

    [Parameter(Mandatory = $false, ParameterSetName = 'Reset')]
    [switch]$ResetSources,

    [Parameter(Mandatory = $false, ParameterSetName = 'Export')]
    [switch]$ExportConfig,

    [Parameter(Mandatory = $false, ParameterSetName = 'Import')]
    [string]$ImportConfig,

    [Parameter(Mandatory = $false)]
    [string]$OutputPath = ".",

    [Parameter(Mandatory = $false, ParameterSetName = 'Add')]
    [switch]$GenerateIntuneScript
)

#Requires -RunAsAdministrator

function Write-ColorOutput {
    param([string]$Message, [string]$Level = 'Info')
    $color = switch ($Level) {
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
        if ($wingetExe) {
            return $wingetExe[-1].Path
        }
        return $null
    }
}

function Get-CurrentSources {
    $wingetPath = Get-WingetPath
    if (-not $wingetPath) {
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
    if (-not $wingetPath) { return }

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
    [CmdletBinding(SupportsShouldProcess)]
    param()
    $wingetPath = Get-WingetPath
    if (-not $wingetPath) { return }

    Write-Host "`nRemoving default sources..." -ForegroundColor Yellow

    $defaultSources = @('winget', 'msstore')

    foreach ($source in $defaultSources) {
        try {
            if ($PSCmdlet.ShouldProcess($source, 'Remove winget source')) {
                & $wingetPath source remove --name $source 2>&1 | Out-Null
                Write-ColorOutput "  Removed: $source" -Level Success
            }
        }
        catch {
            Write-ColorOutput "  Could not remove $source (may not exist)" -Level Warning
        }
    }
}

function Reset-WingetSources {
    [CmdletBinding(SupportsShouldProcess)]
    param()
    $wingetPath = Get-WingetPath
    if (-not $wingetPath) { return }

    Write-Host "`nResetting winget sources to defaults..." -ForegroundColor Cyan

    try {
        if ($PSCmdlet.ShouldProcess('winget', 'Reset sources to defaults')) {
            & $wingetPath source reset --force
            Write-ColorOutput "Successfully reset winget sources" -Level Success
        }
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

function Import-SourceConfig {
    param([string]$ConfigPath)

    $wingetPath = Get-WingetPath
    if (-not $wingetPath) {
        Write-ColorOutput "Winget not found - cannot import configuration" -Level Error
        return
    }

    if (-not (Test-Path $ConfigPath)) {
        Write-ColorOutput "Configuration file not found: $ConfigPath" -Level Error
        return
    }

    Write-Host "`nImporting winget source configuration from: $ConfigPath" -ForegroundColor Cyan

    try {
        $config = Get-Content -Path $ConfigPath -Raw | ConvertFrom-Json

        $sources = @()
        if ($config.Sources) {
            $sources = @($config.Sources)
        }
        elseif ($config -is [System.Array]) {
            $sources = @($config)
        }

        $removeSources = @()
        if ($config.RemoveSources) {
            $removeSources = @($config.RemoveSources)
        }

        # Remove sources first
        foreach ($source in $removeSources) {
            try {
                & $wingetPath source remove --name $source.Name 2>&1 | Out-Null
                Write-ColorOutput "  Removed: $($source.Name)" -Level Success
            }
            catch {
                Write-ColorOutput "  Could not remove $($source.Name) (may not exist)" -Level Warning
            }
        }

        # Add/update sources
        foreach ($source in $sources) {
            $sourceName = $source.Name
            $sourceArg = $source.Arg
            $sourceType = if ($source.Type) { $source.Type } else { 'Microsoft.Rest' }

            if (-not $sourceName -or -not $sourceArg) {
                Write-ColorOutput "  Skipping invalid source entry (Name and Arg are required)" -Level Warning
                continue
            }

            # Remove existing entry first so configuration changes are applied
            & $wingetPath source remove --name $sourceName 2>&1 | Out-Null
            & $wingetPath source add --name $sourceName --arg $sourceArg --type $sourceType
            Write-ColorOutput "  Configured: $sourceName ($sourceArg)" -Level Success
        }

        Write-ColorOutput "`nSuccessfully imported winget source configuration" -Level Success
    }
    catch {
        Write-ColorOutput "Failed to import configuration: $($_.Exception.Message)" -Level Error
    }
}

function New-IntuneDeploymentScript {
    [CmdletBinding(SupportsShouldProcess)]
    param()
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

    if ($RemoveDefaultSources) {
        $scriptContent += @"

# Remove default sources
Write-Host "Removing default sources..."
& `$wingetPath source remove --name "winget" 2>&1 | Out-Null
& `$wingetPath source remove --name "msstore" 2>&1 | Out-Null
"@
    }

    $scriptPath = Join-Path $OutputPath "Deploy-WingetSource_$SourceName.ps1"
    if ($PSCmdlet.ShouldProcess($scriptPath, 'Write Intune deployment script')) {
        $scriptContent | Out-File -FilePath $scriptPath -Encoding UTF8
        Write-ColorOutput "`nIntune deployment script generated: $scriptPath" -Level Success
    }
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

if ($ResetSources) {
    Reset-WingetSources
}
elseif ($ExportConfig) {
    Export-SourceConfig
}
elseif ($ImportConfig) {
    Import-SourceConfig -ConfigPath $ImportConfig
}
else {
    if ($RemoveDefaultSources) {
        Remove-DefaultSources
    }

    Add-CustomSource

    if ($GenerateIntuneScript) {
        New-IntuneDeploymentScript
    }
}

Write-Host "`nFinal Configuration:" -ForegroundColor Cyan
Get-CurrentSources

Write-Host "`n========================================`n" -ForegroundColor Cyan
