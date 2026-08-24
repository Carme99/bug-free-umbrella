<#
.SYNOPSIS
    Detect the UseWUServer Windows Update policy

.DESCRIPTION
    Exits 1 when the UseWUServer value is present under
    HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU so the paired remediation removes it; exits 0
    when the device is compliant.
    Runs read-only registry checks only and is safe to re-run at any time.

.EXAMPLE
    PS C:\> .\Detect.ps1

    Runs the detection; exit 0 means compliant, exit 1 means the policy value is present.

.EXAMPLE
    PS C:\> .\Detect.ps1 -Verbose

    Runs the detection with verbose preference enabled.

.NOTES
    File Name  : Detect.ps1
    Author     : Intune / Proactive Remediations
    Prerequisite: PowerShell 5.1+
    Version    : 1.0.0
    Date       : 2026-08-23
#>

[CmdletBinding()]
param()

# PSScriptAnalyzer: Write-Host with prefix/color output is mandated by docs/RELAUNCH-SPEC.md section 3.

$ErrorActionPreference = 'Stop'

$script:RegPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU'
$script:RegValueName = 'UseWUServer'

function Test-PolicyValuePresent {
# Returns $true when the policy value exists under the policy key.
    $key = Get-ItemProperty -Path $script:RegPath -ErrorAction SilentlyContinue
    if ($null -eq $key) {
        return $false
    }
    return ($key.PSObject.Properties.Name -contains $script:RegValueName)
}

function Main {
    try {
        if (Test-PolicyValuePresent) {
            Write-Host "[*] '$($script:RegValueName)' is present; remediation needed." -ForegroundColor Yellow
            return 1
        }
        Write-Host "[+] '$($script:RegValueName)' is not present; device is compliant." -ForegroundColor Green
        return 0
    }
    catch {
        Write-Host "[-] Error: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
