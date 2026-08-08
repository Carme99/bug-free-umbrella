#Requires -Version 5.1
#Requires -Modules SqlServer, UpdateServices, IISAdministration
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Comprehensive Windows Server Update Services (WSUS) optimization and maintenance script.

.DESCRIPTION
    Modern WSUS optimization script with interactive configuration wizard and automated scheduling.

    Features:
    - Interactive configuration wizard for first-time setup
    - Deep cleaning of unnecessary updates by product and title
    - IIS configuration validation and optimization
    - Driver synchronization management
    - WSUS integrated cleanup processes
    - Microsoft best practice database optimization
    - Automatic scheduled task creation with saved configuration
    - Comprehensive logging and progress tracking
    - Safety features with backups and confirmations

.PARAMETER Interactive
    Launches the interactive configuration wizard. Prompts for all settings and creates scheduled tasks.

.PARAMETER ConfigFile
    Path to configuration file. If not specified, uses default location: C:\Scripts\WSUS\wsus-config.json

.PARAMETER DeclineSupersededUpdates
    Declines all approved updates that are superseded by other approved updates.

.PARAMETER DeepClean
    Performs deep cleaning of unneeded updates and drivers based on configuration.

.PARAMETER DisableDrivers
    Disables device driver synchronization and caching.

.PARAMETER CheckConfig
    Validates current WSUS IIS configuration against recommended settings.

.PARAMETER OptimizeServer
    Runs all built-in WSUS cleanup processes.

.PARAMETER OptimizeDatabase
    Runs Microsoft's recommended SQL reindexing and optimization.

.PARAMETER CreateTasks
    Creates scheduled tasks based on current configuration.

.PARAMETER LogPath
    Custom log file path. Default: C:\Scripts\WSUS\Logs\wsus-optimization.log

.PARAMETER SqlServerInstance
    SQL Server instance for WSUS database. If not specified, auto-detects from WSUS configuration or defaults to WID.

.NOTES
    Version:        2.0.0
    Author:         Modernized by Carme99 for 2025
    Original:       Austin Warren (awarre/Optimize-WsusServer v1.2.1)
                    https://github.com/awarre/Optimize-WsusServer
    Last Updated:   2025-01-09

    Requirements:
    - Windows Server 2016 or later
    - WSUS role installed
    - SQL Server (Express or Full)
    - PowerShell 5.1 or later
    - Administrator privileges

.EXAMPLE
    .\Optimize-WsusServer.ps1 -Interactive
    Launches the interactive configuration wizard.

.EXAMPLE
    .\Optimize-WsusServer.ps1 -OptimizeServer -OptimizeDatabase
    Runs server and database optimization using saved configuration.

.EXAMPLE
    .\Optimize-WsusServer.ps1 -DeepClean -ConfigFile "C:\Custom\config.json"
    Runs deep clean using a custom configuration file.
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param (
    [Parameter()]
    [switch]$Interactive,

    [Parameter()]
    [ValidateScript({
        # Validate path format and prevent path traversal
        if ($_ -match '\.\.[/\\]') {
            throw "Path traversal detected in ConfigFile parameter"
        }
        if ($_ -notmatch '^[A-Za-z]:\\') {
            throw "ConfigFile must be an absolute Windows path"
        }
        return $true
    })]
    [string]$ConfigFile = "C:\Scripts\WSUS\wsus-config.json",

    [Parameter()]
    [switch]$DeclineSupersededUpdates,

    [Parameter()]
    [switch]$DeepClean,

    [Parameter()]
    [switch]$DisableDrivers,

    [Parameter()]
    [switch]$CheckConfig,

    [Parameter()]
    [switch]$OptimizeServer,

    [Parameter()]
    [switch]$OptimizeDatabase,

    [Parameter()]
    [switch]$CreateTasks,

    [Parameter()]
    [string]$LogPath = "C:\Scripts\WSUS\Logs\wsus-optimization.log",

    [Parameter()]
    [string]$SqlServerInstance
)

#region Configuration

# Default configuration structure
$script:DefaultConfig = @{
    Version = "2.0.0"
    LastUpdated = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")

    # IIS Settings
    IISSettings = @{
        QueueLength = 25000
        LoadBalancerCapabilities = 'TcpLevel'
        CpuResetInterval = 15
        RecyclingMemory = 0
        RecyclingPrivateMemory = 0
        ClientMaxRequestLength = 204800
        ClientExecutionTimeout = 7200
    }

    # Deep Clean Settings
    DeepClean = @{
        Enabled = $true
        UnneededProductTitles = @(
            # Legacy Windows versions (EOL)
            "Windows 2000",
            "Windows XP",
            "Windows XP x64 Edition",
            "Windows XP Embedded",
            "Windows Vista",
            "Windows 7",
            "Windows 8",
            "Windows 8.1",
            "Windows 8 Embedded",
            "Windows Ultimate Extras",

            # Legacy Server versions (EOL)
            "Windows Server 2003",
            "Windows Server 2003 R2",
            "Windows Server 2008",
            "Windows Server 2008 R2",

            # Legacy Office versions (EOL)
            "Office 2002/XP",
            "Office 2003",
            "Office 2007",
            "Office 2010",

            # Legacy SQL Server (EOL)
            "SQL Server 2000",
            "SQL Server 2005",
            "SQL Server 2008",

            # Other legacy products
            "Forefront Identity Manager 2010",
            "Microsoft Lync Server 2010",
            "Microsoft Lync Server 2013",
            "Virtual PC"
        )

        UnneededUpdateTitles = @(
            # Legacy browsers
            "Internet Explorer 6",
            "Internet Explorer 7",
            "Internet Explorer 8",
            "Internet Explorer 9",
            "Internet Explorer 10",

            # Architecture filters
            "Itanium",
            "ARM64",

            # Edition filters (customize based on your environment)
            "Windows 10 (consumer editions)",
            "Windows 11 (consumer editions)",
            "Windows 10 Education",
            "Windows 10 Enterprise N",
            "Windows 11 Education N",

            # Language packs (if not needed)
            "Language Interface Pack"
        )

        RemoveDrivers = $true
        DeclineSuperseded = $true
    }

    # Maintenance Tasks
    ScheduledTasks = @{
        Daily = @{
            Enabled = $true
            Time = "02:00"
            Actions = @("OptimizeServer", "DeclineSupersededUpdates")
        }
        Weekly = @{
            Enabled = $true
            DayOfWeek = "Sunday"
            Time = "03:00"
            Actions = @("OptimizeDatabase", "CheckConfig")
        }
        Monthly = @{
            Enabled = $false
            Day = 1
            Time = "04:00"
            Actions = @("DeepClean")
        }
    }

    # Features
    Features = @{
        DisableDriverSync = $true
        CreateCustomIndexes = $true
        AutomaticCleanup = $true
    }

    # Database Settings
    Database = @{
        SqlServerInstance = $null  # Auto-detect from WSUS registry or use WID
    }

    # Logging
    Logging = @{
        Enabled = $true
        LogPath = "C:\Scripts\WSUS\Logs"
        RetentionDays = 30
        VerboseLogging = $false
    }
}

#endregion

#region Logging Functions

function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter()]
        [ValidateSet('Info', 'Warning', 'Error', 'Success')]
        [string]$Level = 'Info',

        [Parameter()]
        [switch]$NoConsole
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"

    # Ensure log directory exists
    $logDir = Split-Path -Path $script:LogPath -Parent
    if (-not (Test-Path -Path $logDir)) {
        New-Item -Path $logDir -ItemType Directory -Force | Out-Null
    }

    # Write to log file
    Add-Content -Path $script:LogPath -Value $logMessage -ErrorAction SilentlyContinue

    # Write to console unless suppressed
    if (-not $NoConsole) {
        switch ($Level) {
            'Info'    { Write-Host $logMessage -ForegroundColor Cyan }
            'Warning' { Write-Warning $Message }
            'Error'   { Write-Host $logMessage -ForegroundColor Red }
            'Success' { Write-Host $logMessage -ForegroundColor Green }
        }
    }
}

