<#
.SYNOPSIS
    Resets Windows Update components to resolve update issues on Windows Server 2016-2022.

.DESCRIPTION
    This script performs a comprehensive reset of Windows Update components by:
    - Stopping Windows Update services (wuauserv, cryptSvc, bits, msiserver)
    - Clearing the SoftwareDistribution and catroot2 update caches
    - Running the DISM /RestoreHealth repair path and sfc /scannow (default) or the
      legacy manual reset (regsvr32 re-registration + Windows Update policy key deletion)
    - Optionally clearing the BITS transfer queue (-FullReset)
    - Restarting Windows Update services and triggering update detection

    All mutations are gated by -WhatIf/-Confirm (SupportsShouldProcess). Steps use a
    check-then-act pattern, so re-running on an already-converged system succeeds
    without further changes.

    Exit codes: 0 = reset completed, 1 = fatal error or missing Administrator privileges.

.PARAMETER FullReset
    Performs a complete reset including BITS and Cryptographic services.

.PARAMETER RunDismRepair
    Runs the documented repair path for Server 2016+ (DISM /Online /Cleanup-Image
    /RestoreHealth followed by sfc /scannow) before the legacy reset steps. Defaults
    to ON; when the DISM repair succeeds, the legacy regsvr32 re-registration and
    policy-key deletion steps are skipped. Disable with -RunDismRepair:$false.

.PARAMETER LegacyReset
    Forces the legacy manual reset (regsvr32 re-registration and Windows Update
    policy key deletion) even when the DISM repair succeeds.

.EXAMPLE
    PS C:\> .\Reset-WindowsUpdate.ps1
    Performs a standard Windows Update reset (DISM repair first).

.EXAMPLE
    PS C:\> .\Reset-WindowsUpdate.ps1 -FullReset
    Performs a comprehensive reset including all related services.

.EXAMPLE
    PS C:\> .\Reset-WindowsUpdate.ps1 -LegacyReset
    Performs the legacy manual reset without the DISM repair step.

.NOTES
    File Name:     Reset-WindowsUpdate.ps1
    Author:        Bug-Free Umbrella
    Prerequisite:  PowerShell 5.1+
    Version:       1.0.0
    Date:          2026-08-23

    Requires Administrator privileges on supported operating systems.
    Compatible with Windows Server 2016, 2019, and 2022.
#>

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
    Justification = 'Console remediation tool: prefixed, color-coded host output is the intended user interface.')]
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $false)]
    [switch]$FullReset,

    [Parameter(Mandatory = $false)]
    # Justification: documented default-ON repair path; disable with -RunDismRepair:$false.
    [switch]$RunDismRepair = $true,

    [Parameter(Mandatory = $false)]
    [switch]$LegacyReset
)

$ErrorActionPreference = 'Stop'

function Test-AdminPrivilege {
    [CmdletBinding()]
    param()

    try {
        $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = [System.Security.Principal.WindowsPrincipal]$identity
        return $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch {
        # Non-Windows platform or unavailable identity APIs.
        return $false
    }
}

function Write-LogEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [ValidateSet("INFO", "SUCCESS", "WARNING", "ERROR", "HEADER")]
        [string]$Type = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $prefix = switch ($Type) {
        "ERROR" { "[-]" }
        "SUCCESS" { "[+]" }
        "WARNING" { "[!]" }
        default { "[*]" }
    }
    $color = switch ($Type) {
        "ERROR" { "Red" }
        "SUCCESS" { "Green" }
        "WARNING" { "Yellow" }
        "HEADER" { "Cyan" }
        default { "Cyan" }
    }
    Write-Host "[$timestamp] $prefix $Message" -ForegroundColor $color
}

function Invoke-DismRepair {
    [CmdletBinding()]
    param()

    & "$env:windir\System32\Dism.exe" /Online /Cleanup-Image /RestoreHealth
    return $LASTEXITCODE
}

function Invoke-SfcScan {
    [CmdletBinding()]
    param()

    & "$env:windir\System32\sfc.exe" /scannow
    return $LASTEXITCODE
}

