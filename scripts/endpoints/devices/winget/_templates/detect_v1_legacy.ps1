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
    try { Import-Module Microsoft.WinGet.Client -ErrorAction Stop } catch { }
    if (Get-Command Get-WinGetPackage -ErrorAction SilentlyContinue) {
        $package = Get-WinGetPackage -Id $ID -MatchOption EqualsCaseInsensitive -ErrorAction SilentlyContinue
        $process = get-process -name "$AppProcess" -ErrorAction SilentlyContinue
        #check if there's an available update
        if (-not $package) { write-host "$name is not installed on this device."; exit 0 }
        if ($package.IsUpdateAvailable -and $process -ne $null) {
            $verinstalled = $package.InstalledVersion
            $verAvailable = $package.AvailableVersions | Select-Object -Last 1
            Write-Verbose -Verbose "Application update available for $Name. Current version is $verinstalled, version available is $verAvailable. $Name is currently running, will try again later."
            [pscustomobject] @{
                Name = $Name
                InstalledVersion = $verInstalled
                AvailableVersion = $verAvailable
            }
            write-host "Application update available for $Name. Current version is $verinstalled, version available is $verAvailable. $Name is currently running, will try again later."
            exit 1
        }
        if ($package.IsUpdateAvailable -and $process -eq $null) {
            $verinstalled = $package.InstalledVersion
            $verAvailable = $package.AvailableVersions | Select-Object -Last 1
            Write-Verbose -Verbose "Application update available for $Name. Current version is $verinstalled, version available is $verAvailable"
            [pscustomobject] @{
                Name = $Name
                InstalledVersion = $verInstalled
                AvailableVersion = $verAvailable
            }
            write-host "Application update available for $Name. Current version is $verinstalled, version available is $verAvailable"
            exit 1
        }
        Write-Host "$name upgraded to $($package.InstalledVersion), or $name was already up to date."
        exit 0
    }
}

#location of the winget exe
$wingetexe = Resolve-Path "C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\winget.exe"
    if ($wingetexe){
           $SystemContext = $wingetexe[-1].Path
    }
#create the sysget alias so winget can be ran as system
new-alias -Name sysget -Value "$systemcontext"
#this gets the info on the app (if it has an update, or not)
$lines = sysget list --exact --id $ID --accept-source-agreements
try {
$process = get-process -name "$AppProcess" -ErrorAction SilentlyContinue
#check if there's an available update
if (($lines -match '\bVersion\s+Available\b' -and $process -ne $null)) {
$verinstalled, $verAvailable = (-split $lines[-1])[-3,-2]
Write-Verbose -Verbose "Application update available for $Name. Current version is $verinstalled, version available is $verAvailable. $Name is currently running, will try again later."
#create custom psobject for reporting the output in intune
[pscustomobject] @{
Name = $Name
InstalledVersion = $verInstalled
AvailableVersion = $verAvailable
}
write-host "Application update available for $Name. Current version is $verinstalled, version available is $verAvailable. $Name is currently running, will try again later."
exit 1
}
if (($lines -match '\bVersion\s+Available\b' -and $process -eq $null)) {
$verinstalled, $verAvailable = (-split $lines[-1])[-3,-2]
Write-Verbose -Verbose "Application update available for $Name. Current version is $verinstalled, version available is $verAvailable"
#create custom psobject for reporting the output in intune
[pscustomobject] @{
Name = $Name
InstalledVersion = $verInstalled
AvailableVersion = $verAvailable
}
write-host "Application update available for $Name. Current version is $verinstalled, version available is $verAvailable"
exit 1
}else {
if ($lines -eq "No installed package found matching input criteria.") {write-host "$name is not installed on this device." 
exit 0
}else{
#rechecks the version if it installed and creates values for final output.
$lines = sysget list --exact --id $ID --accept-source-agreements
if ($Lines -match '\d+(\.\d+)+') {
$versionavailable, $versioninstalled = (-split $Lines[-1])[-3,-2]
}
#the final output as a pscustomobject
[pscustomobject] @{
Name = $name
InstalledVersion = $VersionInstalled
}}
Write-Host "$name upgraded to $versioninstalled, or $name was already up to date."
exit 0
}
}
catch {
  $errMsg = $_.Exception.Message
    Write-Error $errMsg
   exit 1
} 
