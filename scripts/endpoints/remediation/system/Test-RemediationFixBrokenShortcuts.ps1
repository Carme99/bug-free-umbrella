<#
.SYNOPSIS
    Detects broken shortcuts on Desktop and Start Menu.

.DESCRIPTION
    This detection script scans for broken shortcuts (.lnk files) that point to non-existent targets.
    Checks common locations: per-user Desktops, Public Desktop, Start Menu, Quick Launch.
    In SYSTEM context $env:USERPROFILE is the system profile - real user desktops
    must be enumerated via Win32_UserProfile or they are never scanned.

.NOTES
    Exit 0: No broken shortcuts found
    Exit 1: Broken shortcuts detected (triggers remediation)
#>

$ErrorActionPreference = "SilentlyContinue"

# Paths to scan
$pathsToScan = @(
    "$env:PUBLIC\Desktop",
    "$env:APPDATA\Microsoft\Windows\Start Menu",
    "$env:ProgramData\Microsoft\Windows\Start Menu"
)

# Per-user desktops (SYSTEM context never sees them via $env:USERPROFILE) -
# every non-special profile is enumerated. OneDrive-known-folder redirection
# moves the desktop under the user's OneDrive folder; the default folder name is
# "OneDrive" (tenant-renamed folders cannot be derived without loading each user
# hive, so only the default is covered).
$userProfiles = Get-CimInstance Win32_UserProfile | Where-Object {
    $_.Special -eq $false -and $_.LocalPath -notmatch 'systemprofile|defaultuser'
}

foreach ($profile in $userProfiles) {
    $desktopPath = Join-Path $profile.LocalPath "Desktop"
    $pathsToScan += $desktopPath

    $oneDriveDesktop = Join-Path $profile.LocalPath "OneDrive\Desktop"
    if (Test-Path $oneDriveDesktop) {
        $pathsToScan += $oneDriveDesktop
    }
}

$brokenShortcuts = @()

foreach ($path in $pathsToScan) {
    if (Test-Path $path) {
        $shortcuts = Get-ChildItem -Path $path -Filter "*.lnk" -Recurse -ErrorAction SilentlyContinue

        foreach ($shortcut in $shortcuts) {
            try {
                $shell = New-Object -ComObject WScript.Shell
                $link = $shell.CreateShortcut($shortcut.FullName)
                $target = $link.TargetPath

                # Check if target exists
                if ($target -and -not (Test-Path $target)) {
                    $brokenShortcuts += $shortcut.FullName
                }
            }
            catch {
                # Skip shortcuts that can't be read
                continue
            }
        }
    }
}

if ($brokenShortcuts.Count -gt 0) {
    Write-Output "Found $($brokenShortcuts.Count) broken shortcut(s)"
    exit 1  # Triggers remediation
}
else {
    Write-Output "No broken shortcuts found"
    exit 0  # Compliant
}
