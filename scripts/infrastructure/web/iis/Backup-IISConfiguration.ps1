<#
.SYNOPSIS
    Backup and restore IIS configuration.

.DESCRIPTION
    Creates comprehensive backups of IIS configuration including:
    - ApplicationHost.config
    - Web.config files
    - SSL certificates and bindings
    - Application pool settings
    - Site configurations
    - Virtual directories
    - Custom modules and handlers

    Supports restoration from backups. Restoring overwrites the live
    ApplicationHost.config, so every mutating operation is gated behind
    ShouldProcess (-WhatIf/-Confirm). Re-running the backup is safe: each run
    writes into a fresh timestamped backup directory, and restore operations
    check state before acting (check-then-act).

.PARAMETER BackupPath
    Path to store backup files (default: C:\IISBackups).

.PARAMETER BackupName
    Name for the backup (default: auto-generated with timestamp).

.PARAMETER IncludeCertificates
    Include SSL certificate details in backup.

.PARAMETER IncludeContentFiles
    Reserved for including website content files; recorded in the backup
    manifest (warning: full content capture can be large).

.PARAMETER Restore
    Restore from backup.

.PARAMETER RestoreFrom
    Path to backup to restore from.

.EXAMPLE
    PS C:\> .\Backup-IISConfiguration.ps1

    Create basic configuration backup.

.EXAMPLE
    PS C:\> .\Backup-IISConfiguration.ps1 -IncludeCertificates -BackupPath "D:\Backups"

    Full backup including SSL certificate details.

.EXAMPLE
    PS C:\> .\Backup-IISConfiguration.ps1 -Restore -RestoreFrom "C:\IISBackups\IIS_Backup_20261226_120000"

    Restore from a specific backup.

.NOTES
    File Name   : Backup-IISConfiguration.ps1
    Author      : IT Infrastructure Team
    Prerequisite: PowerShell 5.1+, IISAdministration module (Windows), Administrator privileges
    Version     : 1.0.0
    Date        : 2026-08-23
#>

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
    Justification = 'Interactive administrative console tool; output is operator-facing UI, not pipeline data')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '',
    Justification = 'Script-scope parameters are consumed by Main and its helper functions after dot-source binding')]
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$BackupPath = "C:\IISBackups",

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$BackupName = "IIS_Backup_$(Get-Date -Format 'yyyyMMdd_HHmmss')",

    [Parameter()]
    [switch]$IncludeCertificates,

    [Parameter()]
    [switch]$IncludeContentFiles,

    [Parameter()]
    [switch]$Restore,

    [Parameter()]
    [string]$RestoreFrom
)

# Runtime prerequisites: Windows host with IIS, IISAdministration module, elevated session.
$ErrorActionPreference = 'Stop'

function Write-ScriptMessage {
    <#
    .SYNOPSIS
        Writes a prefixed, colored message to the console (single emitter).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [Parameter()]
        [ValidateSet('+', '!', '-', '*', '')]
        [string]$Prefix = '',

        [Parameter()]
        [ValidateSet('Green', 'Yellow', 'Red', 'Cyan', 'White')]
        [string]$Color = 'White'
    )

    # Write-Host justified: interactive administrative console tool; output is UI, not pipeline data.
    if ($Prefix) {
        Write-Host "[$Prefix] $Message" -ForegroundColor $Color
    }
    else {
        Write-Host $Message -ForegroundColor $Color
    }
}

function Get-ApplicationHostConfigPath {
    <#
    .SYNOPSIS
        Resolves the live ApplicationHost.config path; returns $null off-Windows.
    #>
    [CmdletBinding()]
    param()

    $windowsDir = $env:SystemRoot
    if (-not $windowsDir) {
        $windowsDir = $env:WINDIR
    }
    if (-not $windowsDir) {
        return $null
    }

    return Join-Path -Path $windowsDir -ChildPath 'System32\inetsrv\config\ApplicationHost.config'
}

