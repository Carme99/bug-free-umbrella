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
    Exit 0
}

# Fallback: check for the installed client's data folder
if (Test-Path "C:\Windows\CCM\ServiceData") {
    Write-Output " SCCM client is installed."
    Exit 0
}

Write-Output " SCCM client is NOT installed."
Exit 1
