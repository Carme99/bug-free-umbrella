<#
.SYNOPSIS
    Install the SCCM client from a source path when it is missing.

.DESCRIPTION
    Installs the Configuration Manager (SCCM) client from a local or UNC source path when the client
    is not already installed. Uses the secure ProcessStartInfo pattern (no shell, no window) to run
    ccmsetup.exe against the supplied source tree and reports the actual install outcome.
    Idempotent: when the client is already installed the script exits 0 without changes.
    Exit codes: 0 = installed, already installed, or ccmsetup signaled reboot-required (exit 7);
    1 = validation or installation failure.

.PARAMETER SourcePath
    Local or UNC path containing ccmsetup.exe and the client source (e.g.
    \\SCCM-SERVER\SCCMContentLib\Client or C:\SCCM). Required when the client is not already installed.

.PARAMETER ManagementPoint
    (Optional) FQDN of the management point to pass to ccmsetup via /MP:.

.EXAMPLE
    PS C:\> .\remediate.ps1 -SourcePath '\\SCCM-SERVER\SCCMContentLib\Client'

    Installs the client from the UNC source tree when it is not already installed.

.EXAMPLE
    PS C:\> .\remediate.ps1 -SourcePath 'C:\SCCM' -ManagementPoint 'MP.contoso.com' -WhatIf

    Shows which installation steps would run without changing the system.

.NOTES
    File Name  : remediate.ps1
    Author     : Intune / Proactive Remediations
    Prerequisite: PowerShell 7.0
    Version    : 1.0.0
    Date       : 2026-08-23
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $false)]
    [string]$SourcePath,

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$ManagementPoint
)

# PSAvoidUsingWriteHost is intentionally accepted: prefixed, colored console output is the mandated
# output convention of docs/RELAUNCH-SPEC.md section 3.
$ErrorActionPreference = 'Stop'

function Test-InstalledCcmSetup {
    # Path to an already-installed ccmsetup.exe.
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    return (Test-Path "$env:windir\ccmsetup\ccmsetup.exe")
}

function Resolve-SourceCcmSetup {
    # Locate ccmsetup.exe in the source tree (source root or ccmsetup subfolder).
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$SourceRoot
    )

    $rootCandidate = Join-Path $SourceRoot 'ccmsetup.exe'
    if (Test-Path $rootCandidate) {
        return $rootCandidate
    }

    $subCandidate = Join-Path $SourceRoot 'ccmsetup\ccmsetup.exe'
    if (Test-Path $subCandidate) {
        return $subCandidate
    }

    throw "ccmsetup.exe was not found under -SourcePath '$SourceRoot'. Verify the source tree."
}

function Invoke-CcmSetup {
    # Native executable seam: ccmsetup.exe runs only through this wrapper so tests can mock it.
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$FilePath,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ArgumentList
    )

    # Secure launch pattern: no shell, no window.
    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $FilePath
    $psi.Arguments = $ArgumentList
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $psi
    $null = $process.Start()

    # Drain output/error streams before waiting, then read ExitCode only after exit.
    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()

    return [pscustomobject]@{
        ExitCode       = $process.ExitCode
        StandardOutput = $stdout
        StandardError  = $stderr
    }
}

function Main {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([int])]
    param(
        [string]$SourcePath,
        [string]$ManagementPoint
    )

    try {
        Write-Host '[*] Checking SCCM client state...' -ForegroundColor Cyan

        # Already converged: nothing to remediate (idempotent re-run).
        if (Test-InstalledCcmSetup) {
            Write-Host '[+] SCCM client is already installed.' -ForegroundColor Green
            return 0
        }

        if (-not $SourcePath -or -not (Test-Path $SourcePath)) {
            Write-Host '[-] Error: SCCM client is NOT installed and no valid -SourcePath was provided.' `
                -ForegroundColor Red
            Write-Host '    Supply a local/UNC path containing ccmsetup.exe' `
                '(e.g. \\SCCM-SERVER\SCCMContentLib\Client or C:\SCCM).' -ForegroundColor Red
            return 1
        }

        $sourceCcmSetup = Resolve-SourceCcmSetup -SourceRoot $SourcePath

        $arguments = "/Source:$SourcePath"
        if ($ManagementPoint) {
            $arguments = "$arguments /MP:$ManagementPoint"
        }

        if (-not $PSCmdlet.ShouldProcess($sourceCcmSetup, "Install SCCM client from '$SourcePath'")) {
            Write-Host '[!] WhatIf: skipped SCCM client installation.' -ForegroundColor Yellow
            return 0
        }

        Write-Host "[*] Installing SCCM client from '$SourcePath' using ccmsetup.exe..." -ForegroundColor Cyan
        $result = Invoke-CcmSetup -FilePath $sourceCcmSetup -ArgumentList $arguments

        Write-Host "[*] ccmsetup.exe exit code: $($result.ExitCode)" -ForegroundColor Cyan
        foreach ($line in ($result.StandardOutput -split "`r?`n" | Where-Object { $_ })) {
            Write-Host "[*] $line" -ForegroundColor Cyan
        }
        foreach ($line in ($result.StandardError -split "`r?`n" | Where-Object { $_ })) {
            Write-Host "[!] $line" -ForegroundColor Yellow
        }

        # ccmsetup returns 0 on success and 7 when a reboot is required (still success).
        $installSucceeded = ($result.ExitCode -eq 0 -or $result.ExitCode -eq 7)

        if ($installSucceeded -and (Test-InstalledCcmSetup)) {
            Write-Host '[+] SCCM client installation succeeded.' -ForegroundColor Green
            return 0
        }

        Write-Host "[-] Error: SCCM client installation did not succeed (ccmsetup exit code: $($result.ExitCode))." `
            -ForegroundColor Red
        return 1
    }
    catch {
        Write-Host "[-] Error: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main @PSBoundParameters) }
