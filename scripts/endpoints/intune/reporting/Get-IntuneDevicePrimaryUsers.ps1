<#
.SYNOPSIS
    Resolve Intune Primary Users and friendly hardware specs for one or more devices.

.DESCRIPTION
    - Accepts device names (comma/newline separated) or an input file (.txt/.csv)
    - Looks up each device in Intune (managedDevices)
    - Retrieves true Primary User via managedDevice /users relation (Graph beta)
    - Adds LastSeen from managedDevice.lastSyncDateTime
    - Pulls hardware fields (RAM, storage, model, manufacturer, serial) via a per device GET call
    - Pulls Friendly Model Name from Entra device extensionAttributes (default extensionAttribute1)
    - Exports results to CSV (default Desktop\PrimaryUsers.csv)

    The report is read-only: it never mutates tenant configuration, so re-running it is safe
    (idempotent).
    Exit codes:
    - 0: processing completed (including no usable device names or devices not found).
    - 1: missing prerequisite module or a terminating error during processing.

.PARAMETER DeviceName
    One or more device names (comma or newline separated) to query

.PARAMETER InputFile
    Path to a .txt or .csv file containing device names

.PARAMETER OutputPath
    Path where the CSV report will be saved (default: Desktop\PrimaryUsers.csv)

.PARAMETER FriendlyModelAttribute
    Which Entra device extension attribute contains your friendly model name
    extensionAttribute1 to extensionAttribute15 (default: extensionAttribute1)

.PARAMETER NoExport
    Skip CSV export and only display results in console

.PARAMETER Quiet
    Suppress INFO and DEBUG messages

.EXAMPLE
    PS C:\> .\Get-IntuneDevicePrimaryUsers.ps1 -DeviceName "LTW1010013,LTW1010334"
    Resolves primary users and hardware specs for two devices and saves Desktop\PrimaryUsers.csv.

.EXAMPLE
    PS C:\> .\Get-IntuneDevicePrimaryUsers.ps1 -InputFile "C:\Temp\devices.txt" `
        -OutputPath "C:\Reports\PrimaryUsers.csv"
    Resolves every device listed in the input file and writes the CSV to C:\Reports.

.EXAMPLE
    PS C:\> .\Get-IntuneDevicePrimaryUsers.ps1 -DeviceName "LTW1010013" `
        -FriendlyModelAttribute "extensionAttribute2" -NoExport
    Resolves one device reading the friendly model from extensionAttribute2, console output only.

.NOTES
    File Name   : Get-IntuneDevicePrimaryUsers.ps1
    Author      : System Administrator
    Prerequisite: PowerShell 7.0
    Version     : 1.0.0
    Date        : 2026-08-23

    Requires the Microsoft Graph PowerShell SDK
    Required Graph Permissions:
        - DeviceManagementManagedDevices.Read.All
        - Directory.Read.All
        - User.Read.All
        - Device.Read.All
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false, Position = 0)]
    [string[]]$DeviceName,

    [Parameter(Mandatory = $false)]
    [ValidateScript({ Test-Path -LiteralPath $_ })]
    [string]$InputFile,

    [Parameter(Mandatory = $false)]
    [string]$OutputPath = (Join-Path $env:USERPROFILE "Desktop\PrimaryUsers.csv"),

    [Parameter(Mandatory = $false)]
    [ValidateSet(
        "extensionAttribute1", "extensionAttribute2", "extensionAttribute3", "extensionAttribute4",
        "extensionAttribute5", "extensionAttribute6", "extensionAttribute7", "extensionAttribute8",
        "extensionAttribute9", "extensionAttribute10", "extensionAttribute11", "extensionAttribute12",
        "extensionAttribute13", "extensionAttribute14", "extensionAttribute15"
    )]
    [string]$FriendlyModelAttribute = "extensionAttribute1",

    [Parameter(Mandatory = $false)]
    [switch]$NoExport,

    [Parameter(Mandatory = $false)]
    [switch]$Quiet
)

