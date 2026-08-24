<#
.SYNOPSIS
    Provides remediation recommendations for application crash issues.

.DESCRIPTION
    Application crashes require investigation and potential software updates.
    This script logs crash patterns and prints troubleshooting guidance (update
    applications, repair/reinstall, compatibility checks, .NET and Office
    specifics, conflicting software, crash dump review) so IT can analyze
    recurring stability problems flagged by the companion detection script.
    Exit codes: 0 = recommendations provided successfully, 1 = an unexpected
    error occurred while emitting the guidance. The script only writes to the
    console and changes no system state, so re-running it always converges to
    exit 0 (idempotent).

.EXAMPLE
    PS C:\> .\Invoke-RemediationCheckApplicationCrashes.ps1
    Prints the application-crash troubleshooting playbook and exits 0.

.EXAMPLE
    PS C:\> & 'C:\Program Files\Intune\ProactiveRemediations\Invoke-RemediationCheckApplicationCrashes.ps1'
    Runs the same guidance from the Intune Management Extension under the SYSTEM context.

.NOTES
    File Name: Invoke-RemediationCheckApplicationCrashes.ps1
    Author: Intune Admin
    Prerequisite: PowerShell 7.0
    Version: 1.0.0
    Date: 2026-08-23

    Companion to Test-RemediationCheckApplicationCrashes.ps1, which flags
    devices whose crash counts exceed the configured maximum.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

function Main {
    try {
        Write-Host "[*] Application Crash Remediation:" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "Frequent application crashes impact productivity."
        Write-Host ""
        Write-Host "Troubleshooting steps:"
        Write-Host ""
        Write-Host "1. Update all applications to latest versions"
        Write-Host "   - Check Windows Update for app updates"
        Write-Host "   - Visit vendor websites for latest releases"
        Write-Host ""
        Write-Host "2. Repair or reinstall problematic applications"
        Write-Host "   - Settings > Apps > Select app > Advanced options > Repair"
        Write-Host "   - If repair fails, uninstall and reinstall"
        Write-Host ""
        Write-Host "3. Check application compatibility"
        Write-Host "   - Right-click executable > Properties > Compatibility"
        Write-Host "   - Try compatibility mode for older apps"
        Write-Host ""
        Write-Host "4. For .NET application errors"
        Write-Host "   - Install latest .NET Framework updates"
        Write-Host "   - Run: DISM /Online /Cleanup-Image /RestoreHealth"
        Write-Host ""
        Write-Host "5. For Office crashes"
        Write-Host "   - Run Office repair: Control Panel > Programs > Microsoft Office"
        Write-Host "   - Disable COM add-ins that may cause issues"
        Write-Host "   - Start in Safe Mode: hold Ctrl while starting Office app"
        Write-Host ""
        Write-Host "6. Check for conflicting software"
        Write-Host "   - Antivirus may block certain app operations"
        Write-Host "   - Third-party DLLs may cause conflicts"
        Write-Host ""
        Write-Host "7. Review crash dumps"
        Write-Host "   - Use WinDbg to analyze dump files"
        Write-Host "   - Look for specific error codes and faulting modules"
        Write-Host ""
        Write-Host "[+] Device flagged for application stability review." -ForegroundColor Green
        Write-Host "Device: $env:COMPUTERNAME"

        return 0
    }
    catch {
        Write-Host "[-] Error during application crash remediation: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
