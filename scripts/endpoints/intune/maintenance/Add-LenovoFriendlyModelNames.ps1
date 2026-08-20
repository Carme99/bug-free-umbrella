<#
.SYNOPSIS
    Adds Lenovo friendly model names to Intune device Notes and Entra ID device extension attributes.

.DESCRIPTION
    This script automates the process of enriching Lenovo device records with human-readable model names:

    1) Retrieves all Lenovo managed devices from Intune (managedDevice objects)
    2) Extracts the Lenovo MTM (Machine Type Model) code (first 4 characters of Model string)
    3) Maps MTM codes to friendly family names using Lenovo's official allModels.json dataset
    4) Updates device records in two locations:
       - Intune managedDevice Notes field (append only, avoids duplicates)
       - Entra ID device extensionAttributes (set/overwrite)

    Key Features:
    - AuditOnly mode to validate mapping coverage without making changes
    - FailIfMissingMappings to enforce complete mapping coverage
    - SupportsShouldProcess for safe testing with -WhatIf and -Confirm
    - Robust authentication with automatic device code fallback
    - Progress indicators for large device collections
    - Comprehensive error logging with CSV export
    - Rate limiting protection to avoid Graph API throttling
    - Retry logic for network resilience

    Authentication Strategy:
    - Attempts interactive sign-in first (best for console/Windows Terminal)
    - Falls back to device code authentication if window handle issues occur
    - Supports both authentication methods via Connect-MgGraph

    Update Strategy:
    - Intune Notes: Appends friendly name if not already present
    - Entra extensionAttributes: Sets/overwrites attribute value
    - Entra addressing: Tries object ID first, falls back to deviceId if 404

.PARAMETER AuditOnly
    Run in audit mode - validates mappings and shows what would be updated without making changes

.PARAMETER FailIfMissingMappings
    Stop execution if any tenant MTM codes cannot be resolved from Lenovo dataset

.PARAMETER UpdateNotes
    Enable updates to Intune managedDevice Notes field (enabled by default)

.PARAMETER UpdateExtensionAttributes
    Enable updates to Entra device extension attributes (enabled by default)

.PARAMETER ExtensionAttributeName
    Which Entra device extension attribute to use for friendly model name
    Valid values: extensionAttribute1 through extensionAttribute15
    Default: extensionAttribute1

.PARAMETER NotesPrefix
    Optional prefix for Notes field entries
    If provided, format is "Prefix: FriendlyName"
    If empty, format is "FriendlyName"

.PARAMETER NotesSeparator
    Separator used when appending to existing Notes
    Default: newline character

.PARAMETER VerboseOutput
    Enable detailed per-device logging

.EXAMPLE
    .\Add-LenovoFriendlyModelNames.ps1 -AuditOnly

    Validates MTM mapping coverage without making any changes.
    Shows which devices would be updated and identifies unmapped MTM codes.

.EXAMPLE
    .\Add-LenovoFriendlyModelNames.ps1 -WhatIf

    Preview all changes that would be made without actually updating devices.
    Uses PowerShell's built-in ShouldProcess support.

.EXAMPLE
    .\Add-LenovoFriendlyModelNames.ps1 -AuditOnly -FailIfMissingMappings

    Audit mode with strict validation - fails if any MTM codes are unmapped.
    Useful for ensuring complete coverage before running updates.

.EXAMPLE
    .\Add-LenovoFriendlyModelNames.ps1 -ExtensionAttributeName "extensionAttribute2" -NotesPrefix "Model"

    Updates using extensionAttribute2 instead of default extensionAttribute1.
    Adds "Model: <FriendlyName>" to Notes instead of just friendly name.

.EXAMPLE
    .\Add-LenovoFriendlyModelNames.ps1 -UpdateNotes:$false -VerboseOutput

    Only updates Entra extension attributes, skips Notes updates.
    Enables detailed per-device logging.

