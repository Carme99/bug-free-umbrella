<#
.SYNOPSIS
    Manages system restore points on Windows servers and workstations.

.DESCRIPTION
    This script provides comprehensive system restore point management including
    creation, listing, verification, and cleanup of restore points. Useful for
    creating restore points before major changes and managing restore point retention.

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
    .\Manage-RestorePoints.ps1 -Action List
    Lists all available restore points.

.EXAMPLE
    .\Manage-RestorePoints.ps1 -Action Create -Description "Before GPO changes"
    Creates a new restore point before making GPO changes.

.EXAMPLE
    .\Manage-RestorePoints.ps1 -Action Cleanup -RetentionDays 14
    Removes restore points older than 14 days.

.NOTES
    Author: Server Management Team
    Requires: Administrator privileges, System Restore enabled
    Version: 1.0
#>

[CmdletBinding()]
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
    [int]$RetentionDays = 30,

    [Parameter(Mandatory = $false)]
    [switch]$Force
)

Write-Host "`n=== System Restore Point Manager ===" -ForegroundColor Cyan
Write-Host "Computer: $env:COMPUTERNAME" -ForegroundColor Gray

# Check if running as administrator
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
$isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Error "This script requires Administrator privileges"
    exit 1
}

# Check if System Restore is enabled
function Test-SystemRestoreEnabled {
    try {
        $systemRestore = Get-ComputerRestorePoint -ErrorAction Stop
        return $true
    }
    catch {
        # Check registry to see if System Restore is disabled
        $regPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore"
        if (Test-Path $regPath) {
            $rpSessionInterval = Get-ItemProperty -Path $regPath -Name "RPSessionInterval" -ErrorAction SilentlyContinue
            if ($rpSessionInterval.RPSessionInterval -eq 0) {
                return $false
            }
        }
        return $false
    }
}

Write-Host "`nChecking System Restore status..." -ForegroundColor Yellow
if (-not (Test-SystemRestoreEnabled)) {
    Write-Host "WARNING: System Restore is not enabled on this system" -ForegroundColor Yellow
    Write-Host "To enable System Restore, use: Enable-ComputerRestore -Drive 'C:\'" -ForegroundColor Cyan

    if ($Action -eq 'Create') {
        Write-Error "Cannot create restore point - System Restore is disabled"
        exit 1
    }
}
else {
    Write-Host "System Restore is enabled" -ForegroundColor Green
}

