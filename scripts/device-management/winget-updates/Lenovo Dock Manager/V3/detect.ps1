$name = 'Lenovo Dock Manager'
$ID = 'Lenovo.DockManager'

# Find winget in system context
$wingetexe = Resolve-Path "C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\winget.exe"
if ($wingetexe) {
    $SystemContext = $wingetexe[-1].Path
}
New-Alias -Name sysget -Value "$SystemContext"

try {
    # Get the installed package info
    $lines = sysget list --accept-source-agreements --Id $ID

    if ($lines -match '\bVersion\s+Available\b') {
        $updateLine = $lines | Where-Object { $_ -match $ID }
        $verinstalled, $verAvailable = (-split $updateLine)[-3,-2]

        # Detect if installed version is older than available version
        if ($verinstalled -lt $verAvailable) {
            # If installed version is lower, trigger an update
            [pscustomobject]@{
                Name = $name
                InstalledVersion = $verinstalled
                AvailableVersion = $verAvailable
                Status = 'Update Available'
            }
            Write-Host "$name needs an update: $verinstalled -> $verAvailable"
            exit 1
        }
        else {
            # If already up-to-date
            [pscustomobject]@{
                Name = $name
                InstalledVersion = $verinstalled
                AvailableVersion = $verAvailable
                Status = 'Up-to-Date'
            }
            Write-Host "$name is up to date: $verinstalled"
            exit 0
        }
    }
    else {
        # No installed version found
        Write-Host "$name is not installed."
        exit 0
    }
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}