$ErrorActionPreference = "Stop"

#region Helper Functions

function Write-Log {
    <#
    .SYNOPSIS
        Writes formatted log messages to console using the relaunch output prefixes
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet("INFO", "WARN", "ERROR", "SUCCESS", "DEBUG")]
        [string]$Level = "INFO"
    )

    if ($Quiet -and $Level -in @("INFO", "DEBUG")) { return }

    switch ($Level) {
        "INFO" { Write-Host "[*] $Message" -ForegroundColor Cyan }
        "WARN" { Write-Warning $Message }
        "ERROR" { Write-Host "[-] $Message" -ForegroundColor Red }
        "SUCCESS" { Write-Host "[+] $Message" -ForegroundColor Green }
        "DEBUG" { Write-Host "[*] $Message" -ForegroundColor DarkGray }
    }
}

function Protect-ODataString {
    <#
    .SYNOPSIS
        Escapes single quotes in OData filter strings
    #>
    [CmdletBinding()]
    param([AllowNull()][string]$Value)
    if ($null -eq $Value) { return $null }
    return ($Value -replace "'", "''")
}

function Format-BytesToGB {
    <#
    .SYNOPSIS
        Converts bytes to gigabytes with specified decimal precision
    #>
    [CmdletBinding()]
    param([AllowNull()][double]$Bytes, [int]$Decimals = 0)
    if ($null -eq $Bytes -or $Bytes -le 0) { return $null }
    return [math]::Round(($Bytes / 1GB), $Decimals)
}

function Format-Percent {
    <#
    .SYNOPSIS
        Calculates percentage with specified decimal precision
    #>
    [CmdletBinding()]
    param([AllowNull()][double]$Numerator, [AllowNull()][double]$Denominator, [int]$Decimals = 0)
    if ($null -eq $Numerator -or $null -eq $Denominator -or $Denominator -le 0) { return $null }
    return [math]::Round(($Numerator / $Denominator) * 100, $Decimals)
}

function Format-CpuString {
    <#
    .SYNOPSIS
        Normalizes CPU name strings for better readability
    #>
    [CmdletBinding()]
    param([AllowNull()][string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $null }

    $v = $Value.Trim()
    $v = $v -replace "AuthenticAMD", "AMD"
    $v = $v -replace "GenuineIntel", "Intel"
    $v = ($v -replace "\s{2,}", " ").Trim()

    return $v
}

function Resolve-InputTokens {
    <#
    .SYNOPSIS
        Resolves device names from various input sources
    #>
    [CmdletBinding()]
    param(
        [string[]]$DeviceName,
        [string]$InputFile
    )

    $tokens = New-Object System.Collections.Generic.List[string]

    if ($DeviceName -and $DeviceName.Count -gt 0) {
        foreach ($d in $DeviceName) {
            if ([string]::IsNullOrWhiteSpace($d)) { continue }
            ($d -split '[,\r\n]+' | ForEach-Object { $_.Trim() } | Where-Object { $_ }) |
                ForEach-Object { $tokens.Add($_) }
        }
    }
    elseif ($InputFile) {
        $ext = [IO.Path]::GetExtension($InputFile).ToLowerInvariant()

        if ($ext -eq ".csv") {
            try {
                $csv = Import-Csv -LiteralPath $InputFile
                if (-not $csv) { return @() }

                $first = $csv | Select-Object -First 1
                $props = $first.PSObject.Properties.Name

                # Try to find a likely device name column
                $col = @("DeviceName", "deviceName", "Name", "ComputerName", "Computer", "Hostname", "Host") |
                    Where-Object { $props -contains $_ } |
                    Select-Object -First 1

                if (-not $col) { $col = $props | Select-Object -First 1 }

                foreach ($row in $csv) {
                    $val = $row.$col
                    if ($val) { $tokens.Add(($val.ToString()).Trim()) }
                }
            }
            catch {
                Write-Log "Could not read CSV cleanly. Falling back to line by line text parse." "WARN"
                Get-Content -LiteralPath $InputFile -ErrorAction SilentlyContinue |
                    ForEach-Object {
                        $line = $_.Trim()
                        if ($line) { $tokens.Add($line) }
                    }
            }
        }
        else {
            Get-Content -LiteralPath $InputFile -ErrorAction SilentlyContinue |
                ForEach-Object {
                    $line = $_.Trim()
                    if ($line) { $tokens.Add($line) }
                }
        }
    }
    else {
        Write-Host "Enter one or more device names separated by commas" -ForegroundColor Cyan
        Write-Host "OR enter a path to a .txt or .csv file that contains device names." -ForegroundColor Cyan
        Write-Host "Examples:  LTW1010013, LTW1010334, LTW1010344   OR   C:\Temp\devices.txt" -ForegroundColor DarkGray
        $raw = Read-Host "Input"

        if ([string]::IsNullOrWhiteSpace($raw)) { return @() }

        if (Test-Path -LiteralPath $raw) {
            return @(Resolve-InputTokens -DeviceName $null -InputFile $raw)
        }

        ($raw -split '[,\r\n]+' | ForEach-Object { $_.Trim() } | Where-Object { $_ }) |
            ForEach-Object { $tokens.Add($_) }
    }

    $arr = $tokens.ToArray() |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ } |
        Sort-Object -Unique

    return @($arr)
}

