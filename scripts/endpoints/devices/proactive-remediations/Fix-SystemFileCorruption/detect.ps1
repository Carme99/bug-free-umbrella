<#
.SYNOPSIS
    Detects Windows system file corruption.

.DESCRIPTION
    Checks for corrupted system files using SFC scan results and component
    store health status.

.NOTES
    Author: Intune Admin
    Version: 1.0
    Intune Context: SYSTEM
    Exit 0: No corruption detected
    Exit 1: Corruption found
#>

try {
    $issues = @()

    # Check component store health using DISM
    Write-Host "Checking component store health (this may take a few minutes)..."
    $dismResult = Dism /Online /Cleanup-Image /ScanHealth 2>&1

    if ($dismResult -match "The component store is repairable") {
        $issues += "Component store corruption detected (repairable)"
    } elseif ($dismResult -match "The component store corruption was detected") {
        $issues += "Component store corruption detected"
    }

    # Check for recent SFC scan results in CBS log
    $cbsLog = "$env:SystemRoot\Logs\CBS\CBS.log"
    if (Test-Path $cbsLog) {
        $recentLog = Get-Content $cbsLog -Tail 500 -ErrorAction SilentlyContinue
        if ($recentLog -match "found corrupt files" -or $recentLog -match "verification failed") {
            $issues += "SFC detected corrupted files in recent scan"
        }
    }

    if ($issues.Count -gt 0) {
        Write-Host "System file corruption detected:"
        foreach ($issue in $issues) {
            Write-Host "  - $issue"
        }
        exit 1
    }

    Write-Host "No system file corruption detected"
    exit 0

} catch {
    Write-Host "Error checking system file integrity: $_"
    exit 1
}
