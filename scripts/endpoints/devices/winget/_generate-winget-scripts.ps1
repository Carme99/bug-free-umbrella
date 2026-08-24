<#
.SYNOPSIS
    Generate winget update script pairs (detect/remediate) for configured applications.

.DESCRIPTION
    Automates creation of detect.ps1 and remediate.ps1 pairs from the V3 templates in the _templates
    folder next to this script. Creates the category/folder directory structure, substitutes the
    WINGETID placeholder in both scripts and, for force-close apps with notifications, enables the
    pre-close user prompt. Honors -WhatIf/-Confirm for directory creation and file writes.
    Exit codes: 0 = every application's script pair generated successfully; 1 = one or more failed.

.EXAMPLE
    PS C:\> .\_generate-winget-scripts.ps1

    Generates detect/remediate script pairs for every application in the built-in definitions list.

.EXAMPLE
    PS C:\> .\_generate-winget-scripts.ps1 -WhatIf

    Shows which directories and script files would be created without writing anything.

.NOTES
    File Name  : _generate-winget-scripts.ps1
    Author     : Bug-Free Umbrella
    Prerequisite: PowerShell 7.0
    Version    : 1.0.0
    Date       : 2026-08-23
#>

[CmdletBinding(SupportsShouldProcess)]
param()

# PSAvoidUsingWriteHost is intentionally accepted: prefixed, colored console output is the mandated
# output convention of docs/RELAUNCH-SPEC.md section 3.
$ErrorActionPreference = 'Stop'

$TemplatePath = Join-Path $PSScriptRoot '_templates'
$ScriptsBasePath = $PSScriptRoot

# Applications to create.
$AppDefinitions = @(
    # Communication
    @{
        WingetId      = 'Discord.Discord'
        Category      = 'communication'
        FolderName    = 'Discord'
        ForceClose    = $true
        NotifySeconds = 60
    }

    # Security Tools
    @{
        WingetId      = 'AgileBits.1Password'
        Category      = 'security'
        FolderName    = '1Password'
        ForceClose    = $false
        NotifySeconds = 0
    }
    @{
        WingetId      = 'Bitwarden.Bitwarden'
        Category      = 'security'
        FolderName    = 'Bitwarden'
        ForceClose    = $false
        NotifySeconds = 0
    }
    @{
        WingetId      = 'KeePassXCTeam.KeePassXC'
        Category      = 'security'
        FolderName    = 'KeePass'
        ForceClose    = $false
        NotifySeconds = 0
    }

    # Cloud Storage
    @{
        WingetId      = 'Dropbox.Dropbox'
        Category      = 'cloud-storage'
        FolderName    = 'Dropbox'
        ForceClose    = $false
        NotifySeconds = 0
    }
    @{
        WingetId      = 'Google.GoogleDrive'
        Category      = 'cloud-storage'
        FolderName    = 'GoogleDrive'
        ForceClose    = $false
        NotifySeconds = 0
    }
    @{
        WingetId      = 'Box.Box'
        Category      = 'cloud-storage'
        FolderName    = 'Box'
        ForceClose    = $false
        NotifySeconds = 0
    }

    # VPN
    @{
        WingetId      = 'NordVPN.NordVPN'
        Category      = 'vpn'
        FolderName    = 'NordVPN'
        ForceClose    = $false
        NotifySeconds = 0
    }
    @{
        WingetId      = 'ProtonTechnologies.ProtonVPN'
        Category      = 'vpn'
        FolderName    = 'ProtonVPN'
        ForceClose    = $false
        NotifySeconds = 0
    }

    # Database Tools
    @{
        WingetId      = 'Oracle.MySQLWorkbench'
        Category      = 'database'
        FolderName    = 'MySQLWorkbench'
        ForceClose    = $false
        NotifySeconds = 0
    }
    @{
        WingetId      = 'Microsoft.AzureDataStudio'
        Category      = 'database'
        FolderName    = 'AzureDataStudio'
        ForceClose    = $false
        NotifySeconds = 0
    }

    # Development (additions to existing development category)
    @{
        WingetId      = 'Docker.DockerDesktop'
        Category      = 'development'
        FolderName    = 'DockerDesktop'
        ForceClose    = $false
        NotifySeconds = 0
    }
    @{
        WingetId      = 'Postman.Postman'
        Category      = 'development'
        FolderName    = 'Postman'
        ForceClose    = $false
        NotifySeconds = 0
    }
    @{
        WingetId      = 'OpenJS.NodeJS'
        Category      = 'development'
        FolderName    = 'Nodejs'
        ForceClose    = $false
        NotifySeconds = 0
    }
    @{
        WingetId      = 'Python.Python.3.12'
        Category      = 'development'
        FolderName    = 'Python'
        ForceClose    = $false
        NotifySeconds = 0
    }
)