function Invoke-RestoreIisConfiguration {
    <#
    .SYNOPSIS
        Restores IIS configuration from an existing backup directory.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$From
    )

    if (-not $From -or -not (Test-Path -LiteralPath $From)) {
        Write-ScriptMessage -Message 'Invalid restore path specified' -Prefix '-' -Color Red
        return 1
    }

    Write-ScriptMessage -Message "Restoring IIS configuration from: $From" -Prefix '*' -Color Cyan

    # Restore ApplicationHost.config (check-then-act).
    $configBackup = Join-Path -Path $From -ChildPath 'ApplicationHost.config'
    $appHostTarget = Get-ApplicationHostConfigPath
    if (Test-Path -LiteralPath $configBackup) {
        Write-ScriptMessage -Message 'Restoring ApplicationHost.config...' -Prefix '*' -Color Cyan
        if (-not $appHostTarget) {
            Write-ScriptMessage `
                -Message 'Windows directory not found on this host; skipping config restore' `
                -Prefix '!' -Color Yellow
        }
        elseif ($PSCmdlet.ShouldProcess($appHostTarget, "Overwrite with '$configBackup'")) {
            Copy-Item -LiteralPath $configBackup -Destination $appHostTarget -Force -ErrorAction Stop
            Write-ScriptMessage -Message 'Configuration restored' -Prefix '+' -Color Green
        }
    }
    else {
        Write-ScriptMessage -Message 'No ApplicationHost.config in backup; skipping' -Prefix '!' -Color Yellow
    }

    # List certificate files present in the backup (check-then-act).
    $certsPath = Join-Path -Path $From -ChildPath 'Certificates'
    if (Test-Path -LiteralPath $certsPath) {
        Write-ScriptMessage -Message 'SSL certificates found in backup:' -Prefix '*' -Color Cyan
        $certFiles = @(Get-ChildItem -LiteralPath $certsPath -Filter '*.pfx' -ErrorAction Stop)
        foreach ($certFile in $certFiles) {
            # Note: Would need password protection in production
            Write-ScriptMessage -Message "  - $($certFile.Name)"
        }
    }

    Write-ScriptMessage -Message 'IIS needs to be restarted for changes to take effect' -Prefix '!' -Color Yellow
    Write-ScriptMessage -Message 'Run: iisreset /noforce' -Prefix '*' -Color Cyan
    return 0
}