function Write-Progress-Custom {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Activity,

        [Parameter()]
        [string]$Status = "Processing...",

        [Parameter()]
        [int]$PercentComplete = -1,

        [Parameter()]
        [switch]$Completed
    )

    $params = @{
        Activity = $Activity
        Status = $Status
    }

    if ($PercentComplete -ge 0) {
        $params.PercentComplete = $PercentComplete
    }

    if ($Completed) {
        $params.Completed = $true
    }

    Write-Progress @params
}

function Test-SafePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter()]
        [switch]$MustExist
    )

    try {
        # Resolve to absolute path
        $resolved = [System.IO.Path]::GetFullPath($Path)

        # Check for valid Windows path format
        if ($resolved -notmatch '^[A-Za-z]:\\') {
            throw "Invalid path format: $Path"
        }

        # Check for path traversal attempts
        if ($resolved -match '\.\.[/\\]') {
            throw "Path traversal detected: $Path"
        }

        # Check for dangerous characters in path
        $invalidChars = [System.IO.Path]::GetInvalidPathChars()
        foreach ($char in $invalidChars) {
            if ($Path.Contains($char)) {
                throw "Path contains invalid character: $char"
            }
        }

        # If must exist, verify the path exists
        if ($MustExist -and -not (Test-Path -Path $resolved)) {
            throw "Path does not exist: $resolved"
        }

        return $resolved
    }
    catch {
        Write-Log "Path validation failed for '$Path': $_" -Level Error
        throw
    }
}

function Test-SafeString {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$InputString,

        [Parameter()]
        [int]$MaxLength = 255,

        [Parameter()]
        [string[]]$DisallowedChars = @('<', '>', ':', '"', '|', '?', '*')
    )

    # Check length
    if ($InputString.Length -gt $MaxLength) {
        throw "Input exceeds maximum length of $MaxLength characters"
    }

    # Check for disallowed characters
    foreach ($char in $DisallowedChars) {
        if ($InputString.Contains($char)) {
            throw "Input contains disallowed character: $char"
        }
    }

    return $true
}

function Get-SafeXmlDocument {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    try {
        # Create XML reader settings to prevent XXE attacks
        $xmlSettings = New-Object System.Xml.XmlReaderSettings
        $xmlSettings.DtdProcessing = [System.Xml.DtdProcessing]::Prohibit
        $xmlSettings.XmlResolver = $null

        # Load XML safely
        $reader = [System.Xml.XmlReader]::Create($Path, $xmlSettings)
        $xmlDoc = New-Object System.Xml.XmlDocument
        $xmlDoc.Load($reader)
        $reader.Close()

        return $xmlDoc
    }
    catch {
        Write-Log "Failed to load XML document from '$Path': $_" -Level Error
        throw
    }
}

function Get-WsusSqlInstance {
    [CmdletBinding()]
    param()

    try {
        # Try to get SQL instance from WSUS registry
        $wsusSetupKey = "HKLM:\SOFTWARE\Microsoft\Update Services\Server\Setup"

        if (Test-Path $wsusSetupKey) {
            $sqlInstance = (Get-ItemProperty -Path $wsusSetupKey -Name "SqlServerName" -ErrorAction SilentlyContinue).SqlServerName

            if (-not [string]::IsNullOrEmpty($sqlInstance)) {
                Write-Log "Detected SQL Server instance from WSUS configuration: $sqlInstance" -Level Info
                return $sqlInstance
            }
        }

        # Default to Windows Internal Database (WID)
        $widInstance = "\\.\pipe\MICROSOFT##WID\tsql\query"
        Write-Log "Using default Windows Internal Database (WID): $widInstance" -Level Info
        return $widInstance
    }
    catch {
        Write-Log "Failed to detect SQL instance, using WID default: $_" -Level Warning
        return "\\.\pipe\MICROSOFT##WID\tsql\query"
    }
}

#endregion

#region Configuration Management

function Get-WsusConfig {
    [CmdletBinding()]
    param(
        [string]$Path = $script:ConfigFile
    )

    if (Test-Path -Path $Path) {
        try {
            $config = Get-Content -Path $Path -Raw | ConvertFrom-Json
            Write-Log "Configuration loaded from: $Path" -Level Info

            # Convert PSCustomObject to hashtable recursively
            return ConvertTo-Hashtable $config
        }
        catch {
            Write-Log "Failed to load configuration from $Path. Using defaults. Error: $_" -Level Warning
            return Copy-HashtableDeep $script:DefaultConfig
        }
    }
    else {
        Write-Log "Configuration file not found. Using defaults." -Level Info
        return Copy-HashtableDeep $script:DefaultConfig
    }
}

function Save-WsusConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Config,

        [string]$Path = $script:ConfigFile
    )

    try {
        $configDir = Split-Path -Path $Path -Parent
        if (-not (Test-Path -Path $configDir)) {
            New-Item -Path $configDir -ItemType Directory -Force | Out-Null
        }

        $Config.LastUpdated = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $Config | ConvertTo-Json -Depth 10 | Set-Content -Path $Path -Force
        Write-Log "Configuration saved to: $Path" -Level Success
        return $true
    }
    catch {
        Write-Log "Failed to save configuration: $_" -Level Error
        return $false
    }
}

function ConvertTo-Hashtable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $InputObject
    )

    if ($InputObject -is [System.Collections.IDictionary]) {
        return $InputObject
    }

    $hash = @{}

    if ($InputObject -is [PSCustomObject]) {
        $InputObject.PSObject.Properties | ForEach-Object {
            $value = $_.Value
            if ($value -is [PSCustomObject] -or $value -is [System.Collections.IDictionary]) {
                $hash[$_.Name] = ConvertTo-Hashtable $value
            }
            elseif ($value -is [Array]) {
                $hash[$_.Name] = @($value | ForEach-Object {
                    if ($_ -is [PSCustomObject] -or $_ -is [System.Collections.IDictionary]) {
                        ConvertTo-Hashtable $_
                    }
                    else {
                        $_
                    }
                })
            }
            else {
                $hash[$_.Name] = $value
            }
        }
    }

    return $hash
}

function Copy-HashtableDeep {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $InputObject
    )

    $clone = @{}

    foreach ($key in $InputObject.Keys) {
        $value = $InputObject[$key]

        if ($value -is [hashtable]) {
            # Recursively clone nested hashtables
            $clone[$key] = Copy-HashtableDeep $value
        }
        elseif ($value -is [Array]) {
            # Clone array elements
            $clone[$key] = @($value | ForEach-Object {
                if ($_ -is [hashtable]) {
                    Copy-HashtableDeep $_
                }
                else {
                    $_
                }
            })
        }
        else {
            # Copy value types and strings
            $clone[$key] = $value
        }
    }

    return $clone
}

#endregion

#region Interactive Configuration Wizard

function Show-Banner {
    $banner = @"

╔════════════════════════════════════════════════════════════════╗
║                                                                ║
║           WSUS OPTIMIZATION & MAINTENANCE WIZARD               ║
║                       Version 2.0.0                            ║
║                                                                ║
╚════════════════════════════════════════════════════════════════╝

"@
    Write-Host $banner -ForegroundColor Cyan
}

