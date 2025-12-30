if ((Get-ItemProperty HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate).PSObject.Properties.Name -contains 'DisableWindowsUpdateAccess') {
    exit 1
} else {
    exit 0
} 