<#
.SYNOPSIS
    Check BitLocker recovery key backup to Azure AD for the system drive

.DESCRIPTION
    Intune Proactive Remediation detection script for BitLocker key escrow. Confirms the device is Azure AD joined,
    queries the BitLocker Management event log for event ID 845 confirming recovery-key backup of the system drive
    within the past 7 days, and collects per-drive encryption status for the Intune report.

    Exit codes: 0 when the recovery key is backed up, 1 when the backup event is missing so the paired
    remediation runs,
    and 0 with a WARNING line when the device is not Azure AD joined (remediation cannot apply, so failing would be
    noise). The last output line is uploaded to Intune and visible in the Remediation Device Status columns.

.EXAMPLE
    PS C:\> .\Detect_BitLockerKeyBackup.ps1

    Runs the detection and prints an OK, FAIL, or WARNING summary line; exits 0, 1, or 0 respectively.

.EXAMPLE
    PS C:\> .\Detect_BitLockerKeyBackup.ps1 -Verbose

    Runs the detection with verbose preference enabled for richer diagnostics.

.NOTES
    File Name  : Detect_BitLockerKeyBackup.ps1
    Author     : Intune / Proactive Remediations
    Prerequisite: PowerShell 5.1+
    Version    : 1.0.0
    Date       : 2026-08-23

    Run as administrator/SYSTEM on Windows with the BitLocker management cmdlets available.
    Reference:
    https://techcommunity.microsoft.com/t5/intune-customer-success/using-bitlocker-recovery-keys-with-microsoft-endpoint-manager/ba-p/2255517
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

# PSScriptAnalyzer: Write-Host with prefix/color output is mandated by docs/RELAUNCH-SPEC.md section 3.

#region Functions

function Invoke-JoinStatusQuery {
    <#
    .SYNOPSIS
        Thin wrapper around dsregcmd.exe and findstr.exe that reads the device join status.

    .DESCRIPTION
        Wraps the native dsregcmd /status query and filters the relevant AzureAdJoined and DomainJoined lines so
        both native
        executables stay behind a single mockable seam. Returns the filtered output lines.

    .EXAMPLE
        PS C:\> Invoke-JoinStatusQuery

    .NOTES
        Wrapper only; takes no parameters.
    #>
    [CmdletBinding()]
    param()

    $status = & "$env:SystemRoot\System32\dsregcmd.exe" /status
    return ($status | findstr.exe /i "AzureAdJoined DomainJoined")
}

function Test-DeviceJoinStatus {
    <#
    .SYNOPSIS
        Verifies the Azure AD and Domain join status of a device.

    .DESCRIPTION
        The function checks if the device is joined to Azure AD and/or a traditional AD domain. It returns a
        custom object
        with properties StatusCode and Summary; StatusCode is 0 when the device is Azure AD joined and 1 when it
        is not.
        Summary provides a string describing the join status including the hostname.

    .NOTES
        If the device is not Azure AD joined there is no way to back up BitLocker recovery keys to Azure AD, so Main
        documents the details but exits 0 to avoid remediation noise.
    #>
    [CmdletBinding()]
    param ()

    try {
# Capture dsregcmd output, looking for lines containing AzureAdJoined or DomainJoined.
        $result = Invoke-JoinStatusQuery

        if ($null -eq $result) {
            throw "Failed to execute dsregcmd command."
        }

# Check the result for "AzureAdJoined : YES" / "DomainJoined : YES".
        $AzureAdJoined = if ($result -match "AzureAdJoined : YES") { "Yes" } else { "No" }
        $DomainJoined = if ($result -match "DomainJoined : YES") { "Yes" } else { "No" }

# Retrieve the hostname of the device.
        $hostname = $env:COMPUTERNAME

# Compile the findings into a summary string including the hostname.
        $summary = "Hostname = $hostname - AADJ = $AzureAdJoined, ADJ = $DomainJoined. "

# Status code based on Azure AD join status.
        $statusCode = if ($AzureAdJoined -eq "Yes") { 0 } else { 1 }

        return New-Object PSObject -Property @{
            StatusCode = $statusCode
            Summary = $summary
        }
    }
    catch {
        Write-Host "[-] An error occurred: $_" -ForegroundColor Red
    }
}

