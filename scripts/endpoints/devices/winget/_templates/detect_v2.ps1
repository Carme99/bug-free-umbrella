<#
.SYNOPSIS
    Winget update detection script for Intune Proactive Remediations.

.DESCRIPTION
    This template checks if an app update is available via winget.
    Returns exit code 1 if update is available (triggers remediation).
    Returns exit code 0 if app is up to date or not installed (no action needed).
    It prefers the Microsoft.WinGet.Client PowerShell module (the winget CLI is NOT
    supported in the SYSTEM context that Intune Proactive Remediations run in) and
    falls back to the winget.exe CLI only when the module is unavailable.

.NOTES
    REQUIRED: Only the winget ID is required. The script will auto-detect app name.

.CONFIGURATION
    1. Set the $ID variable to your winget package ID
    2. (Optional) Customize $name if you want a specific display name

.EXAMPLE
    # For Google Chrome, you only need to set:
    $ID = 'Google.Chrome'

    # The script will automatically detect the name from winget
#>

#region Configuration
# ===== REQUIRED: Set your winget package ID =====
$ID = 'WINGETID'  # Example: 'Google.Chrome', 'Mozilla.Firefox', 'Adobe.Acrobat.Reader.64-bit'

# ===== OPTIONAL: Customize these if needed =====
$name = $null     # Leave as $null to auto-detect from winget, or set manually: 'Google Chrome'
#endregion

#region Script - DO NOT MODIFY BELOW THIS LINE
try {
    # Prefer the Microsoft.WinGet.Client PowerShell module - the winget CLI is NOT supported in
    # the SYSTEM context (Intune Proactive Remediations run as SYSTEM). Only fall back to the
    # winget.exe CLI when the module is unavailable.
    # Reference: https://learn.microsoft.com/en-us/windows/package-manager/winget/troubleshooting
    if (Get-Module -ListAvailable -Name Microsoft.WinGet.Client) {
        try { Import-Module Microsoft.WinGet.Client -ErrorAction Stop } catch { }
        if (Get-Command Get-WinGetPackage -ErrorAction SilentlyContinue) {
            $package = Get-WinGetPackage -Id $ID -MatchOption EqualsCaseInsensitive -ErrorAction SilentlyContinue

            # Auto-detect name if not provided
            if (-not $name) {
                $name = if ($package.Name) { $package.Name } else { $ID }
            }

            # Check if package is installed
            if (-not $package) {
                Write-Host "$name is not installed on this device."
                exit 0
            }

            # Check if update is available
            if ($package.IsUpdateAvailable) {
                $verInstalled = $package.InstalledVersion
                $verAvailable = $package.AvailableVersions | Select-Object -Last 1
                Write-Host "Application update available for $name. Current: $verInstalled, Available: $verAvailable"
                [pscustomobject] @{
                    Name = $name
                    InstalledVersion = $verInstalled
                    AvailableVersion = $verAvailable
                }
                exit 1  # Trigger remediation
            } else {
                # No update available
                $versionInstalled = $package.InstalledVersion
                Write-Host "$name is already up to date (version $versionInstalled)"
                [pscustomobject] @{
                    Name = $name
                    InstalledVersion = $versionInstalled
                }
                exit 0  # No action needed
            }
        }
    }

    # Fallback: winget.exe CLI (only reached when the Microsoft.WinGet.Client module is unavailable)
    # Locate winget executable
    $wingetexe = Resolve-Path "C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\winget.exe" -ErrorAction Stop
    $SystemContext = $wingetexe[-1].Path
    New-Alias -Name sysget -Value "$SystemContext" -Force

    # Get package information (exact ID match)
    $packageInfo = sysget list --exact --id $ID --accept-source-agreements 2>$null

    # Auto-detect name if not provided
    if (-not $name) {
        $nameMatch = $packageInfo | Select-String -Pattern "^($ID)\s+(.+?)\s+\d"
        if ($nameMatch) {
            $name = $nameMatch.Matches[0].Groups[2].Value.Trim()
        } else {
            $name = $ID
        }
    }

    # Check if package is installed
    if ($packageInfo -match "No installed package found matching input criteria") {
        Write-Host "$name is not installed on this device."
        exit 0
    }

    # Check if update is available
    if ($packageInfo -match '\bVersion\s+Available\b') {
        $verInstalled, $verAvailable = (-split $packageInfo[-1])[-3,-2]
        Write-Host "Application update available for $name. Current: $verInstalled, Available: $verAvailable"
        [pscustomobject] @{
            Name = $name
            InstalledVersion = $verInstalled
            AvailableVersion = $verAvailable
        }
        exit 1  # Trigger remediation
    } else {
        # No update available
        if ($packageInfo -match '\d+(\.\d+)+') {
            $versionInstalled = (-split $packageInfo[-1])[-2]
            Write-Host "$name is already up to date (version $versionInstalled)"
            [pscustomobject] @{
                Name = $name
                InstalledVersion = $versionInstalled
            }
            exit 0  # No action needed
        }
    }
} catch {
    $errMsg = $_.Exception.Message
    Write-Error "Failed to check $name for updates: $errMsg"
    exit 0  # Don't trigger remediation on error
}
#endregion
