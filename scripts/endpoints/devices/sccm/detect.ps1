<#
.SYNOPSIS
    Detect if the SCCM client is installed

.DESCRIPTION
    Checks whether the Configuration Manager client is installed by looking for the SMS Agent Host (CcmExec) service running and, as a fallback, the installed client data folder C:\Windows\CCM\ServiceData. The ccmsetup folder is deliberately not used as an indicator because it can exist after a failed install.

.EXAMPLE
    ./detect.ps1

.NOTES
    File Name  : detect.ps1
    Author     : Intune / Proactive Remediations
    Prerequisite: PowerShell 5.1 or later, run in the Intune Proactive Remediation context
    Version    : 1.0.0
    Date       : 2026-08-08
#>

# Detection script for SCCM
#
# The installed SCCM client is the SMS Agent Host (CcmExec) service. The
# ccmsetup folder (%windir%\ccmsetup) holds setup/bootstrap files and can
# exist after a failed install, so it is NOT a reliable indicator.
# See https://learn.microsoft.com/en-us/mem/configmgr/core/clients/deploy/about-client-installation-properties

# Check for the SMS Agent Host service (running)
$ccmService = Get-Service -Name "CcmExec" -ErrorAction SilentlyContinue

if ($ccmService -and $ccmService.Status -eq "Running") {
    Write-Output " SCCM client is installed."
    exit 0
}

# Fallback: check for the installed client's data folder
if (Test-Path "C:\Windows\CCM\ServiceData") {
    Write-Output " SCCM client is installed."
    exit 0
}

Write-Output " SCCM client is NOT installed."
exit 1
