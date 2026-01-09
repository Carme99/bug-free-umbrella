<#
.SYNOPSIS
    Repairs Windows Store licensing issues.

.DESCRIPTION
    Resets Windows Store license cache and re-registers Store apps.
    This can fix issues with apps not launching or updating.

.NOTES
    Author: Intune Admin
    Version: 1.0
    Intune Context: SYSTEM
    Exit 0: Remediation successful
#>

try {
    $remediationActions = @()

    # Ensure Client License Service is started
    $storeService = Get-Service -Name "ClipSVC" -ErrorAction SilentlyContinue

    if ($storeService) {
        if ($storeService.Status -ne "Running") {
            try {
                Start-Service -Name "ClipSVC" -ErrorAction Stop
                $remediationActions += "Started Client License Service (ClipSVC)"
            } catch {
                Write-Host "Warning: Could not start ClipSVC: $_"
            }
        }
    }

    # Reset Store license cache
    $licensingPaths = @(
        "$env:ProgramData\Microsoft\Windows\ClipSVC\tokens.dat",
        "$env:LOCALAPPDATA\Microsoft\Windows\ClipSVC\tokens.dat"
    )

    foreach ($path in $licensingPaths) {
        if (Test-Path $path) {
            try {
                Remove-Item -Path $path -Force -ErrorAction Stop
                $remediationActions += "Removed Store licensing cache: $path"
            } catch {
                Write-Host "Warning: Could not remove licensing cache: $_"
            }
        }
    }

    # Restart Client License Service to rebuild cache
    if ($storeService -and $storeService.Status -eq "Running") {
        Restart-Service -Name "ClipSVC" -Force -ErrorAction SilentlyContinue
        $remediationActions += "Restarted Client License Service"
    }

    # Re-register Store app
    try {
        $storeApp = Get-AppxPackage -Name "Microsoft.WindowsStore" -AllUsers -ErrorAction SilentlyContinue

        if ($storeApp) {
            Add-AppxPackage -DisableDevelopmentMode -Register "$($storeApp.InstallLocation)\AppXManifest.xml" -ErrorAction SilentlyContinue
            $remediationActions += "Re-registered Microsoft Store app"
        }
    } catch {
        Write-Host "Note: Could not re-register Store app: $_"
    }

    # Reset Windows Store cache using wsreset
    try {
        Start-Process "wsreset.exe" -WindowStyle Hidden -ErrorAction SilentlyContinue
        $remediationActions += "Reset Windows Store cache"
    } catch {
        Write-Host "Note: Could not run wsreset: $_"
    }

    if ($remediationActions.Count -gt 0) {
        Write-Host "Windows Store licensing remediation completed:"
        foreach ($action in $remediationActions) {
            Write-Host "  - $action"
        }
        Write-Host ""
        Write-Host "Note: Users may need to sign out and back in for changes to take effect"
    } else {
        Write-Host "No Store licensing remediation was necessary"
    }

    exit 0

} catch {
    Write-Host "Error during Windows Store licensing remediation: $_"
    exit 1
}
