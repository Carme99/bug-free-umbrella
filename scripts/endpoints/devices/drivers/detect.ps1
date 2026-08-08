# Detect if the AMD Radeon driver block (DeviceInstallation policy) is applied
#
# Documented layout (Policy CSP PreventInstallationOfMatchingDeviceIDs / ADMX
# DeviceInstall_IDs_Deny): a REG value named "DenyDeviceIDs" directly under
# HKLM\SOFTWARE\Policies\Microsoft\Windows\DeviceInstall\Restrictions.
# The OS policy engine never reads a "DenyDeviceIDs" subkey.
# See https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-deviceinstallation

$DeviceModel = (Get-CimInstance -ClassName Win32_ComputerSystem).Model

if ($DeviceModel -ne "21L8S0VP00") {
    Write-Output "Device is not a Lenovo 21L8S0VP00. No action needed."
    Exit 0
}

# Documented registry location
$RegPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeviceInstall\Restrictions"
$RegValueName = "DenyDeviceIDs"
$RegValue = "PCIVEN_1002&DEV_1681"

# Read the DenyDeviceIDs value (REG_MULTI_SZ array, or a single REG_SZ string)
$denyList = @()
if (Test-Path $RegPath) {
    $denyList = @((Get-ItemProperty -Path $RegPath -Name $RegValueName -ErrorAction SilentlyContinue).$RegValueName | Where-Object { $_ })
}

if ($denyList -contains $RegValue) {
    Write-Output "Driver block is already applied."
    Exit 0
} else {
    Write-Output "Driver block is missing."
    Exit 1
}
