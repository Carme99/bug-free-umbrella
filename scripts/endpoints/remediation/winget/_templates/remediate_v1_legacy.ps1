<#
.SYNOPSIS
    Legacy winget update remediation template (V1)

.DESCRIPTION
    Template for winget application update remediation scripts. Upgrades the package to the available version without force-closing the application process; exits 0 on success and 1 when the app is running or the upgrade fails. Replace the APPNAME, WINGETID and PROCESS placeholders before use.

.EXAMPLE
    ./remediate.ps1

.NOTES
    File Name  : remediate_v1_legacy.ps1
    Author     : Intune / Proactive Remediations
    Prerequisite: PowerShell 5.1 or later, run in the Intune Proactive Remediation context
    Version    : 1.0.0
    Date       : 2026-08-08
#>

#Display name of your application (Used for reporting purposes)
$name = 'APPNAME'
#winget ID for the package
$ID = 'WINGETID'
#Name of the running process (so you don't force close it)
$AppProcess = "PROCESS"

# Prefer the Microsoft.WinGet.Client PowerShell module - the winget CLI is NOT supported in
# the SYSTEM context (Intune Proactive Remediations run as SYSTEM). Only fall back to the
# winget.exe CLI when the module is unavailable.
# Reference: https://learn.microsoft.com/en-us/windows/package-manager/winget/troubleshooting
if (Get-Module -ListAvailable -Name Microsoft.WinGet.Client) {
    try { Import-Module Microsoft.WinGet.Client -ErrorAction Stop } catch { Write-Verbose "Handled exception: $($_.Exception.Message)" -Verbose:$false }
    if (Get-Command Get-WinGetPackage -ErrorAction SilentlyContinue) {
        $package = Get-WinGetPackage -Id $ID -MatchOption EqualsCaseInsensitive -ErrorAction SilentlyContinue
        if (-not $package) { Write-Host "$name is not installed on this device."; exit 0 }
        $process = Get-Process -Name "$AppProcess" -ErrorAction SilentlyContinue
        if ($process -eq $null) {
            #run the upgrade
            Update-WinGetPackage -Id $ID -MatchOption EqualsCaseInsensitive -Mode Silent -Force -ErrorAction Stop
            #rechecks the version if it installed and creates values for final output.
            $package = Get-WinGetPackage -Id $ID -MatchOption EqualsCaseInsensitive -ErrorAction SilentlyContinue
            if ($package) {
                $versioninstalled = $package.InstalledVersion
                [pscustomobject] @{
                    Name = $name
                    InstalledVersion = $VersionInstalled
                }
                Write-Host "$name upgraded to $versioninstalled, or $name was already up to date."
                exit 0
            }
        }
        else {
            Write-Host "$Name is currently running, will try again later."
            exit 1
        }
    }
}

#location of the winget exe
$wingetexe = Resolve-Path "C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\winget.exe"
if ($wingetexe) {
    $SystemContext = $wingetexe[-1].Path
}
#create the sysget alias so winget can be ran as system
New-Alias -Name sysget -Value "$systemcontext"
#this gets the info on the app (if it has an update, or not)
$lines = sysget list --exact --id $ID --accept-source-agreements
#tries to upgrade if the installed version is lower than the available version
try {
    if ($lines -match '\bVersion\s+Available\b') {
        $verinstalled, $verAvailable = (-split $lines[-1])[-3, -2]
        Write-Verbose -Verbose "Application update available for $name"
        Write-Verbose -Verbose "Downloading and Installing $name"
    }
    #checks if your app is running as to not auto-close. change the process value to the app you want.
    $process = Get-Process -Name "$AppProcess" -ErrorAction SilentlyContinue
    if ($process -eq $null) {
        #run the upgrade
        sysget upgrade -e --id $ID --silent --accept-package-agreements --accept-source-agreements
        #rechecks the version if it installed and creates values for final output.
        $lines = sysget list --exact --id $ID --accept-source-agreements 
    }
    else {
        Write-Host "$Name is currently running, will try again later."
        exit 1
    }
    if ($Lines -match '\d+(\.\d+)+') {
        $versionavailable, $versioninstalled = (-split $Lines[-1])[-3, -2]

        #the final output as a pscustomobject
        [pscustomobject] @{
            Name = $name
            InstalledVersion = $VersionInstalled
        }
        exit 0
    }
    else {
        Write-Host "$Name is currently running, will try again later."
        exit 1
    } 

}
catch {
    $errMsg = $_.Exception.Message
    Write-Error $errMsg
    exit 1
}
