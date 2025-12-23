# Remediate disk space by cleaning temp files, recycle bin, and Windows Update cache
$cleaned = 0

# Clean Windows temp
$winTemp = "$env:SystemRoot\Temp"
$beforeSize = (Get-ChildItem $winTemp -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
Get-ChildItem $winTemp -Recurse -File -ErrorAction SilentlyContinue | Where-Object {$_.LastWriteTime -lt (Get-Date).AddDays(-7)} | Remove-Item -Force -ErrorAction SilentlyContinue
$afterSize = (Get-ChildItem $winTemp -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
$cleaned += [math]::Round(($beforeSize - $afterSize) / 1GB, 2)

# Empty recycle bin
Clear-RecycleBin -Force -ErrorAction SilentlyContinue

# Clean Windows Update cache
$wuCache = "$env:SystemRoot\SoftwareDistribution\Download"
if(Test-Path $wuCache) {
    Stop-Service wuauserv -Force -ErrorAction SilentlyContinue
    $beforeSize = (Get-ChildItem $wuCache -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
    Get-ChildItem $wuCache -Recurse -ErrorAction SilentlyContinue | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
    $afterSize = (Get-ChildItem $wuCache -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
    $cleaned += [math]::Round(($beforeSize - $afterSize) / 1GB, 2)
    Start-Service wuauserv -ErrorAction SilentlyContinue
}

Write-Host "Cleaned $cleaned GB of disk space"
exit 0
