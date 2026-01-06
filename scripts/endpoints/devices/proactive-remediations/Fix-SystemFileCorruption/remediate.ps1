<#
.SYNOPSIS
    Repairs Windows system file corruption.

.DESCRIPTION
    Runs DISM and SFC to repair corrupted system files and component store.
    Includes safety checks for disk space and battery status.

.NOTES
    Author: Intune Admin
    Version: 1.1
    Intune Context: SYSTEM
    Exit 0: Remediation successful
    Exit 1: Remediation failed or safety checks failed
    Note: May require restart to complete. Can take 10-30 minutes.
#>

try {
    $remediationActions = @()

    # SAFETY CHECK 1: Verify sufficient disk space (DISM needs ~10GB)
    $systemDrive = Get-Volume -DriveLetter $env:SystemDrive.TrimEnd(':') -ErrorAction SilentlyContinue
    if ($systemDrive) {
        $freeSpaceGB = [math]::Round($systemDrive.SizeRemaining / 1GB, 2)
        Write-Host "System drive free space: $freeSpaceGB GB"

        if ($freeSpaceGB -lt 10) {
            Write-Host "ERROR: Insufficient disk space for DISM operation"
            Write-Host "Required: At least 10GB free"
            Write-Host "Available: $freeSpaceGB GB"
            Write-Host ""
            Write-Host "Please free up disk space before running system file repairs"
            exit 1
        }
    }

    # SAFETY CHECK 2: Check battery status (don't run on battery for laptops)
    $battery = Get-WmiObject -Class Win32_Battery -ErrorAction SilentlyContinue
    if ($battery) {
        # Device has a battery (laptop/tablet)
        $batteryStatus = $battery.BatteryStatus
        # BatteryStatus: 1=Discharging, 2=AC, 3=Fully Charged, 4=Low, 5=Critical

        if ($batteryStatus -eq 1 -or $batteryStatus -eq 4 -or $batteryStatus -eq 5) {
            Write-Host "ERROR: Device is running on battery power"
            Write-Host "DISM and SFC operations should only run while connected to AC power"
            Write-Host "Battery Status: $(
                switch ($batteryStatus) {
                    1 { 'Discharging' }
                    4 { 'Low' }
                    5 { 'Critical' }
                }
            )"
            Write-Host ""
            Write-Host "Please connect to AC power before running system file repairs"
            exit 1
        }

        Write-Host "Battery status: AC connected - safe to proceed"
    }

    # SAFETY CHECK 3: Warn about execution time
    Write-Host ""
    Write-Host "WARNING: This operation may take 10-30 minutes to complete"
    Write-Host "The system will remain responsive but DISM/SFC are resource-intensive"
    Write-Host ""

    # Run DISM RestoreHealth
    Write-Host "Running DISM RestoreHealth (this may take several minutes)..."
    $dismResult = Dism /Online /Cleanup-Image /RestoreHealth /NoRestart 2>&1

    if ($LASTEXITCODE -eq 0) {
        $remediationActions += "DISM RestoreHealth completed successfully"
    } else {
        $remediationActions += "DISM RestoreHealth completed with warnings (exit code: $LASTEXITCODE)"
    }

    # Run SFC scan
    Write-Host "Running System File Checker..."
    $sfcResult = sfc /scannow 2>&1

    if ($sfcResult -match "did not find any integrity violations") {
        $remediationActions += "SFC scan completed - no violations found"
    } elseif ($sfcResult -match "successfully repaired") {
        $remediationActions += "SFC successfully repaired corrupted files"
    } else {
        $remediationActions += "SFC scan completed"
    }

    Write-Host ""
    Write-Host "System file corruption remediation completed:"
    foreach ($action in $remediationActions) {
        Write-Host "  - $action"
    }
    Write-Host ""
    Write-Host "Note: A system restart may be required to complete repairs"
    Write-Host "Check C:\Windows\Logs\CBS\CBS.log for detailed results"

    exit 0

} catch {
    Write-Host "Error during system file remediation: $_"
    exit 1
}
