<#
.SYNOPSIS
    Detect if the AMD Radeon driver block is applied

.DESCRIPTION
    Checks whether the DeviceInstallation DenyDeviceIDs policy contains the AMD Radeon hardware ID
    (PCIVEN_1002&DEV_1681). Skips non-target Lenovo 21L8S0VP00 devices and exits 0.
    Intune Proactive Remediation detection script: exits 1 when the driver block is missing on a target device
    so the
    paired remediation runs, and 0 when it is already applied. Runs read-only checks only and is safe to re-run.
    Documented layout (Policy CSP PreventInstallationOfMatchingDeviceIDs / ADMX DeviceInstall_IDs_Deny): a REG value
    named DenyDeviceIDs directly under HKLM\SOFTWARE\Policies\Microsoft\Windows\DeviceInstall\Restrictions. See
    https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-deviceinstallation

.EXAMPLE
    PS C:\> .\detect.ps1

    Runs the detection; exit 0 means compliant, exit 1 means the driver block is missing.

.EXAMPLE
    PS C:\> .\detect.ps1 -Verbose

    Runs the detection with verbose preference enabled.

.NOTES
    File Name  : detect.ps1
    Author     : Intune / Proactive Remediations
    Prerequisite: PowerShell 5.1+
    Version    : 1.0.0
    Date       : 2026-08-23
#>

[CmdletBinding()]
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

function Test-DriverBlockApplied {
# Returns $true when the deny list already contains the AMD hardware ID.
    if (-not (Test-Path -Path $script:RegPath)) {
        return $false
    }
    return ((Read-DenyList) -contains $script:RegValue)
}

function Main {
    try {
        $model = Get-TargetDeviceModel
        if ($model -ne $script:TargetModel) {
            Write-Output 'Device is not a Lenovo 21L8S0VP00. No action needed.'
            Write-Host "[+] Non-target device ($model); skipping." -ForegroundColor Green
            return 0
        }
        if (Test-DriverBlockApplied) {
            Write-Output 'Driver block is already applied.'
            Write-Host '[+] Driver block is already applied.' -ForegroundColor Green
            return 0
        }
        Write-Output 'Driver block is missing.'
        Write-Host '[!] Driver block is missing; remediation needed.' -ForegroundColor Yellow
        return 1
    }
    catch {
        Write-Host "[-] Error: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