function Show-Menu {
    param(
        [string]$Title,
        [string[]]$Options,
        [int]$DefaultSelection = 0
    )

    Write-Host "`n$Title" -ForegroundColor Yellow
    Write-Host ("=" * $Title.Length) -ForegroundColor Yellow

    for ($i = 0; $i -lt $Options.Count; $i++) {
        $prefix = if ($i -eq $DefaultSelection) { ">" } else { " " }
        Write-Host "$prefix [$($i + 1)] $($Options[$i])" -ForegroundColor $(if ($i -eq $DefaultSelection) { "Green" } else { "White" })
    }

    do {
        $input = Read-Host "`nSelect option (1-$($Options.Count))"
        if ([string]::IsNullOrWhiteSpace($input)) {
            return $DefaultSelection
        }
    } while (-not ($input -match '^\d+$' -and [int]$input -ge 1 -and [int]$input -le $Options.Count))

    return ([int]$input - 1)
}

function Confirm-Choice {
    param(
        [string]$Message,
        [bool]$DefaultYes = $true
    )

    $defaultChar = if ($DefaultYes) { "Y" } else { "N" }
    $prompt = if ($DefaultYes) { "[Y/n]" } else { "[y/N]" }

    $response = Read-Host "$Message $prompt"

    if ([string]::IsNullOrWhiteSpace($response)) {
        return $DefaultYes
    }

    return $response -match '^[Yy]'
}

function Start-InteractiveWizard {
    [CmdletBinding()]
    param()

    Show-Banner

    Write-Host "This wizard will help you configure WSUS optimization and create scheduled tasks.`n" -ForegroundColor Cyan

    # Load existing config or create new
    $config = Get-WsusConfig

    # Section 1: Deep Clean Configuration
    Write-Host "`n" + ("=" * 70) -ForegroundColor Magenta
    Write-Host "SECTION 1: DEEP CLEAN CONFIGURATION" -ForegroundColor Magenta
    Write-Host ("=" * 70) -ForegroundColor Magenta

    $config.DeepClean.Enabled = Confirm-Choice -Message "Enable deep cleaning of obsolete updates?" -DefaultYes $true

    if ($config.DeepClean.Enabled) {
        Write-Host "`nThe following obsolete products are configured for removal:" -ForegroundColor Yellow
        $config.DeepClean.UnneededProductTitles | ForEach-Object { Write-Host "  - $_" -ForegroundColor DarkGray }

        if (Confirm-Choice -Message "`nModify the list of obsolete products?" -DefaultYes $false) {
            # Allow user to add custom products
            Write-Host "Enter additional products to remove (one per line, blank line to finish):" -ForegroundColor Yellow
            $customProducts = @()
            do {
                $product = Read-Host "Product"
                if (-not [string]::IsNullOrWhiteSpace($product)) {
                    # Validate input
                    try {
                        Test-SafeString -InputString $product -MaxLength 255
                        $customProducts += $product
                    }
                    catch {
                        Write-Host "Invalid input: $_" -ForegroundColor Red
                    }
                }
            } while (-not [string]::IsNullOrWhiteSpace($product))

            if ($customProducts.Count -gt 0) {
                $config.DeepClean.UnneededProductTitles = $config.DeepClean.UnneededProductTitles + $customProducts | Select-Object -Unique
            }
        }

        $config.DeepClean.RemoveDrivers = Confirm-Choice -Message "Remove all drivers during deep clean?" -DefaultYes $true
        $config.DeepClean.DeclineSuperseded = Confirm-Choice -Message "Decline superseded updates?" -DefaultYes $true
    }

    # Section 2: Driver Synchronization
    Write-Host "`n" + ("=" * 70) -ForegroundColor Magenta
    Write-Host "SECTION 2: DRIVER SYNCHRONIZATION" -ForegroundColor Magenta
    Write-Host ("=" * 70) -ForegroundColor Magenta

    Write-Host "`nDriver synchronization can cause:" -ForegroundColor Yellow
    Write-Host "  - Significant storage usage" -ForegroundColor DarkGray
    Write-Host "  - Slower WSUS performance" -ForegroundColor DarkGray
    Write-Host "  - Database bloat" -ForegroundColor DarkGray
    Write-Host "`nMost environments manage drivers through other methods (SCCM, WDS, etc.)" -ForegroundColor Yellow

    $config.Features.DisableDriverSync = Confirm-Choice -Message "`nDisable driver synchronization? (Recommended)" -DefaultYes $true

    # Section 3: Scheduled Tasks
    Write-Host "`n" + ("=" * 70) -ForegroundColor Magenta
    Write-Host "SECTION 3: SCHEDULED TASKS" -ForegroundColor Magenta
    Write-Host ("=" * 70) -ForegroundColor Magenta

    # Daily task
    Write-Host "`n--- DAILY MAINTENANCE ---" -ForegroundColor Cyan
    $config.ScheduledTasks.Daily.Enabled = Confirm-Choice -Message "Create daily optimization task?" -DefaultYes $true

    if ($config.ScheduledTasks.Daily.Enabled) {
        do {
            $time = Read-Host "Daily task time (HH:MM, default: 02:00)"
            if ([string]::IsNullOrWhiteSpace($time)) {
                $time = "02:00"
            }
        } while (-not ($time -match '^\d{2}:\d{2}$'))

        $config.ScheduledTasks.Daily.Time = $time

        Write-Host "`nDaily task will perform:" -ForegroundColor Yellow
        Write-Host "  - Server optimization (WSUS cleanup)" -ForegroundColor DarkGray
        Write-Host "  - Decline superseded updates" -ForegroundColor DarkGray
    }

    # Weekly task
    Write-Host "`n--- WEEKLY MAINTENANCE ---" -ForegroundColor Cyan
    $config.ScheduledTasks.Weekly.Enabled = Confirm-Choice -Message "Create weekly optimization task?" -DefaultYes $true

    if ($config.ScheduledTasks.Weekly.Enabled) {
        $daysOfWeek = @("Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday")
        $dayIndex = Show-Menu -Title "Select day of week for weekly task" -Options $daysOfWeek -DefaultSelection 0
        $config.ScheduledTasks.Weekly.DayOfWeek = $daysOfWeek[$dayIndex]

        do {
            $time = Read-Host "Weekly task time (HH:MM, default: 03:00)"
            if ([string]::IsNullOrWhiteSpace($time)) {
                $time = "03:00"
            }
        } while (-not ($time -match '^\d{2}:\d{2}$'))

        $config.ScheduledTasks.Weekly.Time = $time

        Write-Host "`nWeekly task will perform:" -ForegroundColor Yellow
        Write-Host "  - Database optimization and reindexing" -ForegroundColor DarkGray
        Write-Host "  - IIS configuration check" -ForegroundColor DarkGray
    }

    # Monthly task
    Write-Host "`n--- MONTHLY DEEP CLEAN ---" -ForegroundColor Cyan
    $config.ScheduledTasks.Monthly.Enabled = Confirm-Choice -Message "Create monthly deep clean task?" -DefaultYes $false

    if ($config.ScheduledTasks.Monthly.Enabled) {
        do {
            $day = Read-Host "Day of month (1-28, default: 1)"
            if ([string]::IsNullOrWhiteSpace($day)) {
                $day = 1
            }
        } while (-not ($day -match '^\d+$' -and [int]$day -ge 1 -and [int]$day -le 28))

        $config.ScheduledTasks.Monthly.Day = [int]$day

        do {
            $time = Read-Host "Monthly task time (HH:MM, default: 04:00)"
            if ([string]::IsNullOrWhiteSpace($time)) {
                $time = "04:00"
            }
        } while (-not ($time -match '^\d{2}:\d{2}$'))

        $config.ScheduledTasks.Monthly.Time = $time
    }

    # Section 4: Advanced Options
    Write-Host "`n" + ("=" * 70) -ForegroundColor Magenta
    Write-Host "SECTION 4: ADVANCED OPTIONS" -ForegroundColor Magenta
    Write-Host ("=" * 70) -ForegroundColor Magenta

    $config.Features.CreateCustomIndexes = Confirm-Choice -Message "Create custom database indexes? (Improves performance)" -DefaultYes $true
    $config.Logging.VerboseLogging = Confirm-Choice -Message "Enable verbose logging?" -DefaultYes $false

    do {
        $retention = Read-Host "Log retention in days (default: 30)"
        if ([string]::IsNullOrWhiteSpace($retention)) {
            $retention = 30
        }
    } while (-not ($retention -match '^\d+$'))

    $config.Logging.RetentionDays = [int]$retention

    # Summary
    Write-Host "`n" + ("=" * 70) -ForegroundColor Green
    Write-Host "CONFIGURATION SUMMARY" -ForegroundColor Green
    Write-Host ("=" * 70) -ForegroundColor Green

    Write-Host "`nDeep Clean:" -ForegroundColor Yellow
    Write-Host "  Enabled: $($config.DeepClean.Enabled)" -ForegroundColor White
    if ($config.DeepClean.Enabled) {
        Write-Host "  Remove Drivers: $($config.DeepClean.RemoveDrivers)" -ForegroundColor White
        Write-Host "  Decline Superseded: $($config.DeepClean.DeclineSuperseded)" -ForegroundColor White
        Write-Host "  Products to Remove: $($config.DeepClean.UnneededProductTitles.Count)" -ForegroundColor White
    }

    Write-Host "`nFeatures:" -ForegroundColor Yellow
    Write-Host "  Disable Driver Sync: $($config.Features.DisableDriverSync)" -ForegroundColor White
    Write-Host "  Custom Indexes: $($config.Features.CreateCustomIndexes)" -ForegroundColor White

    Write-Host "`nScheduled Tasks:" -ForegroundColor Yellow
    Write-Host "  Daily Task: $($config.ScheduledTasks.Daily.Enabled) $(if ($config.ScheduledTasks.Daily.Enabled) { "at $($config.ScheduledTasks.Daily.Time)" })" -ForegroundColor White
    Write-Host "  Weekly Task: $($config.ScheduledTasks.Weekly.Enabled) $(if ($config.ScheduledTasks.Weekly.Enabled) { "on $($config.ScheduledTasks.Weekly.DayOfWeek) at $($config.ScheduledTasks.Weekly.Time)" })" -ForegroundColor White
    Write-Host "  Monthly Task: $($config.ScheduledTasks.Monthly.Enabled) $(if ($config.ScheduledTasks.Monthly.Enabled) { "on day $($config.ScheduledTasks.Monthly.Day) at $($config.ScheduledTasks.Monthly.Time)" })" -ForegroundColor White

    Write-Host "`nLogging:" -ForegroundColor Yellow
    Write-Host "  Verbose: $($config.Logging.VerboseLogging)" -ForegroundColor White
    Write-Host "  Retention: $($config.Logging.RetentionDays) days" -ForegroundColor White

    # Save configuration
    Write-Host ""
    if (Confirm-Choice -Message "Save this configuration?" -DefaultYes $true) {
        if (Save-WsusConfig -Config $config) {
            Write-Host "`nConfiguration saved successfully!" -ForegroundColor Green

            # Offer to create tasks now
            if (Confirm-Choice -Message "Create scheduled tasks now?" -DefaultYes $true) {
                New-WsusScheduledTasks -Config $config
            }

            # Offer to run initial optimization
            if (Confirm-Choice -Message "Run initial optimization now?" -DefaultYes $true) {
                Write-Host "`nStarting initial optimization..." -ForegroundColor Cyan

                if ($config.Features.DisableDriverSync) {
                    Disable-WsusDriverSync
                }

                if ($config.Features.CreateCustomIndexes) {
                    Initialize-WsusDatabase
                }

                if (Confirm-Choice -Message "Run database optimization? (This may take a while)" -DefaultYes $true) {
                    Optimize-WsusDatabase -Config $config
                }

                if (Confirm-Choice -Message "Run server optimization?" -DefaultYes $true) {
                    Optimize-WsusUpdates -Config $config
                }

                if (Confirm-Choice -Message "Check IIS configuration?" -DefaultYes $true) {
                    Test-WsusIISConfig -Config $config
                }
            }
        }
        else {
            Write-Host "`nFailed to save configuration!" -ForegroundColor Red
        }
    }
    else {
        Write-Host "`nConfiguration not saved." -ForegroundColor Yellow
    }
}

