# Block the AMD Radeon driver (DeviceInstallation policy)
#
# Documented layout (Policy CSP PreventInstallationOfMatchingDeviceIDs / ADMX
# DeviceInstall_IDs_Deny): a REG value named "DenyDeviceIDs" directly under
# HKLM\SOFTWARE\Policies\Microsoft\Windows\DeviceInstall\Restrictions.
# DenyDeviceIDsRetroactive (REG_DWORD 1) additionally blocks already-installed devices.
# See https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-deviceinstallation

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
Exit 0