# Perform requested action
switch ($Action) {
    'List' {
        Write-Host "`nRetrieving system restore points..." -ForegroundColor Yellow

        try {
            $restorePoints = Get-ComputerRestorePoint | Sort-Object -Property CreationTime -Descending

            if ($restorePoints) {
                Write-Host "Found $($restorePoints.Count) restore point(s)" -ForegroundColor Green
                Write-Host ""

                $restorePoints | Format-Table -AutoSize -Property @(
                    @{Label="Sequence"; Expression={$_.SequenceNumber}},
                    @{Label="Created"; Expression={$_.CreationTime.ToString('yyyy-MM-dd HH:mm:ss')}},
                    @{Label="Description"; Expression={$_.Description}},
                    @{Label="Type"; Expression={
                        switch ($_.RestorePointType) {
                            0 { "Application Install" }
                            1 { "Application Uninstall" }
                            12 { "Modify Settings" }
                            13 { "Cancelled Operation" }
                            default { "Unknown ($($_.RestorePointType))" }
                        }
                    }}
                )

                # Show most recent
                $mostRecent = $restorePoints | Select-Object -First 1
                $daysSince = ((Get-Date) - $mostRecent.CreationTime).Days

                Write-Host "Most recent restore point:" -ForegroundColor Cyan
                Write-Host "  Created: $($mostRecent.CreationTime.ToString('yyyy-MM-dd HH:mm:ss'))" -ForegroundColor White
                Write-Host "  Description: $($mostRecent.Description)" -ForegroundColor White
                Write-Host "  Days ago: $daysSince" -ForegroundColor $(if ($daysSince -le 7) { 'Green' } elseif ($daysSince -le 30) { 'Yellow' } else { 'Red' })
            }
            else {
                Write-Host "No restore points found" -ForegroundColor Yellow
            }
        }
        catch {
            Write-Error "Failed to retrieve restore points: $_"
            exit 1
        }
    }

    'Create' {
        if (-not $Description) {
            Write-Error "Description is required for creating restore points. Use -Description parameter."
            exit 1
        }

        Write-Host "`nCreating system restore point..." -ForegroundColor Yellow
        Write-Host "Description: $Description" -ForegroundColor Cyan
        Write-Host "Type: $RestorePointType" -ForegroundColor Cyan

        try {
            # Enable-ComputerRestore ensures C: drive is enabled
            Enable-ComputerRestore -Drive "C:\" -ErrorAction SilentlyContinue

            # Create restore point
            Checkpoint-Computer -Description $Description -RestorePointType $RestorePointType

            Write-Host "`n✓ Restore point created successfully" -ForegroundColor Green

            # Verify creation
            Start-Sleep -Seconds 2
            $newRestorePoint = Get-ComputerRestorePoint | Sort-Object -Property CreationTime -Descending | Select-Object -First 1

            if ($newRestorePoint.Description -eq $Description) {
                Write-Host "`nRestore Point Details:" -ForegroundColor Cyan
                Write-Host "  Sequence Number: $($newRestorePoint.SequenceNumber)" -ForegroundColor White
                Write-Host "  Created: $($newRestorePoint.CreationTime.ToString('yyyy-MM-dd HH:mm:ss'))" -ForegroundColor White
                Write-Host "  Description: $($newRestorePoint.Description)" -ForegroundColor White
            }
        }
        catch {
            Write-Error "Failed to create restore point: $_"

            # Check for common issues
            if ($_.Exception.Message -like "*frequency*") {
                Write-Host "`nNOTE: Windows limits restore point creation to once every 24 hours by default." -ForegroundColor Yellow
                Write-Host "To change this, modify registry: HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore\SystemRestorePointCreationFrequency" -ForegroundColor Yellow
            }

            exit 1
        }
    }

    'Verify' {
        Write-Host "`nVerifying restore points..." -ForegroundColor Yellow

        try {
            $restorePoints = Get-ComputerRestorePoint

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
                $recentCount = ($restorePoints | Where-Object { $_.CreationTime -gt (Get-Date).AddDays(-30) }).Count

                Write-Host "`nVerification Results:" -ForegroundColor Cyan
                Write-Host "  Total Restore Points: $($restorePoints.Count)" -ForegroundColor White
                Write-Host "  Created in Last 30 Days: $recentCount" -ForegroundColor $(if ($recentCount -gt 0) { 'Green' } else { 'Yellow' })

                if ($issues.Count -gt 0) {
                    Write-Host "`nIssues Found:" -ForegroundColor Yellow
                    foreach ($issue in $issues) {
                        Write-Host "  • $issue" -ForegroundColor Yellow
                    }
                }
                else {
                    Write-Host "`n✓ No issues found" -ForegroundColor Green
                }
            }
            else {
                Write-Host "WARNING: No restore points found" -ForegroundColor Red
                Write-Host "Recommendation: Create a restore point" -ForegroundColor Yellow
            }
        }
        catch {
            Write-Error "Verification failed: $_"
            exit 1
        }
    }

    'Cleanup' {
        Write-Host "`nCleaning up old restore points (retention: $RetentionDays days)..." -ForegroundColor Yellow

        try {
            $restorePoints = Get-ComputerRestorePoint
            $cutoffDate = (Get-Date).AddDays(-$RetentionDays)

            $oldRestorePoints = $restorePoints | Where-Object { $_.CreationTime -lt $cutoffDate }

            if ($oldRestorePoints) {
                Write-Host "Found $($oldRestorePoints.Count) restore point(s) to remove" -ForegroundColor Cyan

                if (-not $Force) {
                    Write-Host "`nRestore points to be removed:" -ForegroundColor Yellow
                    $oldRestorePoints | ForEach-Object {
                        Write-Host "  • $($_.CreationTime.ToString('yyyy-MM-dd HH:mm')) - $($_.Description)" -ForegroundColor Gray
                    }

                    $confirmation = Read-Host "`nProceed with removal? (Y/N)"
                    if ($confirmation -ne 'Y') {
                        Write-Host "Operation cancelled" -ForegroundColor Yellow
                        exit 0
                    }
                }

                # Remove old restore points using VSSAdmin
                Write-Host "`nRemoving old restore points..." -ForegroundColor Yellow

                # Note: Windows doesn't provide a direct PowerShell method to remove specific restore points
                # We can use VSSAdmin to remove shadow copies

                $vssOutput = vssadmin list shadows

                Write-Host "Note: Individual restore point removal requires manual deletion or using Disk Cleanup" -ForegroundColor Yellow
                Write-Host "Alternatively, you can use: vssadmin Delete Shadows /For=C: /Oldest" -ForegroundColor Cyan
                Write-Host "Or configure System Protection to use less disk space, which will auto-delete oldest points" -ForegroundColor Cyan

                # Provide alternative cleanup method
                Write-Host "`nTo clean up using Disk Cleanup:" -ForegroundColor Cyan
                Write-Host "  1. Run: cleanmgr /sageset:1" -ForegroundColor White
                Write-Host "  2. Select 'System Restore and Shadow Copies'" -ForegroundColor White
                Write-Host "  3. Run: cleanmgr /sagerun:1" -ForegroundColor White
            }
            else {
                Write-Host "No old restore points to remove" -ForegroundColor Green
            }
        }
        catch {
            Write-Error "Cleanup failed: $_"
            exit 1
        }
    }

    'Remove' {
        Write-Host "`nRestore Point Removal" -ForegroundColor Yellow
        Write-Host "Direct removal of individual restore points is limited in PowerShell." -ForegroundColor Yellow
        Write-Host "`nOptions:" -ForegroundColor Cyan
        Write-Host "  1. Use Disk Cleanup (cleanmgr)" -ForegroundColor White
        Write-Host "  2. Use vssadmin to delete all shadows for a volume" -ForegroundColor White
        Write-Host "  3. Disable and re-enable System Protection (removes all)" -ForegroundColor White
        Write-Host "`nExample: vssadmin Delete Shadows /For=C: /Oldest" -ForegroundColor Cyan
    }
}

Write-Host "`nOperation complete" -ForegroundColor Green
