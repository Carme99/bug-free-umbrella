# Proactive Remediation Remediation Script for Adobe Acrobat (32-bit) via Winget
$name = 'Adobe Acrobat'
$AppID = 'Adobe.Acrobat.Reader.32-bit'

$wingetexe = Resolve-Path "C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\winget.exe"
if ($wingetexe) { $SystemContext = $wingetexe[-1].Path }

New-Alias -Name sysget -Value "$SystemContext"

try {
    Write-Output "Starting $name (32-bit) update via Winget."
    sysget install --id $AppID --silent --accept-source-agreements --accept-package-agreements -v
    Write-Output "$name (32-bit) update attempt completed."
} catch {
    Write-Output "Error updating $name (32-bit): $_"
}