function Test-AzureADBitLockerBackup {
    <#
    .SYNOPSIS
        Check the BitLocker Management event log for event ID 845 confirming successful backup of the BitLocker
        key to Azure
        AD for the system drive.

    .DESCRIPTION
        Queries the BitLocker Management event log for event ID 845 at Information level within the past nDays.
        If an event
        exists specifically for the system drive, the BitLocker key backup to Azure AD was successful. Returns 0
        on success
        and 1 when no confirming event is found.

    .PARAMETER nDays
        The number of past days to check for the event. The default is 1.

    .EXAMPLE
        PS C:\> Test-AzureADBitLockerBackup -nDays 7

        Checks the last seven days for a successful system drive key backup event.

    .NOTES
        Run this script as an administrator.

        Reference:
        https://techcommunity.microsoft.com/t5/intune-customer-success/using-bitlocker-recovery-keys-with-microsoft-endpoint-manager/ba-p/2255517
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 3650)]
        [int]
        $nDays = 1
    )

    try {
# Get the date nDays ago.
        $pastDate = (Get-Date).AddDays(-$nDays)

# Get the system drive from the environment variables.
        $systemDrive = $env:SystemDrive

# Get BitLocker Management events with ID 845 and Level 4 (Information) from the past nDays.
        $events = Get-WinEvent -FilterHashtable @{
            LogName = "Microsoft-Windows-BitLocker/BitLocker Management"
            ID = 845
            Level = 4
            StartTime = $pastDate
        } -ErrorAction Stop

# If events exist, check whether any of them are for the system drive.
        if ($events) {
            foreach ($evt in $events) {
                $eventData = [xml]$evt.ToXml()
                $volume = $eventData.Event.EventData.Data |
                    Where-Object { $_.Name -eq 'VolumeMountPoint' } |
                    Select-Object -ExpandProperty '#text'
                if ($volume -eq $systemDrive) {
                    Write-Host ("[+] Key backup to Azure AD for the system drive ($systemDrive) was successful " +
                        "in the past $nDays day(s).") -ForegroundColor Green
                    return 0
                }
            }

            Write-Host ("[!] No events found in the past $nDays day(s) indicating successful BitLocker key backup " +
                "to Azure AD for the system drive ($systemDrive).") -ForegroundColor Yellow
            return 1
        }
        else {
            Write-Host ("[!] No events found in the past $nDays day(s) indicating a successful " +
                "key backup to Azure AD.") -ForegroundColor Yellow
            return 1
        }
    }
    catch {
        Write-Host "[-] Failed to query BitLocker Management event log: $_" -ForegroundColor Red
        return 1
    }
}

function Test-OSBitLockerStatus {
    <#
    .SYNOPSIS
        Checks if the system drive is BitLocker encrypted.

    .DESCRIPTION
        Checks whether the system drive on the computer is BitLocker encrypted. Returns 0 if the system drive is
        encrypted,
        and 1 if it is not.

    .EXAMPLE
        PS C:\> Test-OSBitLockerStatus

    .NOTES
        Run this script with administrator privileges.

        Originally intended as the primary check; Test-AzureADBitLockerBackup is used instead because it
        confirms successful
        key backup to Azure AD.
    #>
    [CmdletBinding()]
    param ()

# Identify the system drive.
    $systemDrive = [Environment]::GetFolderPath("System").Substring(0, 2)

# Get the BitLocker volume status for the system drive.
    $BitLockerVolume = Get-BitLockerVolume -MountPoint $systemDrive

# Check if BitLocker protection is enabled for the system drive.
    if ($BitLockerVolume.ProtectionStatus -eq 'On') {
        return 0
    }
    else {
        return 1
    }
}

