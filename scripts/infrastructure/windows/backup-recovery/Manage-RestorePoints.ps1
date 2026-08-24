<#
.SYNOPSIS
    Manages system restore points on Windows servers and workstations.

.DESCRIPTION
    This script provides system restore point management including creation, listing,
    verification, and cleanup of restore points. It requires Administrator privileges and
    System Restore to be enabled for most actions. Creating a restore point mutates system
    state (Checkpoint-Computer) and is therefore gated behind -WhatIf/-Confirm support;
    cleanup reports old restore points and only inspects shadow copies. Re-running List or
    Verify is read-only and always safe.

.PARAMETER Action
    Action to perform: Create, List, Remove, Verify, or Cleanup. Default is List.

.PARAMETER Description
    Description for new restore point (required for Create action).

.PARAMETER RestorePointType
    Type of restore point: ApplicationInstall, ApplicationUninstall, ModifySettings. Default is ModifySettings.

.PARAMETER RetentionDays
    For Cleanup action, number of days to retain restore points. Default is 30.

.PARAMETER Force
    Force removal of restore points without confirmation.

.EXAMPLE
    PS C:\> .\Manage-RestorePoints.ps1 -Action List
    Lists all available restore points.

.EXAMPLE
    PS C:\> .\Manage-RestorePoints.ps1 -Action Create -Description "Before GPO changes"
    Creates a new restore point before making GPO changes.

.EXAMPLE
    PS C:\> .\Manage-RestorePoints.ps1 -Action Cleanup -RetentionDays 14 -Force
    Reports restore points older than 14 days without prompting for confirmation.

.NOTES
    File Name: Manage-RestorePoints.ps1
    Author: Server Management Team
    Prerequisite: PowerShell 7.0
    Version: 1.0.0
    Date: 2026-08-23
#>

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification='Spec 3 requirement')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification='Used in Main scope')]
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $false)]
    [ValidateSet('Create', 'List', 'Remove', 'Verify', 'Cleanup')]
    [string]$Action = 'List',

    [Parameter(Mandatory = $false)]
    [string]$Description,

    [Parameter(Mandatory = $false)]
    [ValidateSet('ApplicationInstall', 'ApplicationUninstall', 'ModifySettings')]
    [string]$RestorePointType = 'ModifySettings',

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 3650)]
    [int]$RetentionDays = 30,

    [Parameter(Mandatory = $false)]
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

function Test-IsAdministrator {
    [CmdletBinding()]
    param()

    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-SystemRestoreEnabled {
    [CmdletBinding()]
    param()

    try {
        Get-ComputerRestorePoint -ErrorAction Stop | Out-Null
        return $true
    }
    catch {
        # Check registry to see if System Restore is disabled
        $regPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore'
        if (Test-Path $regPath) {
            $rpSessionInterval = Get-ItemProperty -Path $regPath -Name 'RPSessionInterval' -ErrorAction SilentlyContinue
            if ($rpSessionInterval.RPSessionInterval -eq 0) {
                return $false
            }
        }
        return $false
    }
}

function Invoke-VssAdmin {
    # Thin wrapper around the native vssadmin.exe so tests can mock it (Pester cannot mock native exes).
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string[]]$VssAdminArgs
    )

    & vssadmin.exe @VssAdminArgs
    return $LASTEXITCODE
}

