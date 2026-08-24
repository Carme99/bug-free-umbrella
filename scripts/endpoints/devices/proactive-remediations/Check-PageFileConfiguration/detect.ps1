<#
.SYNOPSIS
    DEPRECATED: use scripts/endpoints/remediation/system/Test-RemediationCheckPageFileConfiguration.ps1.

.DESCRIPTION
    Deprecated compatibility shim retained so existing Intune Proactive Remediations assignments keep working.
    Every invocation, including all arguments, is forwarded unchanged to the canonical script:
    scripts/endpoints/remediation/system/Test-RemediationCheckPageFileConfiguration.ps1
    This file performs no work of its own; it only preserves the original path and exit-code contract.
    Exit codes are returned verbatim from the canonical script (detect pairs: 0 = compliant/healthy, 1 =
    non-compliant; remediate pairs: 0 = success, non-zero = failed). Update Intune assignments to the
    canonical path; this shim will be removed in 6.0.0.

.EXAMPLE
    PS C:\> .\detect.ps1
    Forwards execution to the canonical script and exits with the exit code the canonical script returned.

.EXAMPLE
    PS C:\> .\detect.ps1 -Verbose
    Forwards execution to the canonical script; common parameters bound by this shim are not forwarded.

.NOTES
    File Name     : detect.ps1
    Author        : Bug-Free Umbrella
    Prerequisite  : PowerShell 7.0
    Version       : 1.0.0
    Date          : 2026-08-23
    Deprecated    : moved to
                    scripts/endpoints/remediation/system/Test-RemediationCheckPageFileConfiguration.ps1 —
                    shim will be removed in 6.0.0.
    Intune        : exit 0 = healthy, exit 1 = needs remediation (preserved via $LASTEXITCODE).
    Context       : runs as SYSTEM in Proactive Remediations — uses Win32_UserProfile /
                    Win32_Battery / Microsoft.WinGet.Client as applicable.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

function Invoke-ForwardedScript {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

    # Single seam for invoking the external canonical script; $LASTEXITCODE is the forwarding contract.
    $null = & $Path @args
    return $LASTEXITCODE
}

function Main {
    try {
        $movedTo = 'scripts/endpoints/remediation/system/Test-RemediationCheckPageFileConfiguration.ps1'
        $targetRel = '../../../remediation/system/Test-RemediationCheckPageFileConfiguration.ps1'
        $targetPath = Join-Path $PSScriptRoot $targetRel
        Write-Warning ('Deprecated: moved to {0} — shim will be removed in 6.0.0.' -f $movedTo)
        return (Invoke-ForwardedScript -Path $targetPath @args)
    }
    catch {
        Write-Host "[-] Error: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

if ($MyInvocation.InvocationName -ne '.') { exit (Main @args) }