#endregion

#region WSUS Core Functions

function Get-WsusServerInstance {
    [CmdletBinding()]
    param()

    try {
        [reflection.assembly]::LoadWithPartialName("Microsoft.UpdateServices.Administration") | Out-Null
        $wsusServer = [Microsoft.UpdateServices.Administration.AdminProxy]::GetUpdateServer()
        Write-Log "Connected to WSUS server: $($wsusServer.Name)" -Level Info
        return $wsusServer
    }
    catch {
        Write-Log "Failed to connect to WSUS server: $_" -Level Error
        throw
    }
}

function Get-WsusIISConfig {
    [CmdletBinding()]
    param()

    try {
        Import-Module IISAdministration -ErrorAction Stop

        $appPool = Get-IISAppPool -Name "WsusPool"

        $config = @{
            QueueLength = $appPool.QueueLength
            CpuResetInterval = $appPool.Cpu.ResetInterval.TotalMinutes
            RecyclingMemory = $appPool.Recycling.PeriodicRestart.Memory
            RecyclingPrivateMemory = $appPool.Recycling.PeriodicRestart.PrivateMemory
        }

        # Get site-specific settings
        $site = Get-IISSite -Name "WSUS Administration"
        $webConfigPath = Join-Path $site.Applications[0].VirtualDirectories[0].PhysicalPath "web.config"

        if (Test-Path $webConfigPath) {
            # Load XML safely to prevent XXE attacks
            $webConfig = Get-SafeXmlDocument -Path $webConfigPath
            $config.ClientMaxRequestLength = [int]$webConfig.configuration.'system.web'.httpRuntime.maxRequestLength
            $config.ClientExecutionTimeout = [int]$webConfig.configuration.'system.web'.httpRuntime.executionTimeout
        }

        # Load balancer capabilities
        # ApplicationPoolProcessModel exposes no typed LoadBalancerCapabilities property,
        # so read the raw processModel.loadBalancerCapabilities attribute instead.
        if ($null -ne $site.Applications["/ClientWebService"]) {
            $config.LoadBalancerCapabilities = $appPool.ProcessModel.GetAttributeValue("loadBalancerCapabilities")
        }

        return $config
    }
    catch {
        Write-Log "Failed to retrieve IIS configuration: $_" -Level Error
        return $null
    }
}

function Test-WsusIISConfig {
    [CmdletBinding()]
    param(
        [hashtable]$Config
    )

    Write-Log "Checking WSUS IIS configuration..." -Level Info

    $currentConfig = Get-WsusIISConfig

    if ($null -eq $currentConfig) {
        Write-Log "Unable to retrieve current IIS configuration" -Level Error
        return
    }

    $recommendedSettings = $Config.IISSettings
    $issues = @()

    foreach ($setting in $recommendedSettings.Keys) {
        if ($currentConfig.ContainsKey($setting)) {
            $current = $currentConfig[$setting]
            $recommended = $recommendedSettings[$setting]

            if ($current -ne $recommended) {
                $issues += [PSCustomObject]@{
                    Setting = $setting
                    Current = $current
                    Recommended = $recommended
                }
            }
        }
    }

    if ($issues.Count -eq 0) {
        Write-Log "IIS configuration is optimal" -Level Success
    }
    else {
        Write-Log "Found $($issues.Count) IIS configuration issues:" -Level Warning
        $issues | Format-Table -AutoSize | Out-String | ForEach-Object { Write-Log $_ -Level Warning }

        if ($PSCmdlet.ShouldProcess("WSUS IIS Configuration", "Apply recommended settings")) {
            Set-WsusIISConfig -RecommendedSettings $recommendedSettings
        }
    }
}

