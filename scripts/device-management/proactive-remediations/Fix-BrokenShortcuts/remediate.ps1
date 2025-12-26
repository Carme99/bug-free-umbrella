<#
.SYNOPSIS
    Removes broken shortcuts from Desktop and Start Menu.

.DESCRIPTION
    This remediation script removes shortcuts that point to non-existent targets.
    Helps clean up user desktops and start menus.

.NOTES
    Exit 0: Successfully removed broken shortcuts
    Exit 1: Failed to remove broken shortcuts
#>

$ErrorActionPreference = "SilentlyContinue"

# Paths to scan
$pathsToScan = @(
    "$env:USERPROFILE\Desktop",
    "$env:PUBLIC\Desktop",
    "$env:APPDATA\Microsoft\Windows\Start Menu",
    "$env:ProgramData\Microsoft\Windows\Start Menu"
)

$removedCount = 0

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
                    Remove-Item -Path $shortcut.FullName -Force -ErrorAction Stop
                    $removedCount++
                }
            }
            catch {
                continue
            }
        }
    }
}

if ($removedCount -gt 0) {
    Write-Output "Removed $removedCount broken shortcut(s)"
    exit 0  # Success
}
else {
    Write-Output "No broken shortcuts to remove"
    exit 0  # Success (nothing to do)
}
