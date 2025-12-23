# Detect if the device model matches
$DeviceModel = (Get-CimInstance -ClassName Win32_ComputerSystem).Model

if ($DeviceModel -ne "21L8S0VP00") {
    Write-Output "Device is not a Lenovo 21L8S0VP00. No action needed."
    Exit 0
}

# Check if the registry key exists
$RegPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeviceInstall\Restrictions\DenyDeviceIDs"
$RegValue = "PCIVEN_1002&DEV_1681"

if ((Test-Path $RegPath) -and ((Get-ItemProperty -Path $RegPath).1 -eq $RegValue)) {
    Write-Output "Driver block is already applied."
    Exit 0
} else {
    Write-Output "Driver block is missing."
    Exit 1
}