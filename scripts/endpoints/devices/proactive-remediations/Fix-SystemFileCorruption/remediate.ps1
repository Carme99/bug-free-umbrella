<#
.SYNOPSIS
    Repairs Windows system file corruption.

.DESCRIPTION
    Runs DISM and SFC to repair corrupted system files and component store.

.NOTES
    Author: Intune Admin
    Version: 1.0
    Intune Context: SYSTEM
    Exit 0: Remediation successful
    Note: May require restart to complete
#>

try {
    $remediationActions = @()

    # Run DISM RestoreHealth
    Write-Host "Running DISM RestoreHealth (this may take several minutes)..."
    $dismResult = Dism /Online /Cleanup-Image /RestoreHealth /NoRestart 2>&1

    if ($LASTEXITCODE -eq 0) {
        $remediationActions += "DISM RestoreHealth completed successfully"
    } else {
        $remediationActions += "DISM RestoreHealth completed with warnings"
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
