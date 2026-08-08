<#
.SYNOPSIS
    Detect the WUServer Windows Update policy

.DESCRIPTION
    Exits 1 when the WUServer value is present under HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate (indicating a WSUS server is configured) and 0 otherwise, so the paired remediation can remove it.

.EXAMPLE
    ./Detect.ps1

.NOTES
    File Name  : Detect.ps1
    Author     : Intune / Proactive Remediations
    Prerequisite: PowerShell 5.1 or later, run in the Intune Proactive Remediation context
    Version    : 1.0.0
    Date       : 2026-08-08
#>

if ((Get-ItemProperty HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate).PSObject.Properties.Name -contains 'WUServer') {
    exit 1
}
else {
    exit 0
} 