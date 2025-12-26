<#
.SYNOPSIS
    Detects broken shortcuts on Desktop and Start Menu.

.DESCRIPTION
    This detection script scans for broken shortcuts (.lnk files) that point to non-existent targets.
    Checks common locations: Desktop, Start Menu, Quick Launch.

.NOTES
    Exit 0: No broken shortcuts found
    Exit 1: Broken shortcuts detected (triggers remediation)
#>

$ErrorActionPreference = "SilentlyContinue"

# Paths to scan
$pathsToScan = @(
    "$env:USERPROFILE\Desktop",
    "$env:PUBLIC\Desktop",
    "$env:APPDATA\Microsoft\Windows\Start Menu",
    "$env:ProgramData\Microsoft\Windows\Start Menu"
)

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
