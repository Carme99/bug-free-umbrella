# Define the registry path
$RegPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeviceInstall\Restrictions\DenyDeviceIDs"

# Check if the key exists
if (Test-Path $RegPath) {
    # Get all existing properties under the key
    $props = Get-ItemProperty -Path $RegPath

    # Loop through each named value (excluding system properties)
    foreach ($name in $props.PSObject.Properties.Name) {
        $value = $props.$name

        # Check if it matches the AMD device ID and remove it
        if ($value -eq "PCIVEN_1002&DEV_1681") {
            Remove-ItemProperty -Path $RegPath -Name $name -ErrorAction SilentlyContinue
            Write-Output "Removed driver block for AMD device: $name"
        }
    }

    # If the key is now empty, remove it
    if ((Get-ItemProperty -Path $RegPath).PSObject.Properties.Count -eq 0) {
        Remove-Item -Path $RegPath -Force
        Write-Output "Registry key removed as it was empty."
    }
} else {
    Write-Output "Registry path does not exist. No action needed."
}

Exit 0