<#
.SYNOPSIS
    Configures custom winget sources for enterprise environments.
.DESCRIPTION
    Helps configure and manage winget sources on a device:
    - Add custom enterprise repositories
    - Remove default sources if needed
    - Reset winget configuration
    - Export/import source configuration as JSON
    - Generate an Intune deployment script
    - Validate source connectivity

    The script is idempotent: adding an already-present source or resetting an already-
    default configuration completes successfully without harmful side effects. Source
    changes are gated by -WhatIf/-Confirm via SupportsShouldProcess.
.PARAMETER SourceName
    Name for the custom source (Add parameter set).
.PARAMETER SourceURL
    URL of the custom winget source (Add parameter set).
.PARAMETER SourceType
    Type of source: Microsoft.Rest (default) or Microsoft.PreIndexed.Package.
.PARAMETER RemoveDefaultSources
    Remove default winget sources (winget, msstore).
.PARAMETER ResetSources
    Reset to default winget sources.
.PARAMETER ExportConfig
    Export current source configuration to JSON under -OutputPath.
.PARAMETER ImportConfig
    Path to a JSON file to import. The file must contain a "Sources" array of objects
    with Name, Arg (URL) and optional Type (Microsoft.Rest or Microsoft.PreIndexed.Package),
    e.g.: {"Sources": [{"Name": "CompanyRepo", "Arg": "https://packages.company.com", "Type": "Microsoft.Rest"}]}
    An optional "RemoveSources" array of {Name} objects removes sources first.
.PARAMETER OutputPath
    Directory where exported configs and generated Intune scripts are written. Default: current directory.
.PARAMETER GenerateIntuneScript
    Generate a PowerShell script for Intune deployment of the custom source.
