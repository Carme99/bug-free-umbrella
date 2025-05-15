# Proactive Remediation Remediation Script for Adobe Acrobat (64-bit) via Winget
$name = 'Adobe Acrobat'
$AppID = 'Adobe.Acrobat.Reader.64-bit'

$wingetexe = Resolve-Path "C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\winget.exe"
if ($wingetexe) { $SystemContext = $wingetexe[-1].Path }

New-Alias -Name sysget -Value "$SystemContext"

try {
    Write-Output "Starting $name (64-bit) update via Winget."
    sysget install --id $AppID --silent --accept-source-agreements --accept-package-agreements -v
    Write-Output "$name (64-bit) update attempt completed."
} catch {
    Write-Output "Error updating $name (64-bit): $_"
}
