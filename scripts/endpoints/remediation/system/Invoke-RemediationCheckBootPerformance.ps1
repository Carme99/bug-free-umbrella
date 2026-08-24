<#
.SYNOPSIS
    Report boot performance optimization recommendations.

.DESCRIPTION
    Prints prioritized recommendations for improving device boot times, covering startup
    program overhead, driver currency, disk health, Fast Startup, system cleanup and
    malware scanning. The script is purely informational: it reads no protected state and
    changes no system state, so it is safe to re-run at any time (idempotent).

.EXAMPLE
    PS C:\> .\Invoke-RemediationCheckBootPerformance.ps1

    Prints the boot performance optimization recommendations for this device.

.EXAMPLE
    PS C:\> .\Invoke-RemediationCheckBootPerformance.ps1 -Verbose

    Runs the same report with verbose progress information.

.NOTES
    File Name  : Invoke-RemediationCheckBootPerformance.ps1
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
        Write-Host "[*] Boot Performance Remediation:" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "Slow boot times impact user productivity."
        Write-Host ""
        Write-Host "[*] Optimization recommendations:" -ForegroundColor Cyan
        Write-Host ""

        Write-Host "1. Disable unnecessary startup programs"
        Write-Host "   - Open Task Manager > Startup tab"
        Write-Host "   - Disable programs not needed at startup"
        Write-Host ""

        Write-Host "2. Update device drivers"
        Write-Host "   - Use Windows Update for driver updates"
        Write-Host "   - Check manufacturer website for latest drivers"
        Write-Host ""

        Write-Host "3. Check disk health"
        Write-Host "   - Run: chkdsk /f /r (requires reboot)"
        Write-Host "   - Consider SSD upgrade if using HDD"
        Write-Host ""

        Write-Host "4. Enable Fast Startup (if not enabled)"
        Write-Host "   - Control Panel > Power Options > Choose what power buttons do"
        Write-Host "   - Enable 'Turn on fast startup'"
        Write-Host ""

        Write-Host "5. Clean up system"
        Write-Host "   - Run Disk Cleanup"
        Write-Host "   - Remove temp files and old Windows installations"
        Write-Host ""

        Write-Host "6. Check for malware"
        Write-Host "   - Run full Windows Defender scan"
        Write-Host ""

        Write-Host "[!] Device flagged for boot performance review." -ForegroundColor Yellow
        Write-Host "Device: $env:COMPUTERNAME"
        Write-Host "Report Date: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"

        Write-Host "[+] Boot performance recommendations provided" -ForegroundColor Green
        return 0
    }
    catch {
        Write-Host "[-] Error during boot performance remediation: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
