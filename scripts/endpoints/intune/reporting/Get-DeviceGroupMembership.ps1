<#
.SYNOPSIS
    Audit device group memberships in Azure AD/Intune and export an HTML/CSV report.

.DESCRIPTION
    This script generates a report showing which devices belong to which Azure AD groups.
    Especially useful for:
    - Auditing dynamic group memberships
    - Verifying policy targeting
    - Troubleshooting assignment issues
    - Understanding device categorization

    Can show:
    - All groups a specific device belongs to
    - All devices in a specific group
    - Complete device-to-group mapping

    Requires connection to Microsoft Graph with Group.Read.All, Device.Read.All and
    DeviceManagementManagedDevices.Read.All permissions. Reports are written to the
    user's Documents\Reports folder.

.PARAMETER DeviceName
    Specific device name to check group membership for.

.PARAMETER GroupName
    Specific group name to show device members of.

.PARAMETER ShowDynamicGroupsOnly
    Only show dynamic group memberships.

.PARAMETER ExportFormat
    Report format: HTML, CSV, or Both (default: Both).

.PARAMETER ShowAllMappings
    Generate full device-to-group membership matrix.

.EXAMPLE
    PS C:\> .\Get-DeviceGroupMembership.ps1 -DeviceName "DESKTOP-ABC123"
    Shows all groups that DESKTOP-ABC123 belongs to.

.EXAMPLE
    PS C:\> .\Get-DeviceGroupMembership.ps1 -GroupName "Windows 10 Devices"
    Shows all devices in the "Windows 10 Devices" group.

.EXAMPLE
    PS C:\> .\Get-DeviceGroupMembership.ps1 -ShowAllMappings
    Generates complete device-to-group membership report.

.NOTES
    File Name: Get-DeviceGroupMembership.ps1
    Author: Bug-Free Umbrella
    Prerequisite: PowerShell 7.0
    Version: 1.0.0
    Date: 2026-08-23

    Requires Microsoft.Graph PowerShell module
    Requires permissions: Group.Read.All, Device.Read.All
    Can take several minutes for large tenants
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$DeviceName,

    [Parameter(Mandatory = $false)]
    [string]$GroupName,

    [Parameter(Mandatory = $false)]
    [switch]$ShowDynamicGroupsOnly,

    [Parameter(Mandatory = $false)]
    [ValidateSet('HTML', 'CSV', 'Both')]
    [string]$ExportFormat = 'Both',

    [Parameter(Mandatory = $false)]
    [switch]$ShowAllMappings
)

$ErrorActionPreference = 'Stop'

