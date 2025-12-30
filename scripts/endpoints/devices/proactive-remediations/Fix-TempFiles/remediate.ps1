# Clean temp files older than 7 days
$tempPaths = @("$env:TEMP", "$env:SystemRoot\Temp")
$cleaned = 0

foreach($path in $tempPaths) {
    if(Test-Path $path) {
        $beforeSize = (Get-ChildItem $path -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
        Get-ChildItem $path -Recurse -File -ErrorAction SilentlyContinue | Where-Object {$_.LastWriteTime -lt (Get-Date).AddDays(-7)} | Remove-Item -Force -ErrorAction SilentlyContinue
        $afterSize = (Get-ChildItem $path -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
        $cleaned += [math]::Round(($beforeSize - $afterSize) / 1GB, 2)
    }
}

Write-Host "Cleaned $cleaned GB of temp files"
exit 0