.NOTES
    Author: System Administrator
    Version: 2.0
    Last Modified: 2026-01-16

    Requirements:
    - Microsoft Graph PowerShell SDK
    - PowerShell 5.1 or later
    - Run from PowerShell console or Windows Terminal for best interactive auth

    Required Graph API Permissions:
    - DeviceManagementManagedDevices.ReadWrite.All (for Intune managedDevice updates)
    - Device.ReadWrite.All (for Entra device updates)

    API Endpoints Used:
    - GET  /deviceManagement/managedDevices (retrieve Lenovo devices)
    - PATCH /deviceManagement/managedDevices/{id} (update Notes)
    - PATCH /v1.0/devices/{id} (update extensionAttributes)
    - PATCH /v1.0/devices(deviceId='{deviceId}') (fallback addressing)

    External Resources:
    - Lenovo Model Dataset: https://download.lenovo.com/bsco/public/allModels.json

    Reference Documentation:
    - Lenovo MTM System: https://www.linkedin.com/pulse/use-lenovo-friendly-model-names-sccm-queries-instead-machine-philip
    - Intune Notes API: https://community.spiceworks.com/t/intune-enrolled-device-notes/953047
    - Lenovo Commercial Systems: https://docs.lenovocdrt.com/guides/lcsm/lcsm_top/
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "Medium")]
param(
    [Parameter(Mandatory = $false)]
    [switch]$AuditOnly,

    [Parameter(Mandatory = $false)]
    [switch]$FailIfMissingMappings,

    [Parameter(Mandatory = $false)]
    [switch]$UpdateNotes,

    [Parameter(Mandatory = $false)]
    [switch]$UpdateExtensionAttributes,

    [Parameter(Mandatory = $false)]
    [ValidateSet(
        "extensionAttribute1", "extensionAttribute2", "extensionAttribute3", "extensionAttribute4", "extensionAttribute5",
        "extensionAttribute6", "extensionAttribute7", "extensionAttribute8", "extensionAttribute9", "extensionAttribute10",
        "extensionAttribute11", "extensionAttribute12", "extensionAttribute13", "extensionAttribute14", "extensionAttribute15"
    )]
    [string]$ExtensionAttributeName = "extensionAttribute1",

    [Parameter(Mandatory = $false)]
    [string]$NotesPrefix = "",

    [Parameter(Mandatory = $false)]
    [string]$NotesSeparator = "`n",

    [Parameter(Mandatory = $false)]
    [switch]$VerboseOutput
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

#region Logging

function Write-Log {
    <#
    .SYNOPSIS
        Writes formatted log messages to console
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [ValidateSet("Info", "Warn", "Error", "Verbose")]
        [string]$Level = "Info"
    )

    switch ($Level) {
        "Info" { Write-Host $Message -ForegroundColor Cyan }
        "Warn" { Write-Host $Message -ForegroundColor Yellow }
        "Error" { Write-Host $Message -ForegroundColor Red }
        "Verbose" { if ($VerboseOutput) { Write-Host $Message -ForegroundColor DarkGray } }
    }
}

#endregion Logging

#region Authentication

function Connect-GraphRobust {
    <#
    .SYNOPSIS
        Connect to Microsoft Graph with robust error handling

    .DESCRIPTION
        Attempts interactive sign-in first. If interactive authentication fails due to
        window handle issues (common in certain PowerShell environments), automatically
        falls back to device code authentication.
    #>
    param(
        [Parameter(Mandatory)]
        [string[]]$Scopes
    )

    try {
        Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
    }
    catch {
        Write-Verbose "Handled exception: $($_.Exception.Message)" -Verbose:$false
    }

    try {
        Connect-MgGraph -Scopes $Scopes -NoWelcome -ErrorAction Stop | Out-Null
        Write-Log "Connected to Microsoft Graph using interactive authentication" "Info"
        return
    }
    catch {
        if ($_.Exception.Message -match "window handle must be configured") {
            Write-Log "Interactive auth failed (window handle issue). Falling back to device code authentication." "Warn"
            try {
                Connect-MgGraph -Scopes $Scopes -UseDeviceCode -NoWelcome -ErrorAction Stop | Out-Null
                Write-Log "Connected to Microsoft Graph using device code authentication" "Info"
                return
            }
            catch {
                Write-Log "Device code authentication failed: $($_.Exception.Message)" "Error"
                throw
            }
        }

        Write-Log "Authentication failed: $($_.Exception.Message)" "Error"
        throw
    }
}

