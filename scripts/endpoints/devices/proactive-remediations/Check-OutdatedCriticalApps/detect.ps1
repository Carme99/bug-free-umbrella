<#
.SYNOPSIS
    DEPRECATED: use scripts/endpoints/remediation/security/Test-RemediationCheckOutdatedCriticalApps.ps1

.DESCRIPTION
    Deprecated compatibility shim retained so existing Intune Proactive Remediation assignments keep working.
    Forwards execution, arguments, and exit code to the canonical script at
    scripts/endpoints/remediation/security/Test-RemediationCheckOutdatedCriticalApps.ps1.
    Update Intune assignments to the canonical path; this shim will be removed in version 6.0.0.

.EXAMPLE
    PS C:\> .\detect.ps1

    Forwards to the canonical script and exits with its exit code.

.EXAMPLE
    PS C:\> .\detect.ps1 -Verbose

    Forwards with the caller verbose preference inherited by the canonical script.

.NOTES
    File Name  : detect.ps1
    Author     : Bug-Free Umbrella
    Prerequisite: PowerShell 5.1+
    Version    : 1.0.0
    Date       : 2026-08-23

    Exit code of the canonical script is preserved (Intune: 0 = healthy/compliant, 1 = needs remediation).
#>

[CmdletBinding()]
param()

# PSScriptAnalyzer: Write-Host with prefix/color output is mandated by docs/RELAUNCH-SPEC.md section 3.

$ErrorActionPreference = 'Stop'

$canonicalScript = Join-Path $PSScriptRoot '../../../remediation/security/Test-RemediationCheckOutdatedCriticalApps.ps1'
$forwardArgs = $args

function Invoke-ForwardedScript {
# Thin seam around the canonical script invocation so tests can mock forwarding.
    $null = & $canonicalScript @forwardArgs
    return $LASTEXITCODE
}

function Main {
    try {
        Write-Warning "Deprecated: moved to $canonicalScript - shim will be removed in 6.0.0."
        return (Invoke-ForwardedScript)
    }
    catch {
        Write-Host "[-] Error: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