function Set-WsusIISConfig {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [hashtable]$RecommendedSettings
    )

    if (-not $PSCmdlet.ShouldProcess("WSUS IIS Configuration", "Update settings")) {
        return
    }

    try {
        Write-Log "Applying recommended IIS settings..." -Level Info

        # App pool settings
        $serverManager = Get-IISServerManager
        $appPool = $serverManager.ApplicationPools["WsusPool"]
        $appPool.QueueLength = $RecommendedSettings.QueueLength
        $appPool.Cpu.ResetInterval = New-TimeSpan -Minutes $RecommendedSettings.CpuResetInterval
        $appPool.Recycling.PeriodicRestart.Memory = $RecommendedSettings.RecyclingMemory
        $appPool.Recycling.PeriodicRestart.PrivateMemory = $RecommendedSettings.RecyclingPrivateMemory
        $serverManager.CommitChanges()

        # Web.config settings require unlocking and modifying the file
        $site = Get-IISSite -Name "WSUS Administration"
        $webConfigPath = Join-Path $site.Applications[0].VirtualDirectories[0].PhysicalPath "web.config"

        if (Test-Path $webConfigPath) {
            # Backup web.config
            $backupPath = "$webConfigPath.backup-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
            Copy-Item -Path $webConfigPath -Destination $backupPath -Force
            Write-Log "Web.config backed up to: $backupPath" -Level Info

            # Load XML safely to prevent XXE attacks
            $webConfig = Get-SafeXmlDocument -Path $webConfigPath

            # Update httpRuntime settings
            if ($null -eq $webConfig.configuration.'system.web'.httpRuntime) {
                $httpRuntime = $webConfig.CreateElement("httpRuntime")
                $webConfig.configuration.'system.web'.AppendChild($httpRuntime) | Out-Null
            }

            $webConfig.configuration.'system.web'.httpRuntime.SetAttribute("maxRequestLength", $RecommendedSettings.ClientMaxRequestLength)
            $webConfig.configuration.'system.web'.httpRuntime.SetAttribute("executionTimeout", $RecommendedSettings.ClientExecutionTimeout)

            $webConfig.Save($webConfigPath)
            Write-Log "Web.config updated successfully" -Level Success
        }

        # Restart app pool (IISAdministration equivalent of Restart-WebAppPool)
        (Get-IISAppPool -Name "WsusPool").Recycle()
        Write-Log "WSUS App Pool restarted" -Level Success

        Write-Log "IIS configuration updated successfully" -Level Success
    }
    catch {
        Write-Log "Failed to update IIS configuration: $_" -Level Error
        throw
    }
}

#endregion

#region Database Functions

$script:CreateCustomIndexesSQL = @"
USE [SUSDB]
GO

-- Check and create index on tbLocalizedPropertyForRevision
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID('[dbo].[tbLocalizedPropertyForRevision]')
    AND name = 'nclLocalizedPropertyID'
)
BEGIN
    PRINT 'Creating index [nclLocalizedPropertyID] on [tbLocalizedPropertyForRevision]...'
    CREATE NONCLUSTERED INDEX [nclLocalizedPropertyID]
    ON [dbo].[tbLocalizedPropertyForRevision]([LocalizedPropertyID] ASC)
    WITH (
        PAD_INDEX = OFF,
        STATISTICS_NORECOMPUTE = OFF,
        SORT_IN_TEMPDB = OFF,
        DROP_EXISTING = OFF,
        ONLINE = OFF,
        ALLOW_ROW_LOCKS = ON,
        ALLOW_PAGE_LOCKS = ON
    ) ON [PRIMARY]
    PRINT 'Index created successfully'
END
ELSE
BEGIN
    PRINT 'Index [nclLocalizedPropertyID] already exists'
END
GO

-- Check and create index on tbRevisionSupersedesUpdate
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID('[dbo].[tbRevisionSupersedesUpdate]')
    AND name = 'nclSupercededUpdateID'
)
BEGIN
    PRINT 'Creating index [nclSupercededUpdateID] on [tbRevisionSupersedesUpdate]...'
    CREATE NONCLUSTERED INDEX [nclSupercededUpdateID]
    ON [dbo].[tbRevisionSupersedesUpdate]([SupersededUpdateID] ASC)
    WITH (
        PAD_INDEX = OFF,
        STATISTICS_NORECOMPUTE = OFF,
        SORT_IN_TEMPDB = OFF,
        DROP_EXISTING = OFF,
        ONLINE = OFF,
        ALLOW_ROW_LOCKS = ON,
        ALLOW_PAGE_LOCKS = ON
    ) ON [PRIMARY]
    PRINT 'Index created successfully'
END
ELSE
BEGIN
    PRINT 'Index [nclSupercededUpdateID] already exists'
END
GO
"@

$script:OptimizeDatabaseSQL = @"
USE [SUSDB]
GO

SET NOCOUNT ON

-- Declare variables
DECLARE @msg nvarchar(100)
DECLARE @StartTime datetime = GETDATE()

PRINT 'Starting WSUS database optimization at ' + CONVERT(varchar(20), @StartTime, 120)
PRINT ''

-- Update statistics
PRINT '========================================='
PRINT 'Updating statistics...'
PRINT '========================================='
EXEC sp_updatestats
PRINT 'Statistics updated'
PRINT ''

-- Rebuild indexes
PRINT '========================================='
PRINT 'Rebuilding fragmented indexes...'
PRINT '========================================='

DECLARE @tablename varchar(255)
DECLARE @fragmentation float
DECLARE @indexname varchar(255)
DECLARE @schemaname varchar(255)

DECLARE IndexCursor CURSOR FOR
    SELECT
        s.name AS SchemaName,
        t.name AS TableName,
        i.name AS IndexName,
        ps.avg_fragmentation_in_percent
    FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'LIMITED') ps
    INNER JOIN sys.tables t ON ps.object_id = t.object_id
    INNER JOIN sys.schemas s ON t.schema_id = s.schema_id
    INNER JOIN sys.indexes i ON ps.object_id = i.object_id AND ps.index_id = i.index_id
    WHERE ps.avg_fragmentation_in_percent > 10
        AND ps.index_id > 0
        AND ps.page_count > 100
    ORDER BY ps.avg_fragmentation_in_percent DESC

OPEN IndexCursor

FETCH NEXT FROM IndexCursor INTO @schemaname, @tablename, @indexname, @fragmentation

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @msg = 'Rebuilding index [' + @indexname + '] on [' + @schemaname + '].[' + @tablename + '] (Fragmentation: ' + CAST(@fragmentation AS varchar(10)) + '%)'
    PRINT @msg

    DECLARE @sql nvarchar(1000)
    -- Use QUOTENAME() to prevent SQL injection
    SET @sql = 'ALTER INDEX ' + QUOTENAME(@indexname) + ' ON ' + QUOTENAME(@schemaname) + '.' + QUOTENAME(@tablename) + ' REBUILD WITH (ONLINE = OFF)'

    BEGIN TRY
        EXEC sp_executesql @sql
    END TRY
    BEGIN CATCH
        PRINT 'Error rebuilding index: ' + ERROR_MESSAGE()
    END CATCH

    FETCH NEXT FROM IndexCursor INTO @schemaname, @tablename, @indexname, @fragmentation
