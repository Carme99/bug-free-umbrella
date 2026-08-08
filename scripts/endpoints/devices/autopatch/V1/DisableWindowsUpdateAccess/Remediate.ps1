# Remediate: remove the NoAutoUpdate policy (see Detect.ps1 for the policy
# rationale - DisableWindowsUpdateAccess is unsupported on Windows 10+ /
# Server 2016+, so this pair manages the supported WUaaS policy NoAutoUpdate
# under HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU).
# See https://learn.microsoft.com/en-us/windows/deployment/update/waas-wu-settings
if ((Get-ItemProperty HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU -ErrorAction SilentlyContinue).PSObject.Properties.Name -contains 'NoAutoUpdate') {
    Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name "NoAutoUpdate"
}