#endregion

#region Graph API Functions

$guidRegex = '^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$'

function Get-PrimaryUserFromIntuneUsersRelation {
    <#
    .SYNOPSIS
        Gets the primary user via the managedDevice/users relationship (beta endpoint)
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ManagedDeviceId)

    $uri = ("https://graph.microsoft.com/beta/deviceManagement/managedDevices/{0}/users" +
        "?`$select=id,userPrincipalName,displayName") -f $ManagedDeviceId

    try {
        $resp = Invoke-MgGraphRequest -Method GET -Uri $uri -OutputType PSObject -ErrorAction Stop
        if ($resp -and $resp.value) {
            return ($resp.value | Select-Object -First 1)
        }
        return $null
    }
    catch {
        return $null
    }
}

function Get-ManagedDeviceMatch {
    <#
    .SYNOPSIS
        Finds a managed device by name, ID, or Azure AD Device ID
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Token)

    $selectProps = "id,deviceName,userPrincipalName,azureAdDeviceId,lastSyncDateTime"
    $safeToken = Protect-ODataString -Value $Token

    try {
        if ($Token -match $guidRegex) {
            # Try as managed device ID first
            try {
                $mdById = Get-MgDeviceManagementManagedDevice -ManagedDeviceId $Token `
                    -Property $selectProps -ErrorAction Stop
                if ($mdById) { return $mdById }
            }
            catch {
                Write-Verbose "Handled exception: $($_.Exception.Message)" -Verbose:$false
            }

            # Try as Azure AD Device ID
            $md = Get-MgDeviceManagementManagedDevice -Filter "azureAdDeviceId eq '$safeToken'" `
                -Property $selectProps -Top 1 -ErrorAction SilentlyContinue
            if ($md) { return ($md | Select-Object -First 1) }

            # Try resolving from Azure AD device to get display name
            $aad = Get-MgDevice -DeviceId $Token -ErrorAction SilentlyContinue
            if ($aad -and $aad.DisplayName) {
                $safeName = Protect-ODataString -Value $aad.DisplayName
                $md2 = Get-MgDeviceManagementManagedDevice -Filter "deviceName eq '$safeName'" `
                    -Property $selectProps -Top 1 -ErrorAction SilentlyContinue
                if ($md2) { return ($md2 | Select-Object -First 1) }
            }

            return $null
        }
        else {
            # Try as device name
            $md = Get-MgDeviceManagementManagedDevice -Filter "deviceName eq '$safeToken'" `
                -Property $selectProps -Top 1 -ErrorAction SilentlyContinue
            if ($md) { return ($md | Select-Object -First 1) }
            return $null
        }
    }
    catch {
        return $null
    }
}

function Get-ManagedDeviceDetails {
    <#
    .SYNOPSIS
        Gets detailed hardware and OS information for a managed device
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ManagedDeviceId)

    $select = @(
        "id", "deviceName", "azureAdDeviceId", "userPrincipalName", "lastSyncDateTime",
        "manufacturer", "model", "serialNumber",
        "operatingSystem", "osVersion",
        "totalStorageSpaceInBytes", "freeStorageSpaceInBytes", "physicalMemoryInBytes",
        "processorArchitecture", "hardwareInformation"
    ) -join ","

    $uri = "https://graph.microsoft.com/beta/deviceManagement/managedDevices/{0}?`$select={1}" `
        -f $ManagedDeviceId, $select

    try {
        return (Invoke-MgGraphRequest -Method GET -Uri $uri -OutputType PSObject -ErrorAction Stop)
    }
    catch {
        try {
            return (Get-MgDeviceManagementManagedDevice -ManagedDeviceId $ManagedDeviceId `
                -Property $select -ErrorAction Stop)
        }
        catch {
            return $null
        }
    }
}