END

CLOSE IndexCursor
DEALLOCATE IndexCursor

PRINT ''
PRINT 'Index rebuild complete'
PRINT ''

-- Shrink database (optional, be careful with this)
-- PRINT '========================================='
-- PRINT 'Shrinking database...'
-- PRINT '========================================='
-- DBCC SHRINKDATABASE([SUSDB], 10)
-- PRINT 'Database shrink complete'
-- PRINT ''

DECLARE @EndTime datetime = GETDATE()
DECLARE @Duration int = DATEDIFF(second, @StartTime, @EndTime)

PRINT '========================================='
PRINT 'Optimization complete!'
PRINT 'Duration: ' + CAST(@Duration AS varchar(10)) + ' seconds'
PRINT '========================================='

SET NOCOUNT OFF
GO
"@

function Initialize-WsusDatabase {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter()]
        [string]$SqlInstance
    )

    if (-not $PSCmdlet.ShouldProcess("WSUS Database", "Create custom indexes")) {
        return
    }

    try {
        # Detect SQL instance if not provided
        if ([string]::IsNullOrEmpty($SqlInstance)) {
            $SqlInstance = Get-WsusSqlInstance
        }

        Write-Log "Creating custom database indexes on SQL instance: $SqlInstance" -Level Info

        $result = Invoke-Sqlcmd -Query $script:CreateCustomIndexesSQL -ServerInstance $SqlInstance -Verbose

        if ($result) {
            $result | ForEach-Object { Write-Log $_ -Level Info }
        }

        Write-Log "Custom indexes created successfully" -Level Success
    }
    catch {
        Write-Log "Failed to create custom indexes: $_" -Level Error
        throw
    }
}

function Optimize-WsusDatabase {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [hashtable]$Config,

        [Parameter()]
        [string]$SqlInstance
    )

    if (-not $PSCmdlet.ShouldProcess("WSUS Database", "Optimize and reindex")) {
        return
    }

    try {
        # Detect SQL instance if not provided
        if ([string]::IsNullOrEmpty($SqlInstance)) {
            # Try to get from config first
            if ($Config.Database.SqlServerInstance) {
                $SqlInstance = $Config.Database.SqlServerInstance
            }
            else {
                $SqlInstance = Get-WsusSqlInstance
            }
        }

        Write-Log "Starting WSUS database optimization on SQL instance: $SqlInstance" -Level Info
        Write-Progress-Custom -Activity "WSUS Database Optimization" -Status "Running optimization scripts..."

        $result = Invoke-Sqlcmd -Query $script:OptimizeDatabaseSQL -ServerInstance $SqlInstance -QueryTimeout 7200 -Verbose

        if ($result) {
            $result | ForEach-Object { Write-Log $_ -Level Info }
        }

        Write-Progress-Custom -Activity "WSUS Database Optimization" -Completed
        Write-Log "Database optimization completed successfully" -Level Success
    }
    catch {
        Write-Progress-Custom -Activity "WSUS Database Optimization" -Completed
        Write-Log "Database optimization failed: $_" -Level Error
        throw
    }
}

#endregion

#region Update Cleanup Functions

function Optimize-WsusUpdates {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [hashtable]$Config
    )

    if (-not $PSCmdlet.ShouldProcess("WSUS Server", "Run cleanup operations")) {
        return
    }

    try {
        Write-Log "Starting WSUS server cleanup..." -Level Info

        $wsusServer = Get-WsusServerInstance

        # Run all cleanup operations
        $cleanupTasks = @(
            @{ Name = "Unused updates and update revisions"; Flag = "CleanupObsoleteUpdates" },
            @{ Name = "Expired updates"; Flag = "DeclineExpiredUpdates" },
            @{ Name = "Obsolete computers"; Flag = "CleanupObsoleteComputers" },
            @{ Name = "Unused content files"; Flag = "CleanupUnneededContentFiles" },
            @{ Name = "Obsolete update revisions"; Flag = "CompressUpdates" },
            @{ Name = "Superseded updates"; Flag = "DeclineSupersededUpdates" }
        )

        $totalTasks = $cleanupTasks.Count
        $currentTask = 0

        foreach ($task in $cleanupTasks) {
            $currentTask++
            $percentComplete = [int](($currentTask / $totalTasks) * 100)

            Write-Progress-Custom -Activity "WSUS Server Cleanup" -Status "Processing: $($task.Name)" -PercentComplete $percentComplete
            Write-Log "Cleaning up: $($task.Name)..." -Level Info

            try {
                $params = @{
                    UpdateServer = $wsusServer
                    $task.Flag = $true
                }

                Invoke-WsusServerCleanup @params | Out-Null
                Write-Log "  Completed: $($task.Name)" -Level Success
            }
            catch {
                Write-Log "  Failed: $($task.Name) - $_" -Level Warning
            }
        }

        Write-Progress-Custom -Activity "WSUS Server Cleanup" -Completed
        Write-Log "WSUS server cleanup completed" -Level Success
    }
    catch {
        Write-Progress-Custom -Activity "WSUS Server Cleanup" -Completed
        Write-Log "WSUS server cleanup failed: $_" -Level Error
        throw
    }
}

function Invoke-DeepClean {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [hashtable]$Config
    )

    if (-not $Config.DeepClean.Enabled) {
        Write-Log "Deep clean is disabled in configuration" -Level Warning
        return
    }

    if (-not $PSCmdlet.ShouldProcess("WSUS Updates", "Deep clean obsolete updates")) {
        return
    }

    try {
        Write-Log "Starting WSUS deep clean..." -Level Info

        $wsusServer = Get-WsusServerInstance
        $totalDeclined = 0

        # Decline updates by product title
        if ($Config.DeepClean.UnneededProductTitles.Count -gt 0) {
            Write-Log "Removing updates for obsolete products..." -Level Info
            $totalDeclined += Remove-UpdatesByProduct -WsusServer $wsusServer -ProductTitles $Config.DeepClean.UnneededProductTitles
        }

        # Decline updates by title
        if ($Config.DeepClean.UnneededUpdateTitles.Count -gt 0) {
            Write-Log "Removing updates with obsolete titles..." -Level Info
            $totalDeclined += Remove-UpdatesByTitle -WsusServer $wsusServer -UpdateTitles $Config.DeepClean.UnneededUpdateTitles
        }

        # Remove drivers
        if ($Config.DeepClean.RemoveDrivers) {
            Write-Log "Removing driver updates..." -Level Info
            $totalDeclined += Remove-DriverUpdates -WsusServer $wsusServer
        }

        # Decline superseded updates
        if ($Config.DeepClean.DeclineSuperseded) {
            Write-Log "Declining superseded updates..." -Level Info
            $totalDeclined += Invoke-DeclineSupersededUpdates -WsusServer $wsusServer
        }

        Write-Log "Deep clean completed. Total updates declined: $totalDeclined" -Level Success
    }
    catch {
        Write-Log "Deep clean failed: $_" -Level Error
        throw
    }
}

