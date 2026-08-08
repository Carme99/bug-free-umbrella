# Detect excessive temp files (> 1GB)
# In SYSTEM context $env:TEMP points at the SYSTEM profile temp folder - real
# user temp folders must be enumerated explicitly or they are never cleaned.
$threshold = 1GB
$tempPaths = @("$env:TEMP", "$env:SystemRoot\Temp")

# Per-user temp folders - every non-special profile is enumerated so temp files
# of users who are not currently logged on are also covered.
$userProfiles = Get-CimInstance Win32_UserProfile | Where-Object {
    $_.Special -eq $false -and $_.LocalPath -notmatch 'systemprofile|defaultuser'
}

foreach ($profile in $userProfiles) {
    $userTemp = Join-Path $profile.LocalPath "AppData\Local\Temp"
    if (Test-Path $userTemp) {
        $tempPaths += $userTemp
    }
}

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
