<#
.SYNOPSIS
    Apply the AMD Radeon driver block

.DESCRIPTION
    Applies the DeviceInstallation DenyDeviceIDs policy for the AMD Radeon hardware ID (PCIVEN_1002&DEV_1681) on
    target
    Lenovo 21L8S0VP00 devices, including the DenyDeviceIDsRetroactive flag so already-installed devices are blocked.
    Non-target devices exit 0 without changes.
    Idempotent check-then-act: an already-converged device is detected and left unchanged. Registry mutations
    are gated
    behind -WhatIf/-Confirm.
    Intune Proactive Remediation remediation script; exits 0 on success (including already-compliant devices)
    and 1 on
    failure.
    Documented layout (Policy CSP PreventInstallationOfMatchingDeviceIDs / ADMX DeviceInstall_IDs_Deny): a REG value
    named DenyDeviceIDs directly under HKLM\SOFTWARE\Policies\Microsoft\Windows\DeviceInstall\Restrictions. See
    https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-deviceinstallation
    DenyDeviceIDsRetroactive (REG_DWORD 1) additionally blocks already-installed devices.

.EXAMPLE
    PS C:\> .\remediate.ps1

    Applies the driver block on target devices; exits 0.

.EXAMPLE
    PS C:\> .\remediate.ps1 -WhatIf

    Shows which registry changes would be made without changing anything.

.NOTES
    File Name  : remediate.ps1
    Author     : Intune / Proactive Remediations
    Prerequisite: PowerShell 5.1+
    Version    : 1.0.0
    Date       : 2026-08-23
#>

[CmdletBinding(SupportsShouldProcess)]
param()

# PSScriptAnalyzer: Write-Host with prefix/color output is mandated by docs/RELAUNCH-SPEC.md section 3.

$ErrorActionPreference = 'Stop'

$script:TargetModel = '21L8S0VP00'

$script:RegPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeviceInstall\Restrictions'
$script:RegValueName = 'DenyDeviceIDs'
$script:RegValue = 'PCIVEN_1002&DEV_1681'

function Get-TargetDeviceModel {
# Returns the computer model reported by CIM.
    return (Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop).Model
}

function Read-DenyList {
# Reads the DenyDeviceIDs REG_MULTI_SZ value as a clean string array.
    $current = Get-ItemProperty -Path $script:RegPath -Name $script:RegValueName -ErrorAction SilentlyContinue
    return @(($current.$script:RegValueName) | Where-Object { $_ })
}

function Main {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    try {
        $model = Get-TargetDeviceModel
        if ($model -ne $script:TargetModel) {
            Write-Output 'Device is not a Lenovo 21L8S0VP00. No action needed.'
            Write-Host "[+] Non-target device ($model); skipping." -ForegroundColor Green
            return 0
        }
        if (-not (Test-Path -Path $script:RegPath)) {
            if ($PSCmdlet.ShouldProcess($script:RegPath, 'Create registry key')) {
                New-Item -Path $script:RegPath -Force -ErrorAction Stop | Out-Null
                Write-Host "[+] Created $($script:RegPath)." -ForegroundColor Green
            }
        }
        $denyList = Read-DenyList
        $needDenyList = ($denyList -notcontains $script:RegValue)
        $retroKey = Get-ItemProperty -Path $script:RegPath `
            -Name 'DenyDeviceIDsRetroactive' -ErrorAction SilentlyContinue
        $retroCurrent = $retroKey.DenyDeviceIDsRetroactive
        $needRetroactive = ($retroCurrent -ne 1)
        if ($needDenyList) {
            $denyList += $script:RegValue
        }
        $needsChange = ($needDenyList -or $needRetroactive)
        if ($needsChange -and $PSCmdlet.ShouldProcess($script:RegPath, 'Apply AMD Radeon driver block policy')) {
            if ($needDenyList) {
                Set-ItemProperty -Path $script:RegPath -Name $script:RegValueName `
                    -Value $denyList -Type MultiString -Force -ErrorAction Stop
                Write-Host "[+] Added '$($script:RegValue)' to DenyDeviceIDs." -ForegroundColor Green
            }
            if ($needRetroactive) {
                Set-ItemProperty -Path $script:RegPath -Name 'DenyDeviceIDsRetroactive' `
                    -Value 1 -Type DWord -Force -ErrorAction Stop
                Write-Host '[+] Enabled DenyDeviceIDsRetroactive.' -ForegroundColor Green
            }
            Write-Output 'AMD Radeon driver block policy applied.'
        }
        elseif (-not $needDenyList -and -not $needRetroactive) {
            Write-Output 'AMD Radeon driver block policy already applied.'
            Write-Host '[+] Already converged; no changes made.' -ForegroundColor Green
        }
        return 0
    }
    catch {
        Write-Host "[-] Error: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
