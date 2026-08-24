<#
.SYNOPSIS
    [DEPRECATED] Forward to the canonical remediation script Test-WingetCpp2013RedistX64.ps1.

.DESCRIPTION
    Deprecated compatibility shim retained so existing Intune Proactive Remediations assignments keep
    working. Invokes the canonical script at scripts/endpoints/remediation/winget/runtimes/Cpp2013Redist-x64/Test-WingetCpp2013RedistX64.ps1 and preserves its exit code. Update
    Intune assignments to the canonical path; this shim will be removed in version 6.0.0.
    Exit codes: passes through the canonical script's exit code (Intune convention: 0 =
    compliant/healthy, non-zero = non-compliant/needs remediation).

.EXAMPLE
    PS C:\> .\detect.ps1

    Runs the shim directly. All arguments are forwarded to the canonical script and its exit code is
    preserved as this script's exit code.

.EXAMPLE
    PS C:\> pwsh -NoProfile -File .\detect.ps1

    Runs the shim in a clean process; forwarding behavior is unchanged.

.NOTES
    File Name  : detect.ps1
    Author     : Bug-Free Umbrella
    Prerequisite: PowerShell 7.0
    Version    : 1.0.0
    Date       : 2026-08-23
#>

[CmdletBinding()]
param()

# PSAvoidUsingWriteHost is intentionally accepted: prefixed, colored console output is the mandated
# output convention of docs/RELAUNCH-SPEC.md section 3.
$ErrorActionPreference = 'Stop'

function Invoke-CanonicalScript {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [AllowEmptyCollection()]
        [object[]]$ForwardedArgs
    )

    # Thin wrapper seam: the canonical .ps1 is invoked here so tests can mock this function.
    $null = & $Path @ForwardedArgs
    return $LASTEXITCODE
}

function Main {
    try {
        Write-Host '[*] Forwarding to canonical remediation script...' -ForegroundColor Cyan

        $canonicalFile = 'remediation/winget/runtimes/Cpp2013Redist-x64/Test-WingetCpp2013RedistX64.ps1'
        $canonicalPath = Join-Path $PSScriptRoot ('../../../../' + $canonicalFile)
        if (-not (Test-Path -LiteralPath $canonicalPath)) {
            throw "Canonical script not found at '$canonicalPath'."
        }

        Write-Warning "Deprecated: moved to scripts/endpoints/$canonicalFile — shim will be removed in 6.0.0."

        $exitCode = Invoke-CanonicalScript -Path $canonicalPath -ForwardedArgs $ForwardedArgs

        Write-Host "[+] Forwarded successfully (exit code: $exitCode)." -ForegroundColor Green
        return $exitCode
    }
    catch {
        Write-Host "[-] Error: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

$ForwardedArgs = $args

# Execute only when run as a script; dot-sourcing (Pester tests) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
