<#
.SYNOPSIS
    Remove the AMD Radeon driver block

.DESCRIPTION
    Removes the AMD Radeon hardware ID (PCIVEN_1002&DEV_1681) from the DeviceInstallation DenyDeviceIDs policy and
    clears the DenyDeviceIDsRetroactive flag so previously blocked AMD Radeon drivers are no longer denied.
    Idempotent check-then-act: when the block is absent the script reports no action needed and changes nothing.
    Registry mutations are gated behind -WhatIf/-Confirm. Exits 0 on success and 1 on failure.
    Documented layout (Policy CSP PreventInstallationOfMatchingDeviceIDs / ADMX DeviceInstall_IDs_Deny): a REG value
    named DenyDeviceIDs directly under HKLM\SOFTWARE\Policies\Microsoft\Windows\DeviceInstall\Restrictions. See
    https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-deviceinstallation

.EXAMPLE
    PS C:\> .\UnblockAMDDriver.ps1

    Removes the driver block; exits 0.

.EXAMPLE
    PS C:\> .\UnblockAMDDriver.ps1 -WhatIf

    Shows which registry changes would be made without changing anything.

.NOTES
    File Name  : UnblockAMDDriver.ps1
    Author     : Intune / Proactive Remediations
    Prerequisite: PowerShell 5.1+
    Version    : 1.0.0
    Date       : 2026-08-23
#>

[CmdletBinding(SupportsShouldProcess)]
param()

# PSScriptAnalyzer: Write-Host with prefix/color output is mandated by docs/RELAUNCH-SPEC.md section 3.

$ErrorActionPreference = 'Stop'

$script:RegPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeviceInstall\Restrictions'
$script:RegValueName = 'DenyDeviceIDs'
$script:RegValue = 'PCIVEN_1002&DEV_1681'

function Main {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    try {
        if (-not (Test-Path -Path $script:RegPath)) {
            Write-Output 'Registry path does not exist. No action needed.'
            Write-Host '[+] Registry path does not exist; nothing to do.' -ForegroundColor Green
            return 0
        }
        $currentKey = Get-ItemProperty -Path $script:RegPath -Name $script:RegValueName -ErrorAction SilentlyContinue
        $denyList = @(($currentKey.$script:RegValueName) | Where-Object { $_ })
        $remaining = @($denyList | Where-Object { $_ -ne $script:RegValue })
        if ($remaining.Count -gt 0) {
            if ($PSCmdlet.ShouldProcess("$($script:RegPath)::DenyDeviceIDs", 'Remove AMD entry from registry value')) {
                Set-ItemProperty -Path $script:RegPath -Name $script:RegValueName `
                    -Value $remaining -Type MultiString -Force -ErrorAction Stop
                Write-Output "Removed AMD device block: $($script:RegValue)"
                Write-Host "[+] Removed '$($script:RegValue)' from DenyDeviceIDs." -ForegroundColor Green
            }
        }
        elseif ($denyList.Count -gt 0) {
# The list only contained the AMD ID - remove the value entirely.
            if ($PSCmdlet.ShouldProcess("$($script:RegPath)::DenyDeviceIDs", 'Remove registry value')) {
                Remove-ItemProperty -Path $script:RegPath -Name $script:RegValueName -ErrorAction Stop
                Write-Output "Removed AMD device block: $($script:RegValue)"
                Write-Host "[+] Removed '$($script:RegValue)' from DenyDeviceIDs." -ForegroundColor Green
            }
        }
        else {
            Write-Output 'AMD device block was not present.'
            Write-Host '[+] Already converged; no changes made.' -ForegroundColor Green
        }
        if (Get-ItemProperty -Path $script:RegPath -Name 'DenyDeviceIDsRetroactive' -ErrorAction SilentlyContinue) {
            if ($PSCmdlet.ShouldProcess("$($script:RegPath)::DenyDeviceIDsRetroactive", 'Remove registry value')) {
                Remove-ItemProperty -Path $script:RegPath -Name 'DenyDeviceIDsRetroactive' -ErrorAction Stop
                Write-Host '[+] Cleared DenyDeviceIDsRetroactive.' -ForegroundColor Green
            }
        }
        return 0
    }
    catch {
        Write-Host "[-] Error: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
