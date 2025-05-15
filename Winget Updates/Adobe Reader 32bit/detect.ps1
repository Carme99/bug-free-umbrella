# Proactive Remediation Detection Script for Adobe Acrobat (32-bit) via Winget
$name = 'Adobe Acrobat'
$AppID = 'Adobe.Acrobat.Reader.32-bit'

$wingetexe = Resolve-Path "C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\winget.exe"
if ($wingetexe) { $SystemContext = $wingetexe[-1].Path }

New-Alias -Name sysget -Value "$SystemContext"

try {
    $lines = sysget list --accept-source-agreements --Id $AppID
    if ($lines -match '\bVersion\s+Available\b') {
        Write-Output "$name (32-bit) update available."
        Exit 1
    } elseif ($lines -match "No installed package found matching input criteria.") {
        Write-Output "$name (32-bit) is not installed."
        Exit 0
    } else {
        Write-Output "$name (32-bit) is already up to date."
        Exit 0
    }
} catch {
    Write-Output "Error checking update: $_"
    Exit 0
}