function Get-RegisteredOwnerUser {
    <#
    .SYNOPSIS
        Gets the registered owner of an Azure AD device
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$DeviceName)

    $safeName = Protect-ODataString -Value $DeviceName

    $aadMatches = Get-MgDevice -Filter "displayName eq '$safeName'" `
        -Property Id, DisplayName -ErrorAction SilentlyContinue
    foreach ($dev in ($aadMatches | ForEach-Object { $_ })) {

        $owners = Get-MgDeviceRegisteredOwner -DeviceId $dev.Id -All -ErrorAction SilentlyContinue
        foreach ($o in $owners) {
            if ($o.AdditionalProperties.'@odata.type' -eq '#microsoft.graph.user') {
                try {
                    $u = Get-MgUser -UserId $o.Id -ErrorAction Stop
                    if ($u) { return $u }
                }
                catch {
                    Write-Verbose "Handled exception: $($_.Exception.Message)" -Verbose:$false
                }
            }
        }
    }

    return $null
}

function Resolve-UserDisplayNameFromUpn {
    <#
    .SYNOPSIS
        Resolves a user's display name from their UPN
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$UserPrincipalName)

    $safeUpn = Protect-ODataString -Value $UserPrincipalName

    try {
        $u = Get-MgUser -Filter "userPrincipalName eq '$safeUpn'" `
            -ConsistencyLevel eventual -ErrorAction SilentlyContinue
        if ($u) { return (($u | Select-Object -First 1).DisplayName) }
    }
    catch {
        Write-Verbose "Handled exception: $($_.Exception.Message)" -Verbose:$false
    }

    return $null
}

function Get-EntraFriendlyModel {
    <#
    .SYNOPSIS
        Gets the friendly model name from Entra device extension attributes
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$AzureAdDeviceId,
        [Parameter(Mandatory)][string]$AttributeName
    )

    $safe = Protect-ODataString -Value $AzureAdDeviceId

    try {
        $dev = Get-MgDevice -Filter "deviceId eq '$safe'" `
            -Property "id,displayName,deviceId,extensionAttributes" `
            -ConsistencyLevel eventual -ErrorAction SilentlyContinue |
            Select-Object -First 1

        if (-not $dev) { return $null }
        if (-not $dev.extensionAttributes) { return $null }

        $val = $dev.extensionAttributes.$AttributeName
        if ([string]::IsNullOrWhiteSpace($val)) { return $null }

        return $val.Trim()
    }
    catch {
        return $null
    }
}

#endregion

#region Main Script

