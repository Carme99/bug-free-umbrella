# Detect excessive temp files (> 1GB)
$threshold = 1GB
$tempPaths = @("$env:TEMP", "$env:SystemRoot\Temp")
$totalSize = 0

foreach($path in $tempPaths) {
    if(Test-Path $path) {
        $size = (Get-ChildItem $path -Recurse -File -ErrorAction SilentlyContinue | Where-Object {$_.LastWriteTime -lt (Get-Date).AddDays(-7)} | Measure-Object -Property Length -Sum).Sum
        $totalSize += $size
    }
}

$totalGB = [math]::Round($totalSize / 1GB, 2)

if($totalSize -gt $threshold) {
    Write-Host "Excessive temp files: $totalGB GB"
    exit 1
}

Write-Host "Temp files normal: $totalGB GB"
exit 0