function Remove-UpdatesByProduct {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $WsusServer,

        [Parameter(Mandatory = $true)]
        [string[]]$ProductTitles
    )

    $declinedCount = 0
    $totalProducts = $ProductTitles.Count
    $currentProduct = 0

    foreach ($productTitle in $ProductTitles) {
        $currentProduct++
        $percentComplete = [int](($currentProduct / $totalProducts) * 100)

        Write-Progress-Custom -Activity "Removing Product Updates" -Status "Processing: $productTitle" -PercentComplete $percentComplete

        try {
            $scope = New-Object Microsoft.UpdateServices.Administration.UpdateScope
            # Avoid ApprovedStates.Any when enumerating (MS Learn performance guidance);
            # cover every non-declined state - declined updates are skipped below anyway.
            $scope.ApprovedStates = [Microsoft.UpdateServices.Administration.ApprovedStates]::LatestRevisionApproved -bor [Microsoft.UpdateServices.Administration.ApprovedStates]::NotApproved -bor [Microsoft.UpdateServices.Administration.ApprovedStates]::HasStaleUpdateApprovals

            # Query in per-year arrival-date batches so GetUpdates never loads the
            # entire catalog into memory at once (OOM protection on large servers).
            $productUpdateCount = 0
            for ($year = 1998; $year -le (Get-Date).Year; $year++) {
                $scope.FromArrivalDate = Get-Date -Year $year -Month 1 -Day 1
                $scope.ToArrivalDate = Get-Date -Year ($year + 1) -Month 1 -Day 1

                $updates = $WsusServer.GetUpdates($scope) | Where-Object {
                    $_.ProductTitles -contains $productTitle
                }

                foreach ($update in $updates) {
                    if (-not $update.IsDeclined) {
                        $update.Decline()
                        $declinedCount++
                    }
                }

                $productUpdateCount += $updates.Count
            }

            Write-Log "  Declined $productUpdateCount updates for: $productTitle" -Level Info
        }
        catch {
            Write-Log "  Error processing $productTitle : $_" -Level Warning
        }
    }

    Write-Progress-Custom -Activity "Removing Product Updates" -Completed
    return $declinedCount
}

function Remove-UpdatesByTitle {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $WsusServer,

        [Parameter(Mandatory = $true)]
        [string[]]$UpdateTitles
    )

    $declinedCount = 0

    Write-Progress-Custom -Activity "Removing Updates by Title" -Status "Searching updates..."

    try {
        $scope = New-Object Microsoft.UpdateServices.Administration.UpdateScope
        # Avoid ApprovedStates.Any when enumerating (MS Learn performance guidance);
        # cover every non-declined state - declined updates are skipped below anyway.
        $scope.ApprovedStates = [Microsoft.UpdateServices.Administration.ApprovedStates]::LatestRevisionApproved -bor [Microsoft.UpdateServices.Administration.ApprovedStates]::NotApproved -bor [Microsoft.UpdateServices.Administration.ApprovedStates]::HasStaleUpdateApprovals

        # Query in per-year arrival-date batches so GetUpdates never loads the
        # entire catalog into memory at once (OOM protection on large servers).
        $totalUpdates = 0
        $currentUpdate = 0

        for ($year = 1998; $year -le (Get-Date).Year; $year++) {
            $scope.FromArrivalDate = Get-Date -Year $year -Month 1 -Day 1
            $scope.ToArrivalDate = Get-Date -Year ($year + 1) -Month 1 -Day 1

            $updates = $WsusServer.GetUpdates($scope)
            $totalUpdates += $updates.Count

            foreach ($update in $updates) {
                $currentUpdate++

                if ($currentUpdate % 100 -eq 0) {
                    $percentComplete = [int](($currentUpdate / $totalUpdates) * 100)
                    Write-Progress-Custom -Activity "Removing Updates by Title" -Status "Checking update $currentUpdate of $totalUpdates" -PercentComplete $percentComplete
                }

                foreach ($titlePattern in $UpdateTitles) {
                    if ($update.Title -like "*$titlePattern*" -and -not $update.IsDeclined) {
                        $update.Decline()
                        $declinedCount++
                        Write-Log "  Declined: $($update.Title)" -Level Info -NoConsole
                        break
                    }
                }
            }
        }
    }
    catch {
        Write-Log "Error removing updates by title: $_" -Level Error
    }
    finally {
        Write-Progress-Custom -Activity "Removing Updates by Title" -Completed
    }

    return $declinedCount
}

function Remove-DriverUpdates {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $WsusServer
    )

    $declinedCount = 0

    try {
        Write-Progress-Custom -Activity "Removing Driver Updates" -Status "Searching for drivers..."

        $scope = New-Object Microsoft.UpdateServices.Administration.UpdateScope
        # Avoid ApprovedStates.Any when enumerating (MS Learn performance guidance);
        # cover every non-declined state - declined updates are skipped below anyway.
        $scope.ApprovedStates = [Microsoft.UpdateServices.Administration.ApprovedStates]::LatestRevisionApproved -bor [Microsoft.UpdateServices.Administration.ApprovedStates]::NotApproved -bor [Microsoft.UpdateServices.Administration.ApprovedStates]::HasStaleUpdateApprovals
        $scope.Classifications = $WsusServer.GetUpdateClassifications() | Where-Object { $_.Title -eq "Drivers" }

        # Query in per-year arrival-date batches so GetUpdates never loads the
        # entire catalog into memory at once (OOM protection on large servers).
        $totalUpdates = 0
        $currentUpdate = 0

        for ($year = 1998; $year -le (Get-Date).Year; $year++) {
            $scope.FromArrivalDate = Get-Date -Year $year -Month 1 -Day 1
            $scope.ToArrivalDate = Get-Date -Year ($year + 1) -Month 1 -Day 1

            $updates = $WsusServer.GetUpdates($scope)
            $totalUpdates += $updates.Count

            foreach ($update in $updates) {
                $currentUpdate++

                if ($currentUpdate % 50 -eq 0) {
                    $percentComplete = [int](($currentUpdate / $totalUpdates) * 100)
                    Write-Progress-Custom -Activity "Removing Driver Updates" -Status "Processing driver $currentUpdate of $totalUpdates" -PercentComplete $percentComplete
                }

                if (-not $update.IsDeclined) {
                    $update.Decline()
                    $declinedCount++
                }
            }
        }

        Write-Progress-Custom -Activity "Removing Driver Updates" -Completed
        Write-Log "Found $totalUpdates driver updates" -Level Info
        Write-Log "Declined $declinedCount driver updates" -Level Info
    }
    catch {
        Write-Progress-Custom -Activity "Removing Driver Updates" -Completed
        Write-Log "Error removing driver updates: $_" -Level Error
    }

    return $declinedCount
}

function Invoke-DeclineSupersededUpdates {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $WsusServer
    )

    $declinedCount = 0

    try {
        Write-Progress-Custom -Activity "Declining Superseded Updates" -Status "Searching for superseded updates..."

        $scope = New-Object Microsoft.UpdateServices.Administration.UpdateScope
        $scope.ApprovedStates = "LatestRevisionApproved"

        $updates = $WsusServer.GetUpdates($scope)

        $totalUpdates = $updates.Count
        $currentUpdate = 0

        foreach ($update in $updates) {
            $currentUpdate++

            if ($currentUpdate % 100 -eq 0) {
                $percentComplete = [int](($currentUpdate / $totalUpdates) * 100)
                Write-Progress-Custom -Activity "Declining Superseded Updates" -Status "Checking update $currentUpdate of $totalUpdates" -PercentComplete $percentComplete
            }

            $supersedingUpdates = $update.GetRelatedUpdates("UpdatesThatSupersedeThisUpdate")

            if ($supersedingUpdates.Count -gt 0) {
                $hasApprovedSuperseding = $false

                foreach ($superseding in $supersedingUpdates) {
                    if ($superseding.IsApproved) {
                        $hasApprovedSuperseding = $true
                        break
                    }
                }

                if ($hasApprovedSuperseding) {
                    $update.Decline()
                    $declinedCount++
                }
            }
        }

        Write-Progress-Custom -Activity "Declining Superseded Updates" -Completed
        Write-Log "Declined $declinedCount superseded updates" -Level Info
    }
    catch {
        Write-Progress-Custom -Activity "Declining Superseded Updates" -Completed
        Write-Log "Error declining superseded updates: $_" -Level Error
    }

    return $declinedCount
}

