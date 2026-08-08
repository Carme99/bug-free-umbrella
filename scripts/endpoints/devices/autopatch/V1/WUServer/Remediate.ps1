<#
.SYNOPSIS
    Remove the WUServer Windows Update policy

.DESCRIPTION
    Removes the WUServer value from HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate so the device stops using the configured WSUS server.

.EXAMPLE
    ./Remediate.ps1

.NOTES
    File Name  : Remediate.ps1
    Author     : Intune / Proactive Remediations
    Prerequisite: PowerShell 5.1 or later, run in the Intune Proactive Remediation context
    Version    : 1.0.0
    Date       : 2026-08-08
#>

if ((Get-ItemProperty HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate).PSObject.Properties.Name -contains 'WUServer') {
    Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -Name "WUServer"
}