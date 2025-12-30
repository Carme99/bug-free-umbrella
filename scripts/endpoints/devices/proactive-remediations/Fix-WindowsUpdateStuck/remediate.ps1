# Reset Windows Update components
Write-Host "Resetting Windows Update..."

# Stop services
Stop-Service wuauserv, cryptSvc, bits, msiserver -Force -ErrorAction SilentlyContinue

# Clear Windows Update cache
$wuCache = "$env:SystemRoot\SoftwareDistribution"
if(Test-Path $wuCache) {
    Rename-Item $wuCache "$wuCache.old" -Force -ErrorAction SilentlyContinue
}

$catroot = "$env:SystemRoot\System32\catroot2"
if(Test-Path $catroot) {
    Rename-Item $catroot "$catroot.old" -Force -ErrorAction SilentlyContinue
}

# Restart services
Start-Service wuauserv, cryptSvc, bits, msiserver -ErrorAction SilentlyContinue

Write-Host "Windows Update reset complete"
exit 0