.EXAMPLE
    PS C:\> .\New-WingetSourceConfig.ps1 -SourceName "CompanyRepo" -SourceURL "https://packages.company.com" `
        -GenerateIntuneScript
    Adds the custom source and generates an Intune deployment script.
.EXAMPLE
    PS C:\> .\New-WingetSourceConfig.ps1 -ResetSources
    Resets winget to default sources.
.EXAMPLE
    PS C:\> .\New-WingetSourceConfig.ps1 -ExportConfig -OutputPath "."
    Exports current source configuration to a timestamped JSON file in the current directory.
.EXAMPLE
    PS C:\> .\New-WingetSourceConfig.ps1 -ImportConfig ".\winget-sources.json"
    Imports source configuration from a JSON file.
.NOTES
    File Name   : New-WingetSourceConfig.ps1
    Author      : Bug-Free Umbrella
    Prerequisite: PowerShell 7.0
    Version     : 1.0.0
    Date        : 2026-08-23

    Requires Administrator privileges and an installed winget.
    Custom sources require appropriate certificates/authentication.
#>

[CmdletBinding(DefaultParameterSetName = 'Add', SupportsShouldProcess)]
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

$ErrorActionPreference = 'Stop'

# Justification (PSScriptAnalyzer): the original script used '#Requires -RunAsAdministrator',
# which cannot be evaluated on non-Windows CI runners; elevation is enforced at runtime instead.
function Test-AdministratorPrivilege {
    # Returns $true when running elevated; always $false on non-Windows platforms.
    [CmdletBinding()]
    param()

    $isWindowsVar = Get-Variable IsWindows -ErrorAction SilentlyContinue
    if (-not $isWindowsVar -or -not $isWindowsVar.Value) {
        return $false
    }

    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    return ([Security.Principal.WindowsPrincipal]$identity).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Write-ColorOutput {
    # Writes a prefixed status line; prefix/color follow the relaunch output standard.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [string]$Level = 'Info'
    )

    $prefix = switch ($Level) {
        'Success' { '[+]'; break }
        'Warning' { '[!]'; break }
        'Error' { '[-]'; break }
        default { '[*]' }
    }

    $color = switch ($Level) {
        'Success' { 'Green' }
        'Warning' { 'Yellow' }
        'Error' { 'Red' }
        default { 'Cyan' }
    }

    Write-Host "$prefix $Message" -ForegroundColor $color
}

function Invoke-WingetCommand {
    # Thin wrapper around the native winget executable; the mock seam for tests.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$WingetPath,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]]$ArgumentList
    )

    $output = & $WingetPath @ArgumentList 2>&1
    return [pscustomobject]@{
        Output   = @($output)
        ExitCode = $LASTEXITCODE
    }
}

function Get-WingetPath {
    # Locates winget.exe via PATH or the WindowsApps fallback layout.
    [CmdletBinding()]
    param()

    try {
        $wingetExe = Get-Command winget.exe -ErrorAction Stop
        return $wingetExe.Source
    }
    catch {
        $fallbackGlob = "C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\winget.exe"
        $wingetExe = Resolve-Path $fallbackGlob -ErrorAction SilentlyContinue
        if ($wingetExe) {
            return $wingetExe[-1].Path
        }
        return $null
    }
}

function Get-CurrentSources {
    # Lists the currently configured winget sources.
    [CmdletBinding()]
    param()

    $wingetPath = Get-WingetPath
    if (-not $wingetPath) {
        Write-ColorOutput "Winget not found" -Level Error
        return @()
    }

    try {
        $result = Invoke-WingetCommand -WingetPath $wingetPath -ArgumentList @('source', 'list') -ErrorAction Stop
        Write-ColorOutput "Current winget sources:" -Level Info
        Write-Host $result.Output
        return $result.Output
    }
    catch {
        Write-ColorOutput "Error listing sources: $($_.Exception.Message)" -Level Error
        return @()
    }
}

function Add-CustomSource {
    # Adds the custom enterprise winget source (mutating; honors -WhatIf).
    [CmdletBinding(SupportsShouldProcess)]
    param()

    $wingetPath = Get-WingetPath
    if (-not $wingetPath) { return }

    Write-Host "`nAdding custom source: $SourceName" -ForegroundColor Cyan
    Write-Host "  URL: $SourceURL" -ForegroundColor White
    Write-Host "  Type: $SourceType" -ForegroundColor White

    try {
        if ($PSCmdlet.ShouldProcess("$SourceName ($SourceURL)", 'Add winget source')) {
            $result = Invoke-WingetCommand -WingetPath $wingetPath `
                -ArgumentList @('source', 'add', '--name', $SourceName, '--arg', $SourceURL, '--type', $SourceType)

            if ($result.ExitCode -ne 0) {
                Write-ColorOutput "Failed to add source '$SourceName' (exit code $($result.ExitCode))" -Level Error
                return
            }

            Write-ColorOutput "Successfully added custom source: $SourceName" -Level Success
        }
    }
    catch {
        Write-ColorOutput "Failed to add source: $($_.Exception.Message)" -Level Error
    }
}

function Remove-DefaultSources {
    # Removes the default winget/msstore sources (mutating; honors -WhatIf).
    [CmdletBinding(SupportsShouldProcess)]
    param()

    $wingetPath = Get-WingetPath
    if (-not $wingetPath) { return }

    Write-Host "`nRemoving default sources..." -ForegroundColor Yellow

    $defaultSources = @('winget', 'msstore')

    foreach ($source in $defaultSources) {
        try {
            if ($PSCmdlet.ShouldProcess($source, 'Remove winget source')) {
                $result = Invoke-WingetCommand -WingetPath $wingetPath `
                    -ArgumentList @('source', 'remove', '--name', $source)

                if ($result.ExitCode -ne 0) {
                    Write-ColorOutput "Could not remove $source (may not exist)" -Level Warning
                }
                else {
                    Write-ColorOutput "Removed: $source" -Level Success
                }
            }
        }
        catch {
            Write-ColorOutput "  Could not remove $source (may not exist)" -Level Warning
        }
    }
}

function Reset-WingetSources {
    # Resets winget sources back to defaults (mutating; honors -WhatIf).
    [CmdletBinding(SupportsShouldProcess)]
    param()

    $wingetPath = Get-WingetPath
    if (-not $wingetPath) { return }

    Write-Host "`nResetting winget sources to defaults..." -ForegroundColor Cyan

    try {
        if ($PSCmdlet.ShouldProcess('winget', 'Reset sources to defaults')) {
            $result = Invoke-WingetCommand -WingetPath $wingetPath -ArgumentList @('source', 'reset', '--force')

            if ($result.ExitCode -ne 0) {
                Write-ColorOutput "Failed to reset sources (exit code $($result.ExitCode))" -Level Error
                return
            }

            Write-ColorOutput "Successfully reset winget sources" -Level Success
        }
    }
    catch {
        Write-ColorOutput "Failed to reset sources: $($_.Exception.Message)" -Level Error
    }
}

function Export-SourceConfig {
    # Exports the current source list to a timestamped JSON file (honors -WhatIf).
    [CmdletBinding(SupportsShouldProcess)]
    param()

    $sources = @(Get-CurrentSources)
    $config = @{
        ExportDate = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        Sources    = $sources
    }

    $jsonPath = Join-Path $OutputPath "winget-sources_$(Get-Date -Format 'yyyyMMdd_HHmmss').json"
    if ($PSCmdlet.ShouldProcess($jsonPath, 'Write winget sources export')) {
        $config | ConvertTo-Json -Depth 10 | Out-File -FilePath $jsonPath -Encoding UTF8 -ErrorAction Stop
        Write-ColorOutput "Configuration exported to: $jsonPath" -Level Success
    }
}

function Import-SourceConfig {
    # Applies a JSON source configuration: removes listed sources, then adds/updates entries.
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ConfigPath
    )

    $wingetPath = Get-WingetPath
    if (-not $wingetPath) {
        Write-ColorOutput "Winget not found - cannot import configuration" -Level Error
        return
    }

    if (-not (Test-Path -LiteralPath $ConfigPath)) {
        Write-ColorOutput "Configuration file not found: $ConfigPath" -Level Error
        return
    }

    Write-Host "`nImporting winget source configuration from: $ConfigPath" -ForegroundColor Cyan

    try {
        $config = Get-Content -LiteralPath $ConfigPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop

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
                if ($PSCmdlet.ShouldProcess($source.Name, 'Remove configured winget source')) {
                    $result = Invoke-WingetCommand -WingetPath $wingetPath `
                        -ArgumentList @('source', 'remove', '--name', $source.Name)

                    if ($result.ExitCode -ne 0) {
                        Write-ColorOutput "Could not remove $($source.Name) (may not exist)" -Level Warning
                    }
                    else {
                        Write-ColorOutput "Removed: $($source.Name)" -Level Success
                    }
                }
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
                Write-ColorOutput "Skipping invalid source entry (Name and Arg are required)" -Level Warning
                continue
            }

            if (-not $PSCmdlet.ShouldProcess("$sourceName ($sourceArg)", 'Configure winget source')) {
                continue
            }

            # Remove existing entry first so configuration changes are applied
            $null = Invoke-WingetCommand -WingetPath $wingetPath `
                -ArgumentList @('source', 'remove', '--name', $sourceName)

            $result = Invoke-WingetCommand -WingetPath $wingetPath `
                -ArgumentList @('source', 'add', '--name', $sourceName, '--arg', $sourceArg, '--type', $sourceType)

            if ($result.ExitCode -ne 0) {
                Write-ColorOutput "Failed to configure $sourceName (exit code $($result.ExitCode))" -Level Error
                continue
            }

            Write-ColorOutput "Configured: $sourceName ($sourceArg)" -Level Success
        }

        Write-ColorOutput "Successfully imported winget source configuration" -Level Success
    }
    catch {
        Write-ColorOutput "Failed to import configuration: $($_.Exception.Message)" -Level Error
    }
}

function New-IntuneDeploymentScript {
    # Generates a standalone Intune deployment script for the custom source (honors -WhatIf).
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
`$fallbackGlob = "C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\winget.exe"
`$wingetExe = Resolve-Path `$fallbackGlob -ErrorAction SilentlyContinue

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
        $scriptContent | Out-File -FilePath $scriptPath -Encoding UTF8 -ErrorAction Stop
        Write-ColorOutput "Intune deployment script generated: $scriptPath" -Level Success
    }
    Write-Host "`nTo deploy:" -ForegroundColor Cyan
    Write-Host "  1. Upload to Intune as Win32 app or PowerShell script" -ForegroundColor White
    Write-Host "  2. Deploy to device groups" -ForegroundColor White
    Write-Host "  3. Run in SYSTEM context" -ForegroundColor White
}

function Main {
    # Justification: Write-Host with colors is mandated by the relaunch output-prefix standard.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '')]
    [CmdletBinding(SupportsShouldProcess)]
    param()

    try {
        if (-not (Test-AdministratorPrivilege -ErrorAction SilentlyContinue)) {
            Write-Host "[-] This script requires Administrator privileges. " `
                "Run from an elevated session." -ForegroundColor Red
            return 1
        }

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
        return 0
    }
    catch {
        Write-Host "[-] Error: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
