<#
.SYNOPSIS
    Remove the NoAutoUpdate Windows Update policy (DisableWindowsUpdateAccess pair)

.DESCRIPTION
    Removes the NoAutoUpdate value from HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU (the supported WUaaS control managed by this pair; DisableWindowsUpdateAccess itself is unsupported on Windows 10+ / Server 2016+).

.EXAMPLE
    ./Remediate.ps1

.NOTES
    File Name  : Remediate.ps1
    Author     : Intune / Proactive Remediations
    Prerequisite: PowerShell 5.1 or later, run in the Intune Proactive Remediation context
    Version    : 1.0.0
    Date       : 2026-08-08
#>

# Remediate: remove the NoAutoUpdate policy (see Detect.ps1 for the policy
# rationale - DisableWindowsUpdateAccess is unsupported on Windows 10+ /
# Server 2016+, so this pair manages the supported WUaaS policy NoAutoUpdate
# under HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU).
# See https://learn.microsoft.com/en-us/windows/deployment/update/waas-wu-settings
if ((Get-ItemProperty HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU -ErrorAction SilentlyContinue).PSObject.Properties.Name -contains 'NoAutoUpdate') {
    Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name "NoAutoUpdate"
}
