# Detect user profiles not accessed in 90+ days
$threshold = 90
$profilePath = "C:\Users"
$staleProfiles = @()

$profiles = Get-ChildItem $profilePath -Directory -ErrorAction SilentlyContinue | Where-Object {
    $_.Name -notmatch '^(Public|Default|Default User|All Users)$'
}

foreach($profile in $profiles) {
    $lastAccess = $profile.LastAccessTime
    $age = ((Get-Date) - $lastAccess).Days
    
    if($age -gt $threshold) {
        $sizeGB = [math]::Round((Get-ChildItem $profile.FullName -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum / 1GB, 2)
        $staleProfiles += "$($profile.Name) ($age days old, $sizeGB GB)"
    }
}

if($staleProfiles.Count -gt 0) {
    Write-Host "Found $($staleProfiles.Count) stale profiles: $($staleProfiles -join '; ')"
    exit 1
}

Write-Host "No stale profiles found"
exit 0