function New-WingetScriptPair {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$WingetId,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Category,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$FolderName,

        [bool]$ForceClose,

        [int]$NotifySeconds
    )

    $appPath = Join-Path $ScriptsBasePath "$Category\$FolderName"

    # Create directory if it doesn't exist
    if (-not (Test-Path $appPath) -and $PSCmdlet.ShouldProcess($appPath, 'Create app directory')) {
        New-Item -Path $appPath -ItemType Directory -Force -ErrorAction Stop | Out-Null
        Write-Host "[*] Created directory: $appPath" -ForegroundColor Cyan
    }

    # Read templates
    $detectTemplate = Get-Content (Join-Path $TemplatePath 'detect_v3.ps1') -Raw -ErrorAction Stop
    $remediateTemplate = if ($ForceClose) {
        Get-Content (Join-Path $TemplatePath 'remediate_v3_force_close.ps1') -Raw -ErrorAction Stop
    }
    else {
        Get-Content (Join-Path $TemplatePath 'remediate_v3_standard.ps1') -Raw -ErrorAction Stop
    }

    # Replace WINGETID placeholder in detect script
    $detectContent = $detectTemplate -replace 'WINGETID', $WingetId

    # Replace WINGETID placeholder and configure notification in remediate script
    $remediateContent = $remediateTemplate -replace 'WINGETID', $WingetId

    if ($ForceClose -and $NotifySeconds -gt 0) {
        $notifyOffPattern = '\$NotifyUserBeforeClose = \$false'
        $remediateContent = $remediateContent -replace $notifyOffPattern, '$NotifyUserBeforeClose = $true'
        $secondsPattern = '\$UserNotificationSeconds = \d+'
        $remediateContent = $remediateContent -replace $secondsPattern, "`$UserNotificationSeconds = $NotifySeconds"
    }

    $detectPath = Join-Path $appPath 'detect.ps1'
    $remediatePath = Join-Path $appPath 'remediate.ps1'

    if ($PSCmdlet.ShouldProcess($appPath, 'Write detect/remediate script pair')) {
        Set-Content -Path $detectPath -Value $detectContent -Force -ErrorAction Stop
        Set-Content -Path $remediatePath -Value $remediateContent -Force -ErrorAction Stop
    }

    Write-Host "[+] Created scripts for $WingetId in $Category/$FolderName" -ForegroundColor Green
}

function Main {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([int])]
    param()

    $failedCount = 0
    foreach ($app in $AppDefinitions) {
        try {
            New-WingetScriptPair -WingetId $app.WingetId -Category $app.Category -FolderName $app.FolderName `
                -ForceClose $app.ForceClose -NotifySeconds $app.NotifySeconds
        }
        catch {
            Write-Host "[-] Error: Failed to create scripts for $($app.WingetId): $($_.Exception.Message)" `
                -ForegroundColor Red
            $failedCount++
        }
    }

    if ($failedCount -gt 0) {
        return 1
    }

    Write-Host '[+] Script generation complete!' -ForegroundColor Green
    return 0
}

# Execute only when run as a script; dot-sourcing (Pester tests) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main @PSBoundParameters) }
