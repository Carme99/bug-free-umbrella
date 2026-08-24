<#
.SYNOPSIS
    Detects Windows license activation issues.

.DESCRIPTION
    Checks whether Windows is properly activated and licensed, first via slmgr.vbs (queried
    through cscript.exe, invoked only via the Invoke-WindowsActivationQuery wrapper) and then
    as a secondary check through the SoftwareLicensingProduct WMI class. Unlicensed Windows can
    cause compliance issues and limited functionality. This is a read-only detection script:
    it changes nothing, so re-running it is safe (idempotent).
    Exit codes:
    - 0: compliant - Windows is activated and licensed.
    - 1: non-compliant - activation issues detected, or the check failed.

.EXAMPLE
    PS C:\> .\Test-RemediationFixWindowsLicenseActivation.ps1
    Queries the activation status; exits 0 when licensed, 1 when activation issues are found.

.EXAMPLE
    PS C:\> & 'C:\Program Files\Intune\ProactiveRemediations\Test-RemediationFixWindowsLicenseActivation.ps1'
    Runs the same check from the Intune Management Extension under the SYSTEM context.

.NOTES
    File Name: Test-RemediationFixWindowsLicenseActivation.ps1
    Author: Intune Admin
    Prerequisite: PowerShell 7.0
    Version: 1.0.0
    Date: 2026-08-23
#>

[CmdletBinding()]

$ErrorActionPreference = 'Stop'

#region Functions

function Invoke-WindowsActivationQuery {
    <#
    .SYNOPSIS
        Thin wrapper around cscript.exe //nologo slmgr.vbs /dli; returns output and exit code.
    #>

    $output = & cscript.exe //nologo "$env:SystemRoot\System32\slmgr.vbs" /dli 2>&1
    [pscustomobject] @{
        ExitCode = $LASTEXITCODE
        Output   = ($output | Out-String)
    }
}

function Main {
    try {
        $outputMsg = "[*] Checking Windows activation status..."
        Write-Host $outputMsg -ForegroundColor Cyan

        $issues = @()

        # Check Windows activation status using slmgr (native exe via wrapper).
        $activationQuery = Invoke-WindowsActivationQuery

        if ($activationQuery.ExitCode -ne 0) {
            $outputMsg = "[-] Error checking Windows activation status"
            Write-Host $outputMsg -ForegroundColor Red
            return 1
        }

        $activationStatus = $activationQuery.Output

        # Parse activation status.
        if ($activationStatus -match "License Status: Licensed") {
            $outputMsg = "[+] Windows is properly activated and licensed"
            Write-Host $outputMsg -ForegroundColor Green
            return 0
        }

        # Check for specific activation states.
        if ($activationStatus -match "License Status: Notification") {
            $issues += "Windows is in notification mode (grace period or unlicensed)"
        }
        elseif ($activationStatus -match "License Status: Unlicensed") {
            $issues += "Windows is unlicensed"
        }
        elseif ($activationStatus -match "License Status: Out-of-tolerance") {
            $issues += "Windows is out of tolerance (requires reactivation)"
        }
        else {
            $issues += "Windows activation status is unknown or problematic"
        }

        # Additional check using WMI.
                $licensingStatus = Get-WmiObject -Class SoftwareLicensingProduct `
                    -Filter "ApplicationID='55c92734-d682-4d71-983e-d6ec3f16059f' `
            AND PartialProductKey <> null" `
            -ErrorAction SilentlyContinue

        if ($licensingStatus) {
            $licenseStatusCode = $licensingStatus.LicenseStatus
            # 0 = Unlicensed, 1 = Licensed, 2 = OOBGrace, 3 = OOTGrace, 4 = NonGenuineGrace,
            # 5 = Notification, 6 = ExtendedGrace
            if ($licenseStatusCode -ne 1) {
                $issues += "Windows license status code: $licenseStatusCode (not fully licensed)"
            }
        }

        if ($issues.Count -gt 0) {
            $outputMsg = "[!] Windows activation issues detected:"
            Write-Host $outputMsg -ForegroundColor Yellow
            foreach ($issue in $issues) {
                $outputMsg = "[!]   - $issue"
                Write-Host $outputMsg -ForegroundColor Yellow
            }
            return 1
        }

        $outputMsg = "[+] Windows is properly activated"

        Write-Host $outputMsg -ForegroundColor Green
        return 0
    }
    catch {
        $outputMsg = "[-] Error checking Windows activation: $($_.Exception.Message)"
        Write-Host $outputMsg -ForegroundColor Red
        return 1
    }
}

#endregion

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