function Main {
    Set-StrictMode -Version 2.0

    $scopes = @(
        "DeviceManagementManagedDevices.Read.All",
        "Directory.Read.All",
        "User.Read.All",
        "Device.Read.All"
    )

    try {
        if (-not (Get-Module -Name Microsoft.Graph.Authentication -ListAvailable)) {
            Write-Log "Microsoft.Graph.Authentication module not found!" "ERROR"
            Write-Log "Install with: Install-Module -Name Microsoft.Graph" "INFO"
            return 1
        }

        Write-Log "Connecting to Microsoft Graph" "INFO"
        Connect-MgGraph -Scopes $scopes -NoWelcome -ErrorAction Stop | Out-Null

        $tokens = @(Resolve-InputTokens -DeviceName $DeviceName -InputFile $InputFile)

        if (-not $tokens -or $tokens.Count -eq 0) {
            Write-Log "No usable device names found. Exiting." "WARN"
            return 0
        }

        $results = New-Object System.Collections.Generic.List[object]
        $i = 0

        foreach ($token in $tokens) {
            $i++
            $pct = [math]::Round(($i / [double]$tokens.Count) * 100, 0)
            Write-Progress -Activity "Resolving devices" -Status "$i / $($tokens.Count): $token" -PercentComplete $pct

            # Initialize result variables
            $deviceName = $null
            $lastSeen = $null

            $primaryUserUPN = $null
            $primaryUserDisplayName = $null
            $source = $null

            $manufacturer = $null
            $model = $null
            $serialNumber = $null
            $os = $null
            $osVersion = $null

            $ramGB = $null
            $storageTotalGB = $null
            $storageFreeGB = $null
            $storageFreePct = $null

            $cpuArch = $null
            $cpuFriendly = $null

            $friendlyModel = $null

            try {
                $mdMatch = Get-ManagedDeviceMatch -Token $token

                if ($mdMatch) {
                    $deviceName = $mdMatch.deviceName

                    # Parse last sync date/time
                    if ($mdMatch.lastSyncDateTime) {
                        try { $lastSeen = ([datetimeoffset]$mdMatch.lastSyncDateTime).ToLocalTime().DateTime }
                        catch { $lastSeen = $mdMatch.lastSyncDateTime }
                    }

                    # Get detailed device information
                    $md = Get-ManagedDeviceDetails -ManagedDeviceId $mdMatch.id
                    if (-not $md) { $md = $mdMatch }

                    # Extract hardware information
                    $manufacturer = $md.manufacturer
                    $model = $md.model
                    $serialNumber = $md.serialNumber
                    $os = $md.operatingSystem
                    $osVersion = $md.osVersion

                    # Calculate storage metrics
                    $storageTotalGB = Format-BytesToGB -Bytes ([double]$md.totalStorageSpaceInBytes) -Decimals 0
                    $storageFreeGB = Format-BytesToGB -Bytes ([double]$md.freeStorageSpaceInBytes) -Decimals 0
                    $storageFreePct = Format-Percent -Numerator ([double]$md.freeStorageSpaceInBytes) `
                        -Denominator ([double]$md.totalStorageSpaceInBytes) -Decimals 0

                    $ramGB = Format-BytesToGB -Bytes ([double]$md.physicalMemoryInBytes) -Decimals 0

                    $cpuArch = $md.processorArchitecture

                    # Extract CPU information from hardware details
                    if ($md.hardwareInformation) {
                        $hi = $md.hardwareInformation

                        $candidate = $null
                        if ($hi.processorName) { $candidate = $hi.processorName }
                        elseif ($hi.processorManufacturer) { $candidate = $hi.processorManufacturer }

                        $cpuFriendly = Format-CpuString -Value $candidate
                    }

                    # Resolve primary user with multiple fallback methods
                    # 1. Try Intune managedDevice/users relation (most accurate)
                    $pu = Get-PrimaryUserFromIntuneUsersRelation -ManagedDeviceId $mdMatch.id
                    if ($pu) {
                        $primaryUserUPN = $pu.userPrincipalName
                        $primaryUserDisplayName = $pu.displayName
                        $source = "Intune managedDevice/users (beta)"
                    }
                    # 2. Fallback to managedDevice.userPrincipalName
                    elseif ($mdMatch.userPrincipalName) {
                        $primaryUserUPN = $mdMatch.userPrincipalName
                        $primaryUserDisplayName = Resolve-UserDisplayNameFromUpn -UserPrincipalName $primaryUserUPN
                        $source = "managedDevice.userPrincipalName"
                    }

                    # 3. Final fallback to Azure AD registered owner
                    if (-not $primaryUserUPN -and $deviceName) {
                        $ownerUser = Get-RegisteredOwnerUser -DeviceName $deviceName
                        if ($ownerUser) {
                            $primaryUserUPN = $ownerUser.UserPrincipalName
                            $primaryUserDisplayName = $ownerUser.DisplayName
                            $source = "Entra ID registeredOwner"
                        }
                    }

                    if (-not $primaryUserUPN) {
                        $source = "Found in Intune but no user resolved"
                    }

                    # Get friendly model name from Entra extension attributes
                    if ($md.azureAdDeviceId) {
                        $friendlyModel = Get-EntraFriendlyModel -AzureAdDeviceId $md.azureAdDeviceId `
                            -AttributeName $FriendlyModelAttribute
                    }
                }
                else {
                    $deviceName = $token
                    $source = "Not found in Intune"
                }

                # Add result to collection
                $results.Add([pscustomobject]@{
                        DeviceName           = $deviceName
                        LastSeen             = $lastSeen

                        PrimaryUserDisplayName = $primaryUserDisplayName
                        PrimaryUserUPN       = $primaryUserUPN
                        Source               = $source

                        FriendlyModel        = $friendlyModel
                        Manufacturer         = $manufacturer
                        Model                = $model
                        SerialNumber         = $serialNumber
                        OperatingSystem      = $os
                        OSVersion            = $osVersion

                        CPU                  = $cpuFriendly
                        CPUArchitecture      = $cpuArch

                        RAM_GB               = $ramGB
                        StorageTotal_GB      = $storageTotalGB
                        StorageFree_GB       = $storageFreeGB
                        StorageFree_Percent  = $storageFreePct
                    })
            }
            catch {
                # Add error result
                $results.Add([pscustomobject]@{
                        DeviceName           = $token
                        LastSeen             = $null

                        PrimaryUserDisplayName = $null
                        PrimaryUserUPN       = $null
                        Source               = "Error: $($_.Exception.Message)"

                        FriendlyModel        = $null
                        Manufacturer         = $null
                        Model                = $null
                        SerialNumber         = $null
                        OperatingSystem      = $null
                        OSVersion            = $null

                        CPU                  = $null
                        CPUArchitecture      = $null

                        RAM_GB               = $null
                        StorageTotal_GB      = $storageTotalGB
                        StorageFree_GB       = $storageFreeGB
                        StorageFree_Percent  = $storageFreePct
                    })
            }
        }

        Write-Progress -Activity "Resolving devices" -Completed

        # Display results
        $final = $results | Sort-Object DeviceName
        $final | Format-Table -AutoSize

        # Export to CSV if requested
        if (-not $NoExport) {
            $outDir = Split-Path -Path $OutputPath -Parent
            if ($outDir -and -not (Test-Path -LiteralPath $outDir)) {
                New-Item -ItemType Directory -Path $outDir -Force | Out-Null
            }

            $final | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $OutputPath -ErrorAction Stop
            Write-Log "Saved to: $OutputPath" "SUCCESS"
        }
        else {
            Write-Log "NoExport specified. Skipping CSV export." "INFO"
        }

        return 0
    }
    catch {
        Write-Log "Unhandled error: $($_.Exception.Message)" "ERROR"
        return 1
    }
    finally {
        try { Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null }
        catch { Write-Verbose "Handled exception: $($_.Exception.Message)" -Verbose:$false }
    }
}

#endregion

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