function Main {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    try {
        Write-Host '[*] Starting System Restore Point Manager...' -ForegroundColor Cyan
        Write-Host ''
        Write-Host '=== System Restore Point Manager ===' -ForegroundColor Cyan
        Write-Host "Computer: $env:COMPUTERNAME" -ForegroundColor Gray

        # Check if running as administrator
        if (-not (Test-IsAdministrator)) {
            Write-Host '[-] This script requires Administrator privileges' -ForegroundColor Red
            return 1
        }

        # Check if System Restore is enabled
        Write-Host '[*] Checking System Restore status...' -ForegroundColor Yellow
        if (-not (Test-SystemRestoreEnabled)) {
            Write-Host '[!] WARNING: System Restore is not enabled on this system' -ForegroundColor Yellow
            Write-Host "[*] To enable System Restore, use: Enable-ComputerRestore -Drive 'C:\'" -ForegroundColor Cyan

            if ($Action -eq 'Create') {
                Write-Host '[-] Cannot create restore point - System Restore is disabled' -ForegroundColor Red
                return 1
            }
        }
        else {
            Write-Host '[+] System Restore is enabled' -ForegroundColor Green
        }

        # Perform requested action
        switch ($Action) {
            'List' {
                Write-Host '[*] Retrieving system restore points...' -ForegroundColor Yellow

                try {
                    $restorePoints = Get-ComputerRestorePoint -ErrorAction Stop |
                        Sort-Object -Property CreationTime -Descending

                    if ($restorePoints) {
                        Write-Host "[+] Found $(@($restorePoints).Count) restore point(s)" -ForegroundColor Green
                        Write-Host ''

                        $restorePoints | Format-Table -AutoSize -Property @(
                            @{ Label = 'Sequence'; Expression = { $_.SequenceNumber } },
                            @{ Label = 'Created'; Expression = { $_.CreationTime.ToString('yyyy-MM-dd HH:mm:ss') } },
                            @{ Label = 'Description'; Expression = { $_.Description } },
                            @{ Label = 'Type'; Expression = {
                                    switch ($_.RestorePointType) {
                                        0 { 'Application Install' }
                                        1 { 'Application Uninstall' }
                                        12 { 'Modify Settings' }
                                        13 { 'Cancelled Operation' }
                                        default { "Unknown ($($_.RestorePointType))" }
                                    }
                                }
                            }
                        )

                        # Show most recent
                        $mostRecent = @($restorePoints)[0]
                        $daysSince = ((Get-Date) - $mostRecent.CreationTime).Days

                        Write-Host '[*] Most recent restore point:' -ForegroundColor Cyan
                        $createdText = $($mostRecent.CreationTime.ToString('yyyy-MM-dd HH:mm:ss'))
                        Write-Host "  Created: $createdText" -ForegroundColor White
                        Write-Host "  Description: $($mostRecent.Description)" -ForegroundColor White
                        $fgColor = if ($daysSince -le 7) { 'Green' }
                        elseif ($daysSince -le 30) { 'Yellow' }
                        else { 'Red' }
                        Write-Host "  Days ago: $daysSince" -ForegroundColor $fgColor
                    }
                    else {
                        Write-Host '[!] No restore points found' -ForegroundColor Yellow
                    }
                }
                catch {
                    Write-Host "[-] Failed to retrieve restore points: $_" -ForegroundColor Red
                    return 1
                }
            }

            'Create' {
                if (-not $Description) {
                    Write-Host ('[-] Description is required for creating' +
                        'restore points. Use -Description parameter.') -ForegroundColor Red
                    return 1
                }

                Write-Host '[*] Creating system restore point...' -ForegroundColor Yellow
                Write-Host "Description: $Description" -ForegroundColor Cyan
                Write-Host "Type: $RestorePointType" -ForegroundColor Cyan

                try {
                    if (-not $PSCmdlet.ShouldProcess($env:COMPUTERNAME, "Create system restore point '$Description'")) {
                        Write-Host ('[!] Skipped creating restore' +
                            'point (-WhatIf or user declined)') -ForegroundColor Yellow
                        return 0
                    }

                    # Enable-ComputerRestore ensures C: drive is enabled
                    Enable-ComputerRestore -Drive 'C:\' -ErrorAction SilentlyContinue

                    # Create restore point
                    Checkpoint-Computer -Description $Description -RestorePointType $RestorePointType -ErrorAction Stop

                    Write-Host '[+] Restore point created successfully' -ForegroundColor Green

                    # Verify creation
                    Start-Sleep -Seconds 2
                    $newRestorePoint = Get-ComputerRestorePoint -ErrorAction Stop |
                        Sort-Object -Property CreationTime -Descending |
                        Select-Object -First 1

                    if ($newRestorePoint.Description -eq $Description) {
                        Write-Host '[*] Restore Point Details:' -ForegroundColor Cyan
                        Write-Host "  Sequence Number: $($newRestorePoint.SequenceNumber)" -ForegroundColor White
                        Write-Host ("  Created:" +
                            "$($newRestorePoint.CreationTime.ToString('yyyy-MM-dd HH:mm:ss'))") -ForegroundColor White
                        Write-Host "  Description: $($newRestorePoint.Description)" -ForegroundColor White
                    }
                }
                catch {
                    Write-Host "[-] Failed to create restore point: $_" -ForegroundColor Red

                    # Check for common issues
                    if ($_.Exception.Message -like '*frequency*') {
                        Write-Host ('[!] NOTE: Windows limits restore point' +
                            'creation to once every 24 hours by default.') -ForegroundColor Yellow
                        Write-Host ('[!] To change this, modify registry: HKLM\SOFTWARE\Microsoft\Windows NT\' +
                            'CurrentVersion\SystemRestore\SystemRestorePointCreationFrequency') -ForegroundColor Yellow
                    }

                    return 1
                }
            }

            'Verify' {
                Write-Host '[*] Verifying restore points...' -ForegroundColor Yellow

                try {
                    $restorePoints = Get-ComputerRestorePoint -ErrorAction Stop

                    if ($restorePoints) {
                        $issues = @()

                        foreach ($rp in $restorePoints) {
                            # Check if restore point is too old
                            $age = ((Get-Date) - $rp.CreationTime).Days

                            if ($age -gt 90) {
                                $issues += "Restore point '$($rp.Description)' is $age days old"
                            }
                        }

                        # Check frequency
                        $recentCount = @($restorePoints |
                                Where-Object { $_.CreationTime -gt (Get-Date).AddDays(-30) }).Count

                        Write-Host '[*] Verification Results:' -ForegroundColor Cyan
                        Write-Host "  Total Restore Points: $(@($restorePoints).Count)" -ForegroundColor White
                        $fgColor = if ($recentCount -gt 0) { 'Green' } else { 'Yellow' }
                        Write-Host "  Created in Last 30 Days: $recentCount" -ForegroundColor $fgColor

                        if ($issues.Count -gt 0) {
                            Write-Host '[!] Issues Found:' -ForegroundColor Yellow
                            foreach ($issue in $issues) {
                                Write-Host "  - $issue" -ForegroundColor Yellow
                            }
                        }
                        else {
                            Write-Host '[+] No issues found' -ForegroundColor Green
                        }
                    }
                    else {
                        Write-Host '[-] WARNING: No restore points found' -ForegroundColor Red
                        Write-Host '[!] Recommendation: Create a restore point' -ForegroundColor Yellow
                    }
                }
                catch {
                    Write-Host "[-] Verification failed: $_" -ForegroundColor Red
                    return 1
                }
            }

            'Cleanup' {
                Write-Host ("[*] Cleaning up old restore points" +
                    "(retention: $RetentionDays days)...") -ForegroundColor Yellow

                try {
                    $restorePoints = Get-ComputerRestorePoint -ErrorAction Stop
                    $cutoffDate = (Get-Date).AddDays(-$RetentionDays)

                    $oldRestorePoints = @($restorePoints | Where-Object { $_.CreationTime -lt $cutoffDate })

                    if ($oldRestorePoints.Count -gt 0) {
                        Write-Host ("[*] Found $($oldRestorePoints.Count)" +
                            "restore point(s) past retention") -ForegroundColor Cyan

                        if (-not $Force) {
                            Write-Host '[!] Restore points past retention:' -ForegroundColor Yellow
                            $oldRestorePoints | ForEach-Object {
                                Write-Host ("  - $($_.CreationTime.ToString('yyyy-MM-dd HH:mm'))" +
                                    "- $($_.Description)") -ForegroundColor Gray
                            }

                            $confirmation = Read-Host 'Proceed with removal review? (Y/N)'
                            if ($confirmation -ne 'Y') {
                                Write-Host '[!] Operation cancelled' -ForegroundColor Yellow
                                return 0
                            }
                        }

                        # Remove old restore points using VSSAdmin
                        Write-Host '[*] Inspecting shadow copies via vssadmin...' -ForegroundColor Yellow

                        # Note: Windows doesn't provide a direct PowerShell method to remove specific restore points.
                        # We inspect shadow copies with vssadmin through a thin wrapper (mock seam for tests).
                        $vssExitCode = Invoke-VssAdmin -VssAdminArgs @('list', 'shadows')
                        if ($vssExitCode -ne 0) {
                            Write-Host ("[!] vssadmin list shadows" +
                                "returned exit code $vssExitCode") -ForegroundColor Yellow
                        }

                        Write-Host ('[!] Note: Individual restore point removal' +
                            'requires manual deletion or using Disk Cleanup') -ForegroundColor Yellow
                        Write-Host ("[*] Alternatively, you can use:" +
                            "vssadmin Delete Shadows /For=C: /Oldest") -ForegroundColor Cyan
                        Write-Host ('[*] Or configure System Protection to use less' +
                            'disk space, which will auto-delete oldest points') -ForegroundColor Cyan

                        Write-Host '[*] To clean up using Disk Cleanup:' -ForegroundColor Cyan
                        Write-Host '  1. Run: cleanmgr /sageset:1' -ForegroundColor White
                        Write-Host "  2. Select 'System Restore and Shadow Copies'" -ForegroundColor White
                        Write-Host '  3. Run: cleanmgr /sagerun:1' -ForegroundColor White
                    }
                    else {
                        # Idempotent: nothing past retention, no action needed.
                        Write-Host '[+] No old restore points to remove' -ForegroundColor Green
                    }
                }
                catch {
                    Write-Host "[-] Cleanup failed: $_" -ForegroundColor Red
                    return 1
                }
            }

            'Remove' {
                Write-Host '[*] Restore Point Removal' -ForegroundColor Yellow
                Write-Host ('[!] Direct removal of individual' +
                    'restore points is limited in PowerShell.') -ForegroundColor Yellow
                Write-Host '[*] Options:' -ForegroundColor Cyan
                Write-Host '  1. Use Disk Cleanup (cleanmgr)' -ForegroundColor White
                Write-Host '  2. Use vssadmin to delete all shadows for a volume' -ForegroundColor White
                Write-Host '  3. Disable and re-enable System Protection (removes all)' -ForegroundColor White
                Write-Host '[*] Example: vssadmin Delete Shadows /For=C: /Oldest' -ForegroundColor Cyan
            }
        }

        Write-Host '[+] Operation complete' -ForegroundColor Green
        return 0
    }
    catch {
        Write-Host "[-] Error: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
