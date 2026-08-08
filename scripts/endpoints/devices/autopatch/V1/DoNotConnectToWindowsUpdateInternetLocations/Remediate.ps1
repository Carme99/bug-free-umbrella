<#
.SYNOPSIS
    Remove the DoNotConnectToWindowsUpdateInternetLocations Windows Update policy

.DESCRIPTION
    Removes the DoNotConnectToWindowsUpdateInternetLocations value from HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate so the device can connect to Windows Update internet locations.

.EXAMPLE
    ./Remediate.ps1

.NOTES
    File Name  : Remediate.ps1
    Author     : Intune / Proactive Remediations
    Prerequisite: PowerShell 5.1 or later, run in the Intune Proactive Remediation context
    Version    : 1.0.0
    Date       : 2026-08-08
#>

if ((Get-ItemProperty HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate).PSObject.Properties.Name -contains 'DoNotConnectToWindowsUpdateInternetLocations') {
    Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -Name "DoNotConnectToWindowsUpdateInternetLocations"
}