<#
.SYNOPSIS
    Detect devices that have not been restarted for 4 or more days.

.DESCRIPTION
    Checks the OS uptime (time since last restart, derived from Win32_OperatingSystem.LastBootUpTime
    via Get-ComputerInfo) and exits 1 when the device has not been restarted for 4 or more days so the
    uptime/remediate.ps1 restart notification can run. Sleep/hibernate time does not count towards
    uptime; this measures time since last restart, not cumulative powered-on time.
    Errors default to compliant (exit 0) to avoid false positives.
    Exit codes: 0 = restarted within 4 days, or uptime could not be determined (compliant);
    1 = not restarted for 4 or more days (non-compliant, triggers remediation).

.EXAMPLE
    PS C:\> .\detect.ps1

    Runs the uptime check; exits 1 when the device has not been restarted for 4+ days.

.EXAMPLE
    PS C:\> pwsh -NoProfile -File .\detect.ps1; $LASTEXITCODE

    Runs the check in a clean process and surfaces the documented exit code.

.NOTES
    File Name  : detect.ps1
    Author     : Intune / Proactive Remediations
    Prerequisite: PowerShell 7.0
    Version    : 1.0.0
    Date       : 2026-08-23
#>

[CmdletBinding()]
param()

# PSAvoidUsingWriteHost is intentionally accepted: prefixed, colored console output is the mandated
# output convention of docs/RELAUNCH-SPEC.md section 3.
$ErrorActionPreference = 'Stop'

function Get-RestartAge {
    [CmdletBinding()]
    [OutputType([int])]
    param()

    # OSUptime derives from Win32_OperatingSystem.LastBootUpTime, i.e. time since the OS was last
    # restarted. Sleep/hibernate time does not count.
    # See https://learn.microsoft.com/en-us/windows/win32/cimwin32prov/win32-operatingsystem
    $uptime = (Get-ComputerInfo -ErrorAction Stop).OsUptime
    return [math]::Floor($uptime.TotalDays)
}

function Main {
    [CmdletBinding()]
    [OutputType([int])]
    param()
    try {
        Write-Host '[*] Checking time since last restart...' -ForegroundColor Cyan
        $uptimeDays = Get-RestartAge

        if ($uptimeDays -ge 4) {
            Write-Host "[!] Device has not been restarted in $uptimeDays days. Needs restart." -ForegroundColor Yellow
            return 1
        }

        Write-Host "[+] Device has been restarted within the last $uptimeDays day(s). No action needed." `
            -ForegroundColor Green
        return 0
    }
    catch {
        # Compliant by default on error (no false positives).
        Write-Host "[!] Failed to get uptime: $($_.Exception.Message). Defaulting to compliant." -ForegroundColor Yellow
        return 0
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
