<#
.SYNOPSIS
    Remove the UseWUServer Windows Update policy

.DESCRIPTION
    Removes the UseWUServer value from HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU so the device stops using the WSUS server.

.EXAMPLE
    ./Remediate.ps1

.NOTES
    File Name  : Remediate.ps1
    Author     : Intune / Proactive Remediations
    Prerequisite: PowerShell 5.1 or later, run in the Intune Proactive Remediation context
    Version    : 1.0.0
    Date       : 2026-08-08
#>

if ((Get-ItemProperty HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU).PSObject.Properties.Name -contains 'UseWUServer') {
    Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name "UseWUServer"
}