#endregion Authentication

#region Lenovo Helpers

function Get-MtmTypeFromModel {
    <#
    .SYNOPSIS
        Extracts and validates the 4-character MTM code from a Lenovo model string

    .DESCRIPTION
        Lenovo uses 4-character Machine Type Model (MTM) codes to identify product lines.
        This function extracts the first 4 characters and validates the format.
    #>
    param(
        [AllowNull()]
        [string]$Model
    )

    if ([string]::IsNullOrWhiteSpace($Model)) {
        return $null
    }

    if ($Model.Length -lt 4) {
        return $null
    }

    $mtm = $Model.Substring(0, 4).Trim().ToUpperInvariant()

    # Validate MTM format - should be 4 alphanumeric characters
    if ($mtm -notmatch '^[A-Z0-9]{4}$') {
        Write-Log "Invalid MTM format for model '$Model': '$mtm'" "Verbose"
        return $null
    }

    return $mtm
}

function Get-LenovoModelLookup {
    <#
    .SYNOPSIS
        Creates a mapping of MTM codes to friendly family names

    .DESCRIPTION
        Downloads Lenovo's official allModels.json dataset and builds a lookup table
        mapping MTM codes to human-readable model family names. Includes retry logic
        for network resilience.
    #>
    param(
        [Parameter(Mandatory)]
        [string[]]$TenantMtms
    )

    $allModelsUrl = "https://download.lenovo.com/bsco/public/allModels.json"
    Write-Log "Downloading Lenovo model dataset from $allModelsUrl" "Verbose"

    # Download with retry logic for network resilience
    $allModels = $null
    $maxRetries = 3
    $retryDelay = 2

    for ($attempt = 1; $attempt -le $maxRetries; $attempt++) {
        try {
            $allModels = Invoke-RestMethod -Uri $allModelsUrl -Method Get -TimeoutSec 30 -ErrorAction Stop
            Write-Log "Successfully downloaded Lenovo model dataset (attempt $attempt/$maxRetries)" "Verbose"
            break
        }
        catch {
            if ($attempt -eq $maxRetries) {
                Write-Log "Failed to download Lenovo dataset after $maxRetries attempts: $($_.Exception.Message)" "Error"
                throw
            }

            $waitSeconds = $retryDelay * $attempt
            Write-Log "Download attempt $attempt failed. Retrying in $waitSeconds seconds..." "Warn"
            Start-Sleep -Seconds $waitSeconds
        }
    }

    if (-not $allModels -or $allModels.Count -eq 0) {
        throw "Downloaded Lenovo dataset is empty or invalid"
    }

    Write-Log "Processing $($allModels.Count) model entries from Lenovo dataset" "Verbose"

    $mtmToFamily = @{}
    $missingMtms = New-Object System.Collections.Generic.List[string]

    foreach ($mtm in $TenantMtms) {
        # Improved matching logic - look for MTM in Type codes or product identifiers
        # Example: "ThinkPad T14 Gen 3 (Type 21AH, 21AJ)" - MTM is 21AH or 21AJ
        $match = $allModels |
            Where-Object {
                $_.name -and
                (
                    # Match in parenthetical type codes: "(Type 21AH, 21AJ)"
                    ($_.name -match "\(Type\s+$mtm\b") -or
                    # Match as standalone product code
                    ($_.name -match "\b$mtm\b")
                ) -and
                # Exclude firmware/BIOS entries
                ($_.name -notlike "*-UEFI Lenovo*") -and
                ($_.name -notlike "*dTPM*") -and
                ($_.name -notlike "*fTPM*") -and
                ($_.name -notlike "*Asset*") -and
                ($_.name -notlike "*BIOS*")
            } |
            Select-Object -First 1

        if ($null -eq $match) {
            $missingMtms.Add($mtm) | Out-Null
            Write-Log "No mapping found for MTM: $mtm" "Verbose"
            continue
        }

        # Extract friendly family name (text before first parenthesis)
        # Example: "ThinkPad T14 Gen 3 (Type 21AH, 21AJ)" -> "ThinkPad T14 Gen 3"
        $family = ($match.name -split " \(")[0].Trim()

        if ([string]::IsNullOrWhiteSpace($family)) {
            $missingMtms.Add($mtm) | Out-Null
            Write-Log "Empty family name for MTM: $mtm (source: $($match.name))" "Verbose"
            continue
        }

        if (-not $mtmToFamily.ContainsKey($mtm)) {
            $mtmToFamily[$mtm] = $family
            Write-Log "Mapped MTM $mtm -> $family" "Verbose"
        }
    }

    [PSCustomObject]@{
        Lookup = $mtmToFamily
        Missing = $missingMtms.ToArray()
        SourceUrl = $allModelsUrl
        TotalProcessed = $allModels.Count
    }
}

