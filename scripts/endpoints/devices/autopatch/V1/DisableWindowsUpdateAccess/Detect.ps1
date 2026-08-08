# Detect: the policy "Remove access to use all Windows Update features"
# (DisableWindowsUpdateAccess) is NOT supported on Windows 10 and later or
# Windows Server 2016 and later. This pair instead detects the supported
# WUaaS policy NoAutoUpdate under HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU
# (per waas-wu-settings). Exit 1 when the policy value is present (remediation needed).
# See https://learn.microsoft.com/en-us/windows/deployment/update/waas-wu-settings
if ((Get-ItemProperty HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU -ErrorAction SilentlyContinue).PSObject.Properties.Name -contains 'NoAutoUpdate') {
    exit 1
} else {
    exit 0
} 
