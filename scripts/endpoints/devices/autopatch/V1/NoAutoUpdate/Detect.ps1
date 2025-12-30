if ((Get-ItemProperty HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU).PSObject.Properties.Name -contains 'NoAutoUpdate') {
    exit 1
} else {
    exit 0
} 