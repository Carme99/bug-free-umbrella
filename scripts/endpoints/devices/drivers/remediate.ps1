<#
.SYNOPSIS
    Apply the AMD Radeon driver block

.DESCRIPTION
    Applies the DeviceInstallation DenyDeviceIDs policy for the AMD Radeon hardware ID (PCIVEN_1002&DEV_1681) on target Lenovo 21L8S0VP00 devices, including the DenyDeviceIDsRetroactive flag so already-installed devices are blocked. Non-target devices exit 0 without changes.

.EXAMPLE
    ./remediate.ps1

.NOTES
    File Name  : remediate.ps1
    Author     : Intune / Proactive Remediations
    Prerequisite: PowerShell 5.1 or later, run in the Intune Proactive Remediation context
    Version    : 1.0.0
    Date       : 2026-08-08
#>

# Remediate: apply the AMD Radeon driver block (DeviceInstallation policy)
#
# Documented layout (Policy CSP PreventInstallationOfMatchingDeviceIDs / ADMX
# DeviceInstall_IDs_Deny): a REG value named "DenyDeviceIDs" directly under
# HKLM\SOFTWARE\Policies\Microsoft\Windows\DeviceInstall\Restrictions.
# DenyDeviceIDsRetroactive (REG_DWORD 1) additionally blocks already-installed devices.
# See https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-deviceinstallation

# Get the device model
$DeviceModel = (Get-CimInstance -ClassName Win32_ComputerSystem).Model

if ($DeviceModel -ne "21L8S0VP00") {
    Write-Output "Device is not a Lenovo 21L8S0VP00. No action needed."
    exit 0
}

# Documented registry location
$RegPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeviceInstall\Restrictions"
$RegValueName = "DenyDeviceIDs"
$RegValue = "PCIVEN_1002&DEV_1681"

# Ensure the Restrictions key exists
if (!(Test-Path $RegPath)) {
    New-Item -Path $RegPath -Force | Out-Null
}

# Merge the hardware ID into the existing DenyDeviceIDs value (REG_MULTI_SZ)
$denyList = @()
$current = (Get-ItemProperty -Path $RegPath -Name $RegValueName -ErrorAction SilentlyContinue).$RegValueName
if ($current) {
    $denyList = @($current)
}
if ($denyList -notcontains $RegValue) {
    $denyList += $RegValue
    Set-ItemProperty -Path $RegPath -Name $RegValueName -Value $denyList -Type MultiString -Force
}

# Retroactive flag so already-installed devices are also blocked
Set-ItemProperty -Path $RegPath -Name "DenyDeviceIDsRetroactive" -Value 1 -Type DWord -Force

Write-Output "AMD Radeon driver block policy applied."
exit 0
