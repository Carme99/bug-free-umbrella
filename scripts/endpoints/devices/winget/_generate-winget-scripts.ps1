<#
.SYNOPSIS
    Helper script to generate winget update script pairs (detect/remediate) for new applications.

.DESCRIPTION
    This script automates the creation of detect.ps1 and remediate.ps1 scripts based on the V3 templates.
    It creates the necessary directory structure and generates properly configured scripts.

.PARAMETER AppDefinitions
    Array of hashtables containing app information (WingetId, Category, FolderName, ForceClose, NotifySeconds)

.EXAMPLE
    # Generate scripts for a single app
    .\\_generate-winget-scripts.ps1
#>

# Define applications to create
$AppDefinitions = @(
    # Communication
    @{ WingetId = 'Discord.Discord'; Category = 'communication'; FolderName = 'Discord'; ForceClose = $true; NotifySeconds = 60 }

    # Security Tools
    @{ WingetId = 'AgileBits.1Password'; Category = 'security'; FolderName = '1Password'; ForceClose = $false; NotifySeconds = 0 }
    @{ WingetId = 'Bitwarden.Bitwarden'; Category = 'security'; FolderName = 'Bitwarden'; ForceClose = $false; NotifySeconds = 0 }
    @{ WingetId = 'KeePassXCTeam.KeePassXC'; Category = 'security'; FolderName = 'KeePass'; ForceClose = $false; NotifySeconds = 0 }

    # Cloud Storage
    @{ WingetId = 'Dropbox.Dropbox'; Category = 'cloud-storage'; FolderName = 'Dropbox'; ForceClose = $false; NotifySeconds = 0 }
    @{ WingetId = 'Google.GoogleDrive'; Category = 'cloud-storage'; FolderName = 'GoogleDrive'; ForceClose = $false; NotifySeconds = 0 }
    @{ WingetId = 'Box.Box'; Category = 'cloud-storage'; FolderName = 'Box'; ForceClose = $false; NotifySeconds = 0 }

    # VPN
    @{ WingetId = 'NordVPN.NordVPN'; Category = 'vpn'; FolderName = 'NordVPN'; ForceClose = $false; NotifySeconds = 0 }
    @{ WingetId = 'ProtonTechnologies.ProtonVPN'; Category = 'vpn'; FolderName = 'ProtonVPN'; ForceClose = $false; NotifySeconds = 0 }

    # Database Tools
    @{ WingetId = 'Oracle.MySQLWorkbench'; Category = 'database'; FolderName = 'MySQLWorkbench'; ForceClose = $false; NotifySeconds = 0 }
    @{ WingetId = 'Microsoft.AzureDataStudio'; Category = 'database'; FolderName = 'AzureDataStudio'; ForceClose = $false; NotifySeconds = 0 }

    # Development (additions to existing development category)
    @{ WingetId = 'Docker.DockerDesktop'; Category = 'development'; FolderName = 'DockerDesktop'; ForceClose = $false; NotifySeconds = 0 }
    @{ WingetId = 'Postman.Postman'; Category = 'development'; FolderName = 'Postman'; ForceClose = $false; NotifySeconds = 0 }
    @{ WingetId = 'OpenJS.NodeJS'; Category = 'development'; FolderName = 'Nodejs'; ForceClose = $false; NotifySeconds = 0 }
    @{ WingetId = 'Python.Python.3.12'; Category = 'development'; FolderName = 'Python'; ForceClose = $false; NotifySeconds = 0 }
)

$TemplatePath = "$PSScriptRoot\_templates"
$ScriptsBasePath = $PSScriptRoot

function New-WingetScriptPair {
    param(
        [string]$WingetId,
        [string]$Category,
        [string]$FolderName,
        [bool]$ForceClose,
        [int]$NotifySeconds
    )

    $appPath = Join-Path $ScriptsBasePath "$Category\$FolderName"

    # Create directory if it doesn't exist
    if (-not (Test-Path $appPath)) {
        New-Item -Path $appPath -ItemType Directory -Force | Out-Null
        Write-Host "Created directory: $appPath"
    }

    # Read templates
    $detectTemplate = Get-Content (Join-Path $TemplatePath "detect_v3.ps1") -Raw
    $remediateTemplate = if ($ForceClose) {
        Get-Content (Join-Path $TemplatePath "remediate_v3_force_close.ps1") -Raw
    } else {
        Get-Content (Join-Path $TemplatePath "remediate_v3_standard.ps1") -Raw
    }

    # Replace WINGETID placeholder in detect script
    $detectContent = $detectTemplate -replace "WINGETID", $WingetId

    # Replace WINGETID placeholder and configure notification in remediate script
    $remediateContent = $remediateTemplate -replace "WINGETID", $WingetId

    if ($ForceClose -and $NotifySeconds -gt 0) {
        $remediateContent = $remediateContent -replace '\$NotifyUserBeforeClose = \$false', '$NotifyUserBeforeClose = $true'
        $remediateContent = $remediateContent -replace '\$UserNotificationSeconds = \d+', "`$UserNotificationSeconds = $NotifySeconds"
    }

    # Write scripts
    $detectPath = Join-Path $appPath "detect.ps1"
    $remediatePath = Join-Path $appPath "remediate.ps1"

    Set-Content -Path $detectPath -Value $detectContent -Force
    Set-Content -Path $remediatePath -Value $remediateContent -Force

    Write-Host "Created scripts for $WingetId in $Category/$FolderName"
}

# Generate all scripts
foreach ($app in $AppDefinitions) {
    try {
        New-WingetScriptPair -WingetId $app.WingetId -Category $app.Category -FolderName $app.FolderName -ForceClose $app.ForceClose -NotifySeconds $app.NotifySeconds
    } catch {
        Write-Warning "Failed to create scripts for $($app.WingetId): $($_.Exception.Message)"
    }
}

Write-Host "`nScript generation complete!"
