<#
.SYNOPSIS
    Clean temp files older than 7 days

.DESCRIPTION
    Deletes temp files older than 7 days from the SYSTEM temp folder, the Windows temp folder and every per-user temp folder (enumerated from Win32_UserProfile). Reports the number of files and space reclaimed.

.EXAMPLE
    ./remediate.ps1

.NOTES
    File Name  : remediate.ps1
    Author     : Intune / Proactive Remediations
    Prerequisite: PowerShell 5.1 or later, run in the Intune Proactive Remediation context
    Version    : 1.0.0
    Date       : 2026-08-08
#>

# Clean temp files older than 7 days
# In SYSTEM context $env:TEMP points at the SYSTEM profile temp folder - real
# user temp folders must be enumerated explicitly or they are never cleaned.
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

$cleaned = 0

foreach ($path in $tempPaths) {
    if (Test-Path $path) {
        $beforeSize = (Get-ChildItem $path -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
        Get-ChildItem $path -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-7) } | Remove-Item -Force -ErrorAction SilentlyContinue
        $afterSize = (Get-ChildItem $path -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
        $cleaned += [math]::Round(($beforeSize - $afterSize) / 1GB, 2)
    }
}

Write-Host "Cleaned $cleaned GB of temp files"
exit 0
