<#
.SYNOPSIS
    Remove the DoNotConnectToWindowsUpdateInternetLocations Windows Update policy

.DESCRIPTION
    Removes the DoNotConnectToWindowsUpdateInternetLocations value from
    HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate so the device returns to default Windows Update
    behaviour.
    Idempotent check-then-act: when the value is already absent the script reports compliance and changes
    nothing. Supports -WhatIf/-Confirm.
    Intune Proactive Remediation remediation script; exits 0 on success (including already-compliant) and 1 on
    failure.

.EXAMPLE
    PS C:\> .\Remediate.ps1

    Removes the policy value when present; exits 0.

.EXAMPLE
    PS C:\> .\Remediate.ps1 -WhatIf

    Shows which registry value would be removed without changing anything.

.NOTES
    File Name  : Remediate.ps1
    Author     : Intune / Proactive Remediations
    Prerequisite: PowerShell 5.1+
    Version    : 1.0.0
    Date       : 2026-08-23
#>

[CmdletBinding(SupportsShouldProcess)]
param()

# PSScriptAnalyzer: Write-Host with prefix/color output is mandated by docs/RELAUNCH-SPEC.md section 3.

$ErrorActionPreference = 'Stop'

$script:RegPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
$script:RegValueName = 'DoNotConnectToWindowsUpdateInternetLocations'

function Test-PolicyValuePresent {
# Returns $true when the policy value exists under the policy key.
    $key = Get-ItemProperty -Path $script:RegPath -ErrorAction SilentlyContinue
    if ($null -eq $key) {
        return $false
    }
    return ($key.PSObject.Properties.Name -contains $script:RegValueName)
}

function Main {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    try {
        if (-not (Test-PolicyValuePresent)) {
            Write-Host "[+] Already compliant: '$($script:RegValueName)' is not present." -ForegroundColor Green
            return 0
        }
        if ($PSCmdlet.ShouldProcess("$($script:RegPath)::$($script:RegValueName)", 'Remove registry value')) {
            Remove-ItemProperty -Path $script:RegPath -Name $script:RegValueName -ErrorAction Stop
            Write-Host "[+] Removed '$($script:RegValueName)' from the policy key." -ForegroundColor Green
        }
        return 0
    }
    catch {
        Write-Host "[-] Error: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
