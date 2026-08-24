<#
.SYNOPSIS
    Detect whether the Configuration Manager (SCCM) client is installed.

.DESCRIPTION
    Checks whether the SCCM client is installed by looking for the SMS Agent Host (CcmExec) service
    running and, as a fallback, the installed client data folder C:\Windows\CCM\ServiceData. The
    ccmsetup folder is deliberately not used as an indicator because it can exist after a failed install.
    Idempotent: detection makes no changes and is safe to re-run.
    Exit codes: 0 = client detected (compliant); 1 = client not detected (non-compliant).

.EXAMPLE
    PS C:\> .\detect.ps1

    Runs the detection logic; exits 0 when the client is present, 1 when it is not.

.EXAMPLE
    PS C:\> pwsh -NoProfile -File .\detect.ps1; $LASTEXITCODE

    Runs detection in a clean process and surfaces the documented exit code.

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

function Test-SccmClientPresent {
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    # Primary indicator: the SMS Agent Host service running.
    # The ccmsetup folder (%windir%\ccmsetup) holds setup/bootstrap files and can exist after a failed
    # install, so it is NOT a reliable indicator.
    # See https://learn.microsoft.com/en-us/mem/configmgr/core/clients/deploy/about-client-installation-properties
    $ccmService = Get-Service -Name 'CcmExec' -ErrorAction SilentlyContinue
    if ($ccmService -and $ccmService.Status -eq 'Running') {
        return $true
    }

    # Fallback: the installed client's data folder.
    if (Test-Path "$env:windir\CCM\ServiceData") {
        return $true
    }

    return $false
}

function Main {
    [CmdletBinding()]
    [OutputType([int])]
    param()
    try {
        Write-Host '[*] Detecting SCCM client...' -ForegroundColor Cyan

        if (Test-SccmClientPresent) {
            Write-Host '[+] SCCM client is installed.' -ForegroundColor Green
            return 0
        }

        Write-Host '[!] SCCM client is NOT installed.' -ForegroundColor Yellow
        return 1
    }
    catch {
        Write-Host "[-] Error: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
