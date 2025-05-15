#name of your app in winget
$name = 'Google Chrome'
#winget ID for the package
$ID = 'Google.Chrome'
#Name of the running process (so you don't force close it)
$AppProcess = "chrome"
#location of the winget exe
$wingetexe = Resolve-Path "C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\winget.exe"
    if ($wingetexe){
           $SystemContext = $wingetexe[-1].Path
    }
#create the sysget alias so winget can be ran as system
new-alias -Name sysget -Value "$systemcontext"
#this gets the info on the app (if it has an update, or not)
$lines = sysget list --accept-source-agreements --Id $ID
#tries to upgrade if the installed version is lower than the available version
try {
if ($lines -match '\bVersion\s+Available\b') {
$verinstalled, $verAvailable = (-split $lines[-1])[-3,-2]
Write-Verbose -Verbose "Application update available for $name"
Write-Verbose -Verbose "Downloading and Installing $name"
}
#checks if your app is running as to not auto-close. change the process value to the app you want.
$process = get-process -name "$AppProcess" -ErrorAction SilentlyContinue
if ($process -eq $null){
#run the upgrade
sysget upgrade -e --id $ID --silent --accept-package-agreements --accept-source-agreements
#rechecks the version if it installed and creates values for final output.
$lines = sysget list --accept-source-agreements --Id $ID } else {write-host "$Name is currently running, will try again later."
exit 1
}
if ($Lines -match '\d+(\.\d+)+') {
$versionavailable, $versioninstalled = (-split $Lines[-1])[-3,-2]

#the final output as a pscustomobject
[pscustomobject] @{
Name = $name
InstalledVersion = $VersionInstalled}
exit 0
} else 
{
write-host "$Name is currently running, will try again later."
exit 1
} 

}catch {
  $errMsg = $_.Exception.Message
    Write-Error $errMsg
   exit 1
   }