function Invoke-RegSvr32 {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Dll
    )

    Start-Process -FilePath "regsvr32.exe" -ArgumentList "/s $Dll" `
        -Wait -WindowStyle Hidden -ErrorAction SilentlyContinue
    return $LASTEXITCODE
}

function Main {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory = $false)]
        [switch]$FullReset,

        [Parameter(Mandatory = $false)]
        # Justification: documented default-ON repair path; disable with -RunDismRepair:$false.
        [switch]$RunDismRepair = $true,

        [Parameter(Mandatory = $false)]
        [switch]$LegacyReset
    )

    try {
        Write-LogEntry "Starting Windows Update Reset Process" "INFO"

        if (-not (Test-AdminPrivilege)) {
            $adminMsg = "Administrator privileges are required. Re-run from an elevated PowerShell session."
            Write-LogEntry $adminMsg "ERROR"
            return 1
        }

        $osCaption = (Get-CimInstance -ClassName Win32_OperatingSystem).Caption
        Write-LogEntry "Server: $env:COMPUTERNAME | OS: $osCaption" "INFO"

        # Stop Windows Update Services
        if ($PSCmdlet.ShouldProcess("Windows Update services (wuauserv, cryptSvc, bits, msiserver)", "Stop services")) {
            Write-LogEntry "Stopping Windows Update services..." "INFO"
            $services = @("wuauserv", "cryptSvc", "bits", "msiserver")

            foreach ($service in $services) {
                try {
                    Stop-Service -Name $service -Force -ErrorAction SilentlyContinue
                    Write-LogEntry "Stopped service: $service" "SUCCESS"
                }
                catch {
                    Write-LogEntry "Failed to stop service: $service - $($_.Exception.Message)" "WARNING"
                }
            }
        }

        # Clear Windows Update cache
        Write-LogEntry "Clearing Windows Update cache..." "INFO"
        $cachePaths = @(
            "$env:SystemRoot\SoftwareDistribution",
            "$env:SystemRoot\System32\catroot2"
        )

        foreach ($path in $cachePaths) {
            if (Test-Path $path) {
                if ($PSCmdlet.ShouldProcess($path, "Clear update cache contents")) {
                    try {
                        Remove-Item -Path "$path\*" -Recurse -Force -ErrorAction SilentlyContinue
                        Write-LogEntry "Cleared cache: $path" "SUCCESS"
                    }
                    catch {
                        Write-LogEntry "Failed to clear cache: $path - $($_.Exception.Message)" "WARNING"
                    }
                }
            }
            else {
                Write-LogEntry "Cache already clear: $path" "SUCCESS"
            }
        }

        # DISM component repair (documented repair path for Windows Server 2016+).
        # Runs first when -RunDismRepair is set (default ON) and -LegacyReset is not
        # specified. When the DISM repair succeeds, the legacy regsvr32 re-registration
        # and policy-key deletion steps below are skipped.
        $dismRepairSucceeded = $false

        if (-not $LegacyReset -and $RunDismRepair) {
            Write-LogEntry "Running DISM component repair (RestoreHealth)..." "INFO"
            try {
                if ($PSCmdlet.ShouldProcess("Windows component store", "Run DISM /RestoreHealth")) {
                    $dismExitCode = Invoke-DismRepair
                    $dismRepairSucceeded = ($dismExitCode -eq 0)
                }
                if ($dismRepairSucceeded) {
                    Write-LogEntry "DISM RestoreHealth completed successfully" "SUCCESS"
                }
                else {
                    Write-LogEntry ("DISM RestoreHealth failed (exit code: $dismExitCode); " +
                        "falling back to legacy reset") "WARNING"
                }
            }
            catch {
                Write-LogEntry ("DISM RestoreHealth failed - $($_.Exception.Message); " +
                    "falling back to legacy reset") "WARNING"
            }

            if ($dismRepairSucceeded) {
                Write-LogEntry "Running sfc /scannow..." "INFO"
                try {
                    if ($PSCmdlet.ShouldProcess("System files", "Run sfc /scannow")) {
                        $sfcExitCode = Invoke-SfcScan
                        if ($sfcExitCode -eq 0) {
                            Write-LogEntry "sfc /scannow completed without errors" "SUCCESS"
                        }
                        else {
                            Write-LogEntry "sfc /scannow completed with exit code $sfcExitCode" "WARNING"
                        }
                    }
                }
                catch {
                    Write-LogEntry "sfc /scannow failed - $($_.Exception.Message)" "WARNING"
                }
            }
        }

        # Legacy manual reset steps (regsvr32 re-registration + policy key deletion).
        # Skipped when the DISM repair succeeded, unless -LegacyReset forces them.
        if ($LegacyReset -or -not $dismRepairSucceeded) {

            # Re-register Windows Update DLLs
            if ($PSCmdlet.ShouldProcess("Windows Update DLLs", "Re-register via regsvr32")) {
                Write-LogEntry "Re-registering Windows Update DLLs..." "INFO"
                $dlls = @(
                    "atl.dll", "urlmon.dll", "mshtml.dll", "shdocvw.dll", "browseui.dll",
                    "jscript.dll", "vbscript.dll", "scrrun.dll", "msxml.dll", "msxml3.dll",
                    "msxml6.dll", "actxprxy.dll", "softpub.dll", "wintrust.dll", "dssenh.dll",
                    "rsaenh.dll", "gpkcsp.dll", "sccbase.dll", "slbcsp.dll", "cryptdlg.dll",
                    "oleaut32.dll", "ole32.dll", "shell32.dll", "initpki.dll", "wuapi.dll",
                    "wuaueng.dll", "wuaueng1.dll", "wucltui.dll", "wups.dll", "wups2.dll",
                    "wuweb.dll", "qmgr.dll", "qmgrprxy.dll", "wucltux.dll", "muweb.dll", "wuwebv.dll"
                )

                $registeredCount = 0
                foreach ($dll in $dlls) {
                    try {
                        Invoke-RegSvr32 -Dll $dll | Out-Null
                        $registeredCount++
                    }
                    catch {
                        Write-LogEntry "Failed to register: $dll" "WARNING"
                    }
                }
                Write-LogEntry "Re-registered $registeredCount DLLs" "SUCCESS"

                # Reset Windows Update policies
                Write-LogEntry "Resetting Windows Update policies..." "INFO"
                $regPaths = @(
                    "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate",
                    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate"
                )

                foreach ($regPath in $regPaths) {
                    if (Test-Path $regPath) {
                        if ($PSCmdlet.ShouldProcess($regPath, "Remove Windows Update policy key")) {
                            try {
                                Remove-Item -Path $regPath -Recurse -Force -ErrorAction SilentlyContinue
                                Write-LogEntry "Removed registry path: $regPath" "SUCCESS"
                            }
                            catch {
                                Write-LogEntry ("Failed to remove registry path: $regPath - " +
                                    "$($_.Exception.Message)") "WARNING"
                            }
                        }
                    }
                }
            }
        } # end legacy reset steps (skipped when DISM repair succeeded)

        # Reset BITS queue if FullReset is specified
        if ($FullReset) {
            if ($PSCmdlet.ShouldProcess("BITS transfer queue", "Clear queue")) {
                Write-LogEntry "Performing full reset including BITS queue..." "INFO"
                try {
                    Get-BitsTransfer | Remove-BitsTransfer -ErrorAction SilentlyContinue
                    Write-LogEntry "BITS queue cleared" "SUCCESS"
                }
                catch {
                    Write-LogEntry "Failed to clear BITS queue - $($_.Exception.Message)" "WARNING"
                }
            }
        }

        # Reset Windows Update Agent
        Write-LogEntry "Resetting Windows Update Agent..." "INFO"
        if (Test-Path "$env:SystemRoot\System32\catroot2.bak") {
            if ($PSCmdlet.ShouldProcess("$env:SystemRoot\System32\catroot2.bak", "Remove catroot2 backup")) {
                try {
                    Remove-Item -Path "$env:SystemRoot\System32\catroot2.bak" `
                        -Recurse -Force -ErrorAction SilentlyContinue
                }
                catch {
                    Write-Host "[!] Failed to clean catroot2 backup: $($_.Exception.Message)" -ForegroundColor Yellow
                }
            }
        }

        # Start Windows Update Services
        if ($PSCmdlet.ShouldProcess(
                "Windows Update services (wuauserv, cryptSvc, bits, msiserver)",
                "Start services")) {
            Write-LogEntry "Starting Windows Update services..." "INFO"
            foreach ($service in @("wuauserv", "cryptSvc", "bits", "msiserver")) {
                try {
                    Start-Service -Name $service -ErrorAction SilentlyContinue
                    Write-LogEntry "Started service: $service" "SUCCESS"
                }
                catch {
                    Write-LogEntry "Failed to start service: $service - $($_.Exception.Message)" "WARNING"
                }
            }
        }

        # Trigger Windows Update detection
        Write-LogEntry "Triggering Windows Update detection..." "INFO"
        try {
            if ($PSCmdlet.ShouldProcess("Windows Update Agent", "Trigger update detection")) {
                $updateSession = New-Object -ComObject Microsoft.Update.Session
                $updateSearcher = $updateSession.CreateUpdateSearcher()
                $updateSearcher.Search("IsInstalled=0") | Out-Null
                Write-LogEntry "Windows Update detection triggered successfully" "SUCCESS"
            }
        }
        catch {
            Write-LogEntry "Failed to trigger Windows Update detection - $($_.Exception.Message)" "WARNING"
        }

        Write-LogEntry "Windows Update reset completed!" "SUCCESS"
        Write-LogEntry "Please check Windows Update for available updates." "INFO"
        return 0
    }
    catch {
        Write-Host "[-] Error: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main @PSBoundParameters) }
