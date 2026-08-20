<#
.SYNOPSIS
    Resets Windows Update components to resolve update issues on Windows Server 2016-2022.

.DESCRIPTION
    This script performs a comprehensive reset of Windows Update components by:
    - Stopping Windows Update services
    - Clearing update cache and temporary files
    - Resetting Windows Update settings
    - Re-registering Windows Update DLLs
    - Restarting services

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
    .\Reset-WindowsUpdate.ps1
    Performs a standard Windows Update reset (DISM repair first).

.EXAMPLE
    .\Reset-WindowsUpdate.ps1 -FullReset
    Performs a comprehensive reset including all related services.

.EXAMPLE
    .\Reset-WindowsUpdate.ps1 -LegacyReset
    Performs the legacy manual reset without the DISM repair step.

.NOTES
    Requires Administrator privileges
    Compatible with Windows Server 2016, 2019, and 2022
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [switch]$FullReset,

    [Parameter(Mandatory = $false)]
    [switch]$RunDismRepair = $true,

    [Parameter(Mandatory = $false)]
    [switch]$LegacyReset
)

# Requires Administrator privileges
#Requires -RunAsAdministrator

function Write-Log {
    param([string]$Message, [string]$Type = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $color = switch ($Type) {
        "ERROR" { "Red" }
        "SUCCESS" { "Green" }
        "WARNING" { "Yellow" }
        default { "White" }
    }
    Write-Host "[$timestamp] [$Type] $Message" -ForegroundColor $color
}

Write-Log "Starting Windows Update Reset Process" "INFO"
Write-Log "Server: $env:COMPUTERNAME | OS: $((Get-CimInstance -ClassName Win32_OperatingSystem).Caption)" "INFO"

# Stop Windows Update Services
Write-Log "Stopping Windows Update services..." "INFO"
$services = @("wuauserv", "cryptSvc", "bits", "msiserver")

foreach ($service in $services) {
    try {
        Stop-Service -Name $service -Force -ErrorAction SilentlyContinue
        Write-Log "Stopped service: $service" "SUCCESS"
    }
    catch {
        Write-Log "Failed to stop service: $service - $($_.Exception.Message)" "WARNING"
    }
}

# Clear Windows Update cache
Write-Log "Clearing Windows Update cache..." "INFO"
$cachePaths = @(
    "$env:SystemRoot\SoftwareDistribution",
    "$env:SystemRoot\System32\catroot2"
)

foreach ($path in $cachePaths) {
    if (Test-Path $path) {
        try {
            Remove-Item -Path "$path\*" -Recurse -Force -ErrorAction SilentlyContinue
            Write-Log "Cleared cache: $path" "SUCCESS"
        }
        catch {
            Write-Log "Failed to clear cache: $path - $($_.Exception.Message)" "WARNING"
        }
    }
}

# DISM component repair (documented repair path for Windows Server 2016+).
# Runs first when -RunDismRepair is set (default ON) and -LegacyReset is not
# specified. When the DISM repair succeeds, the legacy regsvr32 re-registration
# and policy-key deletion steps below are skipped.
$dismRepairSucceeded = $false

if (-not $LegacyReset -and $RunDismRepair) {
    Write-Log "Running DISM component repair (RestoreHealth)..." "INFO"
    try {
        Dism.exe /Online /Cleanup-Image /RestoreHealth
        $dismRepairSucceeded = ($LASTEXITCODE -eq 0)
        if ($dismRepairSucceeded) {
            Write-Log "DISM RestoreHealth completed successfully" "SUCCESS"
        }
        else {
            Write-Log "DISM RestoreHealth failed (exit code: $LASTEXITCODE); falling back to legacy reset" "WARNING"
        }
    }
    catch {
        Write-Log "DISM RestoreHealth failed - $($_.Exception.Message); falling back to legacy reset" "WARNING"
    }

    if ($dismRepairSucceeded) {
        Write-Log "Running sfc /scannow..." "INFO"
        try {
            sfc.exe /scannow
            if ($LASTEXITCODE -eq 0) {
                Write-Log "sfc /scannow completed without errors" "SUCCESS"
            }
            else {
                Write-Log "sfc /scannow completed with exit code $LASTEXITCODE" "WARNING"
            }
        }
        catch {
            Write-Log "sfc /scannow failed - $($_.Exception.Message)" "WARNING"
        }
    }
}

# Legacy manual reset steps (regsvr32 re-registration + policy key deletion).
# Skipped when the DISM repair succeeded, unless -LegacyReset forces them.
if ($LegacyReset -or -not $dismRepairSucceeded) {

    # Re-register Windows Update DLLs
    Write-Log "Re-registering Windows Update DLLs..." "INFO"
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
            Start-Process "regsvr32.exe" -ArgumentList "/s $dll" -Wait -WindowStyle Hidden -ErrorAction SilentlyContinue
            $registeredCount++
        }
        catch {
            Write-Log "Failed to register: $dll" "WARNING"
        }
    }
    Write-Log "Re-registered $registeredCount DLLs" "SUCCESS"

    # Reset Windows Update policies
    Write-Log "Resetting Windows Update policies..." "INFO"
    $regPaths = @(
        "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate"
    )

    foreach ($regPath in $regPaths) {
        if (Test-Path $regPath) {
            try {
                Remove-Item -Path $regPath -Recurse -Force -ErrorAction SilentlyContinue
                Write-Log "Removed registry path: $regPath" "SUCCESS"
            }
            catch {
                Write-Log "Failed to remove registry path: $regPath - $($_.Exception.Message)" "WARNING"
            }
        }
    }

} # end legacy reset steps (skipped when DISM repair succeeded)

# Reset BITS queue if FullReset is specified
if ($FullReset) {
    Write-Log "Performing full reset including BITS queue..." "INFO"
    try {
        Get-BitsTransfer | Remove-BitsTransfer -ErrorAction SilentlyContinue
        Write-Log "BITS queue cleared" "SUCCESS"
    }
    catch {
        Write-Log "Failed to clear BITS queue - $($_.Exception.Message)" "WARNING"
    }
}

# Reset Windows Update Agent
Write-Log "Resetting Windows Update Agent..." "INFO"
try {
    Remove-Item -Path "$env:SystemRoot\System32\catroot2.bak" -Recurse -Force -ErrorAction SilentlyContinue
}
catch {
    Write-Host "[!] Failed to clean catroot2 backup: $($_.Exception.Message)" -ForegroundColor Yellow
}

# Start Windows Update Services
Write-Log "Starting Windows Update services..." "INFO"
foreach ($service in $services) {
    try {
        Start-Service -Name $service -ErrorAction SilentlyContinue
        Write-Log "Started service: $service" "SUCCESS"
    }
    catch {
        Write-Log "Failed to start service: $service - $($_.Exception.Message)" "WARNING"
    }
}

# Trigger Windows Update detection
Write-Log "Triggering Windows Update detection..." "INFO"
try {
    $updateSession = New-Object -ComObject Microsoft.Update.Session
    $updateSearcher = $updateSession.CreateUpdateSearcher()
    $updateSearcher.Search("IsInstalled=0") | Out-Null
    Write-Log "Windows Update detection triggered successfully" "SUCCESS"
}
catch {
    Write-Log "Failed to trigger Windows Update detection - $($_.Exception.Message)" "WARNING"
}

Write-Log "Windows Update reset completed!" "SUCCESS"
Write-Log "Please check Windows Update for available updates." "INFO"