#endregion Lenovo Helpers

#region Notes Helpers

function Get-NormalisedNoteLines {
    <#
    .SYNOPSIS
        Splits Notes field into trimmed, non-empty lines
    #>
    param(
        [AllowNull()]
        [string]$Notes
    )

    if ([string]::IsNullOrWhiteSpace($Notes)) {
        return @()
    }

    return $Notes -split "`r?`n" |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ }
}

function Build-NotesLine {
    <#
    .SYNOPSIS
        Builds the line to add to Notes field

    .DESCRIPTION
        If NotesPrefix is supplied: "Prefix: FriendlyName"
        If NotesPrefix is empty: "FriendlyName"
    #>
    param(
        [Parameter(Mandatory)]
        [string]$FamilyName
    )

    if ([string]::IsNullOrWhiteSpace($NotesPrefix)) {
        return $FamilyName
    }

    # Use $() to avoid PowerShell treating "${var}:" as scoped variable
    return "$($NotesPrefix): $FamilyName"
}

#endregion Notes Helpers

#region Entra Device Update Helper

function Set-EntraDeviceExtensionAttribute {
    <#
    .SYNOPSIS
        Sets an Entra device extension attribute value

    .DESCRIPTION
        Microsoft Graph supports two addressing methods for device updates:
        1. By object ID: PATCH /devices/{id}
        2. By device ID: PATCH /devices(deviceId='{deviceId}')

        This function tries method 1 first. If it returns 404 NotFound, it retries
        with method 2. This handles cases where the identifier is actually a deviceId
        rather than an object ID.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$AzureDeviceIdentifier,

        [Parameter(Mandatory)]
        [string]$AttributeName,

        [Parameter(Mandatory)]
        [string]$Value
    )

    $payloadObject = @{
        extensionAttributes = @{
            $AttributeName = $Value
        }
    }

    $payloadJson = $payloadObject | ConvertTo-Json -Depth 5 -Compress

    # Attempt 1: Treat identifier as Entra device object ID
    try {
        if ($PSCmdlet.ShouldProcess($AzureDeviceIdentifier, "Set extension attribute $AttributeName")) {
            Invoke-MgGraphRequest -Method PATCH -Uri "/v1.0/devices/$AzureDeviceIdentifier" -Body $payloadJson -ErrorAction Stop | Out-Null
            return "PatchedByObjectId"
        }
        return
    }
    catch {
        # Only retry on NotFound - other errors are real failures (permissions, payload issues, etc.)
        if ($_.Exception.Message -notmatch "NotFound|404") {
            throw
        }

        Write-Log "Object ID lookup failed for $AzureDeviceIdentifier, trying deviceId addressing" "Verbose"
    }

    # Attempt 2: Treat identifier as Entra deviceId
    try {
        if ($PSCmdlet.ShouldProcess($AzureDeviceIdentifier, "Set extension attribute $AttributeName")) {
            Invoke-MgGraphRequest -Method PATCH -Uri "/v1.0/devices(deviceId='$AzureDeviceIdentifier')" -Body $payloadJson -ErrorAction Stop | Out-Null
            return "PatchedByDeviceId"
        }
        return
    }
    catch {
        Write-Log "Failed to update device with identifier $AzureDeviceIdentifier using both addressing methods" "Error"
        throw
    }
}

