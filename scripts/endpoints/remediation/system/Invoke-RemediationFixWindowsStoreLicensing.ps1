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

    # Reset Store license cache using the documented sequence (MS Learn:
    # "Rebuild the tokens.dat file"): stop ClipSVC, delete tokens.dat from
    # %ProgramData% (the only documented location), restart ClipSVC so it
    # rebuilds the file. Deleting while ClipSVC is running can corrupt the
    # licensing state.
    $storeService = Get-Service -Name "ClipSVC" -ErrorAction SilentlyContinue

    if ($storeService -and $storeService.Status -eq "Running") {
        try {
            Stop-Service -Name "ClipSVC" -Force -ErrorAction Stop
            $remediationActions += "Stopped Client License Service (ClipSVC)"
        }
        catch {
            Write-Host "Warning: Could not stop ClipSVC: $_"
        }
    }

    $tokensPath = "$env:ProgramData\Microsoft\Windows\ClipSVC\tokens.dat"

    if (Test-Path $tokensPath) {
        try {
            Remove-Item -Path $tokensPath -Force -ErrorAction Stop
            $remediationActions += "Removed Store licensing cache: $tokensPath"
        }
        catch {
            Write-Host "Warning: Could not remove licensing cache: $_"
        }
    }

    # Restart Client License Service - it rebuilds tokens.dat on startup
    if ($storeService) {
        try {
            Start-Service -Name "ClipSVC" -ErrorAction Stop
            Start-Sleep -Seconds 2
            $remediationActions += "Started Client License Service (ClipSVC)"
        }
        catch {
            Write-Host "Warning: Could not start ClipSVC: $_"
        }
    }

    # Re-register Store app
    try {
        $storeApp = Get-AppxPackage -Name "Microsoft.WindowsStore" -AllUsers -ErrorAction SilentlyContinue

        if ($storeApp) {
            Add-AppxPackage -DisableDevelopmentMode -Register "$($storeApp.InstallLocation)\AppXManifest.xml" -ErrorAction SilentlyContinue
            $remediationActions += "Re-registered Microsoft Store app"
        }
    }
    catch {
        Write-Host "Note: Could not re-register Store app: $_"
    }

    # Reset Windows Store cache using wsreset
    try {
        Start-Process "wsreset.exe" -WindowStyle Hidden -ErrorAction SilentlyContinue
        $remediationActions += "Reset Windows Store cache"
    }
    catch {
        Write-Host "Note: Could not run wsreset: $_"
    }

    if ($remediationActions.Count -gt 0) {
        Write-Host "Windows Store licensing remediation completed:"
        foreach ($action in $remediationActions) {
            Write-Host "  - $action"
        }
        Write-Host ""
        Write-Host "Note: Users may need to sign out and back in for changes to take effect"
    }
    else {
        Write-Host "No Store licensing remediation was necessary"
    }

    exit 0

}
catch {
    Write-Host "Error during Windows Store licensing remediation: $_"
    exit 1
}
