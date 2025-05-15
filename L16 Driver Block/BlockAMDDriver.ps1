# Define the registry path and value
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