<#
.SYNOPSIS
    Generates winget detect/remediate script pairs for new applications from the V3 templates.

.DESCRIPTION
    This script automates the creation of detect.ps1 and remediate.ps1 script pairs based on the
    V3 templates under the _templates directory. For every entry in the AppDefinitions list it
    creates the category/folder directory structure, substitutes the WINGETID placeholder in both
    templates and, for force-close apps with notifications, configures the notification settings.
    Exit codes:
    - 0: every application's script pair was generated successfully (or nothing failed under -WhatIf).
    - 1: one or more applications failed to generate.
    Supports -WhatIf/-Confirm: pass -WhatIf to preview directories and file writes without performing them.

.EXAMPLE
    PS C:\> .\_generate-winget-scripts.ps1
    Generates detect/remediate script pairs for every application defined in $AppDefinitions.

.EXAMPLE
    PS C:\> .\_generate-winget-scripts.ps1 -WhatIf
    Shows which directories and script files would be created without writing anything to disk.

.NOTES
    File Name: _generate-winget-scripts.ps1
    Author: Bug-Free Umbrella
    Prerequisite: PowerShell 7.0
    Version: 1.0.0
    Date: 2026-08-23
#>

[CmdletBinding(SupportsShouldProcess)]

$ErrorActionPreference = 'Stop'

#region Configuration
$TemplatePath = "$PSScriptRoot\_templates"
$ScriptsBasePath = $PSScriptRoot

# Define applications to create
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
#endregion

#region Functions

function New-WingetScriptPair {
    <#
    .SYNOPSIS
        Generates one detect/remediate script pair for a single application.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$WingetId,
        [string]$Category,
        [string]$FolderName,
        [bool]$ForceClose,
        [int]$NotifySeconds
    )

    $appPath = Join-Path $ScriptsBasePath "$Category\$FolderName"

    # Create directory if it doesn't exist
    if (-not (Test-Path $appPath) -and $PSCmdlet.ShouldProcess($appPath, 'Create app directory')) {
        New-Item -Path $appPath -ItemType Directory -Force | Out-Null
        $outputMsg = "[+] Created directory: $appPath"
        Write-Host $outputMsg -ForegroundColor Green
    }

    # Read templates
    $detectTemplate = Get-Content (Join-Path $TemplatePath "detect_v3.ps1") -Raw
    $remediateTemplate = if ($ForceClose) {
        Get-Content (Join-Path $TemplatePath "remediate_v3_force_close.ps1") -Raw
    }
    else {
        Get-Content (Join-Path $TemplatePath "remediate_v3_standard.ps1") -Raw
    }

    # Replace WINGETID placeholder in detect script
    $detectContent = $detectTemplate -replace "WINGETID", $WingetId

    # Replace WINGETID placeholder and configure notification in remediate script
    $remediateContent = $remediateTemplate -replace "WINGETID", $WingetId

    if ($ForceClose -and $NotifySeconds -gt 0) {
        $remediateContent = $remediateContent `
            -replace '\$NotifyUserBeforeClose = \$false', '$NotifyUserBeforeClose = $true'
        $remediateContent = $remediateContent `
            -replace '\$UserNotificationSeconds = \d+', "`$UserNotificationSeconds = $NotifySeconds"
    }

    # Write scripts
    $detectPath = Join-Path $appPath "detect.ps1"
    $remediatePath = Join-Path $appPath "remediate.ps1"

    if ($PSCmdlet.ShouldProcess($appPath, 'Write detect/remediate script pair')) {
        Set-Content -Path $detectPath -Value $detectContent -Force
        Set-Content -Path $remediatePath -Value $remediateContent -Force
    }

    $outputMsg = "[+] Created scripts for $WingetId in $Category/$FolderName"

    Write-Host $outputMsg -ForegroundColor Green
}

function Main {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    try {
        $outputMsg = "[*] Generating winget detect/remediate script pairs..."
        Write-Host $outputMsg -ForegroundColor Cyan

        $failures = 0
        foreach ($app in $AppDefinitions) {
            try {
                New-WingetScriptPair -WingetId $app.WingetId -Category $app.Category -FolderName $app.FolderName `
                    -ForceClose $app.ForceClose `
                    -NotifySeconds $app.NotifySeconds
            }
            catch {
                $outputMsg = "[!] Failed to create scripts for $($app.WingetId): $($_.Exception.Message)"
                Write-Host $outputMsg -ForegroundColor Yellow
                $failures++
            }
        }

        if ($failures -gt 0) {
            $outputMsg = "[-] Script generation complete with $failures failure(s)."
            Write-Host $outputMsg -ForegroundColor Red
            return 1
        }
        $outputMsg = "[+] Script generation complete!"
        Write-Host $outputMsg -ForegroundColor Green
        return 0
    }
    catch {
        $outputMsg = "[-] Failed: $($_.Exception.Message)"
        Write-Host $outputMsg -ForegroundColor Red
        return 1
    }
}

#endregion

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