function Disable-WsusDriverSync {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()

    if (-not $PSCmdlet.ShouldProcess("WSUS Driver Synchronization", "Disable")) {
        return
    }

    try {
        Write-Log "Disabling WSUS driver synchronization..." -Level Info

        Get-WsusClassification | Where-Object { $_.Classification.Title -in @("Drivers", "Driver Sets") } | ForEach-Object {
            Set-WsusClassification -Classification $_ -Disable
            Write-Log "  Disabled: $($_.Classification.Title)" -Level Info
        }

        Write-Log "Driver synchronization disabled successfully" -Level Success
    }
    catch {
        Write-Log "Failed to disable driver synchronization: $_" -Level Error
        throw
    }
}

#endregion

#region Scheduled Task Functions

function New-WsusScheduledTasks {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Config
    )

    $scriptPath = $PSCommandPath

    if ([string]::IsNullOrWhiteSpace($scriptPath)) {
        Write-Log "Cannot determine script path. Tasks will not be created." -Level Error
        return
    }

    # Create daily task
    if ($Config.ScheduledTasks.Daily.Enabled) {
        if ($PSCmdlet.ShouldProcess("Daily WSUS Optimization Task", "Create")) {
            New-WsusDailyTask -ScriptPath $scriptPath -Config $Config
        }
    }

    # Create weekly task
    if ($Config.ScheduledTasks.Weekly.Enabled) {
        if ($PSCmdlet.ShouldProcess("Weekly WSUS Optimization Task", "Create")) {
            New-WsusWeeklyTask -ScriptPath $scriptPath -Config $Config
        }
    }

    # Create monthly task
    if ($Config.ScheduledTasks.Monthly.Enabled) {
        if ($PSCmdlet.ShouldProcess("Monthly WSUS Deep Clean Task", "Create")) {
            New-WsusMonthlyTask -ScriptPath $scriptPath -Config $Config
        }
    }
}

function New-WsusDailyTask {
    [CmdletBinding()]
    param(
        [string]$ScriptPath,
        [hashtable]$Config
    )

    try {
        $taskName = "WSUS-DailyOptimization"
        $time = $Config.ScheduledTasks.Daily.Time

        # Validate paths to prevent command injection
        $validatedScriptPath = Test-SafePath -Path $ScriptPath -MustExist
        $validatedConfigPath = Test-SafePath -Path $script:ConfigFile

        # Build argument string with validated paths
        $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$validatedScriptPath`" -OptimizeServer -DeclineSupersededUpdates -ConfigFile `"$validatedConfigPath`""

        $action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument $arguments
        $trigger = New-ScheduledTaskTrigger -Daily -At $time
        $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

        # Remove existing task if it exists
        $existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        if ($existingTask) {
            Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
        }

        Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description "Daily WSUS server optimization and superseded update cleanup" | Out-Null

        Write-Log "Daily task created: $taskName at $time" -Level Success
    }
    catch {
        Write-Log "Failed to create daily task: $_" -Level Error
    }
}

function New-WsusWeeklyTask {
    [CmdletBinding()]
    param(
        [string]$ScriptPath,
        [hashtable]$Config
    )

    try {
        $taskName = "WSUS-WeeklyOptimization"
        $time = $Config.ScheduledTasks.Weekly.Time
        $dayOfWeek = $Config.ScheduledTasks.Weekly.DayOfWeek

        # Validate paths to prevent command injection
        $validatedScriptPath = Test-SafePath -Path $ScriptPath -MustExist
        $validatedConfigPath = Test-SafePath -Path $script:ConfigFile

        $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$validatedScriptPath`" -OptimizeDatabase -CheckConfig -ConfigFile `"$validatedConfigPath`""

        $action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument $arguments
        $trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek $dayOfWeek -At $time
        $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

        $existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        if ($existingTask) {
            Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
        }

        Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description "Weekly WSUS database optimization and IIS configuration check" | Out-Null

        Write-Log "Weekly task created: $taskName on $dayOfWeek at $time" -Level Success
    }
    catch {
        Write-Log "Failed to create weekly task: $_" -Level Error
    }
}

function New-WsusMonthlyTask {
    [CmdletBinding()]
    param(
        [string]$ScriptPath,
        [hashtable]$Config
    )

    try {
        $taskName = "WSUS-MonthlyDeepClean"
        $time = $Config.ScheduledTasks.Monthly.Time
        $day = $Config.ScheduledTasks.Monthly.Day

        # Validate paths to prevent command injection
        $validatedScriptPath = Test-SafePath -Path $ScriptPath -MustExist
        $validatedConfigPath = Test-SafePath -Path $script:ConfigFile

        $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$validatedScriptPath`" -DeepClean -ConfigFile `"$validatedConfigPath`""

        $action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument $arguments

        # Use CIM to set monthly schedule properly
        $class = Get-CimClass -ClassName MSFT_TaskMonthlyTrigger -Namespace Root/Microsoft/Windows/TaskScheduler
        $trigger = New-CimInstance -CimClass $class -ClientOnly
        $trigger.DaysOfMonth = $day
        $trigger.MonthsOfYear = 4095  # All months (binary: 111111111111)
        $trigger.StartBoundary = (Get-Date).Date.ToString("yyyy-MM-dd") + "T$time`:00"
        $trigger.Enabled = $true

        $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

        $existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        if ($existingTask) {
            Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
        }

        $task = New-ScheduledTask -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description "Monthly WSUS deep clean of obsolete updates"
        Register-ScheduledTask -TaskName $taskName -InputObject $task | Out-Null

        Write-Log "Monthly task created: $taskName on day $day at $time" -Level Success
    }
    catch {
        Write-Log "Failed to create monthly task: $_" -Level Error
    }
}

#endregion

#region Main Execution

# Initialize logging
$script:LogPath = $LogPath

Write-Log "========================================" -Level Info
Write-Log "WSUS Optimization Script v2.0.0" -Level Info
Write-Log "========================================" -Level Info

# Load configuration
$config = Get-WsusConfig -Path $ConfigFile

# Process command line switches
if ($Interactive) {
    Start-InteractiveWizard
}
elseif ($CreateTasks) {
    New-WsusScheduledTasks -Config $config
}
else {
    # Run requested operations
    $operationsRun = $false

    if ($DisableDrivers) {
        Disable-WsusDriverSync
        $operationsRun = $true
    }

    if ($CheckConfig) {
        Test-WsusIISConfig -Config $config
        $operationsRun = $true
    }

    if ($OptimizeDatabase) {
        if ($config.Features.CreateCustomIndexes) {
            Initialize-WsusDatabase
        }
        Optimize-WsusDatabase -Config $config
        $operationsRun = $true
    }

    if ($OptimizeServer) {
        Optimize-WsusUpdates -Config $config
        $operationsRun = $true
    }

    if ($DeclineSupersededUpdates) {
        $wsusServer = Get-WsusServerInstance
        Invoke-DeclineSupersededUpdates -WsusServer $wsusServer
        $operationsRun = $true
    }

    if ($DeepClean) {
        Invoke-DeepClean -Config $config
        $operationsRun = $true
    }

    if (-not $operationsRun) {
        Write-Host "`nNo operations specified. Use -Interactive for guided setup or see Get-Help for available options.`n" -ForegroundColor Yellow
        Get-Help $PSCommandPath -Detailed
    }
}

Write-Log "========================================" -Level Info
Write-Log "Script execution completed" -Level Info
Write-Log "========================================" -Level Info

#endregion