function Main {
    try {
        $ReportDir = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Reports'
        if ([string]::IsNullOrWhiteSpace($ReportDir) -or
            $ReportDir -match '(^|[\\/])\.\.([\\/]|$)' -or
            $ReportDir -match '^(\\\\|//)') {
            Write-Host "[-] Unsafe report path: $ReportDir." -ForegroundColor Red
            Write-Host "[-] Report path must be a local absolute path without '..' traversal." -ForegroundColor Red
            return 1
        }
        $ReportDir = [System.IO.Path]::GetFullPath($ReportDir)
        if (-not (Test-Path -LiteralPath $ReportDir -PathType Container)) {
            New-Item -ItemType Directory -Path $ReportDir -Force -ErrorAction Stop | Out-Null
        }

        # Import helper module from the parent (intune/) directory
        $modulePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'IntuneGraphHelper.psm1'
        Import-Module $modulePath -Force -ErrorAction Stop

        Write-Host "`n========================================" -ForegroundColor Cyan
        Write-Host "Device Group Membership Audit" -ForegroundColor Cyan
        Write-Host "========================================`n" -ForegroundColor Cyan

        # Connect to Microsoft Graph
        $connected = Connect-IntuneGraph -Scopes @(
            "Group.Read.All",
            "Device.Read.All",
            "DeviceManagementManagedDevices.Read.All"
        ) -ErrorAction Stop

        if (-not $connected) {
            Write-Host "[-] Failed to connect to Microsoft Graph. Exiting." -ForegroundColor Red
            return 1
        }

        try {
            Import-Module Microsoft.Graph.Groups -ErrorAction Stop
            Import-Module Microsoft.Graph.DeviceManagement -ErrorAction Stop

            $report = @()

            # Mode 1: Specific Device
            if ($DeviceName) {
                Write-Host "[*] Searching for device: $DeviceName..." -ForegroundColor Cyan

                # Find device in Azure AD
                $azureAdDevices = Invoke-MgGraphRequest `
                    -Uri "https://graph.microsoft.com/v1.0/devices?`$filter=displayName eq '$DeviceName'" `
                    -ErrorAction Stop

                if (-not $azureAdDevices.value -or $azureAdDevices.value.Count -eq 0) {
                    Write-Host "[-] Device '$DeviceName' not found in Azure AD" -ForegroundColor Red
                    Disconnect-IntuneGraph
                    return 1
                }

                $device = $azureAdDevices.value[0]
                Write-Host "[+] Found device: $($device.displayName)" -ForegroundColor Green

                # Get group memberships
                Write-Host "[*] Retrieving group memberships..." -ForegroundColor Cyan
                $memberOf = Invoke-MgGraphRequest `
                    -Uri "https://graph.microsoft.com/v1.0/devices/$($device.id)/memberOf" -ErrorAction Stop

                if ($memberOf.value) {
                    foreach ($group in $memberOf.value) {
                        # Get group details
                        $groupDetails = Invoke-MgGraphRequest `
                            -Uri "https://graph.microsoft.com/v1.0/groups/$($group.id)" -ErrorAction Stop

                        $isDynamic = $groupDetails.membershipRule -ne $null
                        $membershipType = if ($isDynamic) { "Dynamic" } else { "Assigned" }

                        if ($ShowDynamicGroupsOnly -and -not $isDynamic) {
                            continue
                        }

                        $report += [PSCustomObject]@{
                            DeviceName = $device.displayName
                            DeviceId = $device.id
                            GroupName = $groupDetails.displayName
                            GroupId = $groupDetails.id
                            MembershipType = $membershipType
                            MembershipRule = if ($isDynamic) { $groupDetails.membershipRule } else { "N/A" }
                            GroupDescription = $groupDetails.description
                        }
                    }

                    Write-Host "[+] Found $($report.Count) group memberships" -ForegroundColor Green
                }
                else {
                    Write-Host "[!] Device is not a member of any groups" -ForegroundColor Yellow
                }
            }
            # Mode 2: Specific Group
            elseif ($GroupName) {
                Write-Host "[*] Searching for group: $GroupName..." -ForegroundColor Cyan

                # Find group
                $groups = Invoke-MgGraphRequest `
                    -Uri "https://graph.microsoft.com/v1.0/groups?`$filter=displayName eq '$GroupName'" `
                    -ErrorAction Stop

                if (-not $groups.value -or $groups.value.Count -eq 0) {
                    Write-Host "[-] Group '$GroupName' not found" -ForegroundColor Red
                    Disconnect-IntuneGraph
                    return 1
                }

                $group = $groups.value[0]
                Write-Host "[+] Found group: $($group.displayName)" -ForegroundColor Green

                $isDynamic = $group.membershipRule -ne $null
                Write-Host "  Type: $(if($isDynamic){'Dynamic'}else{'Assigned'})" -ForegroundColor Gray

                if ($isDynamic) {
                    Write-Host "  Rule: $($group.membershipRule)" -ForegroundColor Gray
                }

                # Get group members (devices only)
                Write-Host "`nRetrieving device members..." -ForegroundColor Cyan
                $members = Invoke-MgGraphRequest `
                    -Uri "https://graph.microsoft.com/v1.0/groups/$($group.id)/members" -ErrorAction Stop

                $deviceMembers = $members.value | Where-Object { $_.'@odata.type' -eq '#microsoft.graph.device' }

                if ($deviceMembers) {
                    foreach ($device in $deviceMembers) {
                        $report += [PSCustomObject]@{
                            GroupName = $group.displayName
                            GroupId = $group.id
                            MembershipType = if ($isDynamic) { "Dynamic" } else { "Assigned" }
                            DeviceName = $device.displayName
                            DeviceId = $device.id
                            OperatingSystem = $device.operatingSystem
                            OperatingSystemVersion = $device.operatingSystemVersion
                            TrustType = $device.trustType
                        }
                    }

                    Write-Host "[+] Found $($deviceMembers.Count) device members" -ForegroundColor Green
                }
                else {
                    Write-Host "[!] No device members in this group" -ForegroundColor Yellow
                }
            }
            # Mode 3: All Mappings
            elseif ($ShowAllMappings) {
                Write-Host "[!] Generating complete device-to-group mapping..." -ForegroundColor Yellow
                Write-Host "[!] This may take several minutes for large tenants..." -ForegroundColor Yellow

                # Get all groups
                Write-Host "`nRetrieving all groups..." -ForegroundColor Cyan
                $allGroups = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/v1.0/groups" -ErrorAction Stop
                $groups = $allGroups.value

                Write-Host "[+] Retrieved $($groups.Count) groups" -ForegroundColor Green

                # Filter to groups with devices
                $counter = 0
                foreach ($group in $groups) {
                    $counter++
                    Write-Progress -Activity "Processing groups" -Status "$counter of $($groups.Count)" `
                        -PercentComplete (($counter / $groups.Count) * 100)

                    $isDynamic = $group.membershipRule -ne $null
                    $membershipType = if ($isDynamic) { "Dynamic" } else { "Assigned" }

                    if ($ShowDynamicGroupsOnly -and -not $isDynamic) {
                        continue
                    }

                    # Get members
                    try {
                        $uri = "https://graph.microsoft.com/v1.0/groups/$($group.id)/members" +
                            "?`$select=id,displayName,deviceId"
                        $members = Invoke-MgGraphRequest -Uri $uri -ErrorAction SilentlyContinue

                        $deviceMembers = $members.value |
                            Where-Object { $_.'@odata.type' -eq '#microsoft.graph.device' }

                        if ($deviceMembers) {
                            foreach ($device in $deviceMembers) {
                                $report += [PSCustomObject]@{
                                    DeviceName = $device.displayName
                                    DeviceId = $device.id
                                    GroupName = $group.displayName
                                    GroupId = $group.id
                                    MembershipType = $membershipType
                                    GroupDescription = $group.description
                                }
                            }
                        }
                    }
                    catch {
                        Write-Verbose "Handled exception: $($_.Exception.Message)" -Verbose:$false
                    }
                }

                Write-Progress -Activity "Processing groups" -Completed
                Write-Host "[+] Generated $($report.Count) device-group mappings" -ForegroundColor Green
            }
            else {
                Write-Host "[-] Please specify -DeviceName, -GroupName, or -ShowAllMappings" -ForegroundColor Red
                Write-Host "`nExamples:" -ForegroundColor Yellow
                Write-Host "  .\Get-DeviceGroupMembership.ps1 -DeviceName 'DESKTOP-ABC123'" -ForegroundColor Gray
                Write-Host "  .\Get-DeviceGroupMembership.ps1 -GroupName 'Windows 10 Devices'" -ForegroundColor Gray
                Write-Host "  .\Get-DeviceGroupMembership.ps1 -ShowAllMappings" -ForegroundColor Gray
                Disconnect-IntuneGraph
                return 1
            }

            # Display summary
            Write-Host "`n========================================" -ForegroundColor Cyan
            Write-Host "GROUP MEMBERSHIP SUMMARY" -ForegroundColor Cyan
            Write-Host "========================================" -ForegroundColor Cyan

            if ($report.Count -eq 0) {
                Write-Host "[!] No memberships found matching criteria." -ForegroundColor Yellow
                Disconnect-IntuneGraph
                return 0
            }

            Write-Host "Total Mappings: $($report.Count)" -ForegroundColor White

            if ($ShowAllMappings -or $DeviceName) {
                # Group by membership type
                $byType = $report | Group-Object -Property MembershipType
                Write-Host "`nBy Membership Type:" -ForegroundColor Cyan
                foreach ($type in $byType) {
                    Write-Host "  $($type.Name): $($type.Count)" -ForegroundColor Gray
                }

                # Top groups by device count
                if ($ShowAllMappings) {
                    $topGroups = $report | Group-Object -Property GroupName |
                        Sort-Object Count -Descending | Select-Object -First 10
                    Write-Host "`nTop 10 Groups by Device Count:" -ForegroundColor Cyan
                    foreach ($group in $topGroups) {
                        Write-Host "  $($group.Name): $($group.Count) devices" -ForegroundColor Gray
                    }
                }
            }

            # Sort report
            $report = $report | Sort-Object DeviceName, GroupName

            # Export reports
            $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
            $outputPath = $ReportDir

            $reportTitle = if ($DeviceName) {
                "Device_Group_Membership_$($DeviceName)_$timestamp"
            }
            elseif ($GroupName) {
                "Group_Members_$($GroupName -replace '[\\/:*?`"<>|]', '_')_$timestamp"
            }
            else {
                "All_Device_Group_Memberships_$timestamp"
            }

            if ($ExportFormat -eq 'HTML' -or $ExportFormat -eq 'Both') {
                $htmlPath = Join-Path $outputPath "$reportTitle.html"
                Export-IntuneReportToHTML -Data $report -Title "Device Group Membership Report" `
                    -FilePath $htmlPath -ErrorAction Stop
            }

            if ($ExportFormat -eq 'CSV' -or $ExportFormat -eq 'Both') {
                $csvPath = Join-Path $outputPath "$reportTitle.csv"
                Export-IntuneReportToCSV -Data $report -Title $reportTitle -FilePath $csvPath -ErrorAction Stop
            }

            Write-Host "`n[+] Group membership audit completed!" -ForegroundColor Green
            return 0
        }
        catch {
            Write-Host "`n[-] Error: $($_.Exception.Message)" -ForegroundColor Red
            Write-Host $_.ScriptStackTrace -ForegroundColor Red
            return 1
        }
        finally {
            # Disconnect from Graph
            Disconnect-IntuneGraph
        }
    }
    catch {
        Write-Host "`n[-] Error: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
