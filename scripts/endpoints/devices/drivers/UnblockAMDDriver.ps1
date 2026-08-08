# Unblock the AMD Radeon driver (DeviceInstallation policy)
#
# Documented layout (Policy CSP PreventInstallationOfMatchingDeviceIDs / ADMX
# DeviceInstall_IDs_Deny): a REG value named "DenyDeviceIDs" directly under
# HKLM\SOFTWARE\Policies\Microsoft\Windows\DeviceInstall\Restrictions.
# See https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-deviceinstallation

# Documented registry location
$RegPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeviceInstall\Restrictions"
$RegValueName = "DenyDeviceIDs"
$RegValue = "PCIVEN_1002&DEV_1681"

if (Test-Path $RegPath) {
    # Read the DenyDeviceIDs value (REG_MULTI_SZ array, or a single REG_SZ string)
    $denyList = @((Get-ItemProperty -Path $RegPath -Name $RegValueName -ErrorAction SilentlyContinue).$RegValueName | Where-Object { $_ })

    # Remove the AMD hardware ID from the list
    $remaining = @($denyList | Where-Object { $_ -ne $RegValue })

    if ($remaining.Count -gt 0) {
        Set-ItemProperty -Path $RegPath -Name $RegValueName -Value $remaining -Type MultiString -Force
        Write-Output "Removed AMD device block: $RegValue"
    } elseif ($denyList.Count -gt 0) {
        # The list only contained the AMD ID - remove the value entirely
        Remove-ItemProperty -Path $RegPath -Name $RegValueName -ErrorAction SilentlyContinue
        Write-Output "Removed AMD device block: $RegValue"
    } else {
        Write-Output "AMD device block was not present."
    }

    # Clear the retroactive flag so previously blocked devices are no longer denied
    Remove-ItemProperty -Path $RegPath -Name "DenyDeviceIDsRetroactive" -ErrorAction SilentlyContinue
} else {
    Write-Output "Registry path does not exist. No action needed."
}

Exit 0
