# Get the device model
$DeviceModel = (Get-CimInstance -ClassName Win32_ComputerSystem).Model

if ($DeviceModel -ne "21L8S0VP00") {
    Write-Output "Device is not a Lenovo 21L8S0VP00. No action needed."
    Exit 0
}

# Define the registry path and values
$RegPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeviceInstall\Restrictions\DenyDeviceIDs"
$RegValue = "PCIVEN_1002&DEV_1681"

# Ensure the registry key exists
if (!(Test-Path $RegPath)) {
    New-Item -Path $RegPath -Force | Out-Null
}

# Apply the registry setting
Set-ItemProperty -Path $RegPath -Name "1" -Value $RegValue -Type String -Force

Write-Output "AMD Radeon driver block policy applied."
Exit 0