function Test-AllDrivesEncryption {
    <#
    .SYNOPSIS
        Checks all drives to see if they are encrypted with BitLocker.

    .DESCRIPTION
        Iterates over all drives, checks each one for BitLocker encryption, and builds a summary string of the
        encryption
        status of all drives.

    .EXAMPLE
        PS C:\> Test-AllDrivesEncryption

    .NOTES
        Returns a summary string; includes failure detail if BitLocker status cannot be read.
    #>
    [CmdletBinding()]
    param ()

    $summary = ""

    try {
# Get all BitLocker volumes.
        $BitLockerVolumes = Get-BitLockerVolume -ErrorAction Stop

        foreach ($BitLockerVolume in $BitLockerVolumes) {
            if ($BitLockerVolume.EncryptionMethod -eq "None") {
                $summary += "Drive $($BitLockerVolume.MountPoint) not encrypted. "
            }
            else {
                $summary += "Drive $($BitLockerVolume.MountPoint) encrypted. "
            }
        }
    }
    catch {
        $summary += "Failed to get BitLocker status: $($_.Exception.Message). "
    }

    return $summary
}

function Get-BitLockerVolumeInfo {
    <#
    .SYNOPSIS
        Retrieves BitLocker volume information.

    .DESCRIPTION
        Retrieves BitLocker volume information of the local computer. For each volume it presents volume type,
        mount point,
        volume status, encryption percentage, and key protector type, combined into a single string.

    .EXAMPLE
        PS C:\> Get-BitLockerVolumeInfo

    .NOTES
        Run this script as an administrator.
    #>
    [CmdletBinding()]
    param ()

    begin {
        $volumeInfoString = ""
        Write-Host "[*] Starting BitLocker volume information retrieval process." -ForegroundColor Cyan
    }

    process {
        try {
            $BitLockerVolumes = Get-BitLockerVolume -ErrorAction Stop
            $volumeInfoArray = @()

            foreach ($BitLockerVolume in $BitLockerVolumes) {
# Construct a single string per volume with type, mount point, status, and protector type.
                $v = $BitLockerVolume
                $volumeInfo = "Volume Type: $($v.VolumeType), Mount Point: $($v.MountPoint), " +
                    "Volume Status: $($v.VolumeStatus), Encryption Percentage: $($v.EncryptionPercentage), " +
                    "KeyProtector Type: $($v.KeyProtector[0].KeyProtectorType)"

                $volumeInfoArray += $volumeInfo
                Write-Host "[+] Retrieved BitLocker volume information for $($v.MountPoint)." -ForegroundColor Green
            }

            $volumeInfoString = $volumeInfoArray -join '. '
            Write-Host $volumeInfoString
        }
        catch {
            Write-Host "[-] Failed to retrieve BitLocker volume information: $_" -ForegroundColor Red
        }
    }

    end {
        Write-Host "[*] BitLocker volume information retrieval process completed." -ForegroundColor Cyan
        return $volumeInfoString
    }
}

#endregion Functions

function Main {
    [CmdletBinding()]
    param()

    try {
        $txtStatus = ""

# Document domain join info regardless of outcome so it uploads to Intune.
        $adJoined = Test-DeviceJoinStatus
        $txtStatus += "$($adJoined.Summary)"

# If the device is not Azure AD Joined, keys cannot be backed up to Azure AD;
# document drive status and exit 0 (WARNING) since remediation cannot fix it.
        if ($($adJoined.StatusCode) -eq 0) {
            $bitlockerBackupStatus = Test-AzureADBitLockerBackup -nDays 7
        }
        else {
            $bitlockerBackupStatus = -2
        }

        $encryptedDrives = Test-AllDrivesEncryption
        $bitlockerinfo = Get-BitLockerVolumeInfo

# Build summary text of findings and status.
        $txtStatus += "$encryptedDrives"
        if ($bitlockerinfo -ne "") {
            $txtStatus += "[$bitlockerinfo]"
        }

# The last output line is uploaded to Intune and shown in the Remediation Device Status columns.
        if ($bitlockerBackupStatus -eq 0) {
            Write-Host "OK $([datetime]::Now) : $txtStatus"
            return 0
        }
        elseif ($bitlockerBackupStatus -eq 1) {
            Write-Host "FAIL $([datetime]::Now) : $txtStatus"
            return 1
        }
        else {
            Write-Host "WARNING $([datetime]::Now) : $txtStatus"
            return 0
        }
    }
    catch {
        Write-Host "[-] Error: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
