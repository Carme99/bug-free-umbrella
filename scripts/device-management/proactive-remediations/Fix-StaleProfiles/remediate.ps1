# Remove profiles not accessed in 120+ days (more conservative for remediation)
$threshold = 120
$profilePath = "C:\Users"
$removed = @()

$profiles = Get-ChildItem $profilePath -Directory -ErrorAction SilentlyContinue | Where-Object {
    $_.Name -notmatch '^(Public|Default|Default User|All Users)$'
}

foreach($profile in $profiles) {
    $age = ((Get-Date) - $profile.LastAccessTime).Days
    
    if($age -gt $threshold) {
        try {
            $sizeBefore = [math]::Round((Get-ChildItem $profile.FullName -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum / 1GB, 2)
            Remove-Item $profile.FullName -Recurse -Force -ErrorAction Stop
            $removed += "$($profile.Name) ($sizeBefore GB)"
        }
        catch {
            Write-Host "Could not remove $($profile.Name): $($_.Exception.Message)"
        }
    }
}

if($removed.Count -gt 0) {
    Write-Host "Removed $($removed.Count) stale profiles: $($removed -join '; ')"
} else {
    Write-Host "No profiles removed"
}
exit 0