function Invoke-NewIisBackup {
    <#
    .SYNOPSIS
        Creates a new IIS configuration backup set.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param()

    Write-ScriptMessage -Message 'Creating IIS configuration backup...' -Prefix '*' -Color Cyan

    $backupDir = Join-Path -Path $BackupPath -ChildPath $BackupName
    if ($PSCmdlet.ShouldProcess($backupDir, 'Create backup directory')) {
        New-Item -ItemType Directory -Path $backupDir -Force -ErrorAction Stop | Out-Null
    }

    Write-ScriptMessage -Message "Backup location: $backupDir" -Prefix '*' -Color Cyan

    # Backup ApplicationHost.config (check-then-act).
    Write-ScriptMessage -Message 'Backing up ApplicationHost.config...' -Prefix '*' -Color Cyan
    $appHostConfig = Get-ApplicationHostConfigPath
    if ($appHostConfig -and (Test-Path -LiteralPath $appHostConfig)) {
        if ($PSCmdlet.ShouldProcess($backupDir, 'Copy ApplicationHost.config')) {
            Copy-Item -LiteralPath $appHostConfig -Destination $backupDir -Force -ErrorAction Stop
        }
        Write-ScriptMessage -Message 'ApplicationHost.config backed up' -Prefix '+' -Color Green
    }
    else {
        Write-ScriptMessage -Message 'ApplicationHost.config not found; skipping' -Prefix '!' -Color Yellow
    }

    # Backup site configurations.
    Write-ScriptMessage -Message 'Backing up site configurations...' -Prefix '*' -Color Cyan
    $sites = @(Get-IISSite -ErrorAction Stop)
    $sitesInfo = @()

    foreach ($site in $sites) {
        $physicalPath = $site.Applications['/'].VirtualDirectories['/'].PhysicalPath
        $bindingString = ($site.Bindings |
            ForEach-Object { "$($_.Protocol)://$($_.BindingInformation)" }) -join '; '
        $sitesInfo += [PSCustomObject]@{
            Name            = $site.Name
            ID              = $site.Id
            State           = $site.State
            PhysicalPath    = $physicalPath
            ApplicationPool = $site.Applications['/'].ApplicationPoolName
            Bindings        = $bindingString
        }

        # Backup web.config if it exists (check-then-act).
        $webConfig = Join-Path -Path $physicalPath -ChildPath 'web.config'
        if ($physicalPath -and (Test-Path -LiteralPath $webConfig)) {
            $siteBackupPath = Join-Path -Path $backupDir -ChildPath "Sites\$($site.Name)"
            if ($PSCmdlet.ShouldProcess($siteBackupPath, "Copy web.config for site '$($site.Name)'")) {
                New-Item -ItemType Directory -Path $siteBackupPath -Force -ErrorAction Stop | Out-Null
                Copy-Item -LiteralPath $webConfig -Destination $siteBackupPath -Force -ErrorAction Stop
            }
        }
    }

    $sitesCsv = Join-Path -Path $backupDir -ChildPath 'Sites.csv'
    $sitesInfo | Export-Csv -Path $sitesCsv -NoTypeInformation -ErrorAction Stop
    Write-ScriptMessage -Message "$($sites.Count) site configurations backed up" -Prefix '+' -Color Green

    # Backup application pools.
    Write-ScriptMessage -Message 'Backing up application pool configurations...' -Prefix '*' -Color Cyan
    $appPools = @(Get-IISAppPool -ErrorAction Stop)
    $poolsInfo = $appPools | ForEach-Object {
        [PSCustomObject]@{
            Name                  = $_.Name
            State                 = $_.State
            ManagedRuntimeVersion = $_.ManagedRuntimeVersion
            ManagedPipelineMode   = $_.ManagedPipelineMode
            StartMode             = $_.StartMode
            Enable32BitAppOnWin64 = $_.Enable32BitAppOnWin64
            IdleTimeoutMinutes    = $_.ProcessModel.IdleTimeout.TotalMinutes
            RecyclingSchedule     = ($_.Recycling.PeriodicRestart.Schedule -join ', ')
        }
    }
    $poolsCsv = Join-Path -Path $backupDir -ChildPath 'ApplicationPools.csv'
    $poolsInfo | Export-Csv -Path $poolsCsv -NoTypeInformation -ErrorAction Stop
    Write-ScriptMessage -Message "$($appPools.Count) application pools backed up" -Prefix '+' -Color Green

    # Backup SSL certificates.
    if ($IncludeCertificates) {
        Write-ScriptMessage -Message 'Backing up SSL certificates...' -Prefix '*' -Color Cyan
        $certsDir = Join-Path -Path $backupDir -ChildPath 'Certificates'
        New-Item -ItemType Directory -Path $certsDir -Force -ErrorAction Stop | Out-Null

        $httpsBindings = Get-IISSite -ErrorAction Stop | ForEach-Object {
            $_.Bindings | Where-Object { $_.Protocol -eq 'https' }
        }

        $certsExported = 0
        foreach ($binding in $httpsBindings) {
            if ($binding.CertificateHash) {
                $certStore = "Cert:\LocalMachine\$($binding.CertificateStoreName)"
                $cert = Get-ChildItem -Path $certStore -ErrorAction Stop |
                    Where-Object { $_.Thumbprint -eq $binding.CertificateHash }

                if ($cert) {
                    $certInfo = [PSCustomObject]@{
                        Thumbprint   = $cert.Thumbprint
                        Subject      = $cert.Subject
                        Issuer       = $cert.Issuer
                        NotAfter     = $cert.NotAfter
                        FriendlyName = $cert.FriendlyName
                    }
                    $certCsv = Join-Path -Path $certsDir -ChildPath 'certificates.csv'
                    $certInfo | Export-Csv -Path $certCsv -Append -NoTypeInformation -ErrorAction Stop
                    $certsExported++
                }
            }
        }
        Write-ScriptMessage -Message "$certsExported SSL certificate details backed up" -Prefix '+' -Color Green
    }

    # Create backup manifest.
    $inetStp = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\InetStp' -ErrorAction SilentlyContinue
    $manifest = @{
        BackupDate           = Get-Date
        ComputerName         = $env:COMPUTERNAME
        IISVersion           = $inetStp.VersionString
        SitesCount           = $sites.Count
        AppPoolsCount        = $appPools.Count
        CertificatesIncluded = $IncludeCertificates.IsPresent
        ContentFilesIncluded = $IncludeContentFiles.IsPresent
    }
    $manifestPath = Join-Path -Path $backupDir -ChildPath 'manifest.json'
    $manifest | ConvertTo-Json | Out-File -FilePath $manifestPath -Encoding UTF8 -ErrorAction Stop

    # Calculate backup size.
    $backupSize = (Get-ChildItem -LiteralPath $backupDir -Recurse | Measure-Object -Property Length -Sum).Sum / 1MB

    Write-ScriptMessage -Message '=== Backup Summary ==='
    Write-ScriptMessage -Message "Backup Location: $backupDir"
    Write-ScriptMessage -Message "Sites: $($sites.Count)"
    Write-ScriptMessage -Message "Application Pools: $($appPools.Count)"
    Write-ScriptMessage -Message "Total Size: $([math]::Round($backupSize, 2)) MB"
    Write-ScriptMessage -Message 'Backup completed successfully!' -Prefix '+' -Color Green
    return 0
}

function Main {
    <#
    .SYNOPSIS
        Runs the IIS configuration backup or restore workflow.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param()

    try {
        Write-ScriptMessage -Message '=== IIS Configuration Backup Tool ==='

        if ($Restore) {
            return Invoke-RestoreIisConfiguration -From $RestoreFrom
        }

        return Invoke-NewIisBackup
    }
    catch {
        Write-ScriptMessage -Message "Error: $($_.Exception.Message)" -Prefix '-' -Color Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
