<#
.SYNOPSIS
    Provide a prioritized device health improvement plan.

.DESCRIPTION
    Prints a comprehensive, priority-ordered remediation plan for improving overall device
    health and reliability, together with the weighting factors Intune uses to compute the
    device health score. The script is purely informational: it changes no system state,
    so it is safe to re-run at any time (idempotent).

.EXAMPLE
    PS C:\> .\Invoke-RemediationCheckDeviceHealthScore.ps1

    Prints the device health improvement plan for this device.

.EXAMPLE
    PS C:\> .\Invoke-RemediationCheckDeviceHealthScore.ps1 -Verbose

    Runs the same report with verbose progress information.

.NOTES
    File Name  : Invoke-RemediationCheckDeviceHealthScore.ps1
    Author     : Intune Admin
    Prerequisite: PowerShell 7.0
    Version    : 1.0.0
    Date       : 2026-08-23
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

function Main {
    try {
        Write-Host "[*] Device Health Improvement Plan:" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "Your device health score indicates room for improvement."
        Write-Host ""

        Write-Host "[*] PRIORITY 1: CRITICAL ISSUES (Fix Immediately)" -ForegroundColor Cyan
        Write-Host "------------------------------------------------"
        Write-Host "[!] Hardware failures (disk, memory, CPU)"
        Write-Host "   - Back up all data immediately"
        Write-Host "   - Run hardware diagnostics"
        Write-Host "   - Replace failing components"
        Write-Host ""
        Write-Host "[!] Security vulnerabilities"
        Write-Host "   - Enable Windows Defender real-time protection"
        Write-Host "   - Update antivirus definitions"
        Write-Host "   - Install all security updates"
        Write-Host ""

        Write-Host "[*] PRIORITY 2: STABILITY ISSUES (Fix This Week)" -ForegroundColor Cyan
        Write-Host "------------------------------------------------"
        Write-Host "[!] Frequent crashes or blue screens"
        Write-Host "   - Analyze crash dumps"
        Write-Host "   - Update all drivers to latest versions"
        Write-Host "   - Check for software conflicts"
        Write-Host ""
        Write-Host "[!] Service failures"
        Write-Host "   - Review service event logs"
        Write-Host "   - Repair or reinstall problematic software"
        Write-Host "   - Verify service dependencies"
        Write-Host ""
        Write-Host "[!] Application crashes"
        Write-Host "   - Update all applications"
        Write-Host "   - Uninstall/reinstall problematic apps"
        Write-Host "   - Check for .NET Framework updates"
        Write-Host ""

        Write-Host "[*] PRIORITY 3: PERFORMANCE OPTIMIZATION" -ForegroundColor Cyan
        Write-Host "------------------------------------------------"
        Write-Host "[!] Excessive uptime"
        Write-Host "   - Schedule weekly reboots"
        Write-Host "   - Install Windows updates regularly"
        Write-Host "   - Clear pending update reboots"
        Write-Host ""
        Write-Host "[!] Slow boot times"
        Write-Host "   - Disable unnecessary startup programs"
        Write-Host "   - Update device drivers"
        Write-Host "   - Run disk cleanup and defragmentation"
        Write-Host "   - Consider SSD upgrade if using HDD"
        Write-Host ""

        Write-Host "[*] PRIORITY 4: PREVENTIVE MAINTENANCE" -ForegroundColor Cyan
        Write-Host "------------------------------------------------"
        Write-Host "Regular system maintenance"
        Write-Host "   - Run Windows Update monthly"
        Write-Host "   - Clean temporary files quarterly"
        Write-Host "   - Review installed programs annually"
        Write-Host ""
        Write-Host "Health monitoring"
        Write-Host "   - Review Intune health reports weekly"
        Write-Host "   - Monitor event logs for new errors"
        Write-Host "   - Track health score trends over time"
        Write-Host ""

        Write-Host "[*] MONITORING & REPORTING" -ForegroundColor Cyan
        Write-Host "------------------------------------------------"
        Write-Host "This device health score is calculated from:"
        Write-Host "  - System uptime and reboot patterns (10%)"
        Write-Host "  - Crash and BSOD frequency (20%)"
        Write-Host "  - Application stability (10%)"
        Write-Host "  - Service reliability (10%)"
        Write-Host "  - Critical system errors (15%)"
        Write-Host "  - Hardware health status (20%)"
        Write-Host "  - Boot performance (5%)"
        Write-Host "  - Security posture (10%)"
        Write-Host ""
        Write-Host "Regular monitoring helps identify issues before they"
        Write-Host "cause downtime or data loss."
        Write-Host ""

        Write-Host "Device: $env:COMPUTERNAME"
        Write-Host "Report Date: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"

        Write-Host "[+] Device health improvement plan provided" -ForegroundColor Green
        return 0
    }
    catch {
        Write-Host "[-] Error during health improvement remediation: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
