<#
.SYNOPSIS
    Detects outdated or missing critical drivers.

.DESCRIPTION
    Checks devices with driver problems via Win32_PnPEntity (ConfigManagerErrorCode non-zero) and
    queries Windows Update for available driver updates through the Microsoft.Update.Session COM
    object. A Windows Update failure is tolerated as a warning; device issues still decide.
    Exit codes:
    - 0: healthy - no problem devices and no driver updates offered by Windows Update.
    - 1: non-compliant - driver updates available, problem devices found, or the check failed.

.NOTES
    File Name: Test-RemediationFixOutdatedDrivers.ps1
    Author: Intune Admin
    Prerequisite: PowerShell 7.0
    Version: 1.0.0
    Date: 2026-08-23

.EXAMPLE
    PS C:\> .\Test-RemediationFixOutdatedDrivers.ps1
    Reports driver updates or problem devices and returns 0 when healthy, 1 when remediation needed.

.EXAMPLE
    PS C:\> pwsh -NoProfile -File .\Test-RemediationFixOutdatedDrivers.ps1
    Runs the same detection under the Intune Management Extension SYSTEM context.
#>

[CmdletBinding()]

$ErrorActionPreference = 'Stop'

#region Functions

function Find-DriverUpdate {
    <#
    .SYNOPSIS
        Queries Windows Update for pending driver updates via the COM API (the mock seam for tests).
    #>
    $updateSession = New-Object -ComObject Microsoft.Update.Session
    $updateSearcher = $updateSession.CreateUpdateSearcher()
    return $updateSearcher.Search("IsInstalled=0 and Type='Driver'")
}

function Main {
    try {
        $outputMsg = "[*] Checking driver health..."
        Write-Host $outputMsg -ForegroundColor Cyan

        $issues = @()

        # Check for devices with driver problems
        # PSAvoidUsingWMICmdlet justified: Get-WmiObject kept deliberately to preserve this
        # detection's original runtime behavior on Windows PowerShell-based Intune hosts.
        $problemDevices = Get-WmiObject -Class Win32_PnPEntity -ErrorAction SilentlyContinue |
            Where-Object { $_.ConfigManagerErrorCode -ne 0 }

        if ($problemDevices) {
            foreach ($device in $problemDevices) {
                $issues += "Device with driver issue: $($device.Name) (Error code: $($device.ConfigManagerErrorCode))"
            }
        }

        # Check Windows Update for driver updates
        try {
            $outputMsg = "[*] Searching for driver updates..."
            Write-Host $outputMsg -ForegroundColor Cyan
            $searchResult = Find-DriverUpdate

            if (@($searchResult.Updates).Count -gt 0) {
                $outputMsg = "[!] Driver updates available:"
                Write-Host $outputMsg -ForegroundColor Yellow
                foreach ($update in @($searchResult.Updates)) {
                    Write-Host "- $($update.Title)"
                }
                return 1
            }
        }
        catch {
            $outputMsg = "[!] Could not check Windows Update for drivers: $($_.Exception.Message)"
            Write-Host $outputMsg -ForegroundColor Yellow
        }

        if ($issues.Count -gt 0) {
            $outputMsg = "[!] Driver issues detected:"
            Write-Host $outputMsg -ForegroundColor Yellow
            foreach ($issue in $issues) {
                Write-Host "- $issue"
            }
            return 1
        }

        $outputMsg = "[+] All drivers appear to be up to date."

        Write-Host $outputMsg -ForegroundColor Green
        return 0
    }
    catch {
        $outputMsg = "[-] Error checking driver status: $($_.Exception.Message)"
        Write-Host $outputMsg -ForegroundColor Red
        return 1
    }
}
#endregion

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
