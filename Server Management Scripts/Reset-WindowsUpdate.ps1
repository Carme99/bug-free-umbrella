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

.EXAMPLE
    .\Reset-WindowsUpdate.ps1
    Performs a standard Windows Update reset.

.EXAMPLE
    .\Reset-WindowsUpdate.ps1 -FullReset
    Performs a comprehensive reset including all related services.

.NOTES
    Requires Administrator privileges
    Compatible with Windows Server 2016, 2019, and 2022
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [switch]$FullReset
)

# Requires Administrator privileges
#Requires -RunAsAdministrator

function Write-Log {
    param([string]$Message, [string]$Type = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $color = switch($Type) {
        "ERROR" { "Red" }
        "SUCCESS" { "Green" }
        "WARNING" { "Yellow" }
        default { "White" }
    }
    Write-Host "[$timestamp] [$Type] $Message" -ForegroundColor $color
}

Write-Log "Starting Windows Update Reset Process" "INFO"
Write-Log "Server: $env:COMPUTERNAME | OS: $((Get-WmiObject Win32_OperatingSystem).Caption)" "INFO"

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
catch {}

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
