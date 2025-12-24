# Display name of your application (Used for reporting purposes)
$name = 'TeamViewer Full'

# Winget ID for the package
$ID = 'TeamViewer.TeamViewer'

# Name of the TeamViewer process
$AppProcess = "TeamViewer"

# TeamViewer executable paths
$TeamViewerPaths = @(
    "C:\Program Files\TeamViewer\TeamViewer.exe",
    "C:\Program Files (x86)\TeamViewer\TeamViewer.exe"
)

# Location of the winget executable
$wingetexe = Resolve-Path "C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\winget.exe" -ErrorAction SilentlyContinue
if ($wingetexe) {
    $SystemContext = $wingetexe[-1].Path
} else {
    Write-Error "Winget not found. Exiting."
    exit 1
}

# Create alias for system-wide execution
New-Alias -Name sysget -Value "$SystemContext" -Force

# Check if TeamViewer is installed
$TeamViewerInstalled = $TeamViewerPaths | Where-Object { Test-Path $_ }

if ($TeamViewerInstalled) {
    Write-Host "TeamViewer is installed at: $TeamViewerInstalled"
} else {
    Write-Host "TeamViewer is not installed. Exiting."
    exit 0
}

# Close TeamViewer if running
$process = Get-Process -Name "$AppProcess" -ErrorAction SilentlyContinue
if ($process) {
    Write-Host "Closing TeamViewer..."
    Stop-Process -Name "$AppProcess" -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 5
} else {
    Write-Host "TeamViewer is not running."
}

# Check for available updates
$lines = sysget list --accept-source-agreements --Id $ID
if ($lines -match '\bVersion\s+Available\b') {
    $verinstalled, $verAvailable = (-split $lines[-1])[-3,-2]
    Write-Host "Update available for $name: Installed $verinstalled → Available $verAvailable"
    
    # Run the upgrade
    Write-Host "Updating $name..."
    sysget upgrade -e --id $ID --silent --accept-package-agreements --accept-source-agreements
    Start-Sleep -Seconds 10  # Allow time for the update to complete
    
    # Verify installation
    $lines = sysget list --accept-source-agreements --Id $ID
    if ($lines -match '\d+(\.\d+)+') {
        $versionavailable, $versioninstalled = (-split $lines[-1])[-3,-2]
        Write-Host "$name updated successfully to version $versioninstalled"
        exit 0
    } else {
        Write-Error "Failed to verify installation. Please check manually."
        exit 1
    }
} else {
    Write-Host "No update available for $name."
    exit 0
}
