<#
.SYNOPSIS
    Detect the NoAutoUpdate Windows Update policy (DisableWindowsUpdateAccess pair)

.DESCRIPTION
    The DisableWindowsUpdateAccess policy is unsupported on Windows 10+ / Server 2016+; this pair instead manages the supported WUaaS policy NoAutoUpdate. Exits 1 when NoAutoUpdate is present under HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU and 0 otherwise.

.EXAMPLE
    ./Detect.ps1

.NOTES
    File Name  : Detect.ps1
    Author     : Intune / Proactive Remediations
    Prerequisite: PowerShell 5.1 or later, run in the Intune Proactive Remediation context
    Version    : 1.0.0
    Date       : 2026-08-08
#>

# Detect: the policy "Remove access to use all Windows Update features"
# (DisableWindowsUpdateAccess) is NOT supported on Windows 10 and later or
# Windows Server 2016 and later. This pair instead detects the supported
# WUaaS policy NoAutoUpdate under HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU
# (per waas-wu-settings). Exit 1 when the policy value is present (remediation needed).
# See https://learn.microsoft.com/en-us/windows/deployment/update/waas-wu-settings
if ((Get-ItemProperty HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU -ErrorAction SilentlyContinue).PSObject.Properties.Name -contains 'NoAutoUpdate') {
    exit 1
}
else {
    exit 0
} 