#endregion Entra Device Update Helper

#region Main Script Logic

try {
    Write-Log "=== Lenovo Friendly Model Names Update Script ===" "Info"
    Write-Log "Version 2.0 - Enhanced with retry logic, progress tracking, and error logging" "Info"
    Write-Host ""

    # Set default values for switches (only if not explicitly set)
    if (-not $PSBoundParameters.ContainsKey('UpdateNotes')) {
        $UpdateNotes = $true
    }
    if (-not $PSBoundParameters.ContainsKey('UpdateExtensionAttributes')) {
        $UpdateExtensionAttributes = $true
    }

    # Validation: ensure at least one update target is enabled (unless auditing)
    if (-not $AuditOnly -and -not $UpdateNotes -and -not $UpdateExtensionAttributes) {
        throw "No update targets enabled. Set UpdateNotes and/or UpdateExtensionAttributes to `$true, or run with -AuditOnly"
    }

    # Display configuration
    Write-Log "Configuration:" "Info"
    Write-Log "  Audit Only: $AuditOnly" "Info"
    Write-Log "  Update Notes: $UpdateNotes" "Info"
    Write-Log "  Update Extension Attributes: $UpdateExtensionAttributes" "Info"
    if ($UpdateExtensionAttributes) {
        Write-Log "  Extension Attribute: $ExtensionAttributeName" "Info"
    }
    if ($UpdateNotes -and $NotesPrefix) {
        Write-Log "  Notes Prefix: $NotesPrefix" "Info"
    }
    Write-Host ""

    # Required Graph API scopes
    $scopes = @(
        "DeviceManagementManagedDevices.ReadWrite.All",  # For Intune managedDevice updates
        "Device.ReadWrite.All"                            # For Entra device updates
    )

    # Connect to Microsoft Graph with robust auth handling
    Connect-GraphRobust -Scopes $scopes

    # Retrieve all Lenovo devices from Intune
    Write-Log "Retrieving Lenovo managed devices from Intune..." "Info"

    $lenovoDevices = Get-MgDeviceManagementManagedDevice `
        -Filter "manufacturer eq 'LENOVO'" `
        -All `
        -Property "id,deviceName,manufacturer,model,notes,azureADDeviceId" `
        -ErrorAction Stop

    if (-not $lenovoDevices -or $lenovoDevices.Count -eq 0) {
        Write-Log "No Lenovo devices found in Intune. Exiting." "Warn"
        return
    }

    Write-Log "Found $($lenovoDevices.Count) Lenovo devices" "Info"

    # Extract unique MTM codes from tenant devices
    Write-Log "Extracting unique MTM codes from device models..." "Info"

    $tenantMtms = $lenovoDevices |
        ForEach-Object { Get-MtmTypeFromModel -Model $_.Model } |
        Where-Object { $_ } |
        Sort-Object -Unique

    if (-not $tenantMtms -or $tenantMtms.Count -eq 0) {
        Write-Log "No valid MTM codes could be extracted from device models. Exiting." "Warn"
        return
    }

    Write-Log "Identified $($tenantMtms.Count) unique MTM codes in tenant" "Info"
    Write-Host ""

    # Build MTM to family name mapping from Lenovo dataset
    Write-Log "Building MTM to friendly name mapping from Lenovo dataset..." "Info"

    $mappingResult = Get-LenovoModelLookup -TenantMtms $tenantMtms
    $mtmToFamily = $mappingResult.Lookup
    $missingMtms = $mappingResult.Missing

    Write-Log "Mapping Results:" "Info"
    Write-Log "  Successfully mapped: $($mtmToFamily.Count) MTM codes" "Info"
    Write-Log "  Unable to map: $($missingMtms.Count) MTM codes" "Info"
    Write-Log "  Lenovo dataset entries processed: $($mappingResult.TotalProcessed)" "Info"

    # Report missing MTM codes
    if ($missingMtms.Count -gt 0) {
        Write-Host ""
        Write-Log "WARNING: The following MTM codes could not be mapped:" "Warn"
        $missingMtms | ForEach-Object { Write-Log "  - $_" "Warn" }

        # Find example devices with unmapped MTMs
        $exampleDevices = $lenovoDevices |
            Where-Object { $missingMtms -contains (Get-MtmTypeFromModel -Model $_.Model) } |
            Select-Object -First 3

        if ($exampleDevices) {
            Write-Log "Example devices with unmapped MTMs:" "Warn"
            $exampleDevices | ForEach-Object {
                Write-Log "  - $($_.deviceName): $($_.model)" "Warn"
            }
        }

        if ($FailIfMissingMappings) {
            throw "FailIfMissingMappings specified and $($missingMtms.Count) MTM code(s) could not be resolved"
        }
    }

    Write-Host ""

    # Exit if audit only mode
    if ($AuditOnly) {
        Write-Log "=== Audit Only Mode - No Changes Made ===" "Info"
        Write-Log "To apply changes, run without -AuditOnly flag" "Info"
        return
    }

    # Initialize counters and error tracking
    $stats = @{
        NotesUpdated = 0
        NotesSkipped = 0
        ExtUpdated = 0
        ExtSkipped = 0
        Unknown = 0
        Errors = 0
    }

    $errorLog = New-Object System.Collections.Generic.List[object]

    # Process each device
    Write-Host ""
    Write-Log "Processing devices..." "Info"

    $deviceIndex = 0
    foreach ($device in $lenovoDevices) {
        $deviceIndex++

        # Update progress indicator
        $percentComplete = [math]::Round(($deviceIndex / $lenovoDevices.Count) * 100, 1)
        Write-Progress `
            -Activity "Updating Lenovo device records" `
            -Status "Processing device $deviceIndex of $($lenovoDevices.Count): $($device.deviceName)" `
            -PercentComplete $percentComplete

        # Extract and validate MTM code
        $mtm = Get-MtmTypeFromModel -Model $device.Model

        if (-not $mtm) {
            $stats.Unknown++
            Write-Log "Skipping $($device.deviceName): Could not extract valid MTM from model '$($device.model)'" "Verbose"
            continue
        }

        if (-not $mtmToFamily.ContainsKey($mtm)) {
            $stats.Unknown++
            Write-Log "Skipping $($device.deviceName): MTM code '$mtm' not in mapping" "Verbose"
            continue
        }

        $familyName = [string]$mtmToFamily[$mtm]

        # Determine if Notes update is needed
        $notesLine = Build-NotesLine -FamilyName $familyName
        $existingNoteLines = Get-NormalisedNoteLines -Notes ([string]$device.Notes)
        $needsNotesUpdate = $UpdateNotes -and -not ($existingNoteLines -contains $notesLine)

        $newNotes = $null
        if ($needsNotesUpdate) {
            $newNotes = if ($existingNoteLines.Count -eq 0) {
                $notesLine
            }
            else {
                ($existingNoteLines + $notesLine) -join $NotesSeparator
            }
        }

        # Determine if Entra extension attribute update is needed
        $azureDeviceIdentifier = [string]$device.azureADDeviceId
        $hasAzureId = -not [string]::IsNullOrWhiteSpace($azureDeviceIdentifier)
        $needsExtUpdate = $UpdateExtensionAttributes -and $hasAzureId

        # Skip device if no updates needed
        if (-not $needsNotesUpdate -and -not $needsExtUpdate) {
            if ($UpdateNotes) { $stats.NotesSkipped++ }
            if ($UpdateExtensionAttributes -and $hasAzureId) { $stats.ExtSkipped++ }
            Write-Log "Skipping $($device.deviceName): Already up to date" "Verbose"
            continue
        }

        try {
            # Update Intune Notes
            if ($needsNotesUpdate) {
                if ($PSCmdlet.ShouldProcess($device.deviceName, "Update Intune Notes with '$notesLine'")) {
                    Update-MgDeviceManagementManagedDevice -ManagedDeviceId $device.id -Notes $newNotes -ErrorAction Stop | Out-Null
                    $stats.NotesUpdated++
                    Write-Log "Updated Notes for $($device.deviceName): $familyName" "Verbose"
                }
            }
            elseif ($UpdateNotes) {
                $stats.NotesSkipped++
            }

            # Update Entra extension attribute
            if ($needsExtUpdate) {
                if ($PSCmdlet.ShouldProcess($device.deviceName, "Set Entra $ExtensionAttributeName to '$familyName'")) {
                    $methodUsed = Set-EntraDeviceExtensionAttribute `
                        -AzureDeviceIdentifier $azureDeviceIdentifier `
                        -AttributeName $ExtensionAttributeName `
                        -Value $familyName `
                        -ErrorAction Stop

                    $stats.ExtUpdated++
                    Write-Log "Updated $ExtensionAttributeName for $($device.deviceName) using ${methodUsed}: $familyName" "Verbose"
                }
            }
            elseif ($UpdateExtensionAttributes) {
                $stats.ExtSkipped++
                if (-not $hasAzureId) {
                    Write-Log "Skipping Entra update for $($device.deviceName): No azureADDeviceId" "Verbose"
                }
            }

            # Rate limiting - brief pause to avoid Graph API throttling
            Start-Sleep -Milliseconds 100
        }
        catch {
            $stats.Errors++

            $errorDetails = [PSCustomObject]@{
                DeviceName = $device.deviceName
                Model = $device.model
                MTM = $mtm
                IntuneId = $device.id
                AzureADDeviceId = $azureDeviceIdentifier
                Error = $_.Exception.Message
                Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            }

            $errorLog.Add($errorDetails)

            Write-Log "ERROR updating $($device.deviceName): $($_.Exception.Message)" "Warn"
        }
    }

    Write-Progress -Activity "Updating Lenovo device records" -Completed

    # Display summary
    Write-Host ""
    Write-Host ""
    Write-Log "=== Update Summary ===" "Info"
    Write-Host "Intune Notes:"
    Write-Host "  Updated: $($stats.NotesUpdated)"
    Write-Host "  Skipped (already present): $($stats.NotesSkipped)"
    Write-Host ""
    Write-Host "Entra Extension Attributes:"
    Write-Host "  Updated: $($stats.ExtUpdated)"
    Write-Host "  Skipped: $($stats.ExtSkipped)"
    Write-Host ""
    Write-Host "Other:"
    Write-Host "  Unknown/Unmapped: $($stats.Unknown)"
    Write-Host "  Errors: $($stats.Errors)"

    # Export error log if errors occurred
    if ($errorLog.Count -gt 0) {
        $errorLogPath = Join-Path $PWD "LenovoUpdateErrors_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
        $errorLog | Export-Csv -Path $errorLogPath -NoTypeInformation -Encoding UTF8
        Write-Host ""
        Write-Log "Error log exported to: $errorLogPath" "Warn"
    }

    Write-Host ""
    Write-Log "Script completed successfully" "Info"
}
catch {
    Write-Log "Script failed with error: $($_.Exception.Message)" "Error"
    Write-Log "Stack trace: $($_.ScriptStackTrace)" "Error"
    throw
}
finally {
    # Clean up Graph connection
    try {
        Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
    }
    catch {
        Write-Verbose "Handled exception: $($_.Exception.Message)" -Verbose:$false
    }
}

#endregion Main Script Logic
