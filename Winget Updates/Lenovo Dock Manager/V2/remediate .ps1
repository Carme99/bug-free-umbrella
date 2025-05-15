$name = 'Lenovo Dock Manager'
$ID = 'Lenovo.DockManager'
$AppProcess = "LenovoDockMgr"
$AppExePath = "C:\Program Files\Lenovo\Dock Manager\dockmgr.exe"  # Correct path for the executable

# Find winget in system context
$wingetexe = Resolve-Path "C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\winget.exe"
if ($wingetexe) {
    $SystemContext = $wingetexe[-1].Path
}
New-Alias -Name sysget -Value "$SystemContext"

try {
    $lines = sysget list --accept-source-agreements --Id $ID

    if ($lines -match '\bVersion\s+Available\b') {
        $updateLine = $lines | Where-Object { $_ -match $ID }
        $verinstalled, $verAvailable = (-split $updateLine)[-3,-2]

        Write-Host "$name update found: $verinstalled -> $verAvailable"

        # Stop the app if it's running
        $process = Get-Process -Name "$AppProcess" -ErrorAction SilentlyContinue
        if ($process) {
            Write-Host "Stopping $AppProcess..."
            Stop-Process -Name $AppProcess -Force
            Start-Sleep -Seconds 2
        }

        # Run the update
        Write-Host "Running sysget upgrade..."
        sysget upgrade -e --id $ID --silent --accept-package-agreements --accept-source-agreements

        # Re-check and confirm version
        $lines = sysget list --accept-source-agreements --Id $ID
        $updateLine = $lines | Where-Object { $_ -match $ID }
        $versionavailable, $versioninstalled = (-split $updateLine)[-3,-2]

        # Restart the app
        if (Test-Path $AppExePath) {
            Write-Host "Restarting $AppProcess..."
            Start-Process -FilePath $AppExePath
        } else {
            Write-Warning "Could not find the application executable at $AppExePath to restart it."
        }

        [pscustomobject]@{
            Name = $name
            InstalledVersion = $versioninstalled
        }

        Write-Host "$name updated successfully to $versioninstalled"
        exit 0
    }
    else {
        Write-Host "$name is already up to date."
        exit 0
    }
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}
